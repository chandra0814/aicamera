import Foundation

public struct SceneState: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let frameId: String
    public let cameraState: LiveCameraState
    public let deviceThermal: ThermalState?
    public let scene: SceneSummary
    public let subjects: [SubjectObservation]
    public let background: BackgroundState
    public let motion: MotionState
    public let composition: CompositionState
    public let safety: SafetyState

    public init(
        timestamp: Date,
        frameId: String,
        cameraState: LiveCameraState,
        deviceThermal: ThermalState?,
        scene: SceneSummary,
        subjects: [SubjectObservation],
        background: BackgroundState,
        motion: MotionState,
        composition: CompositionState,
        safety: SafetyState
    ) {
        self.timestamp = timestamp
        self.frameId = frameId
        self.cameraState = cameraState
        self.deviceThermal = deviceThermal
        self.scene = scene
        self.subjects = subjects
        self.background = background
        self.motion = motion
        self.composition = composition
        self.safety = safety
    }
}

public struct LiveCameraState: Codable, Equatable, Sendable {
    public let lensId: String
    public let focalLength35mmEquivalent: Double?
    public let zoomFactor: Double
    public let exposureBias: Double?
    public let orientation: Orientation
    public let rollDegrees: Double
    public let pitchDegrees: Double?

    public init(
        lensId: String,
        focalLength35mmEquivalent: Double?,
        zoomFactor: Double,
        exposureBias: Double?,
        orientation: Orientation,
        rollDegrees: Double,
        pitchDegrees: Double?
    ) {
        self.lensId = lensId
        self.focalLength35mmEquivalent = focalLength35mmEquivalent
        self.zoomFactor = zoomFactor
        self.exposureBias = exposureBias
        self.orientation = orientation
        self.rollDegrees = rollDegrees
        self.pitchDegrees = pitchDegrees
    }

    public enum Orientation: String, Codable, Sendable {
        case portrait
        case landscapeLeft = "landscape_left"
        case landscapeRight = "landscape_right"
    }
}

public enum ThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct SceneSummary: Codable, Equatable, Sendable {
    public let category: Category
    public let confidence: Double
    public let lighting: LightingState
    public let horizon: HorizonState?
    public let sky: SkyState?

    public init(category: Category, confidence: Double, lighting: LightingState, horizon: HorizonState?, sky: SkyState?) {
        self.category = category
        self.confidence = confidence
        self.lighting = lighting
        self.horizon = horizon
        self.sky = sky
    }

    public enum Category: String, Codable, Sendable {
        case portrait
        case landscape
        case cityscape
        case beach
        case mountain
        case indoor
        case night
        case unknown
    }
}

public struct LightingState: Codable, Equatable, Sendable {
    public let exposureMean: Double
    public let highlightClipping: Double
    public let shadowClipping: Double
    public let faceLightQuality: Double?
    public let direction: Direction?
    public let dynamicRangeRisk: Double

    public init(
        exposureMean: Double,
        highlightClipping: Double,
        shadowClipping: Double,
        faceLightQuality: Double?,
        direction: Direction?,
        dynamicRangeRisk: Double
    ) {
        self.exposureMean = exposureMean
        self.highlightClipping = highlightClipping
        self.shadowClipping = shadowClipping
        self.faceLightQuality = faceLightQuality
        self.direction = direction
        self.dynamicRangeRisk = dynamicRangeRisk
    }

    public enum Direction: String, Codable, Sendable {
        case front
        case frontLeft = "front_left"
        case frontRight = "front_right"
        case side
        case backlit
        case unknown
    }
}

public struct HorizonState: Codable, Equatable, Sendable {
    public let y: Double
    public let rollDegrees: Double
    public let confidence: Double

    public init(y: Double, rollDegrees: Double, confidence: Double) {
        self.y = y
        self.rollDegrees = rollDegrees
        self.confidence = confidence
    }
}

public struct SkyState: Codable, Equatable, Sendable {
    public let visibleFraction: Double
    public let sunsetLikelihood: Double
    public let cloudInterest: Double
    public let highlightRisk: Double

    public init(visibleFraction: Double, sunsetLikelihood: Double, cloudInterest: Double, highlightRisk: Double) {
        self.visibleFraction = visibleFraction
        self.sunsetLikelihood = sunsetLikelihood
        self.cloudInterest = cloudInterest
        self.highlightRisk = highlightRisk
    }
}

public struct SubjectObservation: Codable, Equatable, Sendable {
    public let id: String
    public let type: SubjectType
    public let bounds: NormalizedRectangle
    public let segmentationAvailable: Bool
    public let pose: PoseState?
    public let face: FaceQualityState?
    public let distanceEstimateMeters: Double?
    public let confidence: Double

