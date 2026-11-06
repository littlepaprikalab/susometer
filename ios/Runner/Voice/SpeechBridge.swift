import AVFoundation
import Flutter
import Foundation
import Speech

/// Native on-device speech recognition (SPEC.md §1, §7, §8).
///
/// MethodChannel `sus/speech`: permissionStatus, requestPermissions, start,
/// stop, pause, resume. EventChannel `sus/speech/stream`: maps with a `type`
/// of partial, final, level, state or error.
///
/// Privacy: every request sets `requiresOnDeviceRecognition = true`. If the
/// device can't recognize on-device, listening fails with ON_DEVICE_UNAVAILABLE
/// instead of falling back to Apple's servers. Audio is never written to disk.
@MainActor
final class SpeechBridge {
  static let methodChannelName = "sus/speech"
  static let eventChannelName = "sus/speech/stream"

  private static var instance: SpeechBridge?

  static func register(with registrar: FlutterPluginRegistrar) {
    instance = SpeechBridge(messenger: registrar.messenger())
  }

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let stream = EventStreamHandler()
  private let engine = AVAudioEngine()
  private let feed = RecognitionFeed()

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  /// Recognition tasks by segment. Ended segments stay here until they
  /// deliver their final text, so the last words of a question aren't lost.
  private var tasks: [Int: SFSpeechRecognitionTask] = [:]
  private var listening = false
  private var paused = false
  private var segment = 0
  private var quickFailures = 0
  private var segmentStartedAt = Date()
  private var levelTimer: Timer?
  private var observers: [NSObjectProtocol] = []

  // Host voice and sound effects (half-duplex, SPEC.md §7).
  private let synthesizer = AVSpeechSynthesizer()
  private var synthDelegate: SynthDelegate?
  private var pendingSpeech: [ObjectIdentifier: FlutterResult] = [:]
  private var players: [ObjectIdentifier: (AVAudioPlayer, PlayerDelegate, FlutterResult)] = [:]
  private var hostOutputs = 0
  private var reopenWork: DispatchWorkItem?

  private init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(stream)
    let delegate = SynthDelegate(bridge: self)
    synthDelegate = delegate
    synthesizer.delegate = delegate
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

  // MARK: - Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "permissionStatus":
      result(permissionStatus())

    case "requestPermissions":
      Task {
        if AVAudioApplication.shared.recordPermission == .undetermined {
          _ = await AVAudioApplication.requestRecordPermission()
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
          _ = await Self.requestSpeechAuthorization()
        }
        result(self.permissionStatus())
      }

