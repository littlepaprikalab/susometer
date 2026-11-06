// Stand-in for SmartSpectra 3.4.0, copied from the public .swiftinterface for
// every declaration Sus-o-meter uses. Built with library evolution, like the
// real binary, so enums are non-frozen.
import Foundation
import UIKit
import Observation

public enum CameraSelection: Sendable, Equatable { case `default`, front, back, byId(String) }

public enum ProcessingStatus: Sendable, Equatable { case idle, starting, running, stopping, error }

public struct SmartSpectraError: Error, Sendable, Equatable {
  public let code: Code
  public let message: String
  public let retryable: Bool
  public enum Code: Int, Sendable {
    case invalidState = 1, authenticationFailed, configurationFailed, creditExhausted, networkError,
      serverError, inputUnavailable, processingFailed, frameConversionFailed, nonMonotonicTimestamp,
      timestampGap
  }
}
extension SmartSpectraError: LocalizedError {
  public var errorDescription: String? { message }
}

public struct ValidationStatus: Sendable, Equatable {
  public let code: ValidationCode
  public let hint: String
}

public enum ValidationCode: Int, Sendable, Equatable {
  case ok = 0, noFaceFound, multipleFacesFound, faceNotCentered
  @available(*, deprecated, message: "Use .faceTooClose / .faceTooFar instead")
  case faceSizeOutOfRange
  case tooDark, tooBright, chestNotVisible
  case cameraTuning = 10, frameRateTooLow, excessiveMotion, faceTooClose, faceTooFar, faceTooHigh,
    faceTooLow, faceNotForward
}

public enum MetricType: Hashable, Sendable, CaseIterable {
  case chestBreathing, abdomenBreathing, breathingRate, breathingAmplitude, apnea,
    respiratoryLineLength, baseline, inhaleExhaleRatio, glutesMicromotion, kneesMicromotion,
    edaTrace, faceLandmarks, blinking, talking, expressions, pulseRate, arterialPressureTrace, hrv,
    pulseRateStrict, breathingRateStrict
  case UNRECOGNIZED(Int)
  public static let allCases: [MetricType] = []
}

public enum ExpressionType: Hashable, Sendable {
  case unspecified, angry, contempt, disgust, fear, happy, neutral, sad, surprise
  case UNRECOGNIZED(Int)
}

public struct Measurement: Sendable { public var value: Float = 0; public var stable = false; public var timestamp: Int64 = 0; public init() {} }
public struct DetectionStatus: Sendable { public var detected = false; public var stable = false; public var timestamp: Int64 = 0; public init() {} }
public struct MeasurementWithConfidence: Sendable { public var value: Float = 0; public var stable = false; public var confidence: Float = 0; public var timestamp: Int64 = 0; public init() {} }
public struct ExpressionScore: Sendable { public var type: ExpressionType = .unspecified; public var confidence: Float = 0; public init() {} }
public struct Expression: Sendable { public var stable = false; public var timestamp: Int64 = 0; public var scores: [ExpressionScore] = []; public init() {} }
public struct Hrv: Sendable { public var rmssd: Double = 0; public var meanNn: Double = 0; public var sdnn: Double = 0; public var baevsky: Double = 0; public var timestamp: Int64 = 0; public var confidence: Float = 0; public var stable = false; public init() {} }
public struct Face: Sendable { public var blinking: [DetectionStatus] = []; public var talking: [DetectionStatus] = []; public var expression: [Expression] = []; public init() {} }
public struct Cardio: Sendable { public var pulseRate: [MeasurementWithConfidence] = []; public var arterialPressureTrace: [MeasurementWithConfidence] = []; public var hrv: [Hrv] = []; public init() {} }
public struct Metrics: @unchecked Sendable { public var cardio = Cardio(); public var face = Face(); public init() {} }
public struct Insight: Sendable { public var requestID: Int32 = 0; public init() {} }

@MainActor final public class SmartSpectraConfig {
  final public var imageOutputEnabled: Bool = true
  final public var enableTelemetry: Bool = true
  final public var apiKey: String?
  final public var requestedMetrics: [MetricType]?
  public init() {}
}
extension SmartSpectraConfig {
  nonisolated public static let breathingMetrics: [MetricType] = []
  nonisolated public static let cardioMetrics: [MetricType] = []
}

@MainActor final public class SmartSpectraSDK {
  public static let shared = SmartSpectraSDK(config: SmartSpectraConfig())
  final public var metrics: Metrics? { nil }
  final public var imageOutput: UIImage? { nil }
  final public var processingStatus: ProcessingStatus { .idle }
  final public var error: SmartSpectraError? { nil }
  final public var validationStatus: ValidationStatus? { nil }
  final public var insight: Insight? { nil }
  nonisolated public static var version: String { "3.4.0" }
  final public let config: SmartSpectraConfig
  public init(config: SmartSpectraConfig) { self.config = config }
  final public func start() async throws {}
  final public func stop() async throws {}
  final public func reset() async throws {}
  final public func useCamera(_ selection: CameraSelection) throws {}
}
