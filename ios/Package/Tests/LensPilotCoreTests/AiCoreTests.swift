import XCTest
@testable import LensPilotCore

final class AiCoreTests: XCTestCase {
    func testAiCoreProducesSinglePhoneGuidanceAndTargetMatch() {
        let result = LensPilotAiCore().run(
            prompt: "Give me a cinematic portrait with natural skin and a clean background.",
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )

        XCTAssertTrue(result.shotSpec.constraints.singlePhoneOnly)
        XCTAssertFalse(result.shotSpec.subject.identityRecognitionAllowed)
        XCTAssertEqual(result.previewSafety.label, .captureRealistic)
        XCTAssertGreaterThanOrEqual(result.targetMatch.overall, 0)
        XCTAssertLessThanOrEqual(result.targetMatch.overall, 1)
        XCTAssertNotNil(result.guidanceAction)
    }

    func testBestShotRankerReturnsBestAndAlternatives() {
        let ranked = BestShotRanker().rank([
            BestShotCandidate(id: "frame_1", sharpness: 0.7, exposure: 0.8, faceQuality: 0.72, poseScore: 0.7, composition: 0.76, background: 0.7, intentMatch: 0.75),
            BestShotCandidate(id: "frame_2", sharpness: 0.92, exposure: 0.88, faceQuality: 0.9, poseScore: 0.86, composition: 0.84, background: 0.82, intentMatch: 0.88),
            BestShotCandidate(id: "frame_3", sharpness: 0.8, exposure: 0.76, faceQuality: 0.8, poseScore: 0.78, composition: 0.72, background: 0.74, intentMatch: 0.77)
        ])

        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(ranked.first?.id, "frame_2")
        XCTAssertEqual(ranked.first?.label, .best)
        XCTAssertEqual(ranked.dropFirst().map(\.label), [.alternative, .alternative])
    }

    func testTargetMatchCalibrationCanTuneBackgroundPenalty() {
        let shotSpec = ShotSpecFactory().makeShotSpec(
            from: "Give me a cinematic portrait with natural skin and a clean background.",
            source: .text
        )
        let shotPlan = BasicShotPlanner().makeInitialPlan(
            for: shotSpec,
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )
        let defaultScore = TargetMatchEngine().score(
            shotSpec: shotSpec,
            shotPlan: shotPlan,
            sceneState: Self.portraitScene()
        )
        let softerBackgroundCalibration = TargetMatchCalibration(backgroundClutterPenalty: 0.25)
        let tunedScore = TargetMatchEngine(calibration: softerBackgroundCalibration).score(
            shotSpec: shotSpec,
            shotPlan: shotPlan,
            sceneState: Self.portraitScene()
        )

        XCTAssertEqual(TargetMatchCalibration.standard.backgroundClutterPenalty, 0.55, accuracy: 0.0001)
        XCTAssertGreaterThan(tunedScore.background, defaultScore.background)
        XCTAssertGreaterThan(tunedScore.intentMatch, defaultScore.intentMatch)
    }

    func testCalibrationSampleExporterProducesSinglePhoneCandidateJSON() throws {
        let sceneState = Self.portraitScene()
        let deviceCapability = Self.deviceCapability()
        let prompt = "Give me a cinematic portrait with natural skin and a clean background."
        let result = LensPilotAiCore().run(
            prompt: prompt,
            sceneState: sceneState,
            deviceCapability: deviceCapability
        )
        let exporter = CalibrationSampleExporter()
        let sample = exporter.makeCandidate(
            prompt: prompt,
            sceneState: sceneState,
            deviceCapability: deviceCapability,
            aiResult: result,
            usesFrontCameraForSelfShot: false,
            referencePhotoActive: true,
            capturedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
        let data = try exporter.encode(sample)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationSample.self, from: data)

        XCTAssertEqual(decoded.sampleKind, CalibrationSample.SampleKind.iphoneCaptureCandidate)
        XCTAssertEqual(decoded.id, "candidate_frame_test_1786000000")
        XCTAssertTrue(decoded.privacy.singlePhoneOnly)
        XCTAssertFalse(decoded.privacy.cloudAnalysisUsed)
        XCTAssertFalse(decoded.privacy.generativeEditsAllowed)
        XCTAssertFalse(decoded.privacy.identityRecognitionAllowed)
        XCTAssertEqual(decoded.captureMetadata.deviceModel, "iPhone MVP Test Device")
        XCTAssertTrue(decoded.captureMetadata.referencePhotoActive)
        XCTAssertEqual(decoded.targetMatch.overall, result.targetMatch.overall, accuracy: 0.0001)
    }

