import Flutter
import Foundation
import Observation
import SmartSpectra
import UIKit

/// Swift side of the Flutter <-> SmartSpectra bridge (SPEC.md §6).
///
/// MethodChannel `sus/presage`: configure, start, stop, reset, testConnection and
/// the Keychain calls. EventChannel `sus/presage/stream`: a snapshot map about
/// every 100 ms while a session is active, plus blink/talk edges.
///
/// API names checked against the SmartSpectra Swift SDK v3.4.0 docs and its
/// public .swiftinterface. `SmartSpectraSDK` is `@MainActor`, so this class is too.
@MainActor
final class PresageBridge {
  static let methodChannelName = "sus/presage"
  static let eventChannelName = "sus/presage/stream"

  /// Breathing is deliberately NOT requested (SPEC.md "Decisions made during build"):
  /// it isn't scored, and Presage's LLM Insights need breathing + cardio active.
  static let requestedMetrics: [MetricType] = [
    .pulseRate, .arterialPressureTrace, .hrv, .blinking, .talking, .expressions,
  ]

  private static var instance: PresageBridge?

  static func register(with registrar: FlutterPluginRegistrar) {
    KeychainStore.prepareAtLaunch()
    instance = PresageBridge(messenger: registrar.messenger())
    registrar.register(CameraPreviewFactory(), withId: CameraPreviewFactory.viewType)
  }

  private var sdk: SmartSpectraSDK { SmartSpectraSDK.shared }
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let stream = EventStreamHandler()
  private var tickTimer: Timer?
  private var cameraSelected = false
  private var telemetryEnabled = false
  private var state = StreamState()

