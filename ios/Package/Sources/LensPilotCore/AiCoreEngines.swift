import Foundation

public struct PreviewSafety: Codable, Equatable, Sendable {
    public let label: ShotPlan.Label
    public let userFacingDisclosure: String?
    public let allowedOperations: [String]
}

public struct BestShotCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sharpness: Double
    public let exposure: Double
    public let faceQuality: Double?
    public let poseScore: Double?
    public let composition: Double
    public let background: Double
    public let intentMatch: Double

    public init(id: String, sharpness: Double, exposure: Double, faceQuality: Double?, poseScore: Double?, composition: Double, background: Double, intentMatch: Double) {
        self.id = id
        self.sharpness = sharpness
        self.exposure = exposure
        self.faceQuality = faceQuality
        self.poseScore = poseScore
        self.composition = composition
        self.background = background
        self.intentMatch = intentMatch
    }
}

public struct RankedShot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let score: Double
    public let label: Label
    public let reasons: [String]

    public enum Label: String, Codable, Sendable {
        case best
        case alternative
    }
}

public struct AiPipelineResult: Codable, Equatable, Sendable {
    public let shotSpec: ShotSpec
    public let shotPlan: ShotPlan
    public let guidanceAction: GuidanceAction?
    public let targetMatch: TargetMatchScore
    public let previewSafety: PreviewSafety
}

public struct TargetMatchCalibration: Codable, Equatable, Sendable {
    public static let standard = TargetMatchCalibration()

    public let horizonRollFullPenaltyDegrees: Double
    public let eyeLevelPitchFullPenaltyDegrees: Double
    public let highlightClippingPenalty: Double
    public let shadowClippingPenalty: Double
    public let backgroundClutterPenalty: Double
    public let poleBehindHeadPenalty: Double
    public let dynamicRangeLightingPenalty: Double
    public let motionBlurPenalty: Double
    public let missingHorizonScore: Double
    public let missingFaceLightQuality: Double
    public let missingPoseScore: Double
    public let nonPortraitCameraAngleScore: Double

    public init(
        horizonRollFullPenaltyDegrees: Double = 12,
        eyeLevelPitchFullPenaltyDegrees: Double = 35,
        highlightClippingPenalty: Double = 0.8,
        shadowClippingPenalty: Double = 0.6,
        backgroundClutterPenalty: Double = 0.55,
        poleBehindHeadPenalty: Double = 0.25,
        dynamicRangeLightingPenalty: Double = 0.2,
        motionBlurPenalty: Double = 1,
        missingHorizonScore: Double = 0.72,
        missingFaceLightQuality: Double = 0.65,
        missingPoseScore: Double = 0.72,
        nonPortraitCameraAngleScore: Double = 0.75
    ) {
        self.horizonRollFullPenaltyDegrees = horizonRollFullPenaltyDegrees
        self.eyeLevelPitchFullPenaltyDegrees = eyeLevelPitchFullPenaltyDegrees
        self.highlightClippingPenalty = highlightClippingPenalty
        self.shadowClippingPenalty = shadowClippingPenalty
        self.backgroundClutterPenalty = backgroundClutterPenalty
        self.poleBehindHeadPenalty = poleBehindHeadPenalty
        self.dynamicRangeLightingPenalty = dynamicRangeLightingPenalty
        self.motionBlurPenalty = motionBlurPenalty
        self.missingHorizonScore = missingHorizonScore
        self.missingFaceLightQuality = missingFaceLightQuality
        self.missingPoseScore = missingPoseScore
        self.nonPortraitCameraAngleScore = nonPortraitCameraAngleScore
    }
}

public struct GuidanceCalibration: Equatable, Sendable {
    public static let standard = GuidanceCalibration()

    public let globalReasonBoosts: [String: Double]
    public let domainReasonBoosts: [String: [String: Double]]

    public init(
        globalReasonBoosts: [String: Double] = [:],
        domainReasonBoosts: [String: [String: Double]] = [:]
    ) {
        self.globalReasonBoosts = globalReasonBoosts.mapValues(Self.clampedBoost)
        self.domainReasonBoosts = domainReasonBoosts.mapValues { boosts in
            boosts.mapValues(Self.clampedBoost)
        }
    }

    public func scoreBoost(for action: GuidanceAction, domain: CaptureDomain?) -> Double {
        let reason = action.reason.rawValue
        let globalBoost = globalReasonBoosts[reason] ?? 0
        let domainBoost = domain.flatMap { domainReasonBoosts[$0.rawValue]?[reason] } ?? 0
        return Self.clampedBoost(globalBoost + domainBoost)
    }

