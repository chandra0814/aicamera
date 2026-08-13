import Foundation

public struct SceneDebugState: Equatable, Sendable {
    public let frameId: String
    public let timestamp: Date
    public let personBounds: [NormalizedRect]
    public let horizonY: Double?
    public let horizon: HorizonDebugMetric?
    public let exposureWarning: ExposureWarning?
    public let faceMetrics: [FaceDebugMetric]
    public let poseMetrics: [PoseDebugMetric]
    public let segmentationAvailable: Bool
    public let motion: MotionDebugMetric?
    public let frameLatencyMs: Double?

    public init(
        frameId: String,
        timestamp: Date,
        personBounds: [NormalizedRect],
        horizonY: Double?,
        horizon: HorizonDebugMetric? = nil,
        exposureWarning: ExposureWarning?,
        faceMetrics: [FaceDebugMetric] = [],
        poseMetrics: [PoseDebugMetric] = [],
        segmentationAvailable: Bool = false,
        motion: MotionDebugMetric? = nil,
        frameLatencyMs: Double?
    ) {
        self.frameId = frameId
        self.timestamp = timestamp
        self.personBounds = personBounds
        self.horizonY = horizonY
        self.horizon = horizon
        self.exposureWarning = exposureWarning
        self.faceMetrics = faceMetrics
        self.poseMetrics = poseMetrics
        self.segmentationAvailable = segmentationAvailable
        self.motion = motion
        self.frameLatencyMs = frameLatencyMs
    }
}

public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ExposureWarning: String, Equatable, Sendable {
    case underexposed
    case clippedHighlights = "clipped_highlights"
    case balanced
}

public struct HorizonDebugMetric: Equatable, Sendable {
    public let y: Double
    public let rollDegrees: Double
    public let confidence: Double

    public init(y: Double, rollDegrees: Double, confidence: Double) {
        self.y = y
        self.rollDegrees = rollDegrees
        self.confidence = confidence
    }
}

public struct FaceDebugMetric: Equatable, Sendable {
    public let bounds: NormalizedRect
    public let eyeOpenProbability: Double?
    public let expressionStability: Double?
    public let sharpnessProbability: Double?
    public let skinExposureScore: Double?
    public let faceYawDegrees: Double?

    public init(
        bounds: NormalizedRect,
        eyeOpenProbability: Double?,
        expressionStability: Double?,
        sharpnessProbability: Double?,
        skinExposureScore: Double?,
        faceYawDegrees: Double?
    ) {
        self.bounds = bounds
        self.eyeOpenProbability = eyeOpenProbability
        self.expressionStability = expressionStability
        self.sharpnessProbability = sharpnessProbability
        self.skinExposureScore = skinExposureScore
        self.faceYawDegrees = faceYawDegrees
    }
}

public struct PoseDebugMetric: Equatable, Sendable {
    public let bounds: NormalizedRect?
    public let shouldersAngleDegrees: Double?
    public let eyeLineConfidence: Double?
    public let handAwkwardnessRisk: Double?

    public init(
        bounds: NormalizedRect?,
        shouldersAngleDegrees: Double?,
        eyeLineConfidence: Double?,
        handAwkwardnessRisk: Double?
    ) {
        self.bounds = bounds
        self.shouldersAngleDegrees = shouldersAngleDegrees
        self.eyeLineConfidence = eyeLineConfidence
        self.handAwkwardnessRisk = handAwkwardnessRisk
    }
}

public struct MotionDebugMetric: Equatable, Sendable {
    public let cameraShake: Double
    public let subjectMotion: Double
    public let blurRisk: Double

    public init(cameraShake: Double, subjectMotion: Double, blurRisk: Double) {
        self.cameraShake = cameraShake
        self.subjectMotion = subjectMotion
        self.blurRisk = blurRisk
    }
}
