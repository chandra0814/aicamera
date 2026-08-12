import Foundation

public struct NormalizedRectangle: Codable, Equatable, Sendable {
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

public struct ShotPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let shotSpecId: String
    public let achievability: Achievability
    public let cameraControls: CameraControls
    public let photographerChanges: [GuidanceAction]
    public let subjectDirections: [GuidanceAction]
    public let compositionTarget: CompositionTarget
    public let processingIntent: ProcessingIntent
    public let previewConfiguration: PreviewConfiguration
    public let capturePolicy: CapturePolicy

    public init(
        id: String,
        shotSpecId: String,
        achievability: Achievability,
        cameraControls: CameraControls,
        photographerChanges: [GuidanceAction],
        subjectDirections: [GuidanceAction],
        compositionTarget: CompositionTarget,
        processingIntent: ProcessingIntent,
        previewConfiguration: PreviewConfiguration,
        capturePolicy: CapturePolicy
    ) {
        self.id = id
        self.shotSpecId = shotSpecId
        self.achievability = achievability
        self.cameraControls = cameraControls
        self.photographerChanges = photographerChanges
        self.subjectDirections = subjectDirections
        self.compositionTarget = compositionTarget
        self.processingIntent = processingIntent
        self.previewConfiguration = previewConfiguration
        self.capturePolicy = capturePolicy
    }
}

public extension ShotPlan {
    struct Achievability: Codable, Equatable, Sendable {
        public let natural: Double
        public let enhanced: Double
        public let creative: Double
        public let limitingFactors: [String]

        public init(natural: Double, enhanced: Double, creative: Double, limitingFactors: [String]) {
            self.natural = natural
            self.enhanced = enhanced
            self.creative = creative
            self.limitingFactors = limitingFactors
        }
    }

    struct CameraControls: Codable, Equatable, Sendable {
        public let recommendedLens: String
        public let targetZoom: Double
        public let targetExposureBias: Double?
        public let targetFocusMode: FocusMode
        public let targetWhiteBalance: WhiteBalance?
        public let stabilizationMode: String?
        public let captureFormat: CaptureFormat

        public init(
            recommendedLens: String,
            targetZoom: Double,
            targetExposureBias: Double?,
            targetFocusMode: FocusMode,
            targetWhiteBalance: WhiteBalance?,
            stabilizationMode: String?,
            captureFormat: CaptureFormat
        ) {
            self.recommendedLens = recommendedLens
            self.targetZoom = targetZoom
            self.targetExposureBias = targetExposureBias
            self.targetFocusMode = targetFocusMode
            self.targetWhiteBalance = targetWhiteBalance
            self.stabilizationMode = stabilizationMode
            self.captureFormat = captureFormat
        }
    }

    enum FocusMode: String, Codable, Sendable {
        case auto
        case locked
        case manualIfAvailable = "manual_if_available"
    }

    enum WhiteBalance: String, Codable, Sendable {
        case auto
        case daylight
        case cloudy
        case warm
        case cool
        case manualIfAvailable = "manual_if_available"
    }

    enum CaptureFormat: String, Codable, Sendable {
        case heif
        case jpeg
        case rawPlusHeif = "raw_plus_heif"
    }

    struct CompositionTarget: Codable, Equatable, Sendable {
        public let subjectBounds: NormalizedRectangle
        public let horizonY: Double?
        public let crop: NormalizedRectangle

        public init(subjectBounds: NormalizedRectangle, horizonY: Double?, crop: NormalizedRectangle) {
            self.subjectBounds = subjectBounds
            self.horizonY = horizonY
            self.crop = crop
        }
    }

    struct ProcessingIntent: Codable, Equatable, Sendable {
        public let realityMode: RealityMode
        public let toneCurve: ToneCurve
        public let colorTreatment: String
        public let depthEffect: DepthEffect

        public init(realityMode: RealityMode, toneCurve: ToneCurve, colorTreatment: String, depthEffect: DepthEffect) {
            self.realityMode = realityMode
            self.toneCurve = toneCurve
            self.colorTreatment = colorTreatment
            self.depthEffect = depthEffect
        }
    }

    enum ToneCurve: String, Codable, Sendable {
        case natural
        case cinematicSoftContrast = "cinematic_soft_contrast"
        case highDynamicRange = "high_dynamic_range"
        case nightNoiseControl = "night_noise_control"
    }

    enum DepthEffect: String, Codable, Sendable {
        case none
        case natural
        case portraitIfAvailable = "portrait_if_available"
        case postDepthBlur = "post_depth_blur"
    }

    struct PreviewConfiguration: Codable, Equatable, Sendable {
        public let label: Label
        public let operations: [String]

