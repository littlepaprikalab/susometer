// Minimal Flutter iOS embedder stand-in (Objective-C API, no actor annotations).
import Foundation
import UIKit

public typealias FlutterResult = (Any?) -> Void
public typealias FlutterEventSink = (Any?) -> Void
public typealias FlutterMethodCallHandler = (FlutterMethodCall, @escaping FlutterResult) -> Void
public let FlutterMethodNotImplemented: NSObject = NSObject()

open class FlutterMethodCall: NSObject {
  open var method: String { "" }
  open var arguments: Any? { nil }
}

open class FlutterError: NSObject {
  public init(code: String, message: String?, details: Any?) {}
}

public protocol FlutterBinaryMessenger: NSObjectProtocol {}
public protocol FlutterMessageCodec: NSObjectProtocol {}

open class FlutterStandardMessageCodec: NSObject, FlutterMessageCodec {
  public static func sharedInstance() -> FlutterStandardMessageCodec { FlutterStandardMessageCodec() }
}

open class FlutterMethodChannel: NSObject {
  public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {}
  open func setMethodCallHandler(_ handler: FlutterMethodCallHandler?) {}
}

public protocol FlutterStreamHandler: NSObjectProtocol {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
  func onCancel(withArguments arguments: Any?) -> FlutterError?
}

open class FlutterEventChannel: NSObject {
  public init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {}
  open func setStreamHandler(_ handler: (FlutterStreamHandler & NSObjectProtocol)?) {}
}

public protocol FlutterPlatformView: NSObjectProtocol {
  func view() -> UIView
}

public protocol FlutterPlatformViewFactory: NSObjectProtocol {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol
}

public protocol FlutterPluginRegistrar: NSObjectProtocol {
  func messenger() -> FlutterBinaryMessenger & NSObjectProtocol
  func register(_ factory: FlutterPlatformViewFactory & NSObjectProtocol, withId factoryId: String)
}

public protocol FlutterPluginRegistry: NSObjectProtocol {
  func registrar(forPlugin pluginKey: String) -> (FlutterPluginRegistrar & NSObjectProtocol)?
}

open class FlutterImplicitEngineBridge: NSObject {
  open var pluginRegistry: FlutterPluginRegistry & NSObjectProtocol { fatalError() }
}

public protocol FlutterImplicitEngineDelegate: NSObjectProtocol {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge)
}

@preconcurrency @MainActor open class FlutterAppDelegate: UIResponder {
  open func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool { true }
  public static func main() {}
}

open class FlutterStandardTypedData: NSObject {
  open var data: Data { Data() }
}

open class FlutterDartProject: NSObject {
  open class func lookupKey(forAsset asset: String) -> String { asset }
}
