// Screen capture check of the alignment (task 6.3 of the flutter-map-layer
// change, design D29). Captures the window of a process with ScreenCaptureKit
// at 120 Hz while the alignment benchmark runs in its video mode, and
// measures in every captured frame the distance between each red disc that
// MapLibre draws and the blue dot that flutter_map draws at its center.
//
//   swiftc -O -o alignment_capture example/tool/alignment_capture.swift
//   ./alignment_capture <pid> <seconds>
//
// Prints one line starting with ALIGNMENT_CAPTURE_RESULT. Needs the Screen
// Recording permission for the process that runs it.
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

/// The measurement of one captured frame.
struct FrameMeasurement {
  let time: Double
  /// Disc centers, in logical pixels, of the discs that are fully visible.
  let discs: [CGPoint]
  /// Distance from each of those discs' centers to its dot, in logical
  /// pixels.
  let distances: [Double]
  /// Width of flutter_map's gray background at the left and right edges of
  /// the middle row, in logical pixels.
  let leftStrip: Int
  let rightStrip: Int
}

/// Measures one BGRA frame captured at 1 pixel per logical pixel.
func measure(_ buffer: CVPixelBuffer, time: Double) -> FrameMeasurement {
  CVPixelBufferLockBaseAddress(buffer, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
  let width = CVPixelBufferGetWidth(buffer)
  let height = CVPixelBufferGetHeight(buffer)
  let stride = CVPixelBufferGetBytesPerRow(buffer)
  let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)

  // 0: other, 1: red (disc), 2: blue (dot).
  var kind = [UInt8](repeating: 0, count: width * height)
  for y in 0..<height {
    let row = base + y * stride
    for x in 0..<width {
      let b = row[x * 4], g = row[x * 4 + 1], r = row[x * 4 + 2]
      if r > 180 && g < 90 && b < 90 {
        kind[y * width + x] = 1
      } else if b > 180 && r < 90 && g < 90 {
        kind[y * width + x] = 2
      }
    }
  }

  // Connected components of red and blue pixels.
  struct Component {
    var red = 0, blue = 0
    var sx = 0.0, sy = 0.0, rx = 0.0, ry = 0.0, bx = 0.0, by = 0.0
  }
  var seen = [Bool](repeating: false, count: width * height)
  var components: [Component] = []
  var stack: [Int] = []
  for start in 0..<(width * height) where kind[start] != 0 && !seen[start] {
    var c = Component()
    seen[start] = true
    stack.append(start)
    while let i = stack.popLast() {
      let x = i % width, y = i / width
      let fx = Double(x) + 0.5, fy = Double(y) + 0.5
      c.sx += fx
      c.sy += fy
      if kind[i] == 1 {
        c.red += 1
        c.rx += fx
        c.ry += fy
      } else {
        c.blue += 1
        c.bx += fx
        c.by += fy
      }
      for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
      where nx >= 0 && ny >= 0 && nx < width && ny < height {
        let j = ny * width + nx
        if kind[j] != 0 && !seen[j] {
          seen[j] = true
          stack.append(j)
        }
      }
    }
    components.append(c)
  }

  // A disc is fully visible if its pixel count is near the largest count in
  // the frame: discs cut by an edge or a strip have fewer pixels.
  let discArea = components.map { $0.red + $0.blue }.max() ?? 0
  let separateDots = components.filter { $0.red == 0 && $0.blue > 0 }
    .map { CGPoint(x: $0.bx / Double($0.blue), y: $0.by / Double($0.blue)) }
  var discs: [CGPoint] = []
  var distances: [Double] = []
  for c in components where c.red > 0 && Double(c.red + c.blue) > 0.85 * Double(discArea) {
    let center: CGPoint
    let dot: CGPoint?
    if c.blue > 0 {
      // The dot is inside the disc: the disc's center is the centroid of
      // both colors.
      let n = Double(c.red + c.blue)
      center = CGPoint(x: c.sx / n, y: c.sy / n)
      dot = CGPoint(x: c.bx / Double(c.blue), y: c.by / Double(c.blue))
    } else {
      center = CGPoint(x: c.rx / Double(c.red), y: c.ry / Double(c.red))
      dot = separateDots.min { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }
    }
    guard let d = dot else { continue }
    let distance = hypot(d.x - center.x, d.y - center.y)
    // Farther than half the grid spacing means the dot belongs to another
    // disc.
    if distance > 75 { continue }
    discs.append(center)
    distances.append(distance)
  }

  // Gray strips (flutter_map's background, #E0E0E0) in the middle row.
  func isGray(_ x: Int) -> Bool {
    let p = base + (height / 2) * stride + x * 4
    return abs(Int(p[0]) - 224) < 6 && abs(Int(p[1]) - 224) < 6 && abs(Int(p[2]) - 224) < 6
  }
  var left = 0
  while left < width && isGray(left) { left += 1 }
  var right = 0
  while right < width && isGray(width - 1 - right) { right += 1 }

  return FrameMeasurement(time: time, discs: discs, distances: distances,
                          leftStrip: left, rightStrip: right)
}

