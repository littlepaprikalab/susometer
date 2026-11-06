import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Sus-o-meter's own native bridges (SPEC.md §6, §7). Called on the main thread.
    let registry = engineBridge.pluginRegistry
    MainActor.assumeIsolated {
      if let registrar = registry.registrar(forPlugin: "SusPresageBridge") {
        PresageBridge.register(with: registrar)
      }
      if let registrar = registry.registrar(forPlugin: "SusSpeechBridge") {
        SpeechBridge.register(with: registrar)
      }
      if let registrar = registry.registrar(forPlugin: "SusDeviceBridge") {
        DeviceBridge.register(with: registrar)
      }
    }
  }
}
