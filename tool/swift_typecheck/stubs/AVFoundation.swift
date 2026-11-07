// Minimal AVFoundation (audio) stand-in.
@_exported import Foundation

open class AVAudioTime: NSObject {}
open class AVAudioFormat: NSObject {
  open var sampleRate: Double { 44100 }
  open var channelCount: UInt32 { 1 }
}
open class AVAudioPCMBuffer: NSObject {
  open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { nil }
  open var frameLength: UInt32 { 0 }
}
public typealias AVAudioNodeTapBlock = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
public typealias AVAudioNodeBus = Int
public typealias AVAudioFrameCount = UInt32

open class AVAudioInputNode: NSObject {
  open func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { AVAudioFormat() }
  open func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block tapBlock: @escaping AVAudioNodeTapBlock) {}
  open func removeTap(onBus bus: AVAudioNodeBus) {}
}

open class AVAudioEngine: NSObject {
  public override init() {}
  open var inputNode: AVAudioInputNode { AVAudioInputNode() }
  open func prepare() {}
  open var isRunning: Bool { false }
  open func start() throws {}
  open func stop() {}
}

extension Notification.Name {
  public static let AVAudioEngineConfigurationChange = Notification.Name("AVAudioEngineConfigurationChange")
}
public let AVAudioSessionInterruptionTypeKey = "AVAudioSessionInterruptionTypeKey"

open class AVAudioSession: NSObject {
  public static func sharedInstance() -> AVAudioSession { AVAudioSession() }
  public struct Category: Hashable, Sendable { public static let playAndRecord = Category() }
  public struct Mode: Hashable, Sendable { public static let `default` = Mode() }
  public struct CategoryOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let defaultToSpeaker = CategoryOptions(rawValue: 8)
  }
  public struct SetActiveOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1)
  }
  public enum InterruptionType: UInt, Sendable { case began = 1, ended = 0 }
  public static let interruptionNotification = Notification.Name("AVAudioSessionInterruptionNotification")
  open func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {}
  open func setActive(_ active: Bool, options: SetActiveOptions = []) throws {}
}

open class AVAudioApplication: NSObject {
  public enum recordPermission: Int, Sendable { case undetermined, denied, granted }
  public static var shared: AVAudioApplication { AVAudioApplication() }
  open var recordPermission: AVAudioApplication.recordPermission { .undetermined }
  public class func requestRecordPermission() async -> Bool { false }
}

public struct AVMediaType: Hashable, Sendable {
  public let rawValue: String
  public static let video = AVMediaType(rawValue: "vide")
}

public enum AVAuthorizationStatus: Int, Sendable { case notDetermined, restricted, denied, authorized }

open class AVCaptureDevice: NSObject {
  public class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus { .notDetermined }
  public class func requestAccess(for mediaType: AVMediaType) async -> Bool { false }
}

extension AVAudioSession.Category {
  public static let playback = AVAudioSession.Category()
}
extension AVAudioSession.CategoryOptions {
  public static let duckOthers = AVAudioSession.CategoryOptions(rawValue: 2)
}

public enum AVSpeechBoundary: Int, Sendable { case immediate, word }
public enum AVSpeechSynthesisVoiceQuality: Int, Sendable { case `default` = 1, enhanced, premium }
public enum AVSpeechSynthesisVoiceGender: Int, Sendable { case unspecified, male, female }
public let AVSpeechUtteranceDefaultSpeechRate: Float = 0.5

open class AVSpeechSynthesisVoice: NSObject {
  public struct Traits: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let isNoveltyVoice = Traits(rawValue: 1)
    public static let isPersonalVoice = Traits(rawValue: 2)
  }
  public init?(language: String?) { nil }
  open class func speechVoices() -> [AVSpeechSynthesisVoice] { [] }
  open var identifier: String { "" }
  open var name: String { "" }
  open var language: String { "en-US" }
  open var quality: AVSpeechSynthesisVoiceQuality { .default }
  open var gender: AVSpeechSynthesisVoiceGender { .unspecified }
  open var voiceTraits: Traits { [] }
}

open class AVSpeechUtterance: NSObject {
  public init(string: String) {}
  open var voice: AVSpeechSynthesisVoice?
  open var rate: Float = 0.5
  open var pitchMultiplier: Float = 1
}

public protocol AVSpeechSynthesizerDelegate: NSObjectProtocol {
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance)
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
}

open class AVSpeechSynthesizer: NSObject {
  public static let availableVoicesDidChangeNotification = Notification.Name(
    "AVSpeechSynthesizerAvailableVoicesDidChangeNotification")
  public override init() {}
  open weak var delegate: AVSpeechSynthesizerDelegate?
  open var isSpeaking: Bool { false }
  open func speak(_ utterance: AVSpeechUtterance) {}
  @discardableResult open func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { true }
}

public protocol AVAudioPlayerDelegate: NSObjectProtocol {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?)
}

open class AVAudioPlayer: NSObject {
  public init(contentsOf url: URL) throws {}
  open weak var delegate: AVAudioPlayerDelegate?
  open var duration: TimeInterval { 0 }
  open func play() -> Bool { true }
  open func stop() {}
}