    public init(
        id: String,
        type: SubjectType,
        bounds: NormalizedRectangle,
        segmentationAvailable: Bool,
        pose: PoseState?,
        face: FaceQualityState?,
        distanceEstimateMeters: Double?,
        confidence: Double
    ) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.segmentationAvailable = segmentationAvailable
        self.pose = pose
        self.face = face
        self.distanceEstimateMeters = distanceEstimateMeters
        self.confidence = confidence
    }
}

public enum SubjectType: String, Codable, Sendable {
    case person
    case face
    case vehicle
    case animal
    case object
}

public struct PoseState: Codable, Equatable, Sendable {
    public let shouldersAngleDegrees: Double?
    public let faceYawDegrees: Double?
    public let eyeLineConfidence: Double?
    public let handAwkwardnessRisk: Double?

    public init(shouldersAngleDegrees: Double?, faceYawDegrees: Double?, eyeLineConfidence: Double?, handAwkwardnessRisk: Double?) {
        self.shouldersAngleDegrees = shouldersAngleDegrees
        self.faceYawDegrees = faceYawDegrees
        self.eyeLineConfidence = eyeLineConfidence
        self.handAwkwardnessRisk = handAwkwardnessRisk
    }
}

public struct FaceQualityState: Codable, Equatable, Sendable {
    public let eyeOpenProbability: Double?
    public let expressionStability: Double?
    public let sharpnessProbability: Double?
    public let skinExposureScore: Double?

    public init(eyeOpenProbability: Double?, expressionStability: Double?, sharpnessProbability: Double?, skinExposureScore: Double?) {
        self.eyeOpenProbability = eyeOpenProbability
        self.expressionStability = expressionStability
        self.sharpnessProbability = sharpnessProbability
        self.skinExposureScore = skinExposureScore
    }
}

public struct BackgroundState: Codable, Equatable, Sendable {
    public let clutterScore: Double
    public let brightDistractionScore: Double
    public let poleBehindHeadRisk: Double
    public let randomPeopleRisk: Double
    public let horizonIntersectionRisk: Double
    public let cleanerDirection: CleanerDirection?

    public init(
        clutterScore: Double,
        brightDistractionScore: Double,
        poleBehindHeadRisk: Double,
        randomPeopleRisk: Double,
        horizonIntersectionRisk: Double,
        cleanerDirection: CleanerDirection?
    ) {
        self.clutterScore = clutterScore
        self.brightDistractionScore = brightDistractionScore
        self.poleBehindHeadRisk = poleBehindHeadRisk
        self.randomPeopleRisk = randomPeopleRisk
        self.horizonIntersectionRisk = horizonIntersectionRisk
        self.cleanerDirection = cleanerDirection
    }

    public enum CleanerDirection: String, Codable, Sendable {
        case left
        case right
        case forward
        case backward
        case unknown
    }
}

public struct MotionState: Codable, Equatable, Sendable {
    public let cameraShake: Double
    public let subjectMotion: Double
    public let blurRisk: Double

    public init(cameraShake: Double, subjectMotion: Double, blurRisk: Double) {
        self.cameraShake = cameraShake
        self.subjectMotion = subjectMotion
        self.blurRisk = blurRisk
    }
}

public struct CompositionState: Codable, Equatable, Sendable {
    public let subjectPlacementScore: Double
    public let headroomScore: Double?
    public let balanceScore: Double
    public let leadingLinesScore: Double?
    public let negativeSpaceScore: Double?

    public init(subjectPlacementScore: Double, headroomScore: Double?, balanceScore: Double, leadingLinesScore: Double?, negativeSpaceScore: Double?) {
        self.subjectPlacementScore = subjectPlacementScore
        self.headroomScore = headroomScore
        self.balanceScore = balanceScore
        self.leadingLinesScore = leadingLinesScore
        self.negativeSpaceScore = negativeSpaceScore
    }
}

public struct SafetyState: Codable, Equatable, Sendable {
    public let hazards: [Hazard]
    public let movementGuidanceAllowed: Bool
    public let confidence: Double

    public init(hazards: [Hazard], movementGuidanceAllowed: Bool, confidence: Double) {
        self.hazards = hazards
        self.movementGuidanceAllowed = movementGuidanceAllowed
        self.confidence = confidence
    }

    public enum Hazard: String, Codable, Sendable {
        case road
        case traffic
        case stairs
        case edge
        case water
        case obstacle
        case unknown
    }
}