  private init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)

    // The SDK's telemetry default is ON. Turn it off before anything can start
    // (SPEC.md §8). Users can opt in from Settings; `configure` applies it.
    sdk.config.enableTelemetry = false
    sdk.config.imageOutputEnabled = true
    sdk.config.requestedMetrics = Self.requestedMetrics

    eventChannel.setStreamHandler(stream)
    stream.onListenChanged = { [weak self] listening in
      MainActor.assumeIsolated {
        guard let self else { return }
        if listening {
          self.state.dirty = true
          self.startTicking()
        } else {
          self.stopTicking()
        }
      }
    }
    methodChannel.setMethodCallHandler { [weak self] call, result in
      MainActor.assumeIsolated {
        guard let self else {
          result(FlutterError(code: "GONE", message: "Bridge released", details: nil))
          return
        }
        self.handle(call, result: result)
      }
    }
    observeSDK()
    observeFrames(changed: false)
  }

  // MARK: - Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "configure":
      telemetryEnabled = args["telemetry"] as? Bool ?? false
      do {
        try applyConfig()
        result(nil)
      } catch {
        result(Self.flutterError(error))
      }

    case "setApiKey":
      let key = (args["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !key.isEmpty else {
        result(FlutterError(code: "INVALID_ARGS", message: "The key is empty.", details: nil))
        return
      }
      let status = KeychainStore.save(key)
      if status == errSecSuccess {
        result(nil)
      } else {
        result(FlutterError(code: "KEYCHAIN_ERROR", message: "Keychain error \(status)", details: nil))
      }

    case "hasApiKey":
      result(KeychainStore.hasKey())

    case "apiKeyHint":
      result(KeychainStore.hint())

    case "clearApiKey":
      KeychainStore.delete()
      if sdk.processingStatus == .idle || sdk.processingStatus == .error {
        sdk.config.apiKey = nil
      }
      result(nil)

    case "testConnection":
      telemetryEnabled = args["telemetry"] as? Bool ?? telemetryEnabled
      Task {
        let outcome = await self.testConnection()
        result(outcome)
      }

    case "start":
      Task { await self.run(result) { try await self.start() } }

    case "stop":
      Task { await self.run(result) { try await self.stop() } }

    case "reset":
      Task { await self.run(result) { try await self.reset() } }

    case "sdkInfo":
      let info: [String: Any] = [
        "version": SmartSpectraSDK.version,
        "telemetry": sdk.config.enableTelemetry,
        "metrics": Self.requestedMetrics.map { "\($0)" },
      ]
      result(info)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func run(_ result: @escaping FlutterResult, _ operation: () async throws -> Void) async {
    do {
      try await operation()
      result(nil)
    } catch {
      result(Self.flutterError(error))
    }
  }

  // MARK: - Lifecycle

  /// All Presage auth setup lives here (SPEC.md §6), so a later switch to OAuth
  /// (App Attest) only touches this function and Info.plist.
  private func applyConfig() throws {
    guard let key = KeychainStore.read() else { throw BridgeError.noKey }
    if sdk.config.apiKey != key {
      sdk.config.apiKey = key
    }
    sdk.config.requestedMetrics = Self.requestedMetrics
    sdk.config.enableTelemetry = telemetryEnabled
    sdk.config.imageOutputEnabled = true
    if !cameraSelected, sdk.processingStatus == .idle || sdk.processingStatus == .error {
      // Source selection is stopped-only and persists across stop/start/reset.
      // `.default` prefers the front camera.
      do {
        try sdk.useCamera(.default)
        cameraSelected = true
      } catch {
        NSLog("[Presage] useCamera(.default) failed: \(error.localizedDescription)")
      }
    }
  }

  private func start() async throws {
    try applyConfig()
    if sdk.processingStatus == .error {
      try await sdk.reset()
    }
    state.resetMeasurements()
    state.dirty = true
    try await sdk.start()
    startTicking()
  }

  private func stop() async throws {
    defer {
      state.resetMeasurements()
      state.dirty = true
    }
    try await sdk.stop()
  }

  private func reset() async throws {
    defer {
      state.resetMeasurements()
      state.dirty = true
    }
    try await sdk.reset()
  }

  /// Configures, starts a short session, then stops. OK when the pipeline
  /// reaches `.running` and stays there for 2 s without a connection error.
  /// The result also says where auth was decided ("start" or "running") and
  /// how long it took, to answer SPEC.md §16 on the device.
  private func testConnection() async -> [String: Any] {
    let began = Date()
    func elapsedMs() -> Int { Int(Date().timeIntervalSince(began) * 1000) }

    guard sdk.processingStatus == .idle || sdk.processingStatus == .error else {
      return ["ok": false, "code": "BUSY", "message": "A measurement is already running."]
    }
    do {
      try applyConfig()
    } catch {
      return Self.failure(error, phase: "configure", ms: elapsedMs())
    }

    let previousError = sdk.error
    do {
      if sdk.processingStatus == .error {
        try await sdk.reset()
      }
      state.resetMeasurements()
      try await sdk.start()
    } catch {
      try? await sdk.stop()
      return Self.failure(error, phase: "start", ms: elapsedMs())
    }
    let startReturnedMs = elapsedMs()

    var outcome: [String: Any]?
    var runningSince: Date?
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
      if let error = sdk.error, error != previousError, Self.isConnectionError(error.code) {
        outcome = Self.failure(error, phase: "running", ms: elapsedMs())
        break
      }
      if sdk.processingStatus == .error {
        let failure: Error
        if let sdkError = sdk.error {
          failure = sdkError
        } else {
          failure = BridgeError.pipelineError
        }
        outcome = Self.failure(failure, phase: "running", ms: elapsedMs())
        break
      }
      if sdk.processingStatus == .running {
        let since = runningSince ?? Date()
        runningSince = since
        if Date().timeIntervalSince(since) >= 2 {
          outcome = [
            "ok": true, "code": "OK", "message": "Connected",
            "phase": "running", "startMs": startReturnedMs, "ms": elapsedMs(),
          ]
          break
        }
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    try? await sdk.stop()
    state.resetMeasurements()
    state.dirty = true
    return outcome ?? [
      "ok": false, "code": "TIMEOUT",
      "message": "No answer from Presage within 8 seconds. Check the internet connection.",
      "phase": "running", "startMs": startReturnedMs, "ms": elapsedMs(),
    ]
  }

  // MARK: - Observation

  /// `SmartSpectraSDK` is `@Observable`. Outside SwiftUI, track reads with
  /// `withObservationTracking` and re-arm after each change (SDK docs, UIKit).
  private func observeSDK() {
    withObservationTracking {
      _ = sdk.metrics
      _ = sdk.processingStatus
      _ = sdk.validationStatus
      _ = sdk.error
      _ = sdk.insight
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        // Re-arm first, then read (observeSDK ends with ingest()).
        self?.observeSDK()
      }
    }
    ingest()
  }

  /// Notes when the SDK last published a camera frame (`imageOutput`). The
  /// stream sends a snapshot every tick while the SDK says it's running,
  /// even if the camera has stalled, so the snapshots alone can't show a
  /// frozen camera; `frameAt` can.
  private func observeFrames(changed: Bool) {
    let image = withObservationTracking {
      sdk.imageOutput
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.observeFrames(changed: true)
      }
    }
    if changed, image != nil {
      state.frameAt = nowMs()
    }
  }

  private func ingest() {
    let now = nowMs()
    let previousStatus = state.status
    state.status = sdk.processingStatus
    state.validation = sdk.validationStatus
    state.error = sdk.error
    if sdk.insight != nil, !state.insightSeen {
      // Should never happen with breathing off. Flag it so it shows on screen.
      state.insightSeen = true
      NSLog("[Presage] WARNING: an LLM insight was published by the SDK.")
    }
    if previousStatus != state.status {
      state.dirty = true
    }
    if previousStatus != .running, state.status == .running {
      // Frame age counts from here at the latest, so a camera that never
      // delivers a frame shows as frozen too.
      state.frameAt = now
    }
    guard let metrics = sdk.metrics else { return }

    for sample in metrics.cardio.pulseRate.sorted(by: { $0.timestamp < $1.timestamp })
    where sample.timestamp > state.lastPulseTs {
      state.lastPulseTs = sample.timestamp
      guard sample.value > 0, sample.value.isFinite else { continue }
      state.pulse = Double(sample.value)
      state.pulseConf = Double(sample.confidence) / 100.0
      state.pulseStable = sample.stable
      state.pulseAt = now
      state.dirty = true
    }

    for sample in metrics.cardio.hrv.sorted(by: { $0.timestamp < $1.timestamp })
    where sample.timestamp > state.lastHrvTs {
      state.lastHrvTs = sample.timestamp
      guard sample.rmssd > 0, sample.rmssd.isFinite else { continue }
      state.rmssd = sample.rmssd
      state.hrvConf = Double(sample.confidence) / 100.0
      state.hrvStable = sample.stable
      state.dirty = true
    }

    // The pulse waveform, with each sample's SDK timestamp (microseconds) and
    // confidence (0..1), so Dart can find individual heartbeats (SPEC.md
    // decision 63). The three arrays always have the same length.
    for sample in metrics.cardio.arterialPressureTrace.sorted(by: { $0.timestamp < $1.timestamp })
    where sample.timestamp > state.lastTraceTs {
      state.lastTraceTs = sample.timestamp
      guard sample.value.isFinite else { continue }
      state.trace.append(Double(sample.value))
      state.traceTs.append(sample.timestamp)
      state.traceConf.append(Double(sample.confidence) / 100.0)
      state.dirty = true
    }
    if state.trace.count > 300 {
      let extra = state.trace.count - 300
      state.trace.removeFirst(extra)
      state.traceTs.removeFirst(extra)
      state.traceConf.removeFirst(extra)
    }

    for sample in metrics.face.blinking.sorted(by: { $0.timestamp < $1.timestamp })
    where sample.timestamp > state.lastBlinkTs {
      state.lastBlinkTs = sample.timestamp
      if sample.detected && !state.blink {
        state.events.append(["e": "blinkEvent", "t": now, "ts": sample.timestamp])
      }
      state.blink = sample.detected
      state.faceSamples += 1
      state.dirty = true
    }

    for sample in metrics.face.talking.sorted(by: { $0.timestamp < $1.timestamp })
    where sample.timestamp > state.lastTalkTs {
      state.lastTalkTs = sample.timestamp
      if sample.detected != state.talking {
        state.events.append([
          "e": sample.detected ? "talkStart" : "talkEnd", "t": now, "ts": sample.timestamp,
        ])
      }
      state.talking = sample.detected
      state.dirty = true
    }

    if let latest = metrics.face.expression.max(by: { $0.timestamp < $1.timestamp }),
      latest.timestamp > state.lastExprTs
    {
      state.lastExprTs = latest.timestamp
      var expr: [String: Double] = [:]
      for score in latest.scores {
        // Confidence is a percentage [0, 100] (Data Types reference); send 0..1.
        expr[Self.expressionName(score.type)] = Double(score.confidence) / 100.0
      }
      state.expr = expr
      state.exprAt = now
      state.dirty = true
    }
  }

  // MARK: - Stream ticks (~10 Hz)

  private func startTicking() {
    guard tickTimer == nil else { return }
    tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
  }

  private func stopTicking() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func tick() {
    guard stream.hasListener else { return }
    guard state.status != .idle || state.dirty else { return }
    stream.send(state.snapshot(now: nowMs()))
    state.events.removeAll(keepingCapacity: true)
    state.trace.removeAll(keepingCapacity: true)
    state.traceTs.removeAll(keepingCapacity: true)
    state.traceConf.removeAll(keepingCapacity: true)
    state.dirty = false
  }

  // MARK: - Mapping helpers

  nonisolated static func statusName(_ status: ProcessingStatus) -> String {
    switch status {
    case .idle: return "idle"
    case .starting: return "starting"
    case .running: return "running"
    case .stopping: return "stopping"
    case .error: return "error"
    @unknown default: return "unknown"
    }
  }

  nonisolated static func validationName(_ code: ValidationCode) -> String {
    switch code {
    case .ok: return "OK"
    case .noFaceFound: return "NO_FACE_FOUND"
    case .multipleFacesFound: return "MULTIPLE_FACES_FOUND"
    case .faceNotCentered: return "FACE_NOT_CENTERED"
    case .tooDark: return "TOO_DARK"
    case .tooBright: return "TOO_BRIGHT"
    case .chestNotVisible: return "CHEST_NOT_VISIBLE"
    case .cameraTuning: return "CAMERA_TUNING"
    case .frameRateTooLow: return "FRAME_RATE_TOO_LOW"
    case .excessiveMotion: return "EXCESSIVE_MOTION"
    case .faceTooClose: return "FACE_TOO_CLOSE"
    case .faceTooFar: return "FACE_TOO_FAR"
    case .faceTooHigh: return "FACE_TOO_HIGH"
    case .faceTooLow: return "FACE_TOO_LOW"
    case .faceNotForward: return "FACE_NOT_FORWARD"
    default:
      // Includes the deprecated .faceSizeOutOfRange (raw value 4).
      return code.rawValue == 4 ? "FACE_SIZE_OUT_OF_RANGE" : "CODE_\(code.rawValue)"
    }
  }

  nonisolated static func errorName(_ code: SmartSpectraError.Code) -> String {
    switch code {
    case .invalidState: return "invalidState"
    case .authenticationFailed: return "authenticationFailed"
    case .configurationFailed: return "configurationFailed"
    case .creditExhausted: return "creditExhausted"
    case .networkError: return "networkError"
    case .serverError: return "serverError"
    case .inputUnavailable: return "inputUnavailable"
    case .processingFailed: return "processingFailed"
    case .frameConversionFailed: return "frameConversionFailed"
    case .nonMonotonicTimestamp: return "nonMonotonicTimestamp"
    case .timestampGap: return "timestampGap"
    @unknown default: return "code\(code.rawValue)"
    }
  }

  nonisolated static func expressionName(_ type: ExpressionType) -> String {
    switch type {
    case .unspecified: return "unspecified"
    case .angry: return "angry"
    case .contempt: return "contempt"
    case .disgust: return "disgust"
    case .fear: return "fear"
    case .happy: return "happy"
    case .neutral: return "neutral"
    case .sad: return "sad"
    case .surprise: return "surprise"
    case .UNRECOGNIZED(let raw): return "unknown\(raw)"
    @unknown default: return "unknown"
    }
  }

  nonisolated static func isConnectionError(_ code: SmartSpectraError.Code) -> Bool {
    switch code {
    case .authenticationFailed, .creditExhausted, .networkError, .serverError,
      .configurationFailed:
      return true
    default:
      return false
    }
  }

  nonisolated static func errorMap(_ error: SmartSpectraError) -> [String: Any] {
    [
      "code": errorName(error.code),
      "codeNum": error.code.rawValue,
      "message": error.message,
      "retryable": error.retryable,
    ]
  }

  nonisolated static func flutterError(_ error: Error) -> FlutterError {
    if let sdkError = error as? SmartSpectraError {
      let details: [String: Any] = [
        "codeNum": sdkError.code.rawValue, "retryable": sdkError.retryable,
      ]
      return FlutterError(code: errorName(sdkError.code), message: sdkError.message, details: details)
    }
    if let bridgeError = error as? BridgeError {
      return FlutterError(code: bridgeError.code, message: bridgeError.message, details: nil)
    }
    return FlutterError(code: "UNKNOWN", message: error.localizedDescription, details: nil)
  }

  nonisolated static func failure(_ error: Error, phase: String, ms: Int) -> [String: Any] {
    var out: [String: Any] = ["ok": false, "phase": phase, "ms": ms]
    if let sdkError = error as? SmartSpectraError {
      out["code"] = errorName(sdkError.code)
      out["codeNum"] = sdkError.code.rawValue
      out["message"] = sdkError.message
    } else if let bridgeError = error as? BridgeError {
      out["code"] = bridgeError.code
      out["message"] = bridgeError.message
    } else {
      out["code"] = "UNKNOWN"
      out["message"] = error.localizedDescription
    }
    return out
  }
}

