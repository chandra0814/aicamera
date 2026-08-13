import Foundation
import LensPilotCore

public struct SceneStateBuilder: Sendable {
    public init() {}

    public func makeSceneState(
        from debugState: SceneDebugState,
        usesFrontCameraForSelfShot: Bool,
        thermalState: ThermalState? = .nominal
    ) -> SceneState {
        let primarySubject = debugState.personBounds.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
        let lighting = lightingState(for: debugState.exposureWarning)
        let subjects = debugState.personBounds.enumerated().map { index, bounds in
            SubjectObservation(
                id: "person_\(index + 1)_\(debugState.frameId)",
                type: .person,
                bounds: bounds.normalizedRectangle,
                segmentationAvailable: false,
                pose: nil,
                face: FaceQualityState(
                    eyeOpenProbability: nil,
                    expressionStability: nil,
                    sharpnessProbability: 1 - motionState(for: debugState).blurRisk,
                    skinExposureScore: lighting.faceLightQuality
                ),
                distanceEstimateMeters: nil,
                confidence: 0.72
            )
        }

        return SceneState(
            timestamp: debugState.timestamp,
            frameId: debugState.frameId,
            cameraState: LiveCameraState(
                lensId: usesFrontCameraForSelfShot ? "front_wide" : "back_wide",
                focalLength35mmEquivalent: usesFrontCameraForSelfShot ? 24 : 26,
                zoomFactor: 1,
                exposureBias: 0,
                orientation: .portrait,
                rollDegrees: 0,
                pitchDegrees: nil
            ),
            deviceThermal: thermalState,
            scene: SceneSummary(
                category: subjects.isEmpty ? .unknown : .portrait,
                confidence: subjects.isEmpty ? 0.42 : 0.74,
                lighting: lighting,
                horizon: debugState.horizonY.map { HorizonState(y: clamp01($0), rollDegrees: 0, confidence: 0.45) },
                sky: nil
            ),
            subjects: subjects,
            background: backgroundState(for: debugState, primarySubject: primarySubject),
            motion: motionState(for: debugState),
            composition: compositionState(for: primarySubject),
            safety: SafetyState(hazards: [], movementGuidanceAllowed: true, confidence: 0.72)
        )
    }

    private func lightingState(for warning: ExposureWarning?) -> LightingState {
        switch warning {
        case .underexposed:
            return LightingState(
                exposureMean: 0.24,
                highlightClipping: 0.02,
                shadowClipping: 0.48,
                faceLightQuality: 0.32,
                direction: .unknown,
                dynamicRangeRisk: 0.42
            )
        case .clippedHighlights:
            return LightingState(
                exposureMean: 0.86,
                highlightClipping: 0.42,
                shadowClipping: 0.04,
                faceLightQuality: 0.46,
                direction: .unknown,
                dynamicRangeRisk: 0.58
            )
        case .balanced:
            return LightingState(
                exposureMean: 0.54,
                highlightClipping: 0.08,
                shadowClipping: 0.08,
                faceLightQuality: 0.68,
                direction: .front,
                dynamicRangeRisk: 0.18
            )
        case nil:
            return LightingState(
                exposureMean: 0.5,
                highlightClipping: 0.12,
                shadowClipping: 0.12,
                faceLightQuality: 0.58,
                direction: .unknown,
                dynamicRangeRisk: 0.24
            )
        }
    }

    private func backgroundState(for debugState: SceneDebugState, primarySubject: NormalizedRect?) -> BackgroundState {
        let extraPeople = max(0, debugState.personBounds.count - 1)
        let randomPeopleRisk = clamp01(Double(extraPeople) * 0.22)
        let brightDistraction = debugState.exposureWarning == .clippedHighlights ? 0.46 : 0.18
        let clutter = clamp01(0.24 + randomPeopleRisk + brightDistraction * 0.35)

        return BackgroundState(
            clutterScore: clutter,
            brightDistractionScore: brightDistraction,
            poleBehindHeadRisk: 0.08,
            randomPeopleRisk: randomPeopleRisk,
            horizonIntersectionRisk: debugState.horizonY == nil ? 0.16 : 0.08,
            cleanerDirection: cleanerDirection(for: primarySubject)
        )
    }

    private func motionState(for debugState: SceneDebugState) -> MotionState {
        let latency = debugState.frameLatencyMs ?? 0
        let latencyRisk = clamp01((latency - 80) / 240)
        let blurRisk = clamp01(0.16 + latencyRisk * 0.24)
        return MotionState(cameraShake: blurRisk * 0.6, subjectMotion: blurRisk * 0.4, blurRisk: blurRisk)
    }

    private func compositionState(for primarySubject: NormalizedRect?) -> CompositionState {
        guard let primarySubject else {
            return CompositionState(
                subjectPlacementScore: 0.45,
                headroomScore: nil,
                balanceScore: 0.5,
                leadingLinesScore: nil,
                negativeSpaceScore: 0.54
            )
        }

        let target = NormalizedRectangle(x: 0.3, y: 0.18, width: 0.4, height: 0.66)
        let placement = rectSimilarity(primarySubject.normalizedRectangle, target)
        let centerX = primarySubject.x + primarySubject.width / 2
        let balance = clamp01(1 - abs(centerX - 0.5) * 1.6)
        let headroom = clamp01(1 - abs(primarySubject.y - 0.18) * 2)

        return CompositionState(
            subjectPlacementScore: placement,
            headroomScore: headroom,
            balanceScore: balance,
            leadingLinesScore: nil,
            negativeSpaceScore: clamp01(1 - primarySubject.width * primarySubject.height)
        )
    }

    private func cleanerDirection(for subject: NormalizedRect?) -> BackgroundState.CleanerDirection? {
        guard let subject else { return .unknown }
        let centerX = subject.x + subject.width / 2
        if centerX > 0.58 { return .left }
        if centerX < 0.42 { return .right }
        return .unknown
    }

    private func rectSimilarity(_ a: NormalizedRectangle, _ b: NormalizedRectangle) -> Double {
        let centerDistance = hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2))
        let sizeDistance = abs(a.width * a.height - b.width * b.height)
        return clamp01(1 - centerDistance * 1.8 - sizeDistance)
    }
}

private extension NormalizedRect {
    var normalizedRectangle: NormalizedRectangle {
        NormalizedRectangle(x: x, y: y, width: width, height: height)
    }
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}
