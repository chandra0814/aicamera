import Foundation

public enum RealityMode: String, Codable, Sendable {
    case natural
    case enhanced
    case creative
}

public enum CaptureDomain: String, Codable, Sendable {
    case portrait
    case landscape
    case travel
    case lifestyle
    case night
    case reference
}

public struct ShotSpec: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let source: Source
    public let originalPrompt: String?
    public let domain: CaptureDomain
    public let subject: Subject
    public let style: Style
    public let composition: Composition
    public let cameraIntent: CameraIntent
    public let constraints: Constraints
    public let confidence: Double
    public let missingInfo: [String]

    public init(
        id: String,
        version: String = "1.0",
        source: Source,
        originalPrompt: String?,
        domain: CaptureDomain,
        subject: Subject,
        style: Style,
        composition: Composition,
        cameraIntent: CameraIntent,
        constraints: Constraints,
        confidence: Double,
        missingInfo: [String]
    ) {
        self.id = id
        self.version = version
        self.source = source
        self.originalPrompt = originalPrompt
        self.domain = domain
        self.subject = subject
        self.style = style
        self.composition = composition
        self.cameraIntent = cameraIntent
        self.constraints = constraints
        self.confidence = confidence
        self.missingInfo = missingInfo
    }
}

public extension ShotSpec {
    enum Source: String, Codable, Sendable {
        case text
        case voice
        case preset
        case referenceImage = "reference_image"
        case hybrid
    }

    struct Subject: Codable, Equatable, Sendable {
        public let primary: Primary
        public let count: Int?
        public let priority: Priority
        public let identityRecognitionAllowed: Bool

        public init(primary: Primary, count: Int?, priority: Priority, identityRecognitionAllowed: Bool = false) {
            self.primary = primary
            self.count = count
            self.priority = priority
            self.identityRecognitionAllowed = identityRecognitionAllowed
        }
    }

    enum Primary: String, Codable, Sendable {
        case person
        case people
        case landscape
        case vehicle
        case object
        case unknown
    }

    enum Priority: String, Codable, Sendable {
        case subject
        case environment
        case balanced
    }

    struct Style: Codable, Equatable, Sendable {
        public let name: Name
        public let mood: Mood?
        public let colorIntent: ColorIntent?
        public let skinTreatment: SkinTreatment?

        public init(name: Name, mood: Mood?, colorIntent: ColorIntent?, skinTreatment: SkinTreatment?) {
            self.name = name
            self.mood = mood
            self.colorIntent = colorIntent
            self.skinTreatment = skinTreatment
        }
    }

    enum Name: String, Codable, Sendable {
        case natural
        case cinematic
        case professional
        case travel
        case portrait
        case night
        case sky
        case lifestyle
        case custom
    }

    enum Mood: String, Codable, Sendable {
        case bright
        case dramatic
        case soft
        case luxury
        case documentary
        case moody
    }

    enum ColorIntent: String, Codable, Sendable {
        case natural
        case warmHighlights = "warm_highlights"
        case coolShadows = "cool_shadows"
        case warmHighlightsCoolShadows = "warm_highlights_cool_shadows"
        case highContrast = "high_contrast"
        case lowContrast = "low_contrast"
    }

    enum SkinTreatment: String, Codable, Sendable {
        case natural
        case softButRealistic = "soft_but_realistic"
        case none
    }

    struct Composition: Codable, Equatable, Sendable {
        public let framing: Framing
        public let headroom: Headroom?
        public let skyPriority: PriorityLevel?
        public let backgroundPriority: BackgroundPriority?
        public let horizonPlacement: HorizonPlacement?

        public init(
            framing: Framing,
            headroom: Headroom?,
            skyPriority: PriorityLevel?,
            backgroundPriority: BackgroundPriority?,
            horizonPlacement: HorizonPlacement?
        ) {
            self.framing = framing
            self.headroom = headroom
            self.skyPriority = skyPriority
            self.backgroundPriority = backgroundPriority
            self.horizonPlacement = horizonPlacement
        }
    }

    enum Framing: String, Codable, Sendable {
        case close
        case medium
        case wide
        case environmental
        case threeQuarter = "three_quarter"
        case symmetrical
        case ruleOfThirds = "rule_of_thirds"
    }

    enum Headroom: String, Codable, Sendable {
        case minimal
        case balanced
        case moreSpace = "more_space"
    }

    enum PriorityLevel: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    enum BackgroundPriority: String, Codable, Sendable {
        case clean
        case contextual
        case dramatic
        case sunset
        case architecture
        case nature
    }

    enum HorizonPlacement: String, Codable, Sendable {
        case lowerThird = "lower_third"
        case center
        case upperThird = "upper_third"
        case auto
    }

    struct CameraIntent: Codable, Equatable, Sendable {
        public let targetLens: TargetLens?
        public let perspective: Perspective?
        public let exposureStrategy: ExposureStrategy?
        public let focusStrategy: FocusStrategy?
        public let depthIntent: DepthIntent?

        public init(
            targetLens: TargetLens?,
            perspective: Perspective?,
            exposureStrategy: ExposureStrategy?,
            focusStrategy: FocusStrategy?,
            depthIntent: DepthIntent?
        ) {
            self.targetLens = targetLens
            self.perspective = perspective
            self.exposureStrategy = exposureStrategy
            self.focusStrategy = focusStrategy
            self.depthIntent = depthIntent
        }
    }

