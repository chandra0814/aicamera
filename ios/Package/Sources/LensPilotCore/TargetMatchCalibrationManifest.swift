import Foundation

public enum TargetMatchCalibrationManifestError: Error, Equatable, Sendable {
    case singlePhoneCalibrationRequired
    case requiredDomainsMissing
    case samplesMissing
    case invalidWeight(String)
}

public struct TargetMatchCalibrationManifest: Codable, Equatable, Sendable {
    public let version: String
    public let collectionPlan: CollectionPlan
    public let targetMatchCalibration: TargetMatchCalibration
    public let samples: [SampleSummary]

    public init(
        version: String,
        collectionPlan: CollectionPlan,
        targetMatchCalibration: TargetMatchCalibration,
        samples: [SampleSummary]
    ) throws {
        self.version = version
        self.collectionPlan = collectionPlan
        self.targetMatchCalibration = targetMatchCalibration
        self.samples = samples

        try Self.validate(
            collectionPlan: collectionPlan,
            targetMatchCalibration: targetMatchCalibration,
            samples: samples
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let collectionPlan = try container.decode(CollectionPlan.self, forKey: .collectionPlan)
        let targetMatchCalibration = try container.decode(TargetMatchCalibration.self, forKey: .targetMatchCalibration)
        let samples = try container.decode([SampleSummary].self, forKey: .samples)

        try Self.validate(
            collectionPlan: collectionPlan,
            targetMatchCalibration: targetMatchCalibration,
            samples: samples
        )

        self.version = version
        self.collectionPlan = collectionPlan
        self.targetMatchCalibration = targetMatchCalibration
        self.samples = samples
    }

    public static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> TargetMatchCalibrationManifest {
        try decoder.decode(TargetMatchCalibrationManifest.self, from: data)
    }

    public func makeAiCore() -> LensPilotAiCore {
        LensPilotAiCore(targetMatchCalibration: targetMatchCalibration)
    }

    public var reviewedSampleCount: Int {
        samples.filter { $0.sampleKind == "iphone_capture" }.count
    }

    public var reviewedDomains: [String] {
        Array(Set(samples.compactMap { sample in
            sample.sampleKind == "iphone_capture" ? sample.domain : nil
        })).sorted()
    }

    private static func validate(
        collectionPlan: CollectionPlan,
        targetMatchCalibration: TargetMatchCalibration,
        samples: [SampleSummary]
    ) throws {
        guard collectionPlan.singlePhoneOnly else {
            throw TargetMatchCalibrationManifestError.singlePhoneCalibrationRequired
        }
        guard !collectionPlan.requiredDomains.isEmpty else {
            throw TargetMatchCalibrationManifestError.requiredDomainsMissing
        }
        guard !samples.isEmpty else {
            throw TargetMatchCalibrationManifestError.samplesMissing
        }

        try requirePositive(targetMatchCalibration.horizonRollFullPenaltyDegrees, "horizonRollFullPenaltyDegrees")
        try requirePositive(targetMatchCalibration.eyeLevelPitchFullPenaltyDegrees, "eyeLevelPitchFullPenaltyDegrees")
        try require(targetMatchCalibration.highlightClippingPenalty, "highlightClippingPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.shadowClippingPenalty, "shadowClippingPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.backgroundClutterPenalty, "backgroundClutterPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.poleBehindHeadPenalty, "poleBehindHeadPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.dynamicRangeLightingPenalty, "dynamicRangeLightingPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.motionBlurPenalty, "motionBlurPenalty", min: 0, max: 2)
        try require(targetMatchCalibration.missingHorizonScore, "missingHorizonScore", min: 0, max: 1)
        try require(targetMatchCalibration.missingFaceLightQuality, "missingFaceLightQuality", min: 0, max: 1)
        try require(targetMatchCalibration.missingPoseScore, "missingPoseScore", min: 0, max: 1)
        try require(targetMatchCalibration.nonPortraitCameraAngleScore, "nonPortraitCameraAngleScore", min: 0, max: 1)
    }

    private static func requirePositive(_ value: Double, _ label: String) throws {
        guard value > 0 else {
            throw TargetMatchCalibrationManifestError.invalidWeight(label)
        }
    }

    private static func require(_ value: Double, _ label: String, min: Double, max: Double) throws {
        guard value >= min, value <= max else {
            throw TargetMatchCalibrationManifestError.invalidWeight(label)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case collectionPlan
        case targetMatchCalibration
        case samples
    }
}

public extension TargetMatchCalibrationManifest {
    struct CollectionPlan: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let realCaptureTargetCount: Int
        public let minimumBlindReviewers: Int
        public let requiredDomains: [String]

        public init(
            singlePhoneOnly: Bool,
            realCaptureTargetCount: Int,
            minimumBlindReviewers: Int,
            requiredDomains: [String]
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.realCaptureTargetCount = realCaptureTargetCount
            self.minimumBlindReviewers = minimumBlindReviewers
            self.requiredDomains = requiredDomains
        }
    }

    struct SampleSummary: Codable, Equatable, Sendable {
        public let id: String
        public let sampleKind: String
        public let domain: String?
        public let blindPreference: BlindPreference?

        public init(
            id: String,
            sampleKind: String,
            domain: String?,
            blindPreference: BlindPreference?
        ) {
            self.id = id
            self.sampleKind = sampleKind
            self.domain = domain
            self.blindPreference = blindPreference
        }
    }

    struct BlindPreference: Codable, Equatable, Sendable {
        public let reviewCount: Int
        public let preferredGuidanceReason: String
        public let rankedWeaknesses: [String]
        public let notes: String

        public init(
            reviewCount: Int,
            preferredGuidanceReason: String,
            rankedWeaknesses: [String],
            notes: String
        ) {
            self.reviewCount = reviewCount
            self.preferredGuidanceReason = preferredGuidanceReason
            self.rankedWeaknesses = rankedWeaknesses
            self.notes = notes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.reviewCount = try container.decode(Int.self, forKey: .reviewCount)
            self.preferredGuidanceReason = try container.decode(String.self, forKey: .preferredGuidanceReason)
            self.rankedWeaknesses = try container.decode([String].self, forKey: .rankedWeaknesses)
            self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case reviewCount
            case preferredGuidanceReason
            case rankedWeaknesses
            case notes
        }
    }
}