    private static func clampedBoost(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(0.08, max(0, value))
    }
}

public struct GuidancePolicy: Sendable {
    private let calibration: GuidanceCalibration

    public init(calibration: GuidanceCalibration = .standard) {
        self.calibration = calibration
    }

    public func selectNextAction(from shotPlan: ShotPlan) -> GuidanceAction? {
        selectNextAction(from: shotPlan, domain: nil)
    }

    public func selectNextAction(from shotPlan: ShotPlan, domain: CaptureDomain?) -> GuidanceAction? {
        (shotPlan.photographerChanges + shotPlan.subjectDirections)
            .filter { $0.confidence >= 0.55 && $0.expectedGain >= 0.04 }
            .sorted { actionScore($0, domain: domain) > actionScore($1, domain: domain) }
            .first
    }

    private func actionScore(_ action: GuidanceAction, domain: CaptureDomain?) -> Double {
        let ease = action.actor == .camera ? 0.95 : (action.safetyQualifier == .ifSafe ? 0.72 : 0.8)
        let interactionCost = action.actor == .subject ? 0.08 : 0.04
        let safetyRisk = action.safetyQualifier == .ifSafe ? 0.08 : 0
        return action.expectedGain * action.confidence * ease - interactionCost - safetyRisk + Double(action.priority) / 1000 + calibration.scoreBoost(for: action, domain: domain)
    }
}

public struct TargetMatchEngine: Sendable {
    private let calibration: TargetMatchCalibration

    public init(calibration: TargetMatchCalibration = .standard) {
        self.calibration = calibration
    }

    public func score(shotSpec: ShotSpec, shotPlan: ShotPlan, sceneState: SceneState) -> TargetMatchScore {
        let subject = sceneState.subjects.first
        let target = shotPlan.compositionTarget.subjectBounds
        let subjectPosition = subject.map { rectSimilarity($0.bounds, target) } ?? 0.25
        let horizon = sceneState.scene.horizon.map { clamp01(1 - abs($0.rollDegrees) / max(calibration.horizonRollFullPenaltyDegrees, 0.001)) } ?? calibration.missingHorizonScore
        let exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * calibration.highlightClippingPenalty - sceneState.scene.lighting.shadowClipping * calibration.shadowClippingPenalty)
        let background = clamp01(1 - sceneState.background.clutterScore * calibration.backgroundClutterPenalty - sceneState.background.poleBehindHeadRisk * calibration.poleBehindHeadPenalty)
        let lighting = clamp01((sceneState.scene.lighting.faceLightQuality ?? calibration.missingFaceLightQuality) - sceneState.scene.lighting.dynamicRangeRisk * calibration.dynamicRangeLightingPenalty)
        let pose = clamp01(subject?.face?.eyeOpenProbability ?? calibration.missingPoseScore)
        let sharpness = clamp01(1 - sceneState.motion.blurRisk * calibration.motionBlurPenalty)
        let composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore])
        let pitch = sceneState.cameraState.pitchDegrees ?? 0
        let cameraAngle = shotSpec.cameraIntent.perspective == .eyeLevel ? clamp01(1 - abs(pitch) / max(calibration.eyeLevelPitchFullPenaltyDegrees, 0.001)) : calibration.nonPortraitCameraAngleScore
        let intentMatch = average([composition, lighting, background, exposure])

        return TargetMatchScore(
            composition: composition,
            subjectPosition: subjectPosition,
            cameraAngle: cameraAngle,
            lighting: lighting,
            background: background,
            horizon: horizon,
            pose: pose,
            sharpnessProbability: sharpness,
            exposure: exposure,
            intentMatch: intentMatch
        )
    }

    private func rectSimilarity(_ a: NormalizedRectangle, _ b: NormalizedRectangle) -> Double {
        let centerDistance = hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2))
        let sizeDistance = abs(a.width * a.height - b.width * b.height)
        return clamp01(1 - centerDistance * 1.8 - sizeDistance)
    }
}

public struct PreviewSafetyEngine: Sendable {
    public init() {}