enum BridgeError: Error {
  case noKey
  case pipelineError

  var code: String {
    switch self {
    case .noKey: return "NO_KEY"
    case .pipelineError: return "PIPELINE_ERROR"
    }
  }

  var message: String {
    switch self {
    case .noKey: return "No Presage API key yet. Add one in Settings."
    case .pipelineError: return "The SmartSpectra pipeline reported an error."
    }
  }
}

/// Retained "last valid" values plus edges collected since the last tick.
/// Rate metrics can be empty between updates (SPEC.md §5.5), so values stay
/// until replaced, and everything resets at session start and stop.
struct StreamState {
  var status: ProcessingStatus = .idle
  var validation: ValidationStatus?
  var error: SmartSpectraError?
  var insightSeen = false
  var dirty = false

  var pulse: Double?
  var pulseConf: Double?
  var pulseStable = false
  var pulseAt: Int64?
  var rmssd: Double?
  var hrvConf: Double?
  var hrvStable = false
  var blink = false
  var talking = false
  var expr: [String: Double] = [:]
  /// When the latest expression sample arrived, so Dart can tell fresh
  /// scores from ones the SDK stopped updating.
  var exprAt: Int64?
  var faceSamples = 0
  /// When the SDK last published a camera frame, or when it started
  /// running if that's later. Nil before either this session.
  var frameAt: Int64?

