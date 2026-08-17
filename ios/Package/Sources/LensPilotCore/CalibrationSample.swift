import Foundation

public struct CalibrationSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let sampleKind: SampleKind
    public let sourceCandidateId: String?
    public let domain: CalibrationDomain?
    public let prompt: String
    public let captureMetadata: CaptureMetadata
    public let privacy: Privacy
    public let deviceCapability: DeviceCapability
    public let sceneState: SceneState
    public let shotSpec: ShotSpec
    public let shotPlan: ShotPlan
    public let guidanceAction: GuidanceAction?
    public let targetMatch: TargetMatchSnapshot
    public let blindPreference: BlindPreference?
    public let expected: Expected?

    public init(
        id: String,
        version: String,
        sampleKind: SampleKind,
        sourceCandidateId: String? = nil,
        domain: CalibrationDomain? = nil,
        prompt: String,
        captureMetadata: CaptureMetadata,
        privacy: Privacy,
        deviceCapability: DeviceCapability,
        sceneState: SceneState,
        shotSpec: ShotSpec,
        shotPlan: ShotPlan,
        guidanceAction: GuidanceAction?,
        targetMatch: TargetMatchSnapshot,
        blindPreference: BlindPreference? = nil,
        expected: Expected? = nil
    ) {
        self.id = id
        self.version = version
        self.sampleKind = sampleKind
        self.sourceCandidateId = sourceCandidateId
        self.domain = domain
        self.prompt = prompt
        self.captureMetadata = captureMetadata
        self.privacy = privacy
        self.deviceCapability = deviceCapability
        self.sceneState = sceneState
        self.shotSpec = shotSpec
        self.shotPlan = shotPlan
        self.guidanceAction = guidanceAction
        self.targetMatch = targetMatch
        self.blindPreference = blindPreference
        self.expected = expected
    }

    public enum SampleKind: String, Codable, Sendable {
        case fixtureSeed = "fixture_seed"
        case iphoneCaptureCandidate = "iphone_capture_candidate"
        case iphoneCapture = "iphone_capture"
    }

    public enum CalibrationDomain: String, Codable, Sendable, CaseIterable {
        case portrait
        case landscape
        case lifestyle
        case night
    }

    public enum CalibrationWeakness: String, Codable, Sendable, CaseIterable {
        case composition
        case subjectPosition
        case cameraAngle
        case lighting
        case background
        case horizon
        case pose
        case sharpnessProbability
        case exposure
        case intentMatch
    }

    public struct CaptureMetadata: Codable, Equatable, Sendable {
        public let capturedAt: Date
        public let deviceModel: String
        public let usesFrontCameraForSelfShot: Bool
        public let referencePhotoActive: Bool

        public init(
            capturedAt: Date,
            deviceModel: String,
            usesFrontCameraForSelfShot: Bool,
            referencePhotoActive: Bool
        ) {
            self.capturedAt = capturedAt
            self.deviceModel = deviceModel
            self.usesFrontCameraForSelfShot = usesFrontCameraForSelfShot
            self.referencePhotoActive = referencePhotoActive
        }
    }

    public struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let cloudAnalysisUsed: Bool
        public let generativeEditsAllowed: Bool
        public let identityRecognitionAllowed: Bool

        public init(
            singlePhoneOnly: Bool = true,
            cloudAnalysisUsed: Bool = false,
            generativeEditsAllowed: Bool = false,
            identityRecognitionAllowed: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.cloudAnalysisUsed = cloudAnalysisUsed
            self.generativeEditsAllowed = generativeEditsAllowed
            self.identityRecognitionAllowed = identityRecognitionAllowed
        }
    }

    public struct ReviewLabel: Equatable, Sendable {
        public let domain: CalibrationDomain
        public let reviewCount: Int
        public let preferredGuidanceReason: GuidanceAction.Reason
        public let rankedWeaknesses: [CalibrationWeakness]
        public let notes: String

        public init(
            domain: CalibrationDomain,
            reviewCount: Int,
            preferredGuidanceReason: GuidanceAction.Reason,
            rankedWeaknesses: [CalibrationWeakness],
            notes: String = ""
        ) {
            self.domain = domain
            self.reviewCount = reviewCount
            self.preferredGuidanceReason = preferredGuidanceReason
            self.rankedWeaknesses = rankedWeaknesses
            self.notes = notes
        }
    }

    public struct BlindPreference: Codable, Equatable, Sendable {
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
    }

    public struct Expected: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let targetMatch: TargetMatchExpected

        public init(singlePhoneOnly: Bool, targetMatch: TargetMatchExpected) {
            self.singlePhoneOnly = singlePhoneOnly
            self.targetMatch = targetMatch
        }
    }

    public struct ScoreRange: Codable, Equatable, Sendable {
        public let min: Double
        public let max: Double

        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }
    }

    public struct TargetMatchExpected: Codable, Equatable, Sendable {
        public let composition: ScoreRange
        public let subjectPosition: ScoreRange
        public let cameraAngle: ScoreRange
        public let lighting: ScoreRange
        public let background: ScoreRange
        public let horizon: ScoreRange
        public let pose: ScoreRange
        public let sharpnessProbability: ScoreRange
        public let exposure: ScoreRange
        public let intentMatch: ScoreRange
        public let overall: ScoreRange

        public init(snapshot: TargetMatchSnapshot, tolerance: Double) {
            self.composition = Self.range(snapshot.composition, tolerance: tolerance)
            self.subjectPosition = Self.range(snapshot.subjectPosition, tolerance: tolerance)
            self.cameraAngle = Self.range(snapshot.cameraAngle, tolerance: tolerance)
            self.lighting = Self.range(snapshot.lighting, tolerance: tolerance)
            self.background = Self.range(snapshot.background, tolerance: tolerance)
            self.horizon = Self.range(snapshot.horizon, tolerance: tolerance)
            self.pose = Self.range(snapshot.pose, tolerance: tolerance)
            self.sharpnessProbability = Self.range(snapshot.sharpnessProbability, tolerance: tolerance)
            self.exposure = Self.range(snapshot.exposure, tolerance: tolerance)
            self.intentMatch = Self.range(snapshot.intentMatch, tolerance: tolerance)
            self.overall = Self.range(snapshot.overall, tolerance: tolerance)
        }

        private static func range(_ value: Double, tolerance: Double) -> ScoreRange {
            ScoreRange(
                min: roundScore(max(0, value - tolerance)),
                max: roundScore(min(1, value + tolerance))
            )
        }

        private static func roundScore(_ value: Double) -> Double {
            (value * 10_000).rounded() / 10_000
        }
    }

    public struct TargetMatchSnapshot: Codable, Equatable, Sendable {
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
        public let overall: Double

        public init(score: TargetMatchScore) {
            self.composition = score.composition
            self.subjectPosition = score.subjectPosition
            self.cameraAngle = score.cameraAngle
            self.lighting = score.lighting
            self.background = score.background
            self.horizon = score.horizon
            self.pose = score.pose
            self.sharpnessProbability = score.sharpnessProbability
            self.exposure = score.exposure
            self.intentMatch = score.intentMatch
            self.overall = score.overall
        }
    }
}