    public func evaluate(shotSpec: ShotSpec, shotPlan: ShotPlan) -> PreviewSafety {
        if shotSpec.constraints.realityMode == .creative || shotSpec.constraints.generativeEditsAllowed {
            return PreviewSafety(
                label: .aiEnhancementRequired,
                userFacingDisclosure: "AI enhancement required after capture.",
                allowedOperations: ["generative_relight", "object_removal", "background_modification"]
            )
        }

        if shotSpec.constraints.realityMode == .enhanced {
            return PreviewSafety(
                label: .enhancedRealistic,
                userFacingDisclosure: nil,
                allowedOperations: ["crop", "tone", "color", "hdr", "depth_approximation"] + shotPlan.previewConfiguration.operations
            )
        }

        return PreviewSafety(
            label: .captureRealistic,
            userFacingDisclosure: nil,
            allowedOperations: ["crop", "exposure", "white_balance", "focus", "lens", "tone", "composition_overlay"]
        )
    }
}

public struct BestShotRanker: Sendable {
    public init() {}

    public func rank(_ candidates: [BestShotCandidate]) -> [RankedShot] {
        candidates
            .map { candidate in
                let score = average([
                    candidate.sharpness,
                    candidate.exposure,
                    candidate.faceQuality ?? 0.7,
                    candidate.poseScore ?? 0.7,
                    candidate.composition,
                    candidate.background,
                    candidate.intentMatch
                ])

                return RankedShot(
                    id: candidate.id,
                    score: score,
                    label: .alternative,
                    reasons: reasons(for: candidate)
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .enumerated()
            .map { index, shot in
                RankedShot(id: shot.id, score: shot.score, label: index == 0 ? .best : .alternative, reasons: shot.reasons)
            }
    }

    private func reasons(for candidate: BestShotCandidate) -> [String] {
        var reasons: [String] = []
        if candidate.sharpness > 0.82 { reasons.append("sharp") }
        if candidate.exposure > 0.8 { reasons.append("well_exposed") }
        if (candidate.faceQuality ?? 0) > 0.8 { reasons.append("good_face_quality") }
        if candidate.composition > 0.8 { reasons.append("strong_composition") }
        if candidate.intentMatch > 0.8 { reasons.append("matches_intent") }
        return reasons.isEmpty ? ["balanced_result"] : reasons
    }
}

public struct LensPilotAiCore: Sendable {
    private let intentEngine: ShotSpecFactory
    private let shotPlanner: BasicShotPlanner
    private let guidancePolicy: GuidancePolicy
    private let targetMatchEngine: TargetMatchEngine
    private let previewSafetyEngine: PreviewSafetyEngine

    public init(
        intentEngine: ShotSpecFactory = ShotSpecFactory(),
        shotPlanner: BasicShotPlanner = BasicShotPlanner(),
        guidancePolicy: GuidancePolicy = GuidancePolicy(),
        targetMatchEngine: TargetMatchEngine = TargetMatchEngine(),
        previewSafetyEngine: PreviewSafetyEngine = PreviewSafetyEngine()
    ) {
        self.intentEngine = intentEngine
        self.shotPlanner = shotPlanner
        self.guidancePolicy = guidancePolicy
        self.targetMatchEngine = targetMatchEngine
        self.previewSafetyEngine = previewSafetyEngine
    }

    public init(
        targetMatchCalibration: TargetMatchCalibration,
        guidanceCalibration: GuidanceCalibration = .standard
    ) {
        self.init(
            guidancePolicy: GuidancePolicy(calibration: guidanceCalibration),
            targetMatchEngine: TargetMatchEngine(calibration: targetMatchCalibration)
        )
    }

    public func run(prompt: String, sceneState: SceneState, deviceCapability: DeviceCapability) -> AiPipelineResult {
        let shotSpec = intentEngine.makeShotSpec(from: prompt, source: .text)
        let shotPlan = shotPlanner.makeInitialPlan(for: shotSpec, sceneState: sceneState, deviceCapability: deviceCapability)
        let guidanceAction = guidancePolicy.selectNextAction(from: shotPlan, domain: shotSpec.domain)
        let targetMatch = targetMatchEngine.score(shotSpec: shotSpec, shotPlan: shotPlan, sceneState: sceneState)
        let previewSafety = previewSafetyEngine.evaluate(shotSpec: shotSpec, shotPlan: shotPlan)

        return AiPipelineResult(
            shotSpec: shotSpec,
            shotPlan: shotPlan,
            guidanceAction: guidanceAction,
            targetMatch: targetMatch,
            previewSafety: previewSafety
        )
    }
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return clamp01(values.map(clamp01).reduce(0, +) / Double(values.count))
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}
