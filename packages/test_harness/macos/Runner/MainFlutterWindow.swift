import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var secondEngineHost: SecondEngineHost?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // MLT_WINDOW_SIZE=<width>x<height> sets the content size in logical
    // pixels, for the frame rate measurement. MLT_WINDOW_SCREEN=builtin
    // centers the window on the built-in display, whose refresh rate the
    // measurements assume, wherever macOS restores the window.
    let environment = ProcessInfo.processInfo.environment
    var size: NSSize?
    if let value = environment["MLT_WINDOW_SIZE"] {
      let parts = value.split(separator: "x").compactMap { Double($0) }
      if parts.count == 2 {
        size = NSSize(width: parts[0], height: parts[1])
      }
    }
    let screen = environment["MLT_WINDOW_SCREEN"] == "builtin" ? Self.builtinScreen() : nil
    if size != nil || screen != nil {
      place(size: size, screen: screen)
      // Something after awakeFromNib resets the window to the nib's 800x600
      // content size, so apply the size again once launch has finished.
      DispatchQueue.main.async { self.place(size: size, screen: screen) }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    secondEngineHost = SecondEngineHost(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func place(size: NSSize?, screen: NSScreen?) {
    if let size { setContentSize(size) }
    guard let screen else {
      center()
      return
    }
    let area = screen.visibleFrame
    setFrameOrigin(NSPoint(
      x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
  }

  private static func builtinScreen() -> NSScreen? {
    NSScreen.screens.first { screen in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
      else { return false }
      return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
  }
}

/// Starts and destroys a second engine for integration_test/engines_test.dart
/// over the channel `mapigrade_test/engines` (design D159 of the
/// multiple-flutter-engines change).
class SecondEngineHost {
  private static let channelName = "mapigrade_test/engines"
  private let channel: FlutterMethodChannel
  private var engine: FlutterEngine?
  private var options: Any?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      if engine != nil {
        result(FlutterError(code: "started", message: "the second engine is already running", details: nil))
        return
      }
      options = call.arguments
      let engine = FlutterEngine(name: "second", project: nil, allowHeadlessExecution: true)
      // The engine registers every plugin of the app.
      RegisterGeneratedPlugins(registry: engine)
      let secondChannel = FlutterMethodChannel(
        name: Self.channelName, binaryMessenger: engine.binaryMessenger)
      secondChannel.setMethodCallHandler { [weak self] secondCall, secondResult in
        guard let self else { return secondResult(nil) }
        switch secondCall.method {
        case "options":
          secondResult(self.options)
        case "report":
          self.channel.invokeMethod("report", arguments: secondCall.arguments)
          secondResult(nil)
        default:
          secondResult(FlutterMethodNotImplemented)
        }
      }
      engine.run(withEntrypoint: "secondEngineMain")
      self.engine = engine
      result(nil)
    case "destroy":
      engine?.shutDownEngine()
      engine = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
