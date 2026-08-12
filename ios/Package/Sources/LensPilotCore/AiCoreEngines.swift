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

public struct GuidancePolicy: Sendable {
    public init() {}

    public func selectNextAction(from shotPlan: ShotPlan) -> GuidanceAction? {
        (shotPlan.photographerChanges + shotPlan.subjectDirections)
            .filter { $0.confidence >= 0.55 && $0.expectedGain >= 0.04 }
            .sorted { actionScore($0) > actionScore($1) }
            .first
    }

    private func actionScore(_ action: GuidanceAction) -> Double {
        let ease = action.actor == .camera ? 0.95 : (action.safetyQualifier == .ifSafe ? 0.72 : 0.8)
        let interactionCost = action.actor == .subject ? 0.08 : 0.04
        let safetyRisk = action.safetyQualifier == .ifSafe ? 0.08 : 0
        return action.expectedGain * action.confidence * ease - interactionCost - safetyRisk + Double(action.priority) / 1000
    }
}

public struct TargetMatchEngine: Sendable {
    public init() {}

    public func score(shotSpec: ShotSpec, shotPlan: ShotPlan, sceneState: SceneState) -> TargetMatchScore {
        let subject = sceneState.subjects.first
        let target = shotPlan.compositionTarget.subjectBounds
        let subjectPosition = subject.map { rectSimilarity($0.bounds, target) } ?? 0.25
        let horizon = sceneState.scene.horizon.map { clamp01(1 - abs($0.rollDegrees) / 12) } ?? 0.72
        let exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * 0.8 - sceneState.scene.lighting.shadowClipping * 0.6)
        let background = clamp01(1 - sceneState.background.clutterScore * 0.55 - sceneState.background.poleBehindHeadRisk * 0.25)
        let lighting = clamp01((sceneState.scene.lighting.faceLightQuality ?? 0.65) - sceneState.scene.lighting.dynamicRangeRisk * 0.2)
        let pose = clamp01(subject?.face?.eyeOpenProbability ?? 0.72)
        let sharpness = clamp01(1 - sceneState.motion.blurRisk)
        let composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore])
        let pitch = sceneState.cameraState.pitchDegrees ?? 0
        let cameraAngle = shotSpec.cameraIntent.perspective == .eyeLevel ? clamp01(1 - abs(pitch) / 35) : 0.75
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

    public func run(prompt: String, sceneState: SceneState, deviceCapability: DeviceCapability) -> AiPipelineResult {
        let shotSpec = intentEngine.makeShotSpec(from: prompt, source: .text)
        let shotPlan = shotPlanner.makeInitialPlan(for: shotSpec, sceneState: sceneState, deviceCapability: deviceCapability)
        let guidanceAction = guidancePolicy.selectNextAction(from: shotPlan)
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
