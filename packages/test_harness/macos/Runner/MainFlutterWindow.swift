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
    // pixels, for the frame rate measurement.
    if let value = ProcessInfo.processInfo.environment["MLT_WINDOW_SIZE"] {
      let parts = value.split(separator: "x").compactMap { Double($0) }
      if parts.count == 2 {
        let size = NSSize(width: parts[0], height: parts[1])
        self.setContentSize(size)
        self.center()
        // Something after awakeFromNib resets the window to the nib's 800x600
        // content size, so apply the size again once launch has finished.
        DispatchQueue.main.async {
          self.setContentSize(size)
          self.center()
        }
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    secondEngineHost = SecondEngineHost(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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
