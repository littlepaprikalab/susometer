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
