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
}