public enum CalibrationSamplePromotionError: Error, Equatable, Sendable {
    case candidateKindRequired
    case minimumBlindReviewsRequired
    case rankedWeaknessRequired
    case singlePhoneRequired
    case offlineCaptureRequired
    case realCaptureRequired
    case invalidTolerance
}

public struct CalibrationSampleExporter: Sendable {
    public init() {}

    public func makeCandidate(
        prompt: String,
        sceneState: SceneState,
        deviceCapability: DeviceCapability,
        aiResult: AiPipelineResult,
        usesFrontCameraForSelfShot: Bool,
        referencePhotoActive: Bool,
        capturedAt: Date = Date()
    ) -> CalibrationSample {
        CalibrationSample(
            id: sampleId(frameId: sceneState.frameId, capturedAt: capturedAt),
            version: "2026.08.17",
            sampleKind: .iphoneCaptureCandidate,
            prompt: prompt,
            captureMetadata: .init(
                capturedAt: capturedAt,
                deviceModel: deviceCapability.model,
                usesFrontCameraForSelfShot: usesFrontCameraForSelfShot,
                referencePhotoActive: referencePhotoActive
            ),
            privacy: .init(
                singlePhoneOnly: aiResult.shotSpec.constraints.singlePhoneOnly,
                cloudAnalysisUsed: false,
                generativeEditsAllowed: aiResult.shotSpec.constraints.generativeEditsAllowed,
                identityRecognitionAllowed: aiResult.shotSpec.subject.identityRecognitionAllowed
            ),
            deviceCapability: deviceCapability,
            sceneState: sceneState,
            shotSpec: aiResult.shotSpec,
            shotPlan: aiResult.shotPlan,
            guidanceAction: aiResult.guidanceAction,
            targetMatch: .init(score: aiResult.targetMatch)
        )
    }