    enum TargetLens: String, Codable, Sendable {
        case ultraWide = "ultra_wide"
        case wide
        case twoXIfAvailable = "two_x_if_available"
        case telephotoIfAvailable = "telephoto_if_available"
        case auto
    }

    enum Perspective: String, Codable, Sendable {
        case eyeLevel = "eye_level"
        case lowAngle = "low_angle"
        case highAngle = "high_angle"
        case straightOn = "straight_on"
        case auto
    }

    enum ExposureStrategy: String, Codable, Sendable {
        case protectHighlights = "protect_highlights"
        case prioritizeFaces = "prioritize_faces"
        case balanced
        case nightStability = "night_stability"
    }

    enum FocusStrategy: String, Codable, Sendable {
        case subjectEye = "subject_eye"
        case subjectCenter = "subject_center"
        case hyperfocal
        case auto
    }

    enum DepthIntent: String, Codable, Sendable {
        case naturalDepth = "natural_depth"
        case strongSubjectSeparation = "strong_subject_separation"
        case deepFocus = "deep_focus"
        case auto
    }

    struct Constraints: Codable, Equatable, Sendable {
        public let realityMode: RealityMode
        public let cloudAllowed: Bool
        public let generativeEditsAllowed: Bool
        public let userSafetyStrictness: SafetyStrictness
        public let singlePhoneOnly: Bool

        public init(
            realityMode: RealityMode,
            cloudAllowed: Bool,
            generativeEditsAllowed: Bool,
            userSafetyStrictness: SafetyStrictness,
            singlePhoneOnly: Bool = true
        ) {
            self.realityMode = realityMode
            self.cloudAllowed = cloudAllowed
            self.generativeEditsAllowed = generativeEditsAllowed
            self.userSafetyStrictness = userSafetyStrictness
            self.singlePhoneOnly = singlePhoneOnly
        }
    }

    enum SafetyStrictness: String, Codable, Sendable {
        case standard
        case conservative
    }
}

public struct ReferencePhotoState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: Source
    public let localAssetUri: String
    public let thumbnailUri: String
    public var analysisStatus: AnalysisStatus
    public var extractedFeatures: ReferencePhotoFeatures?
    public var display: Display
    public let privacy: Privacy

    public init(
        id: String,
        source: Source,
        localAssetUri: String,
        thumbnailUri: String,
        analysisStatus: AnalysisStatus,
        extractedFeatures: ReferencePhotoFeatures?,
        display: Display,
        privacy: Privacy
    ) {
        self.id = id
        self.source = source
        self.localAssetUri = localAssetUri
        self.thumbnailUri = thumbnailUri
        self.analysisStatus = analysisStatus
        self.extractedFeatures = extractedFeatures
        self.display = display
        self.privacy = privacy
    }
}

public extension ReferencePhotoState {
    enum Source: String, Codable, Sendable {
        case photoLibrary = "photo_library"
        case cameraCapture = "camera_capture"
        case sharedFile = "shared_file"
    }

    enum AnalysisStatus: String, Codable, Sendable {
        case notStarted = "not_started"
        case analyzing
        case ready
        case failed
    }

    struct Display: Codable, Equatable, Sendable {
        public var showCameraPopup: Bool
        public var popupPosition: PopupPosition
        public var viewerState: ViewerState

        public init(showCameraPopup: Bool, popupPosition: PopupPosition, viewerState: ViewerState) {
            self.showCameraPopup = showCameraPopup
            self.popupPosition = popupPosition
            self.viewerState = viewerState
        }
    }

    enum PopupPosition: String, Codable, Sendable {
        case topLeft = "top_left"
        case topRight = "top_right"
        case bottomLeft = "bottom_left"
        case bottomRight = "bottom_right"
    }

    enum ViewerState: String, Codable, Sendable {
        case collapsedPopup = "collapsed_popup"
        case fullReference = "full_reference"
        case referenceVsTarget = "reference_vs_target"
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let cloudAnalysisUsed: Bool
        public let userConsentedToCloudAnalysis: Bool

        public init(cloudAnalysisUsed: Bool, userConsentedToCloudAnalysis: Bool) {
            self.cloudAnalysisUsed = cloudAnalysisUsed
            self.userConsentedToCloudAnalysis = userConsentedToCloudAnalysis
        }
    }
}

public struct ReferencePhotoFeatures: Codable, Equatable, Sendable {
    public let framing: String?
    public let apparentFocalLength: String?
    public let cameraHeight: String?
    public let subjectScale: Double?
    public let poseHints: [String]
    public let lightingDirection: String?
    public let colorMood: String?
    public let depthStyle: String?
    public let achievableTranslationNotes: [String]

    public init(
        framing: String?,
        apparentFocalLength: String?,
        cameraHeight: String?,
        subjectScale: Double?,
        poseHints: [String],
        lightingDirection: String?,
        colorMood: String?,
        depthStyle: String?,
        achievableTranslationNotes: [String]
    ) {
        self.framing = framing
        self.apparentFocalLength = apparentFocalLength
        self.cameraHeight = cameraHeight
        self.subjectScale = subjectScale
        self.poseHints = poseHints
        self.lightingDirection = lightingDirection
        self.colorMood = colorMood
        self.depthStyle = depthStyle
        self.achievableTranslationNotes = achievableTranslationNotes
    }
}
