import Flutter
import Foundation

/// Minimal FlutterStreamHandler that keeps the current sink.
///
/// Flutter calls these methods on the main thread, and `send` must also be
/// called on the main thread. Kept free of actor annotations on purpose so it
/// can satisfy the Objective-C protocol without isolation mismatches.
final class EventStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  /// Called on the main thread when Dart starts or stops listening.
  var onListenChanged: ((Bool) -> Void)?

  var hasListener: Bool { sink != nil }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    onListenChanged?(true)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    onListenChanged?(false)
    return nil
  }

  func send(_ payload: [String: Any]) {
    sink?(payload)
  }
}

/// Wall-clock milliseconds, the single time base shared with Dart.
func nowMs() -> Int64 {
  Int64((Date().timeIntervalSince1970 * 1000).rounded())
}
