import Foundation

public enum TargetMatchCalibrationManifestError: Error, Equatable, Sendable {
    case singlePhoneCalibrationRequired
    case requiredDomainsMissing
    case samplesMissing
    case invalidScenario(String)
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
        LensPilotAiCore(
            targetMatchCalibration: targetMatchCalibration,
            guidanceCalibration: makeGuidanceCalibration()
        )
    }

    public func makeGuidanceCalibration() -> GuidanceCalibration {
        var globalReasonBoosts: [String: Double] = [:]
        var domainReasonBoosts: [String: [String: Double]] = [:]
        let minimumReviewers = max(1, collectionPlan.minimumBlindReviewers)

        for sample in samples where sample.sampleKind == "iphone_capture" {
            guard let preference = sample.blindPreference, preference.reviewCount >= minimumReviewers else {
                continue
            }

            let reviewScale = min(3, Double(preference.reviewCount) / Double(minimumReviewers))
            Self.addBoost(
                for: preference.preferredGuidanceReason,
                domain: sample.domain,
                amount: 0.02 * reviewScale,
                globalReasonBoosts: &globalReasonBoosts,
                domainReasonBoosts: &domainReasonBoosts
            )

            for (index, weakness) in preference.rankedWeaknesses.prefix(3).enumerated() {
                guard let reason = Self.preferredReason(forWeakness: weakness) else { continue }
                Self.addBoost(
                    for: reason,
                    domain: sample.domain,
                    amount: 0.006 * reviewScale / Double(index + 1),
                    globalReasonBoosts: &globalReasonBoosts,
                    domainReasonBoosts: &domainReasonBoosts
                )
            }
        }

        return GuidanceCalibration(
            globalReasonBoosts: globalReasonBoosts,
            domainReasonBoosts: domainReasonBoosts
        )
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
        for scenarioId in collectionPlan.requiredScenarios {
            guard CalibrationCaptureScenario(rawValue: scenarioId) != nil else {
                throw TargetMatchCalibrationManifestError.invalidScenario(scenarioId)
            }
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

    private static func addBoost(
        for reason: String,
        domain: String?,
        amount: Double,
        globalReasonBoosts: inout [String: Double],
        domainReasonBoosts: inout [String: [String: Double]]
    ) {
        guard GuidanceAction.Reason(rawValue: reason) != nil else { return }

        if let domain, CaptureDomain(rawValue: domain) != nil {
            var boosts = domainReasonBoosts[domain] ?? [:]
            boosts[reason, default: 0] += amount
            domainReasonBoosts[domain] = boosts
        } else {
            globalReasonBoosts[reason, default: 0] += amount
        }
    }

    private static func preferredReason(forWeakness weakness: String) -> String? {
        switch weakness {
        case "background":
            return GuidanceAction.Reason.reduceClutter.rawValue
        case "horizon":
            return GuidanceAction.Reason.levelHorizon.rawValue
        case "lighting":
            return GuidanceAction.Reason.improveFaceLight.rawValue
        case "exposure":
            return GuidanceAction.Reason.protectHighlights.rawValue
        case "pose":
            return GuidanceAction.Reason.improvePose.rawValue
        case "sharpnessProbability":
            return GuidanceAction.Reason.reduceMotionBlur.rawValue
        case "composition", "subjectPosition":
            return GuidanceAction.Reason.improveSubjectBackgroundSeparation.rawValue
        case "cameraAngle", "intentMatch":
            return GuidanceAction.Reason.matchReference.rawValue
        default:
            return nil
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
        public let requiredScenarios: [String]

        public init(
            singlePhoneOnly: Bool,
            realCaptureTargetCount: Int,
            minimumBlindReviewers: Int,
            requiredDomains: [String],
            requiredScenarios: [String] = []
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.realCaptureTargetCount = realCaptureTargetCount
            self.minimumBlindReviewers = minimumBlindReviewers
            self.requiredDomains = requiredDomains
            self.requiredScenarios = requiredScenarios
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.singlePhoneOnly = try container.decode(Bool.self, forKey: .singlePhoneOnly)
            self.realCaptureTargetCount = try container.decode(Int.self, forKey: .realCaptureTargetCount)
            self.minimumBlindReviewers = try container.decode(Int.self, forKey: .minimumBlindReviewers)
            self.requiredDomains = try container.decode([String].self, forKey: .requiredDomains)
            self.requiredScenarios = try container.decodeIfPresent([String].self, forKey: .requiredScenarios) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case singlePhoneOnly
            case realCaptureTargetCount
            case minimumBlindReviewers
            case requiredDomains
            case requiredScenarios
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
