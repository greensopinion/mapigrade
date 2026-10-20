// Captures the content area of the demo's window for the README image; see
// design D148 of the readme-demo-recording change. `record_readme.sh`
// compiles and runs it.
//
//   capture_window check
//     Exits with 0 when the app that runs it has Screen Recording permission;
//     otherwise asks macOS for it and exits with 2.
//
//   capture_window record <demo binary> <seconds> <output.mov>
//     Starts the demo in its recording mode, waits for `ready`, captures the
//     window's content area, writes `go` to the demo when the first frame
//     arrives, and stops <seconds> after that frame.

import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The content size of the demo's window in the recording mode, in points.
let contentSize = CGSize(width: 1280, height: 720)

/// The time from the start of the capture to its first frame, at most.
let firstFrameTimeout: TimeInterval = 10

func fail(_ message: String, status: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data("capture_window: \(message)\n".utf8))
  exit(status)
}

func check() -> Int32 {
  if CGPreflightScreenCaptureAccess() { return 0 }
  // Adds the app to the Screen Recording list, or shows the prompt.
  _ = CGRequestScreenCaptureAccess()
  FileHandle.standardError.write(
    Data(
      """
      capture_window: the app that runs this script doesn't have Screen \
      Recording permission. Allow it in System Settings > Privacy & Security \
      > Screen & System Audio Recording, quit and reopen the app, and run the \
      script again.

      """.utf8))
  return 2
}

