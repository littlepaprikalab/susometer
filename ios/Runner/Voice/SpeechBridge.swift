import AVFoundation
import Flutter
import Foundation
import Speech
import UIKit

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
  private var speech = HostSpeech<FlutterResult>()
  private var settleWork: DispatchWorkItem?
  /// The host's voice, chosen on the first line and again after the
  /// installed voices may have changed (decision 73). Reading the voice list
  /// builds an object for every voice on the phone, so it isn't read for
  /// every line.
  private var hostVoice: AVSpeechSynthesisVoice?
  private var hostVoiceStale = true
  private var players: [ObjectIdentifier: (AVAudioPlayer, PlayerDelegate, FlutterResult)] = [:]
  private var reopenWork: DispatchWorkItem?
  private var engineRetry: DispatchWorkItem?

  private init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(stream)
    let delegate = SynthDelegate(bridge: self)
    synthDelegate = delegate
    synthesizer.delegate = delegate
    // A voice downloaded or deleted in Settings, or a new region, means the
    // choice may change. The bridge lives as long as the app, so these stay.
    for name in [
      AVSpeechSynthesizer.availableVoicesDidChangeNotification,
      UIApplication.didBecomeActiveNotification,
    ] {
      _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.hostVoiceStale = true }
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
      stopSpeaking()
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
    engineRetry?.cancel()
    engineRetry = nil
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
    feed.setGated(paused || hostBusy || reopenWork != nil)
  }

  /// Host output that may still be playing: utterances and sounds that
  /// haven't reported finishing (or been given up on, see [HostSpeech] and
  /// `playSound`). Read from what's out, not a counter, so a lost callback
  /// can't hold the gate shut for good.
  private var hostBusy: Bool { speech.busy || !players.isEmpty }

  /// Call after recording the utterance or sound as out.
  private func beginHostOutput() {
    reopenWork?.cancel()
    reopenWork = nil
    applyGate()
  }

  /// Call after an utterance or sound is no longer out. The mic reopens
  /// 150 ms after the last host output ends.
  private func endHostOutput() {
    guard !hostBusy else { return }
    reopenWork?.cancel()
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
    let utterance = AVSpeechUtterance(string: text)
    if hostVoiceStale {
      hostVoice = Self.chooseHostVoice()
      hostVoiceStale = false
    }
    utterance.voice = hostVoice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 1.05
    speech.spoke(utterance, reply: result)
    beginHostOutput()
    synthesizer.speak(utterance)
  }

  /// Called by [SynthDelegate] when an utterance starts playing.
  func utteranceStarted(_ id: ObjectIdentifier) {
    // It was stopped before it started and iOS played it anyway.
    if speech.shouldStopAgain(started: id) {
      synthesizer.stopSpeaking(at: .immediate)
    }
  }

  /// Called by [SynthDelegate] when an utterance finishes or is cancelled.
  func utteranceDone(_ id: ObjectIdentifier) {
    let (wasOut, reply) = speech.ended(id)
    guard wasOut else { return }
    endHostOutput()
    reply?(nil)
  }

  /// Stops the host mid-sentence (a new question, solo "Ready to answer",
  /// pause, end of turn, or Dart's speak timeout). Dart's waiting `speak`
  /// calls complete now; the mic stays gated until the stopped utterances
  /// report back, or at most about 3 s if they never do (decision 71).
  private func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate)
    for reply in speech.stop() {
      reply(nil)
    }
    if speech.stoppedCount > 0 { scheduleSettle(attempt: 1) }
  }

  private func scheduleSettle(attempt: Int) {
    settleWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.settleWork = nil
        self.settleStopped(attempt: attempt)
      }
    }
    settleWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
  }

  /// A second after a stop: stop again if a stopped utterance is still
  /// playing, and give up on any that never reported back.
  private func settleStopped(attempt: Int) {
    switch speech.settle(synthesizerSpeaking: synthesizer.isSpeaking, lastTry: attempt >= 3) {
    case .done:
      break
    case .stopAgain:
      synthesizer.stopSpeaking(at: .immediate)
      scheduleSettle(attempt: attempt + 1)
    case .dropped:
      endHostOutput()
    }
  }

  /// The host's voice: the most natural British female voice installed, else
  /// the best English voice (decisions 33 and 73; [HostVoice] has the rules).
  private static func chooseHostVoice() -> AVSpeechSynthesisVoice? {
    let preferred = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    let language = preferred.hasPrefix("en") ? preferred : "en-US"
    let systemDefault =
      AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let candidates = voices.map { voice in
      HostVoice.Candidate(
        identifier: voice.identifier,
        name: voice.name,
        language: voice.language,
        quality: voice.quality.rawValue,
        gender: voice.gender == .female ? .female : (voice.gender == .male ? .male : .unspecified),
        isNoveltyOrPersonal: voice.voiceTraits.contains(.isNoveltyVoice)
          || voice.voiceTraits.contains(.isPersonalVoice))
    }
    guard
      let best = HostVoice.best(
        candidates, userLanguage: language, systemDefault: systemDefault?.identifier)
    else { return systemDefault }
    return voices[best]
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
    let delegate = PlayerDelegate(bridge: self)
    player.delegate = delegate
    let id = ObjectIdentifier(player)
    players[id] = (player, delegate, result)
    beginHostOutput()
    if !player.play() {
      soundDone(id)
      return
    }
    // A sound paused by an interruption (a call, Siri) or cut off when the
    // audio session is deactivated never reports finishing. Give it its
    // length plus a second, then stop it and stop gating the mic for it.
    let deadline = player.duration + 1.0
    DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { [weak self, weak player] in
      MainActor.assumeIsolated {
        guard let self, let player, self.players[id]?.0 === player else { return }
        player.stop()
        self.soundDone(id)
      }
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
    observers.append(
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          // iOS doesn't always send an interruption's end. If the engine is
          // still down once the app is back in front, restart it.
          guard let self, self.listening, !self.engine.isRunning else { return }
          self.recoverEngine()
        }
      })
  }

  private func removeAudioNotifications() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func recoverEngine(attempt: Int = 0) {
    engineRetry?.cancel()
    engineRetry = nil
    guard listening else { return }
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    do {
      try configureAudioSession()
      try startEngine()
      if !paused {
        // Close the old segment so its last words still arrive.
        feed.setRequest(nil)
        request?.endAudio()
        beginSegment()
      }
      sendState(paused ? "paused" : "listening")
    } catch {
      // A new route can take a moment: the input reads 0 Hz while a headset
      // switches, and the session can refuse to activate just after an
      // interruption. Retry for about 4 s before giving up (Dart then goes
      // tap-to-advance for the rest of the turn).
      if attempt < 4 {
        let work = DispatchWorkItem { [weak self] in
          MainActor.assumeIsolated { self?.recoverEngine(attempt: attempt + 1) }
        }
        engineRetry = work
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 0.25 * Double(1 << attempt), execute: work)
        return
      }
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
    _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak bridge] in bridge?.utteranceStarted(id) }
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

