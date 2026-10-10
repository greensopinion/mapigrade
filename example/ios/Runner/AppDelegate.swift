import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
  }
}
