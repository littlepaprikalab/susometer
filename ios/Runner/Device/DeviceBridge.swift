import AVFoundation
import Flutter
import Foundation
import UIKit

/// Device-level helpers on MethodChannel `sus/device`: camera permission,
/// opening the app's page in iOS Settings, keep-awake, thermal state and the
/// share sheet. Nothing here stores data.
@MainActor
final class DeviceBridge {
  static let methodChannelName = "sus/device"

  private static var instance: DeviceBridge?

  static func register(with registrar: FlutterPluginRegistrar) {
    instance = DeviceBridge(messenger: registrar.messenger())
  }

  private let methodChannel: FlutterMethodChannel

  private init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      MainActor.assumeIsolated {
        guard let self else {
          result(FlutterError(code: "GONE", message: "Bridge released", details: nil))
          return
        }
        self.handle(call, result: result)
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "cameraPermission":
      result(Self.cameraPermission())

    case "requestCameraPermission":
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        result(granted)
      }

    case "openAppSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
      result(nil)

    case "openPortal":
      // Only ever opens the Presage developer portal (Settings link).
      if let url = URL(string: "https://physiology.presagetech.com") {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
      result(nil)

    case "setKeepAwake":
      // Keep the screen awake during a game (SPEC.md §9).
      UIApplication.shared.isIdleTimerDisabled = args["on"] as? Bool ?? false
      result(nil)

    case "thermalState":
      result(Self.thermalState())

    case "shareImage":
      guard let typed = args["png"] as? FlutterStandardTypedData,
        let image = UIImage(data: typed.data)
      else {
        result(FlutterError(code: "INVALID_ARGS", message: "No image to share.", details: nil))
        return
      }
      var items: [Any] = [image]
      if let text = args["text"] as? String, !text.isEmpty {
        items.append(text)
      }
      // Shared straight from memory; nothing is written to disk.
      let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
      guard let presenter = Self.topViewController() else {
        result(FlutterError(code: "NO_WINDOW", message: "Nothing to present from.", details: nil))
        return
      }
      sheet.popoverPresentationController?.sourceView = presenter.view
      presenter.present(sheet, animated: true, completion: nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func cameraPermission() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "undetermined"
    @unknown default: return "unknown"
    }
  }

  private static func thermalState() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