/// Which installed voice the host speaks with (SPEC.md decisions 33 and 73).
/// Pure, so tool/swift_typecheck/HostVoiceTests.swift can check it on Linux.
///
/// The host is a British woman: an en-GB female voice beats every other
/// voice, whatever its quality. A voice that reports no gender counts as
/// female if it's one of Apple's British women (Kate, Martha, Serena,
/// Stephanie). Then quality: premium, then enhanced, then standard. iOS only
/// ships the standard ("compact") voices; enhanced and premium ones show up
/// once the user downloads one in Settings > Accessibility > Spoken Content >
/// Voices > English. Ties go to the user's own English variant, then en-US,
/// then a Siri-derived voice (Martha, say, which sounds more natural than the
/// older compact ones), then the voice iOS uses for that language, then the
/// first in iOS's list. With no British female voice installed, this is the
/// old choice: the best English voice.
///
/// Novelty, personal and legacy voices (Albert, Bells, Zarvox, Fred,
/// Eloquence's Eddy, Flo or Shelley…) are never picked. They're English and
/// the same "default" quality as Samantha, some are British and female, so
/// without this filter a tie could land on one of them, and they're the
/// robotic ones.
enum HostVoice {
  static let british = "en-GB"

  /// Apple's British female voices, by name, for one that reports no gender.
  static let britishWomen: Set<String> = ["Kate", "Martha", "Serena", "Stephanie"]

  enum Gender { case female, male, unspecified }

  /// What the choice looks at for one installed voice.
  struct Candidate {
    var identifier: String
    var name: String
    var language: String
    /// `AVSpeechSynthesisVoiceQuality.rawValue`: 1 default, 2 enhanced,
    /// 3 premium.
    var quality: Int
    var gender: Gender
    var isNoveltyOrPersonal = false
  }

  static func isBritishWoman(_ voice: Candidate) -> Bool {
    guard voice.language == british else { return false }
    switch voice.gender {
    case .female: return true
    case .male: return false
    case .unspecified:
      // "Serena" or, if a name ever carries it, "Serena (Premium)".
      let first = voice.name.split(separator: " ").first.map(String.init) ?? ""
      return britishWomen.contains(first)
    }
  }