// The state that the pipe, the stream and the timers share is guarded by
// [lock], or used only on [queue].
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  init(demo binary: URL, seconds: Int, output: URL) {
    self.binary = binary
    self.seconds = seconds
    self.output = output
  }

  let binary: URL
  let seconds: Int
  let output: URL

  let demo = Process()
  private let toDemo = Pipe()
  private let fromDemo = Pipe()

  /// Guards the state below, which the pipe, the stream and the timers use.
  private let lock = NSLock()
  private var lineBuffer = Data()
  private var ready: CheckedContinuation<Void, Never>?
  private var isReady = false
  private var done: CheckedContinuation<Void, Never>?
  private var finished = false
  private var stopping = false

  private let queue = DispatchQueue(label: "capture_window.frames")
  private var stream: SCStream?
  private var writer: AVAssetWriter!
  private var input: AVAssetWriterInput!
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor!
  private var firstTime: CMTime?
  private var lastPixels: CVPixelBuffer?
  private var frames = 0
  private var dropped = 0

  func run() async {
    startDemo()
    await withCheckedContinuation { continuation in
      lock.withLock {
        if isReady { continuation.resume() } else { ready = continuation }
      }
    }
    let window = await findWindow()
    do {
      try await startCapture(of: window)
    } catch {
      fail("can't start the capture: \(error.localizedDescription)")
    }
    queue.asyncAfter(deadline: .now() + firstFrameTimeout) { [self] in
      if firstTime == nil {
        fail("no frame of the demo's window arrived within \(Int(firstFrameTimeout)) s")
      }
    }
    queue.asyncAfter(deadline: .now() + firstFrameTimeout + Double(seconds) + 5) {
      [self] in
      if !finished { fail("the capture didn't reach \(seconds) s") }
    }
    await withCheckedContinuation { continuation in
      lock.withLock { done = continuation }
    }
    try? await stream?.stopCapture()
    await writer.finishWriting()
    if writer.status != .completed {
      fail("can't write \(output.path): \(writer.error?.localizedDescription ?? "unknown error")")
    }
    stopDemo()
    FileHandle.standardError.write(
      Data("capture_window: \(frames) frames in \(seconds) s, \(dropped) dropped\n".utf8))
  }

  /// Stops the demo, which keeps playing the flyover after the clip.
  func stopDemo() {
    lock.withLock { stopping = true }
    if demo.isRunning { demo.terminate() }
    demo.waitUntilExit()
  }

  private func startDemo() {
    demo.executableURL = binary
    var environment = ProcessInfo.processInfo.environment
    environment["MAPIGRADE_DEMO_RECORDING_SECONDS"] = String(seconds)
    demo.environment = environment
    demo.standardInput = toDemo
    demo.standardOutput = fromDemo
    fromDemo.fileHandleForReading.readabilityHandler = { [self] handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        return
      }
      readLines(data)
    }
    demo.terminationHandler = { [self] process in
      let expected = lock.withLock { stopping }
      if !expected {
        fail("the demo exited with status \(process.terminationStatus) before the capture finished")
      }
    }
    do {
      try demo.run()
    } catch {
      fail("can't start \(binary.path): \(error.localizedDescription)")
    }
  }

  /// Resumes [run] on `ready`; passes the demo's other lines to standard error.
  private func readLines(_ data: Data) {
    var lines: [String] = []
    lock.withLock {
      lineBuffer.append(data)
      while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
        lines.append(String(decoding: lineBuffer[..<newline], as: UTF8.self))
        lineBuffer.removeSubrange(...newline)
      }
    }
    for line in lines {
      if line == "ready" {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
          isReady = true
          defer { ready = nil }
          return ready
        }
        continuation?.resume()
      } else {
        FileHandle.standardError.write(Data("demo: \(line)\n".utf8))
      }
    }
  }

  /// The demo's window, which has the recording mode's content width.
  private func findWindow() async -> SCWindow {
    let pid = demo.processIdentifier
    for _ in 0..<50 {
      if let content = try? await SCShareableContent.excludingDesktopWindows(
        true, onScreenWindowsOnly: true),
        let window = content.windows.first(where: {
          $0.owningApplication?.processID == pid && $0.windowLayer == 0
            && $0.frame.width == contentSize.width
        })
      {
        return window
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    fail("can't find the demo's window with a width of \(Int(contentSize.width)) points")
  }

  private func startCapture(of window: SCWindow) async throws {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let scale = CGFloat(filter.pointPixelScale)
    let width = Int(contentSize.width * scale)
    let height = Int(contentSize.height * scale)

    let config = SCStreamConfiguration()
    // The content area is below the title bar; the rectangle is in points
    // from the top left of the window.
    config.sourceRect = CGRect(
      x: 0, y: window.frame.height - contentSize.height,
      width: contentSize.width, height: contentSize.height)
    config.width = width
    config.height = height
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.colorSpaceName = CGColorSpace.sRGB
    config.queueDepth = 8

    try? FileManager.default.removeItem(at: output)
    writer = try AVAssetWriter(outputURL: output, fileType: .mov)
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 80_000_000],
        AVVideoColorPropertiesKey: [
          AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
          AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
          AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
      ])
    input.expectsMediaDataInRealTime = true
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? CocoaError(.fileWriteUnknown)
    }

    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    self.stream = stream
    try await stream.startCapture()
  }

  // Runs on [queue].
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, !finished,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let rawStatus = attachments.first?[.status] as? Int,
      SCFrameStatus(rawValue: rawStatus) == .complete,
      let pixels = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if firstTime == nil {
      firstTime = time
      writer.startSession(atSourceTime: time)
      // The run starts at the clip's first frame.
      toDemo.fileHandleForWriting.write(Data("go\n".utf8))
    }
    let end = firstTime! + CMTime(value: CMTimeValue(seconds), timescale: 1)
    if time >= end {
      finish(at: end)
      return
    }
    append(pixels, at: time)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    fail("the capture stopped: \(error.localizedDescription)")
  }

  private func append(_ pixels: CVPixelBuffer, at time: CMTime) {
    if input.isReadyForMoreMediaData, adaptor.append(pixels, withPresentationTime: time) {
      frames += 1
    } else {
      dropped += 1
    }
    lastPixels = pixels
  }

  /// Repeats the last frame at [end], so that the clip lasts until [end] even
  /// when the window doesn't change at the end; the stream delivers frames
  /// only when the window changes.
  private func finish(at end: CMTime) {
    finished = true
    if let lastPixels, input.isReadyForMoreMediaData {
      adaptor.append(lastPixels, withPresentationTime: end)
    }
    input.markAsFinished()
    let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
      defer { done = nil }
      return done
    }
    continuation?.resume()
  }
}

/// Stops the demo when the script stops this helper.
var signalSources: [DispatchSourceSignal] = []
func stopDemo(on signals: [Int32], _ recorder: Recorder) {
  for signalNumber in signals {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
      if recorder.demo.isRunning { recorder.demo.terminate() }
      exit(128 + signalNumber)
    }
    source.resume()
    signalSources.append(source)
  }
}

let arguments = CommandLine.arguments
let usage = "usage: capture_window check | record <demo binary> <seconds> <output.mov>"
switch arguments.dropFirst().first {
case "check":
  exit(check())
case "record":
  guard arguments.count == 5, let seconds = Int(arguments[3]), seconds > 0 else {
    fail(usage)
  }
  let recorder = Recorder(
    demo: URL(fileURLWithPath: arguments[2]), seconds: seconds,
    output: URL(fileURLWithPath: arguments[4]))
  stopDemo(on: [SIGINT, SIGTERM, SIGHUP], recorder)
  // ScreenCaptureKit needs a connection to the window server, which a
  // command-line tool doesn't have until it asks for a display.
  _ = CGMainDisplayID()
  Task {
    await recorder.run()
    exit(0)
  }
  dispatchMain()
default:
  fail(usage)
}
