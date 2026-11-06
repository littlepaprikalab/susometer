// Minimal UIKit stand-in for Linux type-checking. Mirrors how Swift 5 mode
// treats Objective-C UIKit: @MainActor annotations imported as @preconcurrency.
@_exported import Foundation

public struct CGAffineTransform: Sendable {
  public init(scaleX: CGFloat, y: CGFloat) {}
}

@preconcurrency @MainActor open class UIResponder: NSObject {
  public override init() {}
}

@preconcurrency @MainActor open class UIColor: NSObject {
  public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
}

@preconcurrency @MainActor open class UIImage: NSObject {
  public override init() {}
  public init?(data: Data) {}
}

public struct UIViewAutoresizing: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let flexibleWidth = UIViewAutoresizing(rawValue: 2)
  public static let flexibleHeight = UIViewAutoresizing(rawValue: 16)
}

@preconcurrency @MainActor open class UIView: UIResponder {
  public enum ContentMode: Int, Sendable { case scaleToFill, scaleAspectFit, scaleAspectFill }
  public typealias AutoresizingMask = UIViewAutoresizing
  public init(frame: CGRect) {}
  open var bounds: CGRect = .zero
  open var backgroundColor: UIColor?
  open var clipsToBounds = false
  open var autoresizingMask: AutoresizingMask = []
  open var contentMode: ContentMode = .scaleToFill
  open var transform = CGAffineTransform(scaleX: 1, y: 1)
  open func addSubview(_ view: UIView) {}
}

@preconcurrency @MainActor open class UIImageView: UIView {
  open var image: UIImage?
}

@preconcurrency @MainActor open class UIPopoverPresentationController: NSObject {
  open var sourceView: UIView?
}

@preconcurrency @MainActor open class UIViewController: UIResponder {
  open var view: UIView! { nil }
  open var presentedViewController: UIViewController? { nil }
  open var popoverPresentationController: UIPopoverPresentationController? { nil }
  open func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)?) {}
}

@preconcurrency @MainActor open class UIActivityViewController: UIViewController {
  public init(activityItems: [Any], applicationActivities: [AnyObject]?) {}
}

@preconcurrency @MainActor open class UIWindow: UIView {
  open var isKeyWindow: Bool { false }
  open var rootViewController: UIViewController?
}

@preconcurrency @MainActor open class UIScene: UIResponder {}

@preconcurrency @MainActor open class UIWindowScene: UIScene {
  open var windows: [UIWindow] { [] }
}

@preconcurrency @MainActor open class UIApplication: UIResponder {
  public static var shared: UIApplication { fatalError() }
  public static let openSettingsURLString = "app-settings:"
  open var isIdleTimerDisabled = false
  open var connectedScenes: Set<UIScene> { [] }
  public struct LaunchOptionsKey: Hashable, Sendable {
    public let rawValue: String
  }
  public struct OpenExternalURLOptionsKey: Hashable, Sendable {
    public let rawValue: String
  }
  open func open(
    _ url: URL,
    options: [OpenExternalURLOptionsKey: Any] = [:],
    completionHandler: (@MainActor @Sendable (Bool) -> Void)? = nil
  ) {}
}

// Linux Foundation has no thermal state.
extension ProcessInfo {
  public enum ThermalState: Int, Sendable { case nominal, fair, serious, critical }
  public var thermalState: ThermalState { .nominal }
}