        public init(label: Label, operations: [String]) {
            self.label = label
            self.operations = operations
        }
    }

    enum Label: String, Codable, Sendable {
        case captureRealistic = "capture_realistic"
        case enhancedRealistic = "enhanced_realistic"
        case aiEnhancementRequired = "ai_enhancement_required"
    }

    struct CapturePolicy: Codable, Equatable, Sendable {
        public let mode: Mode
        public let burstFrameCount: Int?
        public let trigger: Trigger
        public let readinessThreshold: Double

        public init(mode: Mode, burstFrameCount: Int?, trigger: Trigger, readinessThreshold: Double) {
            self.mode = mode
            self.burstFrameCount = burstFrameCount
            self.trigger = trigger
            self.readinessThreshold = readinessThreshold
        }
    }

    enum Mode: String, Codable, Sendable {
        case single
        case burst
    }

    enum Trigger: String, Codable, Sendable {
        case manual
        case readyAssist = "ready_assist"
        case autoWhenStable = "auto_when_stable"
    }
}

public struct GuidanceAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let actor: Actor
    public let action: Action
    public let magnitude: Double?
    public let unit: Unit?
    public let direction: Direction?
    public let confidence: Double
    public let reason: Reason
    public let expectedGain: Double
    public let safetyQualifier: SafetyQualifier?
    public let priority: Int
    public let ttlMs: Int
    public let suppressOppositeUntilMs: Int

    public init(
        id: String,
        actor: Actor,
        action: Action,
        magnitude: Double?,
        unit: Unit?,
        direction: Direction?,
        confidence: Double,
        reason: Reason,
        expectedGain: Double,
        safetyQualifier: SafetyQualifier?,
        priority: Int,
        ttlMs: Int,
        suppressOppositeUntilMs: Int
    ) {
        self.id = id
        self.actor = actor
        self.action = action
        self.magnitude = magnitude
        self.unit = unit
        self.direction = direction
        self.confidence = confidence
        self.reason = reason
        self.expectedGain = expectedGain
        self.safetyQualifier = safetyQualifier
        self.priority = priority
        self.ttlMs = ttlMs
        self.suppressOppositeUntilMs = suppressOppositeUntilMs
    }
}

public extension GuidanceAction {
    enum Actor: String, Codable, Sendable {
        case photographer
        case subject
        case camera
        case processing
    }

    enum Action: String, Codable, Sendable {
        case moveLeft = "move_left"
        case moveRight = "move_right"
        case moveForward = "move_forward"
        case moveBackward = "move_backward"
        case raiseCamera = "raise_camera"
        case lowerCamera = "lower_camera"
        case rotateClockwise = "rotate_clockwise"
        case rotateCounterclockwise = "rotate_counterclockwise"
        case switchLens = "switch_lens"
        case adjustZoom = "adjust_zoom"
        case adjustExposure = "adjust_exposure"
        case turnShoulders = "turn_shoulders"
        case turnFace = "turn_face"
        case holdSteady = "hold_steady"
        case captureNow = "capture_now"
        case ifSafeMove = "if_safe_move"
    }

    enum Unit: String, Codable, Sendable {
        case meter
        case centimeter
        case degree
        case zoomFactor = "zoom_factor"
        case ev
    }

    enum Direction: String, Codable, Sendable {
        case left
        case right
        case up
        case down
        case towardLight = "toward_light"
        case awayFromBackground = "away_from_background"
    }

    enum Reason: String, Codable, Sendable {
        case improveSubjectBackgroundSeparation = "improve_subject_background_separation"
        case levelHorizon = "level_horizon"
        case protectHighlights = "protect_highlights"
        case improveFaceLight = "improve_face_light"
        case reduceClutter = "reduce_clutter"
        case matchReference = "match_reference"
        case improvePose = "improve_pose"
        case increaseSky = "increase_sky"
        case reduceMotionBlur = "reduce_motion_blur"
        case readyToCapture = "ready_to_capture"
    }

    enum SafetyQualifier: String, Codable, Sendable {
        case ifSafe = "if_safe"
        case doNotMove = "do_not_move"
    }
}

public struct TargetMatchScore: Codable, Equatable, Sendable {
    public let composition: Double
    public let subjectPosition: Double
    public let cameraAngle: Double
    public let lighting: Double
    public let background: Double
    public let horizon: Double
    public let pose: Double
    public let sharpnessProbability: Double
    public let exposure: Double
    public let intentMatch: Double

    public var overall: Double {
        let values = [
            composition,
            subjectPosition,
            cameraAngle,
            lighting,
            background,
            horizon,
            pose,
            sharpnessProbability,
            exposure,
            intentMatch
        ]
        return values.reduce(0, +) / Double(values.count)
    }
}
