import Flutter
import Observation
import SmartSpectra
import UIKit

/// Platform view factory for the live camera preview (SPEC.md §6).
/// Dart shows it with `UiKitView(viewType: 'sus/camera_preview')`.
final class CameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "sus/camera_preview"

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    let mirror = params["mirror"] as? Bool ?? true
    return CameraPreviewPlatformView(frame: frame, mirror: mirror)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Hosts a UIImageView that shows `SmartSpectraSDK.shared.imageOutput`.
final class CameraPreviewPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let observer: PreviewObserver

  init(frame: CGRect, mirror: Bool) {
    // Flutter creates platform views on the main thread.
    var madeContainer: UIView?
    var madeObserver: PreviewObserver?
    MainActor.assumeIsolated {
      let container = UIView(frame: frame)
      container.backgroundColor = UIColor(red: 42 / 255, green: 22 / 255, blue: 12 / 255, alpha: 1)
      container.clipsToBounds = true

      let imageView = UIImageView(frame: container.bounds)
      imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      imageView.contentMode = .scaleAspectFill
      imageView.clipsToBounds = true
      // Mirroring flips each image's orientation rather than transforming
      // the view: a transformed view's frame is undefined, and this view
      // resizes with its container (side bars, the bad-signal banner).
      container.addSubview(imageView)

      let observer = PreviewObserver(imageView: imageView, mirror: mirror)
      observer.start()
      madeContainer = container
      madeObserver = observer
    }
    container = madeContainer!
    observer = madeObserver!
    super.init()
  }

  func view() -> UIView {
    container
  }
}

/// Re-arming observation of the SDK's preview image. Stops on its own once
/// the image view is gone (the platform view was disposed).
@MainActor
final class PreviewObserver {
  private weak var imageView: UIImageView?
  private let mirror: Bool

  init(imageView: UIImageView, mirror: Bool) {
    self.imageView = imageView
    self.mirror = mirror
  }

  func start() {
    observe()
  }

  private func observe() {
    guard let imageView else { return }
    let image = withObservationTracking {
      SmartSpectraSDK.shared.imageOutput
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observe()
      }
    }
    // Selfie-style for the front camera. Only the orientation flag changes;
    // no pixels are copied.
    imageView.image = mirror ? image?.withHorizontallyFlippedOrientation() : image
  }
}
