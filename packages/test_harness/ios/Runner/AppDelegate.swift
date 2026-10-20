import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var secondEngineHost: SecondEngineHost?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // MLT_KEEP_AWAKE=1 keeps the device from locking during scripted
    // measurements, for example through
    // `xcrun devicectl device process launch -e '{"MLT_KEEP_AWAKE":"1"}'`.
    if ProcessInfo.processInfo.environment["MLT_KEEP_AWAKE"] == "1" {
      application.isIdleTimerDisabled = true
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecondEngineHost") {
      secondEngineHost = SecondEngineHost(messenger: registrar.messenger())
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
      engine.run(
        withEntrypoint: "secondEngineMain", libraryURI: "package:test_harness/second_engine.dart")
      // The engine registers every plugin of the app.
      GeneratedPluginRegistrant.register(with: engine)
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
      self.engine = engine
      result(nil)
    case "destroy":
      engine?.destroyContext()
      engine = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
