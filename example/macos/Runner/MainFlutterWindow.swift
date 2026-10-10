import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // MLT_WINDOW_SIZE=<width>x<height> sets the content size in logical
    // pixels, for the frame rate measurement.
    if let value = ProcessInfo.processInfo.environment["MLT_WINDOW_SIZE"] {
      let parts = value.split(separator: "x").compactMap { Double($0) }
      if parts.count == 2 {
        self.setContentSize(NSSize(width: parts[0], height: parts[1]))
        self.center()
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
