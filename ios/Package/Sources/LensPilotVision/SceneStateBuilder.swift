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
        let motion = motionState(for: debugState)
        let horizon = horizonState(for: debugState)
        let subjects = debugState.personBounds.enumerated().map { index, bounds in
            let faceMetric = nearestFaceMetric(to: bounds, in: debugState.faceMetrics)
            let poseMetric = nearestPoseMetric(to: bounds, in: debugState.poseMetrics)
            let faceQuality = faceQualityState(
                from: faceMetric,
                lighting: lighting,
                motion: motion
            )
            let pose = poseState(from: poseMetric, faceMetric: faceMetric)
            let confidenceBoost = (faceMetric == nil ? 0 : 0.08)
                + (poseMetric == nil ? 0 : 0.06)
                + (debugState.segmentationAvailable ? 0.04 : 0)

            SubjectObservation(
                id: "person_\(index + 1)_\(debugState.frameId)",
                type: .person,
                bounds: bounds.normalizedRectangle,
                segmentationAvailable: debugState.segmentationAvailable,
                pose: pose,
                face: faceQuality,
                distanceEstimateMeters: nil,
                confidence: clamp01(0.72 + confidenceBoost)
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
                rollDegrees: horizon?.rollDegrees ?? 0,
                pitchDegrees: nil
            ),
            deviceThermal: thermalState,
            scene: SceneSummary(
                category: subjects.isEmpty ? .unknown : .portrait,
                confidence: subjects.isEmpty ? 0.42 : clamp01(0.74 + (debugState.faceMetrics.isEmpty ? 0 : 0.06)),
                lighting: lighting,
                horizon: horizon,
                sky: nil
            ),
            subjects: subjects,
            background: backgroundState(for: debugState, primarySubject: primarySubject),
            motion: motion,
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
        let hasHorizon = debugState.horizon != nil || debugState.horizonY != nil

        return BackgroundState(
            clutterScore: clutter,
            brightDistractionScore: brightDistraction,
            poleBehindHeadRisk: 0.08,
            randomPeopleRisk: randomPeopleRisk,
            horizonIntersectionRisk: hasHorizon ? 0.08 : 0.16,
            cleanerDirection: cleanerDirection(for: primarySubject)
        )
    }

    private func motionState(for debugState: SceneDebugState) -> MotionState {
        if let motion = debugState.motion {
            return MotionState(
                cameraShake: clamp01(motion.cameraShake),
                subjectMotion: clamp01(motion.subjectMotion),
                blurRisk: clamp01(motion.blurRisk)
            )
        }

        let latency = debugState.frameLatencyMs ?? 0
        let latencyRisk = clamp01((latency - 80) / 240)
        let blurRisk = clamp01(0.16 + latencyRisk * 0.24)
        return MotionState(cameraShake: blurRisk * 0.6, subjectMotion: blurRisk * 0.4, blurRisk: blurRisk)
    }

    private func horizonState(for debugState: SceneDebugState) -> HorizonState? {
        if let horizon = debugState.horizon {
            return HorizonState(
                y: clamp01(horizon.y),
                rollDegrees: horizon.rollDegrees,
                confidence: clamp01(horizon.confidence)
            )
        }

        return debugState.horizonY.map {
            HorizonState(y: clamp01($0), rollDegrees: 0, confidence: 0.45)
        }
    }

    private func faceQualityState(
        from metric: FaceDebugMetric?,
        lighting: LightingState,
        motion: MotionState
    ) -> FaceQualityState {
        FaceQualityState(
            eyeOpenProbability: metric?.eyeOpenProbability,
            expressionStability: metric?.expressionStability,
            sharpnessProbability: metric?.sharpnessProbability ?? (1 - motion.blurRisk),
            skinExposureScore: metric?.skinExposureScore ?? lighting.faceLightQuality
        )
    }

    private func poseState(from metric: PoseDebugMetric?, faceMetric: FaceDebugMetric?) -> PoseState? {
        guard metric != nil || faceMetric?.faceYawDegrees != nil else {
            return nil
        }

        return PoseState(
            shouldersAngleDegrees: metric?.shouldersAngleDegrees,
            faceYawDegrees: faceMetric?.faceYawDegrees,
            eyeLineConfidence: metric?.eyeLineConfidence ?? faceMetric?.eyeOpenProbability,
            handAwkwardnessRisk: metric?.handAwkwardnessRisk
        )
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

    private func nearestFaceMetric(to subject: NormalizedRect, in metrics: [FaceDebugMetric]) -> FaceDebugMetric? {
        metrics.min { lhs, rhs in
            centerDistance(subject, lhs.bounds) < centerDistance(subject, rhs.bounds)
        }
    }

    private func nearestPoseMetric(to subject: NormalizedRect, in metrics: [PoseDebugMetric]) -> PoseDebugMetric? {
        metrics.compactMap { metric -> (metric: PoseDebugMetric, distance: Double)? in
            guard let bounds = metric.bounds else { return nil }
            return (metric, centerDistance(subject, bounds))
        }
        .min { lhs, rhs in lhs.distance < rhs.distance }?
        .metric
    }

    private func centerDistance(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        hypot(a.centerX - b.centerX, a.centerY - b.centerY)
    }
}

private extension NormalizedRect {
    var centerX: Double {
        x + width / 2
    }

    var centerY: Double {
        y + height / 2
    }

    var normalizedRectangle: NormalizedRectangle {
        NormalizedRectangle(x: x, y: y, width: width, height: height)
    }
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}
