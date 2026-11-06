// Minimal Speech framework stand-in.
import Foundation
import AVFoundation

public enum SFSpeechRecognizerAuthorizationStatus: Int, Sendable {
  case notDetermined, denied, restricted, authorized
}
public enum SFSpeechRecognitionTaskHint: Int, Sendable { case unspecified, dictation, search, confirmation }

open class SFTranscription: NSObject { open var formattedString: String { "" } }
open class SFSpeechRecognitionResult: NSObject {
  open var bestTranscription: SFTranscription { SFTranscription() }
  open var isFinal: Bool { false }
}
open class SFSpeechRecognitionTask: NSObject {
  open func cancel() {}
  open func finish() {}
}
open class SFSpeechRecognitionRequest: NSObject {
  open var shouldReportPartialResults = true
  open var requiresOnDeviceRecognition = false
  open var addsPunctuation = false
  open var taskHint: SFSpeechRecognitionTaskHint = .unspecified
}
open class SFSpeechAudioBufferRecognitionRequest: SFSpeechRecognitionRequest {
  public override init() {}
  open func append(_ audioPCMBuffer: AVAudioPCMBuffer) {}
  open func endAudio() {}
}
open class SFSpeechRecognizer {
  public init?() { nil }
  public init?(locale: Locale) { nil }
  open var supportsOnDeviceRecognition: Bool { false }
  public class func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { .notDetermined }
  public class func requestAuthorization(_ handler: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {}
  open func recognitionTask(with request: SFSpeechRecognitionRequest, resultHandler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void) -> SFSpeechRecognitionTask { SFSpeechRecognitionTask() }
}