final class Capture: NSObject, SCStreamOutput {
  let queue = DispatchQueue(label: "capture")
  var frames: [FrameMeasurement] = []
  var dropped = 0

  func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
              of type: SCStreamOutputType) {
    guard type == .screen, let buffer = sample.imageBuffer else { return }
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
      as? [[SCStreamFrameInfo: Any]]
    let status = (attachments?.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:))
    guard status == .complete else { return }
    frames.append(measure(buffer, time: sample.presentationTimeStamp.seconds))
  }
}

func percentile(_ values: [Double], _ q: Double) -> Double {
  if values.isEmpty { return .nan }
  let sorted = values.sorted()
  return sorted[Int((Double(sorted.count - 1) * q).rounded())]
}

func summary(_ values: [Double]) -> [String: Double] {
  func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
  return ["p50": r(percentile(values, 0.5)), "p95": r(percentile(values, 0.95)),
          "max": r(values.max() ?? .nan)]
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = Int32(arguments[1]), let seconds = Double(arguments[2]) else {
  print("usage: alignment_capture <pid> <seconds>")
  exit(2)
}

// Connects the process to the window server, which ScreenCaptureKit needs.
_ = NSApplication.shared
let capture = Capture()
let done = DispatchSemaphore(value: 0)
Task {
  do {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: {
      $0.owningApplication?.processID == pid && $0.windowLayer == 0
    }) else {
      print("no window for process \(pid)")
      exit(1)
    }
    let config = SCStreamConfiguration()
    // One image pixel per logical pixel.
    config.width = Int(window.frame.width)
    config.height = Int(window.frame.height)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.queueDepth = 8
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                          configuration: config, delegate: nil)
    try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
    try await stream.startCapture()
    try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    // The stream has already stopped if the window closed first.
    try? await stream.stopCapture()
  } catch {
    print("capture failed: \(error)")
    exit(1)
  }
  done.signal()
}
done.wait()

let frames = capture.queue.sync { capture.frames }.filter { !$0.discs.isEmpty }
// A frame moved if its discs aren't where the previous frame's discs were.
func moved(_ a: FrameMeasurement, _ b: FrameMeasurement) -> Bool {
  guard a.discs.count == b.discs.count else { return true }
  return zip(a.discs.sorted { ($0.x, $0.y) < ($1.x, $1.y) },
             b.discs.sorted { ($0.x, $0.y) < ($1.x, $1.y) })
    .contains { hypot($0.x - $1.x, $0.y - $1.y) > 0.25 }
}
// Frames before the first moving frame are at rest; after it, only frames
// that moved count as the pan, so that pauses don't dilute it.
let firstMoving = (1..<max(frames.count, 1)).first { moved(frames[$0], frames[$0 - 1]) } ?? frames.count
let rest = Array(frames[0..<firstMoving])
let pan = firstMoving < frames.count
  ? (firstMoving..<frames.count).filter { moved(frames[$0], frames[$0 - 1]) }.map { frames[$0] }
  : []

func segment(_ frames: [FrameMeasurement]) -> [String: Any] {
  let medians = frames.map { percentile($0.distances, 0.5) }
  let strips = frames.map { Double(max($0.leftStrip, $0.rightStrip)) }
  return [
    "frames": frames.count,
    "seconds": (((frames.last?.time ?? 0) - (frames.first?.time ?? 0)) * 100).rounded() / 100,
    "discs_per_frame": summary(frames.map { Double($0.discs.count) }),
    // Per frame, the median distance over the frame's discs.
    "frame_median_distance_px": summary(medians),
    "all_distances_px": summary(frames.flatMap { $0.distances }),
    "edge_strip_px": summary(strips),
    "frames_with_strip": strips.filter { $0 > 0 }.count,
  ]
}

let result: [String: Any] = ["rest": segment(rest), "pan": segment(pan)]
let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print("ALIGNMENT_CAPTURE_RESULT \(String(data: json, encoding: .utf8)!)")