    case "start":
      do {
        try startListening(localeId: args["locale"] as? String)
        result(nil)
      } catch let error as SpeechError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        result(FlutterError(code: "AUDIO_ERROR", message: error.localizedDescription, details: nil))
      }

    case "stop":
      stopListening()
      result(nil)

    case "pause":
      pause()
      result(nil)

    case "resume":
      resume()
      result(nil)

    case "newSegment":
      result(newSegment())

    case "speak":
      let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !text.isEmpty else {
        result(nil)
        return
      }
      speak(text, result: result)

    case "stopSpeaking":
      synthesizer.stopSpeaking(at: .immediate)
      result(nil)

    case "playSound":
      playSound(args["name"] as? String ?? "", result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func permissionStatus() -> [String: Any] {
    let mic: String
    switch AVAudioApplication.shared.recordPermission {
    case .granted: mic = "granted"
    case .denied: mic = "denied"
    case .undetermined: mic = "undetermined"
    @unknown default: mic = "unknown"
    }
    let speech: String
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: speech = "authorized"
    case .denied: speech = "denied"
    case .restricted: speech = "restricted"
    case .notDetermined: speech = "notDetermined"
    @unknown default: speech = "unknown"
    }
    let onDevice = (SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer())?
      .supportsOnDeviceRecognition ?? false
    return ["mic": mic, "speech": speech, "onDevice": onDevice]
  }

  nonisolated private static func requestSpeechAuthorization() async
    -> SFSpeechRecognizerAuthorizationStatus
  {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  // MARK: - Listening

  private func startListening(localeId: String?) throws {
    guard !listening else { return }
    guard AVAudioApplication.shared.recordPermission == .granted else { throw SpeechError.micDenied }
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
      throw SpeechError.speechDenied
    }
    let locale = localeId.map { Locale(identifier: $0) } ?? Locale.current
    guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
      throw SpeechError.unavailable
    }
    guard recognizer.supportsOnDeviceRecognition else { throw SpeechError.onDeviceUnavailable }
    self.recognizer = recognizer

    try configureAudioSession()
    try startEngine()

    listening = true
    paused = false
    quickFailures = 0
    applyGate()
    beginSegment()
    startLevelTimer()
    observeAudioNotifications()
    sendState("listening")
  }

  private func stopListening() {
    guard listening else { return }
    listening = false
    paused = false
    feed.setRequest(nil)
    request?.endAudio()
    request = nil
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    levelTimer?.invalidate()
    levelTimer = nil
    removeAudioNotifications()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    sendState("stopped")
  }

  /// Manual pause: ending the request closes the current segment cleanly.
  private func pause() {
    guard listening, !paused else { return }
    paused = true
    applyGate()
    feed.setRequest(nil)
    request?.endAudio()
    request = nil
    sendState("paused")
  }

  private func resume() {
    guard listening, paused else { return }
    paused = false
    applyGate()
    beginSegment()
    sendState("listening")
  }

  /// Ends the current segment (its final text still arrives) and starts a
  /// new one. Returns the new segment id, or nil when not listening.
  private func newSegment() -> Int? {
    guard listening, !paused else { return nil }
    feed.setRequest(nil)
    request?.endAudio()
    beginSegment()
    return segment
  }

  private func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
  }

  /// For host output when not listening (no-mic mode, or before listening):
  /// `.playback` so the host is heard even with the silent switch on.
  private func ensurePlaybackSession() {
    guard !listening else { return }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
    try? session.setActive(true)
  }

  // MARK: - Host voice and sound effects

  /// Recognition hears nothing while the host speaks or a sound plays, and
  /// for 150 ms after (SPEC.md §7), so transcripts never contain the host.
  private func applyGate() {
    feed.setGated(paused || hostOutputs > 0 || reopenWork != nil)
  }

  private func beginHostOutput() {
    hostOutputs += 1
    reopenWork?.cancel()
    reopenWork = nil
    applyGate()
  }

  private func endHostOutput() {
    hostOutputs = max(0, hostOutputs - 1)
    guard hostOutputs == 0 else { return }
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.reopenWork = nil
        self.applyGate()
      }
    }
    reopenWork = work
    applyGate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  }

  private func speak(_ text: String, result: @escaping FlutterResult) {
    ensurePlaybackSession()
    beginHostOutput()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = Self.hostVoice()
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 1.05
    pendingSpeech[ObjectIdentifier(utterance)] = result
    synthesizer.speak(utterance)
  }

  /// Called by [SynthDelegate] when an utterance finishes or is cancelled.
  func utteranceDone(_ id: ObjectIdentifier) {
    guard let result = pendingSpeech.removeValue(forKey: id) else { return }
    endHostOutput()
    result(nil)
  }

  /// Best English voice available: premium, then enhanced, then default.
  private static func hostVoice() -> AVSpeechSynthesisVoice? {
    let preferred = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    let language = preferred.hasPrefix("en") ? preferred : "en-US"
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
    if let best = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
      return best
    }
    return AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
  }

  /// Plays `assets/sfx/<name>.wav` from the Flutter assets. Missing files are
  /// skipped quietly; the game never waits on a sound that can't play.
  private func playSound(_ name: String, result: @escaping FlutterResult) {
    let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "_" }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sfx/\(safe).wav")
    guard !safe.isEmpty, let path = Bundle.main.path(forResource: key, ofType: nil),
      let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    else {
      result(nil)
      return
    }
    ensurePlaybackSession()
    beginHostOutput()
    let delegate = PlayerDelegate(bridge: self)
    player.delegate = delegate
    let id = ObjectIdentifier(player)
    players[id] = (player, delegate, result)
    if !player.play() {
      soundDone(id)
    }
  }

  /// Called by [PlayerDelegate] when a sound finishes or fails.
  func soundDone(_ id: ObjectIdentifier) {
    guard let (_, _, result) = players.removeValue(forKey: id) else { return }
    endHostOutput()
    result(nil)
  }

  private func startEngine() throws {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.noInput }
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: RecognitionFeed.makeTap(feed))
    engine.prepare()
    try engine.start()
  }

  private func beginSegment() {
    guard let recognizer else { return }
    // Don't let finished-but-silent segments pile up.
    while tasks.count >= 4, let oldest = tasks.keys.min() {
      tasks.removeValue(forKey: oldest)?.cancel()
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    request.addsPunctuation = true
    request.taskHint = .dictation
    segment += 1
    segmentStartedAt = Date()
    self.request = request
    feed.setRequest(request)
    tasks[segment] = recognizer.recognitionTask(
      with: request, resultHandler: Self.makeResultHandler(bridge: self, segment: segment))
  }

  /// Built outside the main actor so the callback isn't inferred as main-actor
  /// isolated; it hops to the main actor itself.
  nonisolated private static func makeResultHandler(bridge: SpeechBridge, segment: Int)
    -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
  {
    return { [weak bridge] result, error in
      let text = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal ?? false
      let nsError = error as NSError?
      let errorCode = nsError?.code
      let errorMessage = nsError?.localizedDescription
      Task { @MainActor in
        bridge?.handleResult(
          segment: segment, text: text, isFinal: isFinal,
          errorCode: errorCode, errorMessage: errorMessage)
      }
    }
  }

  private func handleResult(
    segment seg: Int, text: String?, isFinal: Bool, errorCode: Int?, errorMessage: String?
  ) {
    // Text from an ended segment still counts: Dart files it by segment id.
    if let text, !text.isEmpty {
      stream.send([
        "type": isFinal ? "final" : "partial", "text": text, "seg": seg, "t": nowMs(),
      ])
    }
    guard isFinal || errorCode != nil else { return }
    tasks.removeValue(forKey: seg)

    if let errorCode, !Self.isBenign(errorCode) {
      stream.send([
        "type": "error", "code": "RECOGNIZER_\(errorCode)",
        "message": errorMessage ?? "", "t": nowMs(),
      ])
    }
    // Only the current segment restarts listening.
    guard seg == segment, listening, !paused else { return }

    // The recognizer ends segments on long silence or errors. Keep listening
    // with a fresh segment, but don't spin if it keeps failing straight away.
    if Date().timeIntervalSince(segmentStartedAt) < 1.0 {
      quickFailures += 1
    } else {
      quickFailures = 0
    }
    if quickFailures >= 5 {
      stream.send([
        "type": "error", "code": "RECOGNIZER_FAILING",
        "message": "Speech recognition keeps stopping. Try again in a moment.", "t": nowMs(),
      ])
      stopListening()
      return
    }
    beginSegment()
  }

  /// 1110: no speech detected. 216 / 301: request cancelled (we do this ourselves).
  nonisolated private static func isBenign(_ code: Int) -> Bool {
    code == 1110 || code == 216 || code == 301
  }

  // MARK: - Level meter (~10 Hz)

  private func startLevelTimer() {
    levelTimer?.invalidate()
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.listening else { return }
        self.stream.send(["type": "level", "level": Double(self.feed.takeLevel()), "t": nowMs()])
      }
    }
  }

  // MARK: - Audio interruptions and route changes

  private func observeAudioNotifications() {
    removeAudioNotifications()
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.recoverEngine() }
      })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let ended = raw.flatMap { AVAudioSession.InterruptionType(rawValue: $0) } == .ended
        MainActor.assumeIsolated {
          if ended {
            self?.recoverEngine()
          } else {
            self?.sendState("interrupted")
          }
        }
      })
  }

  private func removeAudioNotifications() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func recoverEngine() {
    guard listening else { return }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    do {
      try configureAudioSession()
      try startEngine()
      if !paused { beginSegment() }
      sendState(paused ? "paused" : "listening")
    } catch {
      stream.send([
        "type": "error", "code": "AUDIO_RESTART_FAILED",
        "message": error.localizedDescription, "t": nowMs(),
      ])
    }
  }

  private func sendState(_ state: String) {
    stream.send(["type": "state", "state": state, "t": nowMs()])
  }
}