  var events: [[String: Any]] = []
  var trace: [Double] = []
  /// SDK timestamp (microseconds) and confidence (0..1) of each [trace] value.
  var traceTs: [Int64] = []
  var traceConf: [Double] = []

  var lastPulseTs: Int64 = 0
  var lastHrvTs: Int64 = 0
  var lastTraceTs: Int64 = 0
  var lastBlinkTs: Int64 = 0
  var lastTalkTs: Int64 = 0
  var lastExprTs: Int64 = 0

  mutating func resetMeasurements() {
    pulse = nil
    pulseConf = nil
    pulseStable = false
    pulseAt = nil
    rmssd = nil
    hrvConf = nil
    hrvStable = false
    blink = false
    talking = false
    expr = [:]
    exprAt = nil
    faceSamples = 0
    frameAt = nil
    events.removeAll()
    trace.removeAll()
    traceTs.removeAll()
    traceConf.removeAll()
    lastPulseTs = 0
    lastHrvTs = 0
    lastTraceTs = 0
    lastBlinkTs = 0
    lastTalkTs = 0
    lastExprTs = 0
  }

  func snapshot(now: Int64) -> [String: Any] {
    var out: [String: Any] = [
      "t": now,
      "status": PresageBridge.statusName(status),
      "pulseStable": pulseStable,
      "hrvStable": hrvStable,
      "blink": blink,
      "talking": talking,
      "expr": expr,
      "events": events,
      "trace": trace,
      "traceTs": traceTs,
      "traceConf": traceConf,
      "insightSeen": insightSeen,
    ]
    // Missing keys arrive in Dart as null.
    if let pulse { out["pulse"] = pulse }
    if let pulseConf { out["pulseConf"] = pulseConf }
    if let pulseAt { out["pulseAt"] = pulseAt }
    if let exprAt { out["exprAt"] = exprAt }
    if let frameAt { out["frameAt"] = frameAt }
    if let rmssd { out["rmssd"] = rmssd }
    if let hrvConf { out["hrvConf"] = hrvConf }
    if let validation {
      out["validation"] = [
        "code": PresageBridge.validationName(validation.code), "hint": validation.hint,
      ]
    }
    if let error {
      out["error"] = PresageBridge.errorMap(error)
    }
    return out
  }
}