    public func encode(_ sample: CalibrationSample) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sample)
    }

    public func encodeJSONString(_ sample: CalibrationSample) throws -> String {
        let data = try encode(sample)
        return String(decoding: data, as: UTF8.self)
    }

    private func sampleId(frameId: String, capturedAt: Date) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
        let sanitizedFrameId = frameId.lowercased().unicodeScalars.reduce(into: "") { result, scalar in
            let character = allowedCharacters.contains(scalar) ? Character(scalar) : "_"
            if character != "_" || result.last != "_" {
                result.append(character)
            }
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let frameComponent = sanitizedFrameId.isEmpty ? "frame" : sanitizedFrameId
        return "candidate_\(frameComponent)_\(Int(capturedAt.timeIntervalSince1970))"
    }
}

public struct CalibrationSamplePromoter: Sendable {
    public init() {}

    public func makeReviewedSample(
        from candidate: CalibrationSample,
        review: CalibrationSample.ReviewLabel,
        tolerance: Double = 0.02
    ) throws -> CalibrationSample {
        guard candidate.sampleKind == .iphoneCaptureCandidate else {
            throw CalibrationSamplePromotionError.candidateKindRequired
        }
        guard review.reviewCount >= 2 else {
            throw CalibrationSamplePromotionError.minimumBlindReviewsRequired
        }
        guard !review.rankedWeaknesses.isEmpty else {
            throw CalibrationSamplePromotionError.rankedWeaknessRequired
        }
        guard candidate.privacy.singlePhoneOnly else {
            throw CalibrationSamplePromotionError.singlePhoneRequired
        }
        guard !candidate.privacy.cloudAnalysisUsed, !candidate.privacy.generativeEditsAllowed, !candidate.privacy.identityRecognitionAllowed else {
            throw CalibrationSamplePromotionError.offlineCaptureRequired
        }
        guard !candidate.captureMetadata.deviceModel.isEmpty else {
            throw CalibrationSamplePromotionError.realCaptureRequired
        }
        guard tolerance > 0, tolerance <= 0.25 else {
            throw CalibrationSamplePromotionError.invalidTolerance
        }

        return CalibrationSample(
            id: reviewedSampleId(from: candidate.id),
            version: candidate.version,
            sampleKind: .iphoneCapture,
            sourceCandidateId: candidate.id,
            domain: review.domain,
            prompt: candidate.prompt,
            captureMetadata: candidate.captureMetadata,
            privacy: .init(
                singlePhoneOnly: true,
                cloudAnalysisUsed: false,
                generativeEditsAllowed: false,
                identityRecognitionAllowed: false
            ),
            deviceCapability: candidate.deviceCapability,
            sceneState: candidate.sceneState,
            shotSpec: candidate.shotSpec,
            shotPlan: candidate.shotPlan,
            guidanceAction: candidate.guidanceAction,
            targetMatch: candidate.targetMatch,
            blindPreference: .init(
                reviewCount: review.reviewCount,
                preferredGuidanceReason: review.preferredGuidanceReason.rawValue,
                rankedWeaknesses: review.rankedWeaknesses.map(\.rawValue),
                notes: review.notes
            ),
            expected: .init(
                singlePhoneOnly: true,
                targetMatch: .init(snapshot: candidate.targetMatch, tolerance: tolerance)
            )
        )
    }

    private func reviewedSampleId(from candidateId: String) -> String {
        if candidateId.hasPrefix("candidate_") {
            return "iphone_capture_\(candidateId.dropFirst("candidate_".count))"
        }

        return "iphone_capture_\(candidateId)"
    }
}
