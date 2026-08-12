import Foundation

public protocol ShotPlanning: Sendable {
    func makeInitialPlan(for shotSpec: ShotSpec, deviceCapability: DeviceCapability) -> ShotPlan
}

public struct BasicShotPlanner: ShotPlanning {
    public init() {}

    public func makeInitialPlan(for shotSpec: ShotSpec, deviceCapability: DeviceCapability) -> ShotPlan {
        makeInitialPlan(for: shotSpec, sceneState: nil, deviceCapability: deviceCapability)
    }

    public func makeInitialPlan(for shotSpec: ShotSpec, sceneState: SceneState?, deviceCapability: DeviceCapability) -> ShotPlan {
        let recommendedLens = recommendedLens(for: shotSpec, deviceCapability: deviceCapability)
        let targetZoom = recommendedLens == "telephoto" ? 2.0 : 1.0
        let isPortrait = shotSpec.domain == .portrait
        let realityMode = shotSpec.constraints.realityMode
        let photographerChanges = photographerGuidance(for: shotSpec, sceneState: sceneState)

        return ShotPlan(
            id: "plan_\(UUID().uuidString.lowercased())",
            shotSpecId: shotSpec.id,
            achievability: .init(
                natural: naturalAchievability(for: shotSpec, deviceCapability: deviceCapability),
                enhanced: 0.86,
                creative: 0.93,
                limitingFactors: limitingFactors(for: shotSpec, deviceCapability: deviceCapability)
            ),
            cameraControls: .init(
                recommendedLens: recommendedLens,
                targetZoom: targetZoom,
                targetExposureBias: shotSpec.cameraIntent.exposureStrategy == .protectHighlights ? -0.3 : 0,
                targetFocusMode: deviceCapability.manualFocusSupported ? .locked : .auto,
                targetWhiteBalance: .auto,
                stabilizationMode: deviceCapability.stabilizationModes.contains("cinematic") ? "cinematic" : deviceCapability.stabilizationModes.first,
                captureFormat: deviceCapability.rawSupported ? .rawPlusHeif : .heif
            ),
            photographerChanges: photographerChanges,
            subjectDirections: subjectGuidance(for: shotSpec, sceneState: sceneState),
            compositionTarget: .init(
                subjectBounds: isPortrait
                    ? .init(x: 0.3, y: 0.18, width: 0.4, height: 0.66)
                    : .init(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
                horizonY: shotSpec.domain == .landscape ? 0.38 : nil,
                crop: .init(x: 0, y: 0, width: 1, height: 1)
            ),
            processingIntent: .init(
                realityMode: realityMode,
                toneCurve: shotSpec.style.name == .cinematic ? .cinematicSoftContrast : .natural,
                colorTreatment: shotSpec.style.colorIntent?.rawValue ?? "natural",
                depthEffect: isPortrait ? .portraitIfAvailable : .natural
            ),
            previewConfiguration: .init(
                label: realityMode == .creative ? .aiEnhancementRequired : .captureRealistic,
                operations: ["crop_simulation", "exposure_bias", "tone_preview", "composition_overlay"]
            ),
            capturePolicy: .init(
                mode: .burst,
                burstFrameCount: 5,
                trigger: .readyAssist,
                readinessThreshold: 0.92
            )
        )
    }

    private func photographerGuidance(for shotSpec: ShotSpec, sceneState: SceneState?) -> [GuidanceAction] {
        guard let sceneState else {
            return [
                GuidanceAction(
                    id: "guide_center_subject",
                    actor: .photographer,
                    action: shotSpec.domain == .portrait ? .moveLeft : .holdSteady,
                    magnitude: shotSpec.domain == .portrait ? 0.25 : nil,
                    unit: shotSpec.domain == .portrait ? .meter : nil,
                    direction: shotSpec.domain == .portrait ? .left : nil,
                    confidence: 0.7,
                    reason: shotSpec.domain == .portrait ? .improveSubjectBackgroundSeparation : .readyToCapture,
                    expectedGain: shotSpec.domain == .portrait ? 0.12 : 0.04,
                    safetyQualifier: shotSpec.domain == .portrait ? .ifSafe : nil,
                    priority: 80,
                    ttlMs: 3500,
                    suppressOppositeUntilMs: 5000
                )
            ]
        }

        var actions: [GuidanceAction] = []

        if let horizon = sceneState.scene.horizon, abs(horizon.rollDegrees) > 2.5 {
            actions.append(GuidanceAction(
                id: "level_horizon",
                actor: .photographer,
                action: horizon.rollDegrees > 0 ? .rotateCounterclockwise : .rotateClockwise,
                magnitude: abs(horizon.rollDegrees),
                unit: .degree,
                direction: nil,
                confidence: horizon.confidence,
                reason: .levelHorizon,
                expectedGain: 0.14,
                safetyQualifier: .ifSafe,
                priority: 95,
                ttlMs: 3500,
                suppressOppositeUntilMs: 5000
            ))
        }

        if sceneState.background.clutterScore > 0.55,
           sceneState.safety.movementGuidanceAllowed,
           let cleanerDirection = sceneState.background.cleanerDirection,
           cleanerDirection != .unknown {
            actions.append(GuidanceAction(
                id: "reduce_background_clutter",
                actor: .photographer,
                action: action(for: cleanerDirection),
                magnitude: 0.4,
                unit: .meter,
                direction: cleanerDirection == .left ? .left : (cleanerDirection == .right ? .right : nil),
                confidence: 0.76,
                reason: .reduceClutter,
                expectedGain: 0.16,
                safetyQualifier: .ifSafe,
                priority: 88,
                ttlMs: 3500,
                suppressOppositeUntilMs: 5000
            ))
        }

        if sceneState.motion.blurRisk > 0.55 {
            actions.append(GuidanceAction(
                id: "hold_steady",
                actor: .photographer,
                action: .holdSteady,
                magnitude: nil,
                unit: nil,
                direction: nil,
                confidence: 0.82,
                reason: .reduceMotionBlur,
                expectedGain: 0.18,
                safetyQualifier: nil,
                priority: 90,
                ttlMs: 3500,
                suppressOppositeUntilMs: 5000
            ))
        }

        if sceneState.scene.lighting.highlightClipping > 0.22 {
            actions.append(GuidanceAction(
                id: "protect_highlights",
                actor: .camera,
                action: .adjustExposure,
                magnitude: -0.3,
                unit: .ev,
                direction: nil,
                confidence: 0.8,
                reason: .protectHighlights,
                expectedGain: 0.12,
                safetyQualifier: nil,
                priority: 82,
                ttlMs: 3500,
                suppressOppositeUntilMs: 5000
            ))
        }

        return actions.isEmpty ? [
            GuidanceAction(
                id: "hold_steady_ready",
                actor: .photographer,
                action: .holdSteady,
                magnitude: nil,
                unit: nil,
                direction: nil,
                confidence: 0.74,
                reason: .readyToCapture,
                expectedGain: 0.04,
                safetyQualifier: nil,
                priority: 50,
                ttlMs: 2500,
                suppressOppositeUntilMs: 2500
            )
        ] : actions
    }

    private func subjectGuidance(for shotSpec: ShotSpec, sceneState: SceneState?) -> [GuidanceAction] {
        guard shotSpec.domain == .portrait, let sceneState, sceneState.scene.lighting.faceLightQuality ?? 0.7 < 0.55 else {
            return []
        }

        return [
            GuidanceAction(
                id: "turn_toward_light",
                actor: .subject,
                action: .turnFace,
                magnitude: 10,
                unit: .degree,
                direction: .towardLight,
                confidence: 0.68,
                reason: .improveFaceLight,
                expectedGain: 0.12,
                safetyQualifier: nil,
                priority: 72,
                ttlMs: 3500,
                suppressOppositeUntilMs: 5000
            )
        ]
    }

    private func action(for cleanerDirection: BackgroundState.CleanerDirection) -> GuidanceAction.Action {
        switch cleanerDirection {
        case .left:
            return .moveLeft
        case .right:
            return .moveRight
        case .forward:
            return .moveForward
        case .backward:
            return .ifSafeMove
        case .unknown:
            return .holdSteady
        }
    }

    private func recommendedLens(for shotSpec: ShotSpec, deviceCapability: DeviceCapability) -> String {
        if shotSpec.cameraIntent.targetLens == .twoXIfAvailable,
           deviceCapability.physicalCameras.contains(where: { $0.lensType == .telephoto || ($0.maxZoom ?? 1) >= 2 }) {
            return "telephoto"
        }

        if shotSpec.cameraIntent.targetLens == .ultraWide,
           deviceCapability.physicalCameras.contains(where: { $0.lensType == .ultraWide }) {
            return "ultra_wide"
        }

        return "wide"
    }

    private func naturalAchievability(for shotSpec: ShotSpec, deviceCapability: DeviceCapability) -> Double {
        var score = 0.78
        if shotSpec.domain == .portrait, deviceCapability.depthSupported {
            score += 0.07
        }
        if shotSpec.cameraIntent.targetLens == .twoXIfAvailable,
           deviceCapability.physicalCameras.contains(where: { $0.lensType == .telephoto || ($0.maxZoom ?? 1) >= 2 }) {
            score += 0.05
        }
        return min(score, 0.94)
    }

    private func limitingFactors(for shotSpec: ShotSpec, deviceCapability: DeviceCapability) -> [String] {
        var factors: [String] = []
        if shotSpec.domain == .portrait, !deviceCapability.depthSupported {
            factors.append("hardware_depth_unavailable")
        }
        if shotSpec.cameraIntent.targetLens == .twoXIfAvailable,
           !deviceCapability.physicalCameras.contains(where: { $0.lensType == .telephoto || ($0.maxZoom ?? 1) >= 2 }) {
            factors.append("true_telephoto_unavailable")
        }
        return factors
    }
}