  static func usable(_ voice: Candidate) -> Bool {
    voice.language.hasPrefix("en")
      && !voice.isNoveltyOrPersonal
      && !voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
      && !voice.identifier.hasPrefix("com.apple.eloquence.")
  }

  /// Index in [voices] of the one to use, or nil if none is usable.
  /// [userLanguage] is the user's English variant ("en-AU"), or "en-US".
  static func best(_ voices: [Candidate], userLanguage: String, systemDefault: String?) -> Int? {
    func rank(_ voice: Candidate) -> (Int, Int, Int, Int, Int) {
      let britishFemale = isBritishWoman(voice) ? 1 : 0
      let place = voice.language == userLanguage ? 2 : (voice.language == "en-US" ? 1 : 0)
      let siri = voice.identifier.lowercased().contains("siri") ? 1 : 0
      let isSystemDefault = voice.identifier == systemDefault ? 1 : 0
      return (britishFemale, voice.quality, place, siri, isSystemDefault)
    }
    // Each rank once; on a tie the first in iOS's list wins.
    var best: (index: Int, rank: (Int, Int, Int, Int, Int))?
    for (i, voice) in voices.enumerated() where usable(voice) {
      let r = rank(voice)
      if best.map({ $0.rank < r }) ?? true { best = (i, r) }
    }
    return best?.index
  }
}

/// The host's utterances that are still out, for the half-duplex gate
/// (SPEC.md §7, decision 71). Pure bookkeeping, so
/// tool/swift_typecheck/HostSpeechTests.swift can drive it on Linux;
/// [SpeechBridge] makes the AVSpeechSynthesizer calls it asks for.
///
/// An utterance keeps the mic gated from `speak` until the synthesizer says it
/// finished or was cancelled. iOS promises neither that every utterance a stop
/// drops reports back, nor that a stopped utterance never starts after all.
/// So `stop` hands every reply back at once (Dart moves on), the gate stays
/// shut while a stopped utterance might still play, and `settle` gives up on
/// the ones that never report back.
struct HostSpeech<Reply> {
  private struct Entry {
    /// Held so its identifier can't be reused while it's out.
    let utterance: AnyObject
    /// Dart's waiting `speak` call; nil once the utterance was stopped.
    var reply: Reply?
  }

  private var entries: [ObjectIdentifier: Entry] = [:]

  /// Something may still be playing, so the mic stays gated.
  var busy: Bool { !entries.isEmpty }

  /// Dart is still waiting for one of them.
  var awaited: Bool { entries.values.contains { $0.reply != nil } }

  /// Stopped utterances that haven't reported back yet.
  var stoppedCount: Int { entries.values.filter { $0.reply == nil }.count }

  mutating func spoke(_ utterance: AnyObject, reply: Reply) {
    entries[ObjectIdentifier(utterance)] = Entry(utterance: utterance, reply: reply)
  }

  /// The synthesizer finished or cancelled [id]. `wasOut` is false for a
  /// callback that arrives after `settle` gave up on it; `reply` is set if
  /// Dart is still waiting.
  mutating func ended(_ id: ObjectIdentifier) -> (wasOut: Bool, reply: Reply?) {
    guard let entry = entries.removeValue(forKey: id) else { return (false, nil) }
    return (true, entry.reply)
  }

  /// [id] started playing. True when it had been stopped already and no
  /// utterance Dart waits for would be cut off, so the caller stops the
  /// synthesizer again.
  func shouldStopAgain(started id: ObjectIdentifier) -> Bool {
    guard let entry = entries[id], entry.reply == nil else { return false }
    return !awaited
  }

  /// The host was told to stop: every waiting reply goes back now. The
  /// utterances stay out until they report back or `settle` gives up.
  mutating func stop() -> [Reply] {
    var replies: [Reply] = []
    for id in Array(entries.keys) {
      if let reply = entries[id]?.reply {
        replies.append(reply)
        entries[id]?.reply = nil
      }
    }
    return replies
  }

  enum Settle: Equatable {
    /// Every stopped utterance has reported back.
    case done
    /// Still playing with nothing awaited: stop again and settle later.
    case stopAgain
    /// Gave up on the stopped ones that never reported back.
    case dropped
  }

  /// A while after a stop, for the stopped utterances still out.
  mutating func settle(synthesizerSpeaking: Bool, lastTry: Bool) -> Settle {
    guard stoppedCount > 0 else { return .done }
    // While Dart waits for a newer utterance, that one holds the gate, and
    // the synthesizer plays in order, so anything stopped would come out
    // before it. Otherwise the synthesizer itself says whether it's quiet.
    if synthesizerSpeaking && !awaited && !lastTry { return .stopAgain }
    entries = entries.filter { $0.value.reply != nil }
    return .dropped
  }
}
