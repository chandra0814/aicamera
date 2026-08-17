import Foundation

public struct CalibrationSample: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let sampleKind: SampleKind
    public let prompt: String
    public let captureMetadata: CaptureMetadata
    public let privacy: Privacy
    public let deviceCapability: DeviceCapability
    public let sceneState: SceneState
    public let shotSpec: ShotSpec
    public let shotPlan: ShotPlan
    public let guidanceAction: GuidanceAction?
    public let targetMatch: TargetMatchSnapshot

    public init(
        id: String,
        version: String,
        sampleKind: SampleKind,
        prompt: String,
        captureMetadata: CaptureMetadata,
        privacy: Privacy,
        deviceCapability: DeviceCapability,
        sceneState: SceneState,
        shotSpec: ShotSpec,
        shotPlan: ShotPlan,
        guidanceAction: GuidanceAction?,
        targetMatch: TargetMatchSnapshot
    ) {
        self.id = id
        self.version = version
        self.sampleKind = sampleKind
        self.prompt = prompt
        self.captureMetadata = captureMetadata
        self.privacy = privacy
        self.deviceCapability = deviceCapability
        self.sceneState = sceneState
        self.shotSpec = shotSpec
        self.shotPlan = shotPlan
        self.guidanceAction = guidanceAction
        self.targetMatch = targetMatch
    }

    public enum SampleKind: String, Codable, Sendable {
        case fixtureSeed = "fixture_seed"
        case iphoneCaptureCandidate = "iphone_capture_candidate"
        case iphoneCapture = "iphone_capture"
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
