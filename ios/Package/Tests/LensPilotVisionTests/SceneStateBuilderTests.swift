import XCTest
import LensPilotCore
@testable import LensPilotVision

final class SceneStateBuilderTests: XCTestCase {
    func testBuildsPortraitSceneFromDetectedPerson() {
        let debugState = SceneDebugState(
            frameId: "frame_live_001",
            timestamp: Date(timeIntervalSince1970: 10),
            personBounds: [
                NormalizedRect(x: 0.42, y: 0.2, width: 0.32, height: 0.58)
            ],
            horizonY: 0.48,
            exposureWarning: .balanced,
            frameLatencyMs: 64
        )

        let sceneState = SceneStateBuilder().makeSceneState(
            from: debugState,
            usesFrontCameraForSelfShot: false
        )

        XCTAssertEqual(sceneState.frameId, "frame_live_001")
        XCTAssertEqual(sceneState.cameraState.lensId, "back_wide")
        XCTAssertEqual(sceneState.scene.category, .portrait)
        XCTAssertEqual(sceneState.subjects.count, 1)
        XCTAssertEqual(sceneState.scene.horizon?.y, 0.48)
        XCTAssertGreaterThan(sceneState.composition.subjectPlacementScore, 0.6)
        XCTAssertTrue(sceneState.safety.movementGuidanceAllowed)
    }

    func testMapsExposureWarningIntoLightingRisk() {
        let debugState = SceneDebugState(
            frameId: "frame_hot",
            timestamp: Date(timeIntervalSince1970: 20),
            personBounds: [],
            horizonY: nil,
            exposureWarning: .clippedHighlights,
            frameLatencyMs: 120
        )

        let sceneState = SceneStateBuilder().makeSceneState(
            from: debugState,
            usesFrontCameraForSelfShot: true
        )

        XCTAssertEqual(sceneState.cameraState.lensId, "front_wide")
        XCTAssertEqual(sceneState.scene.category, .unknown)
        XCTAssertGreaterThan(sceneState.scene.lighting.highlightClipping, 0.3)
        XCTAssertGreaterThan(sceneState.scene.lighting.dynamicRangeRisk, 0.5)
        XCTAssertGreaterThanOrEqual(sceneState.motion.blurRisk, 0)
        XCTAssertLessThanOrEqual(sceneState.motion.blurRisk, 1)
    }

    func testMapsOnDeviceQualityMetricsIntoSceneState() {
        let debugState = SceneDebugState(
            frameId: "frame_metrics",
            timestamp: Date(timeIntervalSince1970: 30),
            personBounds: [
                NormalizedRect(x: 0.36, y: 0.18, width: 0.34, height: 0.6)
            ],
            horizonY: 0.51,
            horizon: HorizonDebugMetric(y: 0.51, rollDegrees: -4.2, confidence: 0.82),
            exposureWarning: .balanced,
            faceMetrics: [
                FaceDebugMetric(
                    bounds: NormalizedRect(x: 0.43, y: 0.56, width: 0.16, height: 0.18),
                    eyeOpenProbability: 0.88,
                    expressionStability: 0.79,
                    sharpnessProbability: 0.84,
                    skinExposureScore: 0.73,
                    faceYawDegrees: -8
                )
            ],
            poseMetrics: [
                PoseDebugMetric(
                    bounds: NormalizedRect(x: 0.34, y: 0.2, width: 0.36, height: 0.54),
                    shouldersAngleDegrees: 3.5,
                    eyeLineConfidence: 0.76,
                    handAwkwardnessRisk: 0.2
                )
            ],
            segmentationAvailable: true,
            motion: MotionDebugMetric(cameraShake: 0.21, subjectMotion: 0.14, blurRisk: 0.27),
            frameLatencyMs: 72
        )

        let sceneState = SceneStateBuilder().makeSceneState(
            from: debugState,
            usesFrontCameraForSelfShot: false
        )

        XCTAssertEqual(sceneState.cameraState.rollDegrees, -4.2)
        XCTAssertEqual(sceneState.scene.horizon?.confidence, 0.82)
        XCTAssertEqual(sceneState.motion.cameraShake, 0.21)
        XCTAssertEqual(sceneState.motion.subjectMotion, 0.14)
        XCTAssertEqual(sceneState.subjects.first?.segmentationAvailable, true)
        XCTAssertEqual(sceneState.subjects.first?.face?.eyeOpenProbability, 0.88)
        XCTAssertEqual(sceneState.subjects.first?.face?.sharpnessProbability, 0.84)
        XCTAssertEqual(sceneState.subjects.first?.pose?.shouldersAngleDegrees, 3.5)
        XCTAssertEqual(sceneState.subjects.first?.pose?.faceYawDegrees, -8)
        XCTAssertEqual(sceneState.subjects.first?.pose?.handAwkwardnessRisk, 0.2)
    }
}
