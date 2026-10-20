import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    // The recording mode records a content area of 1280 x 720 points. The
    // window has no title bar, because the rounded corners of a titled window
    // would show in the recording, and isn't restorable, because the restored
    // frame of an earlier launch would replace the size.
    if ProcessInfo.processInfo.environment["MAPIGRADE_DEMO_RECORDING_SECONDS"] != nil {
      self.styleMask = [.borderless]
      self.isRestorable = false
      self.setContentSize(NSSize(width: 1280, height: 720))
    }
  }
}