enum SpeechError: Error {
  case micDenied
  case speechDenied
  case unavailable
  case onDeviceUnavailable
  case noInput

  var code: String {
    switch self {
    case .micDenied: return "MIC_DENIED"
    case .speechDenied: return "SPEECH_DENIED"
    case .unavailable: return "RECOGNIZER_UNAVAILABLE"
    case .onDeviceUnavailable: return "ON_DEVICE_UNAVAILABLE"
    case .noInput: return "NO_AUDIO_INPUT"
    }
  }

  var message: String {
    switch self {
    case .micDenied: return "Microphone access is off."
    case .speechDenied: return "Speech recognition access is off."
    case .unavailable: return "Speech recognition isn't available right now."
    case .onDeviceUnavailable:
      return "On-device speech recognition isn't available for this language on this iPhone."
    case .noInput: return "No microphone input found."
    }
  }
}

/// Hands mic buffers to the current recognition request. Called on the audio
/// thread, so it's lock-protected and has no actor isolation.
final class RecognitionFeed: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var gated = false
  private var peak: Float = 0

  func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
    lock.withLock { self.request = request }
  }

  func setGated(_ gated: Bool) {
    lock.withLock { self.gated = gated }
  }

  /// Peak level (0...1) since the last call.
  func takeLevel() -> Float {
    lock.withLock {
      let value = peak
      peak = 0
      return value
    }
  }

  func consume(_ buffer: AVAudioPCMBuffer) {
    let level = Self.level(of: buffer)
    let target: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
      peak = max(peak, level)
      return gated ? nil : request
    }
    target?.append(buffer)
  }

  /// RMS mapped from about -60 dBFS...0 dBFS to 0...1.
  static func level(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let samples = channels[0]
    let count = Int(buffer.frameLength)
    var sum: Float = 0
    for index in 0..<count {
      sum += samples[index] * samples[index]
    }
    let rms = (sum / Float(count)).squareRoot()
    let db = 20 * log10(max(rms, 1e-6))
    return min(max((db + 60) / 60, 0), 1)
  }

  static func makeTap(_ feed: RecognitionFeed) -> AVAudioNodeTapBlock {
    return { buffer, _ in
      feed.consume(buffer)
    }
  }
}

/// Forwards AVSpeechSynthesizer callbacks to the bridge on the main actor.
final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
  private weak var bridge: SpeechBridge?

  init(bridge: SpeechBridge) {
    self.bridge = bridge
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak bridge] in bridge?.utteranceDone(id) }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak bridge] in bridge?.utteranceDone(id) }
  }
}

/// Forwards AVAudioPlayer callbacks to the bridge on the main actor.
final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
  private weak var bridge: SpeechBridge?

  init(bridge: SpeechBridge) {
    self.bridge = bridge
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let id = ObjectIdentifier(player)
    Task { @MainActor [weak bridge] in bridge?.soundDone(id) }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    let id = ObjectIdentifier(player)
    Task { @MainActor [weak bridge] in bridge?.soundDone(id) }
  }
}