    func testCaptureReviewBuilderRanksBurstFrames() {
        let aiResult = LensPilotAiCore().run(
            prompt: "Give me a cinematic portrait with natural skin and a clean background.",
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )

        let review = CaptureReviewBuilder().makeReview(
            frames: [
                CaptureFrameMetric(id: "capture_1", sequenceIndex: 0, byteCount: 18_400),
                CaptureFrameMetric(id: "capture_2", sequenceIndex: 1, byteCount: 18_940),
                CaptureFrameMetric(id: "capture_3", sequenceIndex: 2, byteCount: 18_280),
                CaptureFrameMetric(id: "capture_4", sequenceIndex: 3, byteCount: 18_120)
            ],
            targetMatch: aiResult.targetMatch
        )

        XCTAssertEqual(review.rankedShots.count, 3)
        XCTAssertEqual(review.rankedShots.first?.label, .best)
        XCTAssertNotNil(review.bestShotId)
        XCTAssertTrue(review.rankedShots.allSatisfy { $0.score >= 0 && $0.score <= 1 })
    }

    func testCaptureReviewBuilderHandlesEmptyBurst() {
        let review = CaptureReviewBuilder().makeReview(frames: [], targetMatch: nil)

        XCTAssertTrue(review.rankedShots.isEmpty)
        XCTAssertNil(review.bestShotId)
    }

    private static func portraitScene() -> SceneState {
        SceneState(
            timestamp: Date(timeIntervalSince1970: 0),
            frameId: "frame_test",
            cameraState: LiveCameraState(
                lensId: "back_wide",
                focalLength35mmEquivalent: 26,
                zoomFactor: 1,
                exposureBias: 0,
                orientation: .portrait,
                rollDegrees: 3.8,
                pitchDegrees: 4
            ),
            deviceThermal: .nominal,
            scene: SceneSummary(
                category: .portrait,
                confidence: 0.86,
                lighting: LightingState(
                    exposureMean: 0.54,
                    highlightClipping: 0.18,
                    shadowClipping: 0.08,
                    faceLightQuality: 0.48,
                    direction: .frontLeft,
                    dynamicRangeRisk: 0.34
                ),
                horizon: HorizonState(y: 0.47, rollDegrees: 3.8, confidence: 0.81),
                sky: SkyState(visibleFraction: 0.22, sunsetLikelihood: 0.38, cloudInterest: 0.44, highlightRisk: 0.18)
            ),
            subjects: [
                SubjectObservation(
                    id: "subject_001",
                    type: .person,
                    bounds: NormalizedRectangle(x: 0.42, y: 0.22, width: 0.33, height: 0.58),
                    segmentationAvailable: true,
                    pose: PoseState(shouldersAngleDegrees: 4, faceYawDegrees: -8, eyeLineConfidence: 0.78, handAwkwardnessRisk: 0.22),
                    face: FaceQualityState(eyeOpenProbability: 0.91, expressionStability: 0.76, sharpnessProbability: 0.83, skinExposureScore: 0.72),
                    distanceEstimateMeters: 2.1,
                    confidence: 0.9
                )
            ],
            background: BackgroundState(
                clutterScore: 0.66,
                brightDistractionScore: 0.34,
                poleBehindHeadRisk: 0.18,
                randomPeopleRisk: 0.12,
                horizonIntersectionRisk: 0.2,
                cleanerDirection: .left
            ),
            motion: MotionState(cameraShake: 0.18, subjectMotion: 0.12, blurRisk: 0.2),
            composition: CompositionState(subjectPlacementScore: 0.61, headroomScore: 0.72, balanceScore: 0.58, leadingLinesScore: nil, negativeSpaceScore: 0.52),
            safety: SafetyState(hazards: [], movementGuidanceAllowed: true, confidence: 0.82)
        )
    }

    private static func deviceCapability() -> DeviceCapability {
        DeviceCapability(
            manufacturer: "Apple",
            model: "iPhone MVP Test Device",
            physicalCameras: [
                CameraCapability(id: "back_wide", position: .back, lensType: .wide, minZoom: 1, maxZoom: 5, supportsFocusLock: true, supportsExposureLock: true),
                CameraCapability(id: "back_tele", position: .back, lensType: .telephoto, minZoom: 2, maxZoom: 15, supportsFocusLock: true, supportsExposureLock: true),
                CameraCapability(id: "front_wide", position: .front, lensType: .wide, minZoom: 1, maxZoom: 2, supportsFocusLock: true, supportsExposureLock: true)
            ],
            rawSupported: true,
            depthSupported: true,
            manualExposureSupported: true,
            manualFocusSupported: true,
            manualWhiteBalanceSupported: true,
            hdrSupported: true,
            nightExtensionSupported: false,
            portraitExtensionSupported: true,
            stabilizationModes: ["standard", "cinematic"],
            thermalClass: "nominal",
            measuredCameraLatency: 180
        )
    }
}
