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
        XCTAssertEqual(result.targetPreview.label, result.previewSafety.label)
        XCTAssertEqual(result.targetPreview.estimatedAchievability, result.shotPlan.achievability.natural, accuracy: 0.0001)
        XCTAssertEqual(result.targetPreview.subjectBounds, result.shotPlan.compositionTarget.subjectBounds)
        XCTAssertTrue(result.targetPreview.operations.contains("composition_overlay"))
        XCTAssertTrue(result.targetPreview.privacy.singlePhoneOnly)
        XCTAssertFalse(result.targetPreview.privacy.usesRawCameraFrameUpload)
        XCTAssertFalse(result.targetPreview.privacy.usesPrivatePhotoUpload)
        XCTAssertGreaterThanOrEqual(result.targetMatch.overall, 0)
        XCTAssertLessThanOrEqual(result.targetMatch.overall, 1)
        XCTAssertNotNil(result.guidanceAction)
    }

    func testPreviewAdjustmentPromptsTuneTheSamePhoneShotPlan() {
        let factory = ShotSpecFactory()
        let planner = BasicShotPlanner()
        let deviceCapability = Self.deviceCapability()
        let baseSpec = factory.makeShotSpec(from: "Give me a cinematic portrait.", source: .text)
        let basePlan = planner.makeInitialPlan(for: baseSpec, sceneState: nil, deviceCapability: deviceCapability)
        let moreSkySpec = factory.makeShotSpec(from: "Give me a cinematic portrait. Show more sky.", source: .text)
        let moreSkyPlan = planner.makeInitialPlan(for: moreSkySpec, sceneState: nil, deviceCapability: deviceCapability)
        let brighterSpec = factory.makeShotSpec(from: "Take a natural lifestyle photo. Make it brighter.", source: .text)
        let brighterPlan = planner.makeInitialPlan(for: brighterSpec, sceneState: nil, deviceCapability: deviceCapability)
        let lessBlurSpec = factory.makeShotSpec(from: "Give me a cinematic portrait. Use less background blur.", source: .text)
        let lessBlurPlan = planner.makeInitialPlan(for: lessBlurSpec, sceneState: nil, deviceCapability: deviceCapability)
        let naturalColorSpec = factory.makeShotSpec(from: "Give me a cinematic portrait. Keep colors natural.", source: .text)

        XCTAssertEqual(moreSkySpec.composition.skyPriority, .some(.high))
        XCTAssertNotNil(moreSkyPlan.compositionTarget.horizonY)
        XCTAssertGreaterThan(moreSkyPlan.compositionTarget.subjectBounds.y, basePlan.compositionTarget.subjectBounds.y)
        XCTAssertLessThan(moreSkyPlan.compositionTarget.subjectBounds.height, basePlan.compositionTarget.subjectBounds.height)
        XCTAssertTrue(moreSkyPlan.previewConfiguration.operations.contains("sky_framing_guide"))

        XCTAssertEqual(brighterSpec.cameraIntent.exposureStrategy, .some(.brighten))
        XCTAssertEqual(brighterPlan.cameraControls.targetExposureBias ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertTrue(brighterPlan.previewConfiguration.operations.contains("exposure_lift"))

        XCTAssertEqual(lessBlurSpec.cameraIntent.depthIntent, .some(.naturalDepth))
        XCTAssertEqual(lessBlurPlan.processingIntent.depthEffect, .natural)
        XCTAssertTrue(lessBlurPlan.previewConfiguration.operations.contains("deep_focus_preview"))

        XCTAssertEqual(naturalColorSpec.style.name, .cinematic)
        XCTAssertEqual(naturalColorSpec.style.colorIntent, .some(.natural))
        XCTAssertTrue(naturalColorSpec.constraints.singlePhoneOnly)
        XCTAssertFalse(naturalColorSpec.constraints.cloudAllowed)
        XCTAssertFalse(naturalColorSpec.constraints.generativeEditsAllowed)
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

    func testTargetMatchCalibrationManifestBuildsCalibratedAiCore() throws {
        let manifest = try TargetMatchCalibrationManifest.decode(
            from: Self.calibrationManifestData(backgroundClutterPenalty: 0.25)
        )
        let guidanceCalibration = manifest.makeGuidanceCalibration()
        let defaultResult = LensPilotAiCore().run(
            prompt: "Give me a cinematic portrait with natural skin and a clean background.",
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )
        let calibratedResult = manifest.makeAiCore().run(
            prompt: "Give me a cinematic portrait with natural skin and a clean background.",
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )

        XCTAssertEqual(manifest.reviewedSampleCount, 1)
        XCTAssertEqual(manifest.reviewedDomains, ["portrait"])
        XCTAssertEqual(manifest.collectionPlan.requiredScenarios, CalibrationCaptureScenario.allCases.map(\.rawValue))
        let readinessReport = manifest.makeCalibrationReadinessReport()
        XCTAssertEqual(readinessReport.status, .needsMoreSamples)
        XCTAssertEqual(readinessReport.reviewedSampleCount, 1)
        XCTAssertEqual(readinessReport.targetRealCaptureCount, 24)
        XCTAssertEqual(readinessReport.missingSampleCount, 23)
        XCTAssertEqual(readinessReport.reviewedDomains, ["portrait"])
        XCTAssertTrue(readinessReport.missingDomains.contains("landscape"))
        XCTAssertEqual(readinessReport.scenarioTargetCount, 3)
        XCTAssertEqual(readinessReport.scenarioCounts["clutter"], 1)
        XCTAssertTrue(readinessReport.missingScenarios.contains("clutter"))
        XCTAssertEqual(readinessReport.nextMissingScenario, .portrait)
        XCTAssertFalse(readinessReport.isReadyForProductionCalibration)
        XCTAssertEqual(manifest.targetMatchCalibration.backgroundClutterPenalty, 0.25, accuracy: 0.0001)
        XCTAssertGreaterThan(calibratedResult.targetMatch.background, defaultResult.targetMatch.background)
        XCTAssertGreaterThan(calibratedResult.targetMatch.intentMatch, defaultResult.targetMatch.intentMatch)

        let clutterAction = try XCTUnwrap(
            calibratedResult.shotPlan.photographerChanges.first { $0.reason == .reduceClutter }
        )
        XCTAssertGreaterThan(guidanceCalibration.scoreBoost(for: clutterAction, domain: .portrait), 0)
        XCTAssertEqual(guidanceCalibration.scoreBoost(for: clutterAction, domain: .landscape), 0, accuracy: 0.0001)
        XCTAssertNotEqual(defaultResult.guidanceAction?.reason, calibratedResult.guidanceAction?.reason)
        XCTAssertEqual(calibratedResult.guidanceAction?.reason, .reduceClutter)
    }

    func testTargetMatchCalibrationReadinessPassesCompleteReviewedScenarioSet() throws {
        let samples = CalibrationCaptureScenario.allCases.flatMap { scenario in
            (0..<scenario.targetSampleCount).map { index in
                TargetMatchCalibrationManifest.SampleSummary(
                    id: "iphone_capture_\(scenario.rawValue)_\(index)",
                    sampleKind: "iphone_capture",
                    domain: scenario.domain.rawValue,
                    captureMetadata: .init(calibrationScenarioId: scenario.rawValue),
                    blindPreference: .init(
                        reviewCount: 2,
                        preferredGuidanceReason: scenario.preferredGuidanceReason.rawValue,
                        rankedWeaknesses: scenario.rankedWeaknesses.map(\.rawValue),
                        notes: "Reviewed \(scenario.title) calibration sample."
                    )
                )
            }
        }
        let manifest = try TargetMatchCalibrationManifest(
            version: "2026.08.30",
            collectionPlan: .init(
                singlePhoneOnly: true,
                realCaptureTargetCount: 24,
                minimumBlindReviewers: 2,
                requiredDomains: ["portrait", "landscape", "lifestyle", "night"],
                requiredScenarios: CalibrationCaptureScenario.allCases.map(\.rawValue)
            ),
            targetMatchCalibration: .standard,
            samples: samples
        )

        let readinessReport = manifest.makeCalibrationReadinessReport()

        XCTAssertEqual(readinessReport.status, .ready)
        XCTAssertEqual(readinessReport.reviewedSampleCount, 24)
        XCTAssertEqual(readinessReport.missingSampleCount, 0)
        XCTAssertEqual(readinessReport.missingDomains, [])
        XCTAssertEqual(readinessReport.missingScenarios, [])
        XCTAssertEqual(readinessReport.scenarioCounts["night"], 3)
        XCTAssertNil(readinessReport.nextMissingScenario)
        XCTAssertTrue(readinessReport.isReadyForProductionCalibration)
    }

    func testTargetMatchCalibrationManifestRejectsNonSinglePhonePlan() {
        XCTAssertThrowsError(try TargetMatchCalibrationManifest.decode(
            from: Self.calibrationManifestData(singlePhoneOnly: false)
        )) { error in
            XCTAssertEqual(error as? TargetMatchCalibrationManifestError, .singlePhoneCalibrationRequired)
        }
    }

    func testTargetMatchCalibrationManifestRejectsUnknownScenario() {
        XCTAssertThrowsError(try TargetMatchCalibrationManifest.decode(
            from: Self.calibrationManifestData(requiredScenarios: ["portrait", "two_phone_setup"])
        )) { error in
            XCTAssertEqual(error as? TargetMatchCalibrationManifestError, .invalidScenario("two_phone_setup"))
        }
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
            calibrationScenario: .clutter,
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
        XCTAssertEqual(decoded.captureMetadata.calibrationScenarioId, "clutter")
        XCTAssertEqual(decoded.targetMatch.overall, result.targetMatch.overall, accuracy: 0.0001)
    }

    func testCalibrationSamplePromoterProducesReviewedSinglePhoneJSON() throws {
        let sceneState = Self.portraitScene()
        let deviceCapability = Self.deviceCapability()
        let prompt = "Give me a cinematic portrait with natural skin and a clean background."
        let result = LensPilotAiCore().run(
            prompt: prompt,
            sceneState: sceneState,
            deviceCapability: deviceCapability
        )
        let exporter = CalibrationSampleExporter()
        let candidate = exporter.makeCandidate(
            prompt: prompt,
            sceneState: sceneState,
            deviceCapability: deviceCapability,
            aiResult: result,
            usesFrontCameraForSelfShot: false,
            referencePhotoActive: true,
            capturedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
        let promoter = CalibrationSamplePromoter()
        let reviewed = try promoter.makeReviewedSample(
            from: candidate,
            review: .init(
                domain: .portrait,
                reviewCount: 2,
                preferredGuidanceReason: .reduceClutter,
                rankedWeaknesses: [.background, .lighting],
                notes: "Blind review preferred the cleaner-background direction."
            )
        )
        let data = try exporter.encode(reviewed)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationSample.self, from: data)

        XCTAssertEqual(decoded.id, "iphone_capture_frame_test_1786000000")
        XCTAssertEqual(decoded.sourceCandidateId, "candidate_frame_test_1786000000")
        XCTAssertEqual(decoded.sampleKind, .iphoneCapture)
        XCTAssertEqual(decoded.domain, .portrait)
        XCTAssertEqual(decoded.blindPreference?.reviewCount, 2)
        XCTAssertEqual(decoded.blindPreference?.preferredGuidanceReason, "reduce_clutter")
        XCTAssertEqual(decoded.blindPreference?.rankedWeaknesses, ["background", "lighting"])
        XCTAssertEqual(decoded.expected?.singlePhoneOnly, true)
        XCTAssertLessThanOrEqual(decoded.expected?.targetMatch.overall.min ?? 1, result.targetMatch.overall)
        XCTAssertGreaterThanOrEqual(decoded.expected?.targetMatch.overall.max ?? 0, result.targetMatch.overall)
        XCTAssertTrue(decoded.privacy.singlePhoneOnly)
        XCTAssertFalse(decoded.privacy.cloudAnalysisUsed)
        XCTAssertFalse(decoded.privacy.generativeEditsAllowed)
        XCTAssertFalse(decoded.privacy.identityRecognitionAllowed)
    }

    func testCaptureReviewBuilderRanksBurstFrames() throws {
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

        let summary = try XCTUnwrap(review.coachingSummary)
        XCTAssertEqual(summary.headline, "Needs another pass")
        XCTAssertEqual(summary.topCorrectionReason, .improveFaceLight)
        XCTAssertEqual(summary.nextShotInstruction, "Next shot: turn toward cleaner light")
        XCTAssertTrue(summary.positiveSignals.contains { $0.id == "pose" })
        XCTAssertTrue(summary.improvementSignals.contains { $0.id == "lighting" })
        XCTAssertTrue(summary.privacy.singlePhoneOnly)
        XCTAssertFalse(summary.privacy.storesRawPhoto)
        XCTAssertFalse(summary.privacy.uploadsLiveCameraFrame)
        XCTAssertFalse(summary.privacy.identityRecognitionAllowed)
    }

    func testCaptureReviewBuilderHandlesEmptyBurst() {
        let review = CaptureReviewBuilder().makeReview(frames: [], targetMatch: nil)

        XCTAssertTrue(review.rankedShots.isEmpty)
        XCTAssertNil(review.bestShotId)
        XCTAssertNil(review.coachingSummary)
    }

    func testSinglePhoneAiDiagnosticsReportPassesSafeOnDeviceFlows() throws {
        let prompt = "Give me a cinematic portrait with online inspiration."
        let aiResult = LensPilotAiCore().run(
            prompt: prompt,
            sceneState: Self.portraitScene(),
            deviceCapability: Self.deviceCapability()
        )
        let profile = PersonalVisualPreferenceProfile(
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true),
            totalEvents: 1
        )
        let plan = try XCTUnwrap(PersonalVisualLearningEngine().makeOnlineReferencePlan(
            for: aiResult.shotSpec,
            prompt: prompt,
            profile: profile
        ))
        let creativePlan = try XCTUnwrap(PersonalVisualLearningEngine().makeCreativeInterpretationPlan(
            for: aiResult.shotSpec,
            prompt: prompt,
            profile: profile,
            onlineReferencePlan: plan
        ))
        let healthSnapshot = OnlineInspirationHealthSnapshot(
            planId: plan.id,
            source: .publicSources,
            providers: [
                OnlineInspirationProviderHealth.available(source: .wikimediaCommons, resultCount: 2)
            ]
        )
        let captureReview = CaptureReviewBuilder().makeReview(
            frames: [
                CaptureFrameMetric(id: "diagnostic_1", sequenceIndex: 0, byteCount: 18_800),
                CaptureFrameMetric(id: "diagnostic_2", sequenceIndex: 1, byteCount: 18_200)
            ],
            targetMatch: aiResult.targetMatch
        )

        let report = SinglePhoneAiDiagnosticsReport.make(
            hasShotPlan: true,
            referencePhoto: Self.referencePhoto(cloudAnalysisUsed: false, showCameraPopup: true),
            onlineReferencePlan: plan,
            creativeInterpretationPlan: creativePlan,
            creativeAPIConfigurationStatus: LensPilotCreativeInterpretationAPIProvider.configurationStatus(
                apiURLValue: "https://lenspilot.example/v1/creative-interpretation?token=should_not_be_reported",
                clientTokenValue: "phone-client-token-should-not-be-reported",
                signingSecretValue: "phone-signing-secret-should-not-be-reported",
                source: .bundle
            ),
            onlineInspirationHealthSnapshot: healthSnapshot,
            calibrationReadinessReport: Self.readyCalibrationReadinessReport(),
            personalProfile: profile,
            personalProfileStoreProtection: .keychainEncryptedThisDeviceOnly,
            captureCoachingSummary: captureReview.coachingSummary,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.overallStatus, .passed)
        XCTAssertEqual(report.checks.map(\.id), [
            "shot_planning",
            "reference_popup",
            "online_reference_plan",
            "creative_interpretation",
            "creative_api_configuration",
            "online_provider_health",
            "calibration_readiness",
            "local_learning",
            "learning_store",
            "capture_coaching"
        ])
        XCTAssertTrue(report.checks.allSatisfy { $0.status == .passed })
        XCTAssertTrue(report.privacy.singlePhoneOnly)
        XCTAssertFalse(report.privacy.uploadsLiveCameraFrame)
        XCTAssertFalse(report.privacy.sendsIdentityData)
    }

    func testSinglePhoneAiDiagnosticsReportBlocksUnsafePayloads() {
        let unsafeHealthSnapshot = OnlineInspirationHealthSnapshot(
            planId: "unsafe_online_health",
            source: .publicSources,
            providers: [],
            privacy: .init(
                singlePhoneOnly: true,
                requiresUserConsent: true,
                sendsRawCameraFrame: true,
                sendsPrivatePhoto: false,
                sendsIdentityData: false,
                sendsPreciseLocation: false
            )
        )

        let report = SinglePhoneAiDiagnosticsReport.make(
            hasShotPlan: true,
            referencePhoto: Self.referencePhoto(cloudAnalysisUsed: true, showCameraPopup: true),
            onlineReferencePlan: nil,
            creativeInterpretationPlan: CreativeInterpretationPlan(
                id: "unsafe_creative_plan",
                reason: .explicitUserRequest,
                inputSummary: ["Prompt: private_photo"],
                suggestions: [
                    CreativeInterpretationPlan.Suggestion(
                        id: "unsafe_private_photo",
                        category: .reference,
                        title: "Upload Private Photo",
                        instruction: "Send private_photo to the provider."
                    )
                ],
                allowedInputs: [.promptText],
                mustNotSend: ["private_photo"],
                userDisclosure: "Unsafe",
                privacy: .init(
                    singlePhoneOnly: true,
                    requiresUserConsent: true,
                    sendsRawCameraFrame: false,
                    sendsPrivatePhoto: true,
                    sendsIdentityData: false,
                    sendsPreciseLocation: false,
                    sendsRawLearningEvents: false,
                    allowsGenerativeOutput: false
                )
            ),
            creativeAPIConfigurationStatus: LensPilotCreativeInterpretationAPIProvider.configurationStatus(
                apiURLValue: "http://lenspilot.example/v1/creative-interpretation",
                clientTokenValue: nil,
                signingSecretValue: nil,
                directOpenAIProviderAllowed: true,
                source: .bundle
            ),
            onlineInspirationHealthSnapshot: unsafeHealthSnapshot,
            personalProfile: .empty(consent: .disabled),
            personalProfileStoreProtection: .localFile,
            captureCoachingSummary: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(report.overallStatus, .blocked)
        XCTAssertEqual(report.checks.first { $0.id == "reference_popup" }?.status, .blocked)
        XCTAssertEqual(report.checks.first { $0.id == "creative_interpretation" }?.status, .blocked)
        XCTAssertEqual(report.checks.first { $0.id == "creative_api_configuration" }?.status, .blocked)
        XCTAssertEqual(report.checks.first { $0.id == "online_provider_health" }?.status, .blocked)
        XCTAssertTrue(report.privacy.singlePhoneOnly)
    }

    func testLensPilotCreativeAPIConfigurationStatusIsRedactedAndProductionSafe() throws {
        let protected = LensPilotCreativeInterpretationAPIProvider.configurationStatus(
            apiURLValue: "https://lenspilot.example/v1/creative-interpretation?token=leaky-query",
            clientTokenValue: "phone-client-token-secret",
            signingSecretValue: "phone-signing-secret",
            source: .bundle
        )

        XCTAssertEqual(protected.readiness, .protected)
        XCTAssertEqual(protected.source, .bundle)
        XCTAssertEqual(protected.endpointHost, "lenspilot.example")
        XCTAssertEqual(protected.endpointPath, "/v1/creative-interpretation")
        XCTAssertTrue(protected.usesHTTPS)
        XCTAssertTrue(protected.hasClientToken)
        XCTAssertTrue(protected.hasSigningSecret)
        XCTAssertFalse(protected.allowsDirectOpenAIProvider)
        XCTAssertTrue(protected.privacy.keepsOpenAIKeyOnServer)
        XCTAssertFalse(protected.privacy.acceptsClientOpenAIKey)
        XCTAssertEqual(protected.diagnosticDetail, "Signed backend ready")

        let encoded = try XCTUnwrap(String(data: try JSONEncoder().encode(protected), encoding: .utf8))
        XCTAssertFalse(encoded.contains("phone-client-token-secret"))
        XCTAssertFalse(encoded.contains("phone-signing-secret"))
        XCTAssertFalse(encoded.contains("leaky-query"))

        let unresolved = LensPilotCreativeInterpretationAPIProvider.configurationStatus(
            apiURLValue: "$(LENSPILOT_CREATIVE_API_URL)",
            clientTokenValue: "$(LENSPILOT_CREATIVE_API_TOKEN)",
            signingSecretValue: "$(LENSPILOT_CREATIVE_API_SIGNING_SECRET)",
            source: .bundle
        )
        XCTAssertEqual(unresolved.readiness, .offline)
        XCTAssertEqual(unresolved.diagnosticDetail, "Generated config missing")
        XCTAssertTrue(unresolved.warnings.contains(.unresolvedBuildSetting))

        let directOpenAI = LensPilotCreativeInterpretationAPIProvider.configurationStatus(
            apiURLValue: "https://lenspilot.example/v1/creative-interpretation",
            clientTokenValue: "phone-client-token-secret",
            signingSecretValue: "phone-signing-secret",
            directOpenAIProviderAllowed: true,
            source: .environment
        )
        XCTAssertEqual(directOpenAI.readiness, .blocked)
        XCTAssertEqual(directOpenAI.diagnosticDetail, "Direct OpenAI enabled")
    }

    func testCalibrationCaptureQueueGuidesRequiredRealCaptureScenarios() {
        let scenarios = CalibrationCaptureScenario.allCases
        let progress = CalibrationCaptureQueueProgress()
            .selecting(.sky)
            .recordingCapture(for: .sky)
            .recordingCapture(for: .sky)
            .recordingCapture(for: .sky)
            .recordingCapture(for: .sky)

        XCTAssertEqual(scenarios.count, 8)
        XCTAssertEqual(progress.requiredSampleCount, 24)
        XCTAssertTrue(scenarios.contains { $0.domain == .portrait })
        XCTAssertTrue(scenarios.contains { $0.domain == .landscape })
        XCTAssertTrue(scenarios.contains { $0.domain == .lifestyle })
        XCTAssertTrue(scenarios.contains { $0.domain == .night })
        XCTAssertTrue(scenarios.map(\.rawValue).contains("portrait"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("landscape"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("sky"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("clutter"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("backlight"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("horizon"))
        XCTAssertTrue(scenarios.map(\.rawValue).contains("motion"))
        XCTAssertEqual(CalibrationCaptureScenario.sky.preferredGuidanceReason, .increaseSky)
        XCTAssertEqual(CalibrationCaptureScenario.motion.domain, .lifestyle)
        XCTAssertTrue(CalibrationCaptureScenario.motion.rankedWeaknesses.contains(.sharpnessProbability))
        XCTAssertEqual(progress.activeScenario, .sky)
        XCTAssertEqual(progress.completedCount(for: .sky), 3)
        XCTAssertEqual(progress.completedSampleCount, 3)
        XCTAssertTrue(progress.isComplete(.sky))
    }

    func testCalibrationCaptureQueueStorePersistsSanitizedProgress() throws {
        var storedData: Data?
        let store = CalibrationCaptureQueueStore(
            readData: { storedData },
            writeData: { storedData = $0 }
        )
        let rawProgress = CalibrationCaptureQueueProgress(
            version: "legacy",
            activeScenarioId: "upload_private_photo",
            completedCounts: [
                "portrait": -4,
                "landscape": 2,
                "sky": 99,
                "external_cloud_album": 7
            ]
        )

        try store.saveProgress(rawProgress)
        let progress = try XCTUnwrap(try store.loadProgress())

        XCTAssertEqual(progress.version, "1.0")
        XCTAssertNil(progress.activeScenario)
        XCTAssertEqual(progress.completedCount(for: .portrait), 0)
        XCTAssertEqual(progress.completedCount(for: .landscape), 2)
        XCTAssertEqual(progress.completedCount(for: .sky), 3)
        XCTAssertNil(progress.completedCounts["external_cloud_album"])

        store.deleteProgress()
        XCTAssertNil(storedData)
    }

    func testCalibrationCaptureQueueStoreRejectsOversizedProgress() {
        let store = CalibrationCaptureQueueStore(
            maxStoredProgressBytes: 8,
            readData: { nil },
            writeData: { _ in }
        )
        let progress = CalibrationCaptureQueueProgress()

        XCTAssertThrowsError(try store.saveProgress(progress)) { error in
            guard case let .progressTooLarge(maxBytes, actualBytes) = error as? CalibrationCaptureQueueStoreError else {
                XCTFail("Expected oversized progress error.")
                return
            }

            XCTAssertEqual(maxBytes, 8)
            XCTAssertGreaterThan(actualBytes, maxBytes)
        }
    }

    func testGuidanceStabilizerSuppressesImmediateOppositeMovement() {
        var stabilizer = GuidanceStabilizer()
        let now = Date(timeIntervalSince1970: 0)
        let left = Self.guidanceAction(id: "move_left", action: .moveLeft, direction: .left)
        let right = Self.guidanceAction(id: "move_right", action: .moveRight, direction: .right)

        XCTAssertEqual(stabilizer.stabilize(left, now: now)?.action, .moveLeft)
        XCTAssertEqual(stabilizer.stabilize(right, now: now.addingTimeInterval(1))?.action, .moveLeft)
        XCTAssertEqual(stabilizer.stabilize(right, now: now.addingTimeInterval(6))?.action, .moveRight)
    }

    func testGuidanceStabilizerRemembersCompletedMovementAfterReadyState() {
        var stabilizer = GuidanceStabilizer()
        let now = Date(timeIntervalSince1970: 0)
        let left = Self.guidanceAction(id: "move_left", action: .moveLeft, direction: .left)
        let ready = Self.guidanceAction(
            id: "hold_steady_ready",
            action: .holdSteady,
            reason: .readyToCapture,
            expectedGain: 0.04,
            priority: 50
        )

        XCTAssertEqual(stabilizer.stabilize(left, now: now)?.action, .moveLeft)
        XCTAssertEqual(stabilizer.stabilize(ready, now: now.addingTimeInterval(1))?.reason, .readyToCapture)
        XCTAssertEqual(stabilizer.stabilize(left, now: now.addingTimeInterval(2))?.reason, .readyToCapture)
        XCTAssertEqual(stabilizer.stabilize(left, now: now.addingTimeInterval(4))?.action, .moveLeft)
    }

    func testGuidanceStabilizerAllowsUrgentCameraActionToInterruptMovementHold() {
        var stabilizer = GuidanceStabilizer()
        let now = Date(timeIntervalSince1970: 0)
        let left = Self.guidanceAction(id: "move_left", action: .moveLeft, direction: .left)
        let exposure = Self.guidanceAction(
            id: "protect_highlights",
            actor: .camera,
            action: .adjustExposure,
            magnitude: -0.3,
            unit: .ev,
            reason: .protectHighlights,
            expectedGain: 0.12,
            priority: 82
        )

        XCTAssertEqual(stabilizer.stabilize(left, now: now)?.action, .moveLeft)
        XCTAssertEqual(stabilizer.stabilize(exposure, now: now.addingTimeInterval(0.4))?.action, .adjustExposure)
    }

    func testPersonalVisualLearningBuildsProfileFromSafeCustomerUsage() {
        let engine = PersonalVisualLearningEngine()
        let event = PersonalLearningEvent(
            id: "learn_event_001",
            timestamp: Date(timeIntervalSince1970: 0),
            domain: .portrait,
            outcome: .savedResult,
            promptRequirements: ["cinematic", "clean_background", "natural_skin"],
            acceptedGuidanceReason: .reduceClutter,
            selectedStyle: .cinematic,
            selectedColorIntent: .warmHighlightsCoolShadows,
            selectedFraming: .environmental,
            selectedTargetMatch: 0.91,
            userRating: 5,
            onlineReferenceUsed: true
        )

        let disabledProfile = engine.updatedProfile(
            from: .empty(consent: .disabled),
            with: event,
            consent: .disabled
        )
        XCTAssertEqual(disabledProfile.totalEvents, 0)

        let profile = engine.updatedProfile(
            from: .empty(consent: .localLearningEnabled),
            with: event,
            consent: .localLearningEnabled
        )
        XCTAssertEqual(profile.totalEvents, 1)
        XCTAssertEqual(profile.domainCounts["portrait"], 1)
        XCTAssertGreaterThan(profile.styleAffinities["cinematic"] ?? 0, 0)
        XCTAssertGreaterThan(profile.requirementAffinities["clean_background"] ?? 0, 0)
        XCTAssertEqual(profile.onlineReferenceUsageCount, 1)

        let action = Self.guidanceAction(id: "reduce_background_clutter", action: .moveLeft, direction: .left)
        let boost = profile.guidanceCalibration().scoreBoost(for: action, domain: .portrait)
        XCTAssertGreaterThan(boost, 0)
        XCTAssertLessThanOrEqual(boost, 0.04)
    }

    func testPersonalVisualLearningInsightSummarizesAggregateCustomerSignals() {
        let engine = PersonalVisualLearningEngine()
        var profile = PersonalVisualPreferenceProfile.empty(consent: .localLearningEnabled)

        for index in 0..<3 {
            let event = PersonalLearningEvent(
                id: "learning_insight_\(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                domain: .portrait,
                outcome: .savedResult,
                promptRequirements: ["cinematic", "clean_background", "natural_skin"],
                acceptedGuidanceReason: .reduceClutter,
                selectedStyle: .cinematic,
                selectedColorIntent: .warmHighlightsCoolShadows,
                selectedFraming: .environmental,
                selectedTargetMatch: 0.91,
                userRating: 5,
                onlineReferenceUsed: index == 0
            )

            profile = engine.updatedProfile(
                from: profile,
                with: event,
                consent: .localLearningEnabled
            )
        }

        let insight = profile.learningInsight()
        let disabledInsight = PersonalVisualPreferenceProfile.empty(consent: .disabled).learningInsight()

        XCTAssertEqual(disabledInsight.status, .disabled)
        XCTAssertEqual(insight.status, .personalized)
        XCTAssertEqual(insight.eventCount, 3)
        XCTAssertEqual(insight.onlineReferenceUsageCount, 1)
        XCTAssertTrue(insight.topSignals.contains { $0.category == .style && $0.label == "Cinematic" })
        XCTAssertTrue(insight.topSignals.contains { $0.category == .guidance && $0.label == "Reduce Clutter" })
        XCTAssertTrue(insight.topSignals.contains { $0.category == .requirement })
        XCTAssertGreaterThan(insight.guidanceBoosts["reduce_clutter"] ?? 0, 0)
        XCTAssertTrue(insight.privacy.singlePhoneOnly)
        XCTAssertFalse(insight.privacy.storesRawPhoto)
        XCTAssertFalse(insight.privacy.uploadsLiveCameraFrame)
        XCTAssertFalse(insight.privacy.storesIdentityData)
        XCTAssertFalse(insight.privacy.cloudPersonalizationSyncAllowed)
    }

    func testPersonalVisualLearningUsesRejectedCustomerFeedbackAsNegativeSignal() {
        let engine = PersonalVisualLearningEngine()
        let event = PersonalLearningEvent(
            id: "learn_rejected_result",
            timestamp: Date(timeIntervalSince1970: 0),
            domain: .portrait,
            outcome: .rejectedGuidance,
            promptRequirements: ["cinematic", "clean_background"],
            rejectedGuidanceReason: .reduceClutter,
            selectedStyle: .cinematic,
            selectedColorIntent: .warmHighlightsCoolShadows,
            selectedFraming: .environmental,
            selectedTargetMatch: 0.42,
            userRating: 1,
            onlineReferenceUsed: false
        )

        let profile = engine.updatedProfile(
            from: .empty(consent: .localLearningEnabled),
            with: event,
            consent: .localLearningEnabled
        )
        let action = Self.guidanceAction(id: "reduce_background_clutter", action: .moveLeft, direction: .left)

        XCTAssertEqual(profile.totalEvents, 1)
        XCTAssertEqual(profile.domainCounts["portrait"], 1)
        XCTAssertLessThan(profile.styleAffinities["cinematic"] ?? 0, 0)
        XCTAssertLessThan(profile.requirementAffinities["clean_background"] ?? 0, 0)
        XCTAssertLessThan(profile.guidanceReasonAffinities["reduce_clutter"] ?? 0, 0)
        XCTAssertEqual(profile.guidanceCalibration().scoreBoost(for: action, domain: .portrait), 0, accuracy: 0.0001)
    }

    func testPersonalVisualLearningBoostsCustomerCorrectionReasonAfterRejectedResult() {
        let engine = PersonalVisualLearningEngine()
        let event = PersonalLearningEvent(
            id: "learn_customer_correction_reason",
            timestamp: Date(timeIntervalSince1970: 0),
            domain: .portrait,
            outcome: .rejectedGuidance,
            promptRequirements: ["cinematic", "clean_background"],
            customerCorrectionReason: .improveFaceLight,
            selectedStyle: .cinematic,
            selectedColorIntent: .warmHighlightsCoolShadows,
            selectedFraming: .environmental,
            selectedTargetMatch: 0.36,
            userRating: 1,
            onlineReferenceUsed: false
        )

        let profile = engine.updatedProfile(
            from: .empty(consent: .localLearningEnabled),
            with: event,
            consent: .localLearningEnabled
        )
        let action = Self.guidanceAction(
            id: "improve_face_light",
            action: .moveLeft,
            reason: .improveFaceLight
        )

        XCTAssertEqual(profile.totalEvents, 1)
        XCTAssertLessThan(profile.styleAffinities["cinematic"] ?? 0, 0)
        XCTAssertGreaterThan(profile.guidanceReasonAffinities["improve_face_light"] ?? 0, 0)
        XCTAssertGreaterThan(profile.requirementAffinities["customer_correction_improve_face_light"] ?? 0, 0)
        XCTAssertGreaterThan(profile.guidanceCalibration().scoreBoost(for: action, domain: .portrait), 0)
        XCTAssertLessThanOrEqual(profile.guidanceCalibration().scoreBoost(for: action, domain: .portrait), 0.04)
    }

    func testPersonalVisualProfileStorePersistsSanitizedLocalProfile() throws {
        var storedData: Data?
        let store = PersonalVisualProfileStore(
            readData: { storedData },
            writeData: { storedData = $0 }
        )
        let rawProfile = PersonalVisualPreferenceProfile(
            version: "legacy",
            consent: PersonalizationConsent(
                learningEnabled: true,
                onlineReferencesAllowed: true,
                cloudPersonalizationSyncAllowed: true
            ),
            totalEvents: 2_000_000,
            domainCounts: [
                "portrait": 4,
                "night": -2,
                "external_cloud_album": 12
            ],
            styleAffinities: [
                "cinematic": 0.7,
                "unknown_cloud_style": 0.8
            ],
            colorAffinities: [
                "warm_highlights_cool_shadows": 0.6,
                "generated_identity_palette": 0.5
            ],
            framingAffinities: [
                "environmental": 0.5
            ],
            guidanceReasonAffinities: [
                "reduce_clutter": 0.9,
                "upload_private_photo": 1
            ],
            requirementAffinities: [
                "Clean Background!!": 0.6,
                "raw_live_camera_feed": 1
            ],
            onlineReferenceUsageCount: 3
        )

        try store.saveProfile(rawProfile)
        let profile = try XCTUnwrap(try store.loadProfile())

        XCTAssertEqual(store.protection, .localFile)
        XCTAssertEqual(profile.version, "1.0")
        XCTAssertTrue(profile.consent.learningEnabled)
        XCTAssertTrue(profile.consent.onlineReferencesAllowed)
        XCTAssertFalse(profile.consent.cloudPersonalizationSyncAllowed)
        XCTAssertEqual(profile.totalEvents, 1_000_000)
        XCTAssertEqual(profile.domainCounts["portrait"], 4)
        XCTAssertNil(profile.domainCounts["night"])
        XCTAssertNil(profile.domainCounts["external_cloud_album"])
        XCTAssertEqual(profile.styleAffinities["cinematic"] ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertNil(profile.styleAffinities["unknown_cloud_style"])
        XCTAssertEqual(profile.colorAffinities["warm_highlights_cool_shadows"] ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertNil(profile.colorAffinities["generated_identity_palette"])
        XCTAssertEqual(profile.guidanceReasonAffinities["reduce_clutter"] ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertNil(profile.guidanceReasonAffinities["upload_private_photo"])
        XCTAssertEqual(profile.requirementAffinities["clean_background"] ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertNil(profile.requirementAffinities["raw_live_camera_feed"])
        XCTAssertEqual(profile.onlineReferenceUsageCount, 3)

        store.deleteProfile()
        XCTAssertNil(storedData)
    }

    func testPersonalVisualProfileStoreReportsEncryptedProtection() throws {
        var storedData: Data?
        let store = PersonalVisualProfileStore(
            protection: .keychainEncryptedThisDeviceOnly,
            readData: { storedData },
            writeData: { storedData = $0 }
        )

        XCTAssertEqual(store.protection, .keychainEncryptedThisDeviceOnly)
        XCTAssertTrue(store.protection.isEncryptedAtRest)

        try store.saveProfile(.empty(consent: .localLearningEnabled))
        XCTAssertNotNil(storedData)
        XCTAssertNotNil(try store.loadProfile())
    }

    func testPersonalVisualProfileDefaultSecureStorePrefersKeychainWhenAvailable() {
        let store = PersonalVisualProfileStore.defaultSecureStore(
            keychainService: "com.lenspilot.tests.\(UUID().uuidString)",
            keychainAccount: "profile"
        )

        #if canImport(Security)
        XCTAssertEqual(store.protection, .keychainEncryptedThisDeviceOnly)
        #else
        XCTAssertEqual(store.protection, .localFile)
        #endif

        store.deleteProfile()
    }

    func testPersonalVisualProfileStoreRejectsOversizedProfiles() {
        let store = PersonalVisualProfileStore(
            maxStoredProfileBytes: 8,
            readData: { nil },
            writeData: { _ in }
        )
        let profile = PersonalVisualPreferenceProfile.empty(consent: .localLearningEnabled)

        XCTAssertThrowsError(try store.saveProfile(profile)) { error in
            guard case let .profileTooLarge(maxBytes, actualBytes) = error as? PersonalVisualProfileStoreError else {
                XCTFail("Expected oversized profile error.")
                return
            }

            XCTAssertEqual(maxBytes, 8)
            XCTAssertGreaterThan(actualBytes, maxBytes)
        }
    }

    func testOnlineReferencePlanRequiresConsentAndNeverUploadsPrivateCameraData() throws {
        let engine = PersonalVisualLearningEngine()
        let shotSpec = ShotSpecFactory().makeShotSpec(
            from: "Give me a cinematic portrait with online inspiration.",
            source: .text
        )
        let profile = PersonalVisualPreferenceProfile.empty(consent: .localLearningEnabled)

        XCTAssertNil(engine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: "Give me a cinematic portrait with online inspiration.",
            profile: profile,
            consent: .localLearningEnabled
        ))

        let plan = try XCTUnwrap(engine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: "Give me a cinematic portrait with online inspiration.",
            profile: profile,
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true)
        ))
        XCTAssertEqual(plan.reason, .explicitUserRequest)
        XCTAssertTrue(plan.privacy.singlePhoneOnly)
        XCTAssertTrue(plan.privacy.requiresUserConsent)
        XCTAssertFalse(plan.privacy.sendsRawCameraFrame)
        XCTAssertFalse(plan.privacy.sendsPrivatePhoto)
        XCTAssertFalse(plan.privacy.sendsIdentityData)
        XCTAssertTrue(plan.allowedInputs.contains(.promptText))
        XCTAssertTrue(plan.mustNotSend.contains("raw_live_camera_feed"))
        XCTAssertTrue(plan.searchQueries.contains { $0.contains("cinematic") })
    }

    func testCreativeInterpretationPlanRequiresConsentAndUsesSafeSummaries() throws {
        let engine = PersonalVisualLearningEngine()
        let prompt = "Give me a cinematic luxury portrait with online inspiration."
        let shotSpec = ShotSpecFactory().makeShotSpec(from: prompt, source: .text)
        let profile = PersonalVisualPreferenceProfile(
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true),
            totalEvents: 3,
            domainCounts: ["portrait": 3],
            styleAffinities: ["cinematic": 0.4],
            colorAffinities: ["warm_highlights_cool_shadows": 0.2],
            framingAffinities: ["environmental": 0.3],
            guidanceReasonAffinities: ["improve_face_light": 0.4],
            requirementAffinities: ["luxury": 0.3],
            onlineReferenceUsageCount: 1
        )

        XCTAssertNil(engine.makeCreativeInterpretationPlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            consent: .localLearningEnabled
        ))

        let onlinePlan = try XCTUnwrap(engine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            consent: profile.consent
        ))
        let creativePlan = try XCTUnwrap(engine.makeCreativeInterpretationPlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            onlineReferencePlan: onlinePlan,
            consent: profile.consent
        ))

        XCTAssertEqual(creativePlan.reason, .explicitUserRequest)
        XCTAssertTrue(creativePlan.allowedInputs.contains(.promptText))
        XCTAssertTrue(creativePlan.allowedInputs.contains(.shotSpecSummary))
        XCTAssertTrue(creativePlan.allowedInputs.contains(.learnedPreferenceSummary))
        XCTAssertTrue(creativePlan.allowedInputs.contains(.publicReferenceSummary))
        XCTAssertTrue(creativePlan.inputSummary.allSatisfy { !$0.contains("raw_live_camera") })
        XCTAssertTrue(creativePlan.suggestions.contains { $0.category == .lighting })
        XCTAssertTrue(creativePlan.suggestions.contains { $0.category == .reference })
        XCTAssertTrue(creativePlan.suggestions.contains { $0.category == .safety })
        XCTAssertTrue(creativePlan.mustNotSend.contains("raw_live_camera_feed"))
        XCTAssertTrue(creativePlan.mustNotSend.contains("private_photo"))
        XCTAssertTrue(creativePlan.mustNotSend.contains("raw_learning_events"))
        XCTAssertTrue(creativePlan.privacy.isSafeForSinglePhoneCreativeReasoning)
        XCTAssertTrue(creativePlan.privacy.singlePhoneOnly)
        XCTAssertTrue(creativePlan.privacy.requiresUserConsent)
        XCTAssertFalse(creativePlan.privacy.sendsRawCameraFrame)
        XCTAssertFalse(creativePlan.privacy.sendsPrivatePhoto)
        XCTAssertFalse(creativePlan.privacy.sendsIdentityData)
        XCTAssertFalse(creativePlan.privacy.sendsPreciseLocation)
        XCTAssertFalse(creativePlan.privacy.sendsRawLearningEvents)
        XCTAssertFalse(creativePlan.privacy.allowsGenerativeOutput)

        let payloadAudit = CreativeInterpretationPayloadAudit.make(for: creativePlan)
        XCTAssertTrue(payloadAudit.safeToSend)
        XCTAssertTrue(payloadAudit.deniedReasons.isEmpty)
        XCTAssertEqual(payloadAudit.allowedInputCount, creativePlan.allowedInputs.count)
        XCTAssertEqual(payloadAudit.suggestionCount, creativePlan.suggestions.count)

        let request = try CreativeInterpretationRequest(
            plan: creativePlan,
            provider: .onlineReasoning,
            maxResponseWords: 999
        )
        XCTAssertEqual(request.planId, creativePlan.id)
        XCTAssertEqual(request.provider, .onlineReasoning)
        XCTAssertEqual(request.maxResponseWords, 240)
        XCTAssertTrue(request.payloadAudit.safeToSend)
        XCTAssertTrue(request.suggestionBriefs.contains { $0.contains("Stay Capture-Realistic") })
        XCTAssertFalse(request.privacy.sendsPrivatePhoto)
    }

    func testCreativeInterpretationRequestRejectsUnsafePayloads() {
        let unsafePlan = CreativeInterpretationPlan(
            id: "unsafe_creative_payload",
            reason: .explicitUserRequest,
            inputSummary: ["Prompt: raw_live_camera_feed base64 image_data"],
            suggestions: [
                CreativeInterpretationPlan.Suggestion(
                    id: "unsafe_summary",
                    category: .reference,
                    title: "Unsafe Payload",
                    instruction: "Use raw_live_camera_feed bytes."
                )
            ],
            allowedInputs: [.promptText],
            mustNotSend: ["private_photo"],
            userDisclosure: "Unsafe",
            privacy: .init()
        )

        let payloadAudit = CreativeInterpretationPayloadAudit.make(for: unsafePlan)
        XCTAssertFalse(payloadAudit.safeToSend)
        XCTAssertTrue(payloadAudit.blockedTermsDetected.contains("raw_live_camera"))
        XCTAssertTrue(payloadAudit.deniedReasons.contains(.blockedTermDetected))
        XCTAssertTrue(payloadAudit.deniedReasons.contains(.missingRequiredBlocklist))

        XCTAssertThrowsError(try CreativeInterpretationRequest(plan: unsafePlan)) { error in
            guard case let .unsafePlan(deniedReasons) = error as? CreativeInterpretationError else {
                XCTFail("Expected unsafe creative interpretation plan.")
                return
            }

            XCTAssertTrue(deniedReasons.contains(.blockedTermDetected))
            XCTAssertTrue(deniedReasons.contains(.missingRequiredBlocklist))
        }
    }

    func testCreativeInterpretationAdapterRunsOnlyAfterSafeProviderHealth() async throws {
        let engine = PersonalVisualLearningEngine()
        let prompt = "Give me a cinematic luxury portrait with online inspiration."
        let shotSpec = ShotSpecFactory().makeShotSpec(from: prompt, source: .text)
        let profile = PersonalVisualPreferenceProfile(
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true),
            totalEvents: 3,
            domainCounts: ["portrait": 3],
            styleAffinities: ["cinematic": 0.4],
            colorAffinities: ["warm_highlights_cool_shadows": 0.2],
            framingAffinities: ["environmental": 0.3],
            guidanceReasonAffinities: ["improve_face_light": 0.4],
            requirementAffinities: ["luxury": 0.3],
            onlineReferenceUsageCount: 1
        )
        let onlinePlan = try XCTUnwrap(engine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            consent: profile.consent
        ))
        let creativePlan = try XCTUnwrap(engine.makeCreativeInterpretationPlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            onlineReferencePlan: onlinePlan,
            consent: profile.consent
        ))
        let healthSnapshot = OnlineInspirationHealthSnapshot(
            planId: onlinePlan.id,
            source: .publicSources,
            providers: [
                OnlineInspirationProviderHealth.available(source: .wikimediaCommons, resultCount: 2),
                OnlineInspirationProviderHealth.failed(source: .openverse, error: OnlineInspirationError.missingProviderData)
            ]
        )

        let response = try await HealthGatedCreativeInterpretationAdapter().interpret(
            for: creativePlan,
            providerHealthSnapshot: healthSnapshot,
            maxResponseWords: 64,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.provider, .onlineReasoning)
        XCTAssertEqual(response.maxResponseWords, 64)
        XCTAssertTrue(response.payloadAudit.safeToSend)
        XCTAssertTrue(response.healthGate.canRunProvider)
        XCTAssertEqual(response.healthGate.providerHealthStatus, .degraded)
        XCTAssertEqual(response.healthGate.publicReferenceCount, 2)
        XCTAssertFalse(response.guidance.isEmpty)
        XCTAssertTrue(response.guidance.contains { $0.contains("Stay Capture-Realistic") })
        XCTAssertTrue(response.privacy.usesAuditedPayload)
        XCTAssertTrue(response.privacy.usesProviderHealthGate)
        XCTAssertTrue(response.privacy.isSafeForSinglePhoneCreativeReasoning)
        XCTAssertFalse(response.privacy.uploadsLiveCameraFrame)
        XCTAssertFalse(response.privacy.sendsPrivatePhoto)
        XCTAssertFalse(response.privacy.sendsIdentityData)
        XCTAssertFalse(response.privacy.sendsRawLearningEvents)
    }

    func testCreativeInterpretationAdapterBlocksMissingOrUnsafeProviderHealth() async throws {
        let prompt = "Give me a cinematic portrait with online inspiration."
        let shotSpec = ShotSpecFactory().makeShotSpec(from: prompt, source: .text)
        let profile = PersonalVisualPreferenceProfile(
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true),
            totalEvents: 3,
            domainCounts: ["portrait": 3],
            styleAffinities: ["cinematic": 0.4],
            guidanceReasonAffinities: ["reduce_clutter": 0.4],
            requirementAffinities: ["cinematic": 0.3]
        )
        let onlinePlan = try XCTUnwrap(PersonalVisualLearningEngine().makeOnlineReferencePlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            consent: profile.consent
        ))
        let creativePlan = try XCTUnwrap(PersonalVisualLearningEngine().makeCreativeInterpretationPlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            onlineReferencePlan: onlinePlan,
            consent: profile.consent
        ))
        let request = try CreativeInterpretationRequest(plan: creativePlan)

        let missingGate = CreativeInterpretationProviderHealthGate.make(
            for: request,
            healthSnapshot: nil
        )
        XCTAssertFalse(missingGate.canRunProvider)
        XCTAssertTrue(missingGate.deniedReasons.contains(.missingProviderHealth))

        let unsafeHealthSnapshot = OnlineInspirationHealthSnapshot(
            planId: onlinePlan.id,
            source: .publicSources,
            providers: [
                OnlineInspirationProviderHealth.available(source: .wikimediaCommons, resultCount: 1)
            ],
            privacy: .init(
                singlePhoneOnly: true,
                requiresUserConsent: true,
                sendsRawCameraFrame: true,
                sendsPrivatePhoto: false,
                sendsIdentityData: false,
                sendsPreciseLocation: false
            )
        )
        let unsafeGate = CreativeInterpretationProviderHealthGate.make(
            for: request,
            healthSnapshot: unsafeHealthSnapshot
        )
        XCTAssertFalse(unsafeGate.canRunProvider)
        XCTAssertTrue(unsafeGate.deniedReasons.contains(.unsafeProviderHealth))

        let failedHealthSnapshot = OnlineInspirationHealthSnapshot(
            planId: onlinePlan.id,
            source: .publicSources,
            providers: [
                OnlineInspirationProviderHealth.failed(source: .wikimediaCommons, error: OnlineInspirationError.missingProviderData)
            ]
        )

        do {
            _ = try await HealthGatedCreativeInterpretationAdapter().interpret(
                for: creativePlan,
                providerHealthSnapshot: failedHealthSnapshot
            )
            XCTFail("Expected the creative interpretation adapter to block failed provider health.")
        } catch let error as CreativeInterpretationAdapterError {
            guard case let .blockedByHealthGate(reasons) = error else {
                XCTFail("Expected health gate block.")
                return
            }

            XCTAssertTrue(reasons.contains(.providerUnavailable))
            XCTAssertTrue(reasons.contains(.noPublicReferences))
        }
    }

    func testOpenAICreativeInterpretationProviderBuildsPrivacySafeResponsesRequest() async throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let providerOutput = #"{"headline":"OpenAI Capture Brief","guidance":["Turn the subject toward the softer side light.","Keep the clean background edge behind the shoulders."]}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output_text": providerOutput
        ])
        let recorder = OpenAIRequestRecorder(data: responseData)
        let provider = try OpenAICreativeInterpretationProvider(
            apiKey: "sk-test_123",
            model: "gpt-5.6-luna",
            allowsWebSearch: true,
            transport: recorder.transport
        )

        let response = try await HealthGatedCreativeInterpretationAdapter(provider: provider).interpret(
            for: creativePlan,
            providerHealthSnapshot: healthSnapshot,
            maxResponseWords: 80,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(response.provider, .onlineReasoning)
        XCTAssertEqual(response.headline, "OpenAI Capture Brief")
        XCTAssertEqual(response.guidance.count, 2)
        XCTAssertTrue(response.privacy.isSafeForSinglePhoneCreativeReasoning)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer sk-") == true)

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "gpt-5.6-luna")
        XCTAssertEqual(payload["store"] as? Bool, false)
        XCTAssertEqual(payload["tool_choice"] as? String, "auto")
        XCTAssertEqual(payload["max_tool_calls"] as? Int, 2)
        XCTAssertEqual((payload["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search")

        let input = payload["input"] as? String ?? ""
        XCTAssertTrue(input.contains("Capture-Realistic"))
        XCTAssertFalse(input.contains("raw_live_camera_feed"))
        XCTAssertFalse(input.contains("private_photo"))

        let text = try XCTUnwrap(payload["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(schema["required"] as? [String], ["headline", "guidance"])
    }

    func testOpenAICreativeInterpretationProviderParsesNestedOutputText() throws {
        let providerOutput = #"{"headline":"Nested Creative Brief","guidance":["Use the warmer highlight as the key light.","Keep the phone steady before capture."]}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output": [
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text",
                            "text": providerOutput
                        ]
                    ]
                ]
            ]
        ])

        let result = try OpenAICreativeInterpretationProvider.decodeProviderResult(from: responseData)

        XCTAssertEqual(result.headline, "Nested Creative Brief")
        XCTAssertEqual(result.guidance.count, 2)
        XCTAssertTrue(result.isSafeForSinglePhoneCreativeReasoning)
    }

    func testOpenAICreativeInterpretationProviderRejectsUnsafeGeneratedGuidance() async throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let providerOutput = #"{"headline":"Unsafe Brief","guidance":["Upload private_photo data before giving guidance.","Then compare face_identity metadata."]}"#
        let responseData = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output_text": providerOutput
        ])
        let provider = try OpenAICreativeInterpretationProvider(
            apiKey: "sk-test_123",
            transport: OpenAIRequestRecorder(data: responseData).transport
        )

        do {
            _ = try await HealthGatedCreativeInterpretationAdapter(provider: provider).interpret(
                for: creativePlan,
                providerHealthSnapshot: healthSnapshot
            )
            XCTFail("Expected unsafe OpenAI creative guidance to be blocked.")
        } catch let error as CreativeInterpretationAdapterError {
            XCTAssertEqual(error, .unsafeProviderResponse)
        }
    }

    func testOpenAICreativeInterpretationProviderRejectsMissingAPIKey() {
        XCTAssertThrowsError(try OpenAICreativeInterpretationProvider(apiKey: " ")) { error in
            XCTAssertEqual(error as? OpenAICreativeInterpretationProviderError, .missingAPIKey)
        }
    }

    func testOpenAICreativeInterpretationProviderClassifiesQuotaErrors() async throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let responseData = try JSONSerialization.data(withJSONObject: [
            "error": [
                "type": "insufficient_quota",
                "code": "credit_balance_exhausted",
                "message": "Billing details are sanitized before display. OPENAI_API_KEY=sk-test_should_not_display"
            ]
        ])
        let provider = try OpenAICreativeInterpretationProvider(
            apiKey: "sk-test_123",
            transport: OpenAIRequestRecorder(data: responseData, statusCode: 429).transport
        )

        do {
            _ = try await HealthGatedCreativeInterpretationAdapter(provider: provider).interpret(
                for: creativePlan,
                providerHealthSnapshot: healthSnapshot
            )
            XCTFail("Expected OpenAI quota errors to be classified before generic HTTP status.")
        } catch let error as OpenAICreativeInterpretationProviderError {
            guard case .apiError(let message) = error else {
                XCTFail("Expected a sanitized OpenAI API error, got \(error).")
                return
            }

            XCTAssertTrue(error.isProviderBillingBlocked)
            XCTAssertEqual(error.safeDiagnosticMessage, "OpenAI credits exhausted")
            XCTAssertTrue(message.contains("openai_credit_balance_exhausted"))
            XCTAssertTrue(message.contains("provider_status_429"))
            XCTAssertTrue(message.contains("credit_balance_exhausted"))
            XCTAssertTrue(message.contains("insufficient_quota"))
            XCTAssertTrue(message.contains("billing_blocked"))
            XCTAssertTrue(message.contains("[redacted]"))
            XCTAssertFalse(message.contains("sk-"))
            XCTAssertFalse(message.contains("OPENAI_API_KEY"))
        }
    }

    func testLensPilotCreativeAPIProviderBuildsMobileSafeBackendRequest() async throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let providerOutput = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "provider": "online_reasoning",
            "result": [
                "headline": "Backend Creative Brief",
                "guidance": [
                    "Turn the subject toward the softer side light.",
                    "Keep the phone steady and preserve the clean background edge."
                ]
            ],
            "privacy": [
                "keepsOpenAIKeyOnServer": true,
                "acceptsClientOpenAIKey": false
            ]
        ])
        let recorder = LensPilotCreativeAPIRequestRecorder(data: providerOutput)
        let provider = try LensPilotCreativeInterpretationAPIProvider(
            apiURL: URL(string: "https://api.lenspilot.example/v1/creative-interpretation")!,
            clientToken: "client-token",
            transport: recorder.transport
        )

        let response = try await HealthGatedCreativeInterpretationAdapter(provider: provider).interpret(
            for: creativePlan,
            providerHealthSnapshot: healthSnapshot,
            maxResponseWords: 80,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(response.provider, .onlineReasoning)
        XCTAssertEqual(response.headline, "Backend Creative Brief")
        XCTAssertTrue(response.privacy.isSafeForSinglePhoneCreativeReasoning)

        let urlRequest = try XCTUnwrap(recorder.request)
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.lenspilot.example/v1/creative-interpretation")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-LensPilot-Client"), "ios")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer client-token")
        XCTAssertFalse(urlRequest.value(forHTTPHeaderField: "Authorization")?.contains("sk-") == true)

        let body = try XCTUnwrap(urlRequest.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["apiVersion"] as? String, "2026-08-31")
        XCTAssertEqual((payload["client"] as? [String: Any])?["platform"] as? String, "ios")
        let apiRequest = try XCTUnwrap(payload["request"] as? [String: Any])
        XCTAssertEqual(apiRequest["provider"] as? String, "online_reasoning")
        XCTAssertEqual((payload["healthGate"] as? [String: Any])?["canRunProvider"] as? Bool, true)
        let mustNotSend = try XCTUnwrap(apiRequest["mustNotSend"] as? [String])
        XCTAssertTrue(mustNotSend.contains("raw_live_camera_feed"))
        XCTAssertTrue(mustNotSend.contains("private_photo"))

        let inputSummary = try XCTUnwrap(apiRequest["inputSummary"] as? [String])
        let suggestionBriefs = try XCTUnwrap(apiRequest["suggestionBriefs"] as? [String])
        XCTAssertFalse(inputSummary.joined(separator: " ").contains("private_photo"))
        XCTAssertFalse(suggestionBriefs.joined(separator: " ").contains("raw_live_camera_feed"))

        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(bodyText.contains("OPENAI_API_KEY"))
        XCTAssertFalse(bodyText.contains("sk-proj"))
    }

    func testLensPilotCreativeAPIProviderSignsBackendRequestsWhenConfigured() throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let request = try CreativeInterpretationRequest(plan: creativePlan, maxResponseWords: 80)
        let healthGate = CreativeInterpretationProviderHealthGate.make(
            for: request,
            healthSnapshot: healthSnapshot
        )
        let provider = try LensPilotCreativeInterpretationAPIProvider(
            apiURL: URL(string: "https://api.lenspilot.example/v1/creative-interpretation")!,
            clientToken: "client-token",
            signingSecret: "client-signing-secret",
            clock: { Date(timeIntervalSince1970: 1_786_000_000) },
            requestIDGenerator: { "signed-swift-test-001" },
            transport: LensPilotCreativeAPIRequestRecorder(data: Data()).transport
        )

        let urlRequest = try provider.makeURLRequest(for: request, healthGate: healthGate)
        let body = try XCTUnwrap(urlRequest.httpBody)
        let expectedSignature = try LensPilotCreativeInterpretationAPIProvider.makeRequestSignature(
            secret: "client-signing-secret",
            method: "POST",
            path: "/v1/creative-interpretation",
            timestampMilliseconds: 1_786_000_000_000,
            requestID: "signed-swift-test-001",
            body: body
        )

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-LensPilot-Request-Id"), "signed-swift-test-001")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-LensPilot-Timestamp"), "1786000000000")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-LensPilot-Signature"), expectedSignature)
        XCTAssertTrue(expectedSignature.hasPrefix("v1="))
        XCTAssertFalse(expectedSignature.dropFirst(3).contains("="), "Base64url signatures should omit padding.")

        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(bodyText.contains("client-signing-secret"))
        XCTAssertFalse(bodyText.contains("signed-swift-test-001"))
        XCTAssertFalse(urlRequest.allHTTPHeaderFields?.description.contains("OPENAI_API_KEY") == true)
        XCTAssertFalse(urlRequest.value(forHTTPHeaderField: "Authorization")?.contains("sk-") == true)
        XCTAssertFalse(urlRequest.value(forHTTPHeaderField: "X-LensPilot-Signature")?.contains("client-signing-secret") == true)
    }

    func testLensPilotCreativeAPIProviderSurfacesSanitizedProviderErrors() async throws {
        let (creativePlan, healthSnapshot) = try makeCreativeInterpretationFixture()
        let request = try CreativeInterpretationRequest(plan: creativePlan, maxResponseWords: 80)
        let healthGate = CreativeInterpretationProviderHealthGate.make(
            for: request,
            healthSnapshot: healthSnapshot
        )
        let providerError = try JSONSerialization.data(withJSONObject: [
            "error": [
                "code": "openai_credit_balance_exhausted",
                "providerStatus": 429,
                "providerErrorType": "insufficient_quota",
                "providerErrorCode": "credit_balance_exhausted",
                "retryable": false,
                "blockedByBilling": true,
                "message": "Creative provider quota is unavailable. OPENAI_API_KEY=sk-test_should_not_display"
            ]
        ])
        let provider = try LensPilotCreativeInterpretationAPIProvider(
            apiURL: URL(string: "https://api.lenspilot.example/v1/creative-interpretation")!,
            transport: LensPilotCreativeAPIRequestRecorder(data: providerError, statusCode: 502).transport
        )

        do {
            _ = try await provider.interpret(request: request, healthGate: healthGate)
            XCTFail("Expected backend provider errors to be surfaced before generic HTTP status.")
        } catch let error as LensPilotCreativeInterpretationAPIProviderError {
            guard case .apiError(let message) = error else {
                XCTFail("Expected a sanitized API error, got \(error).")
                return
            }

            XCTAssertTrue(message.contains("openai_credit_balance_exhausted"))
            XCTAssertTrue(message.contains("provider_status_429"))
            XCTAssertTrue(message.contains("credit_balance_exhausted"))
            XCTAssertTrue(message.contains("insufficient_quota"))
            XCTAssertTrue(message.contains("billing_blocked"))
            XCTAssertTrue(error.isProviderBillingBlocked)
            XCTAssertEqual(error.safeDiagnosticMessage, "OpenAI credits exhausted")
            XCTAssertTrue(message.contains("[redacted]"))
            XCTAssertFalse(message.contains("sk-"))
            XCTAssertFalse(message.contains("OPENAI_API_KEY"))
        }
    }

    func testLensPilotCreativeAPIProviderRejectsDirectUseWithoutHealthGate() async throws {
        let (creativePlan, _) = try makeCreativeInterpretationFixture()
        let request = try CreativeInterpretationRequest(plan: creativePlan)
        let provider = try LensPilotCreativeInterpretationAPIProvider(
            apiURL: URL(string: "https://api.lenspilot.example/v1/creative-interpretation")!,
            transport: LensPilotCreativeAPIRequestRecorder(data: Data()).transport
        )

        do {
            _ = try await provider.interpret(request: request)
            XCTFail("Expected direct creative API provider use to require a health gate.")
        } catch let error as LensPilotCreativeInterpretationAPIProviderError {
            XCTAssertEqual(error, .missingHealthGate)
        }
    }

    func testLensPilotCreativeAPIProviderRejectsUnsafeHealthGate() async throws {
        let (creativePlan, _) = try makeCreativeInterpretationFixture()
        let request = try CreativeInterpretationRequest(plan: creativePlan)
        let unsafeHealthGate = CreativeInterpretationProviderHealthGate(
            canRunProvider: false,
            deniedReasons: [.unsafeProviderHealth],
            providerHealthStatus: nil,
            publicReferenceCount: 0,
            payloadAudit: request.payloadAudit,
            privacy: CreativeInterpretationProviderHealthGate.Privacy(sendsRawCameraFrame: true)
        )
        let provider = try LensPilotCreativeInterpretationAPIProvider(
            apiURL: URL(string: "https://api.lenspilot.example/v1/creative-interpretation")!,
            transport: LensPilotCreativeAPIRequestRecorder(data: Data()).transport
        )

        do {
            _ = try await provider.interpret(request: request, healthGate: unsafeHealthGate)
            XCTFail("Expected unsafe creative API health gate to be rejected.")
        } catch let error as LensPilotCreativeInterpretationAPIProviderError {
            XCTAssertEqual(error, .unsafeHealthGate)
        }
    }

    func testLensPilotCreativeAPIProviderConfiguredFromEnvironmentPrefersSecureBackend() {
        XCTAssertNotNil(LensPilotCreativeInterpretationAPIProvider.configuredFromEnvironment([
            "LENSPILOT_CREATIVE_API_URL": "https://api.lenspilot.example/v1/creative-interpretation",
            "LENSPILOT_CREATIVE_API_TOKEN": "client-token",
            "LENSPILOT_CREATIVE_API_SIGNING_SECRET": "client-signing-secret"
        ]))
        XCTAssertNotNil(LensPilotCreativeInterpretationAPIProvider.configuredFromEnvironment([
            "LENSPILOT_CREATIVE_API_URL": "http://localhost:8787/v1/creative-interpretation"
        ]))
        XCTAssertNil(LensPilotCreativeInterpretationAPIProvider.configuredFromEnvironment([
            "LENSPILOT_CREATIVE_API_URL": "http://api.lenspilot.example/v1/creative-interpretation"
        ]))
    }

    func testLensPilotCreativeAPIProviderConfigIgnoresUnresolvedBuildSettings() {
        XCTAssertNil(LensPilotCreativeInterpretationAPIProvider.configured(
            apiURLValue: "$(LENSPILOT_CREATIVE_API_URL)",
            clientTokenValue: "$(LENSPILOT_CREATIVE_API_TOKEN)"
        ))
        XCTAssertNotNil(LensPilotCreativeInterpretationAPIProvider.configured(
            apiURLValue: "https://api.lenspilot.example/v1/creative-interpretation",
            clientTokenValue: "$(LENSPILOT_CREATIVE_API_TOKEN)",
            signingSecretValue: "$(LENSPILOT_CREATIVE_API_SIGNING_SECRET)"
        ))
        XCTAssertNil(LensPilotCreativeInterpretationAPIProvider.configured(
            apiURLValue: "http://api.lenspilot.example/v1/creative-interpretation",
            clientTokenValue: nil
        ))
    }

    func testWikimediaCommonsOnlineInspirationAdapterUsesSafePublicFileSearch() throws {
        let provider = WikimediaCommonsInspirationProvider()
        let url = try provider.makeSearchURL(query: "cinematic portrait phone photography reference", limit: 50)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(url.host, "commons.wikimedia.org")
        XCTAssertEqual(query["generator"], "search")
        XCTAssertEqual(query["gsrnamespace"], "6")
        XCTAssertEqual(query["gsrlimit"], "10")
        XCTAssertEqual(query["prop"], "imageinfo")
        XCTAssertTrue(query["iiprop"]?.contains("url") == true)
        XCTAssertFalse(url.absoluteString.contains("raw_live_camera_feed"))

        let commonsJSON = """
        {
          "query": {
            "pages": [
              {
                "pageid": 42,
                "index": 1,
                "title": "File:Cinematic portrait reference.jpg",
                "imageinfo": [
                  {
                    "url": "https://upload.wikimedia.org/wikipedia/commons/example.jpg",
                    "thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/example.jpg/640px-example.jpg",
                    "descriptionurl": "https://commons.wikimedia.org/wiki/File:Cinematic_portrait_reference.jpg",
                    "mime": "image/jpeg",
                    "extmetadata": {
                      "LicenseShortName": { "value": "CC BY-SA 4.0" },
                      "Artist": { "value": "<span>Jane Doe</span>" }
                    }
                  }
                ]
              },
              {
                "pageid": 43,
                "index": 2,
                "title": "File:Skipped document.pdf",
                "imageinfo": [
                  {
                    "url": "https://upload.wikimedia.org/wikipedia/commons/example.pdf",
                    "descriptionurl": "https://commons.wikimedia.org/wiki/File:Skipped_document.pdf",
                    "mime": "application/pdf"
                  }
                ]
              }
            ]
          }
        }
        """

        let results = try provider.decodeSearchResponse(
            Data(commonsJSON.utf8),
            query: "cinematic portrait",
            planId: "online_reference_test"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].source, .wikimediaCommons)
        XCTAssertEqual(results[0].title, "Cinematic portrait reference.jpg")
        XCTAssertEqual(results[0].license, "CC BY-SA 4.0")
        XCTAssertEqual(results[0].creator, "Jane Doe")
        XCTAssertTrue(results[0].privacy.publicSourceOnly)
        XCTAssertTrue(results[0].privacy.derivedFromPromptOnly)
        XCTAssertFalse(results[0].privacy.uploadsLiveCameraFrame)
    }

    func testOpenverseOnlineInspirationAdapterUsesSafePublicImageSearch() throws {
        let provider = OpenverseInspirationProvider()
        let url = try provider.makeSearchURL(query: "cinematic portrait phone photography reference", limit: 50)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(url.host, "api.openverse.engineering")
        XCTAssertEqual(query["q"], "cinematic portrait phone photography reference")
        XCTAssertEqual(query["page_size"], "10")
        XCTAssertEqual(query["mature"], "false")
        XCTAssertFalse(url.absoluteString.contains("raw_live_camera_feed"))

        let openverseJSON = """
        {
          "results": [
            {
              "id": "ov_99",
              "title": "Cinematic street portrait",
              "foreign_landing_url": "https://example.org/photos/cinematic-street-portrait",
              "url": "https://images.example.org/cinematic-street-portrait.jpg",
              "thumbnail": "https://images.example.org/thumbs/cinematic-street-portrait.jpg",
              "license": "by",
              "license_version": "4.0",
              "creator": "<strong>Open Photographer</strong>",
              "mature": false
            },
            {
              "id": "ov_mature",
              "title": "Skipped mature result",
              "url": "https://images.example.org/mature.jpg",
              "mature": true
            }
          ]
        }
        """

        let results = try provider.decodeSearchResponse(
            Data(openverseJSON.utf8),
            query: "cinematic portrait",
            planId: "online_reference_test"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].source, .openverse)
        XCTAssertEqual(results[0].id, "openverse_ov_99")
        XCTAssertEqual(results[0].title, "Cinematic street portrait")
        XCTAssertEqual(results[0].license, "CC BY 4.0")
        XCTAssertEqual(results[0].creator, "Open Photographer")
        XCTAssertEqual(results[0].mimeType, "image/jpeg")
        XCTAssertTrue(results[0].privacy.publicSourceOnly)
        XCTAssertTrue(results[0].privacy.derivedFromPromptOnly)
        XCTAssertFalse(results[0].privacy.uploadsLiveCameraFrame)
    }

    func testOnlineInspirationRequestRejectsUnsafePlans() {
        let unsafePlan = OnlineReferencePlan(
            id: "unsafe_online_reference",
            reason: .explicitUserRequest,
            searchQueries: ["portrait reference"],
            allowedInputs: [.promptText],
            mustNotSend: [],
            userDisclosure: "Unsafe",
            privacy: .init(
                singlePhoneOnly: true,
                requiresUserConsent: true,
                sendsRawCameraFrame: true,
                sendsPrivatePhoto: false,
                sendsIdentityData: false
            )
        )

        XCTAssertThrowsError(try OnlineInspirationRequest(plan: unsafePlan)) { error in
            XCTAssertEqual(error as? OnlineInspirationError, .unsafePlan)
        }
    }

    func testOnlineInspirationRankerPrioritizesRelevantPhotographicReferences() {
        let request = OnlineInspirationRequest(
            planId: "online_reference_ranker_test",
            queries: [
                "cinematic portrait phone photography reference",
                "portrait environmental clean photography ideas"
            ]
        )
        XCTAssertEqual(request.source, .publicSources)

        let icon = OnlineInspirationResult(
            id: "wikimedia_commons_icon",
            source: .wikimediaCommons,
            query: "cinematic portrait phone photography reference",
            title: "Portrait location map icon.svg",
            pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:Portrait_location_map_icon.svg")!,
            thumbnailURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/map.svg/640px-map.svg.png"),
            imageURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/map.svg"),
            mimeType: "image/svg+xml",
            license: nil,
            creator: nil
        )
        let photograph = OnlineInspirationResult(
            id: "wikimedia_commons_photo",
            source: .wikimediaCommons,
            query: "portrait environmental clean photography ideas",
            title: "Cinematic portrait photograph with clean background.jpg",
            pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:Cinematic_portrait.jpg")!,
            thumbnailURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/photo.jpg/640px-photo.jpg"),
            imageURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/photo.jpg"),
            mimeType: "image/jpeg",
            license: "CC BY-SA 4.0",
            creator: "Jane Doe"
        )
        let openversePhotograph = OnlineInspirationResult(
            id: "openverse_photo",
            source: .openverse,
            query: "portrait environmental clean photography ideas",
            title: "Street portrait photo.jpg",
            pageURL: URL(string: "https://example.org/photos/street-portrait")!,
            thumbnailURL: URL(string: "https://images.example.org/thumbs/street-portrait.jpg"),
            imageURL: URL(string: "https://images.example.org/street-portrait.jpg"),
            mimeType: "image/jpeg",
            license: "CC BY 4.0",
            creator: "Open Photographer"
        )

        let ranked = OnlineInspirationRanker().rank([icon, photograph, openversePhotograph], for: request)

        XCTAssertEqual(ranked.first?.id, "wikimedia_commons_photo")
        XCTAssertEqual(ranked.dropFirst().first?.source, .openverse)
    }

    func testPublicSourceOnlineInspirationReportsProviderHealthForPartialFailures() async throws {
        let request = OnlineInspirationRequest(
            planId: "online_reference_provider_health_test",
            queries: ["cinematic portrait phone photography reference"]
        )
        let availableReference = OnlineInspirationResult(
            id: "wikimedia_commons_health_photo",
            source: .wikimediaCommons,
            query: request.queries[0],
            title: "Cinematic portrait photograph.jpg",
            pageURL: URL(string: "https://commons.wikimedia.org/wiki/File:Cinematic_portrait_photograph.jpg")!,
            thumbnailURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/photo.jpg/640px-photo.jpg"),
            imageURL: URL(string: "https://upload.wikimedia.org/wikipedia/commons/photo.jpg"),
            mimeType: "image/jpeg",
            license: "CC BY-SA 4.0",
            creator: "Jane Doe"
        )
        let provider = PublicSourceInspirationProvider(providers: [
            FixedOnlineInspirationProvider(source: .wikimediaCommons, results: [availableReference]),
            FailingOnlineInspirationProvider(source: .openverse, error: OnlineInspirationError.invalidHTTPStatus(503))
        ])

        let outcome = try await provider.fetchReferencesWithHealth(for: request)

        XCTAssertEqual(outcome.results.map(\.id), ["wikimedia_commons_health_photo"])
        XCTAssertEqual(outcome.providerHealth.map(\.source), [.wikimediaCommons, .openverse])
        XCTAssertEqual(outcome.providerHealth[0].status, .available)
        XCTAssertEqual(outcome.providerHealth[0].resultCount, 1)
        XCTAssertEqual(outcome.providerHealth[1].status, .failed)
        XCTAssertEqual(outcome.providerHealth[1].message, "HTTP 503")
        XCTAssertTrue(outcome.providerHealth[0].privacy.publicSourceOnly)
        XCTAssertFalse(outcome.providerHealth[0].privacy.uploadsLiveCameraFrame)

        let response = try await OnlineInspirationService(provider: provider).fetchResponse(for: request)
        XCTAssertEqual(response.healthSnapshot.status, .degraded)
        XCTAssertEqual(response.healthSnapshot.totalResultCount, 1)
        XCTAssertTrue(response.healthSnapshot.privacy.singlePhoneOnly)
        XCTAssertFalse(response.healthSnapshot.privacy.sendsRawCameraFrame)
    }

    func testOnlineInspirationServiceReturnsFailedHealthWhenEveryPublicSourceFails() async throws {
        let request = OnlineInspirationRequest(
            planId: "online_reference_provider_health_failed_test",
            queries: ["cinematic portrait phone photography reference"]
        )
        let provider = PublicSourceInspirationProvider(providers: [
            FailingOnlineInspirationProvider(source: .wikimediaCommons, error: OnlineInspirationError.invalidHTTPStatus(503)),
            FailingOnlineInspirationProvider(source: .openverse, error: OnlineInspirationError.invalidHTTPStatus(429))
        ])

        let response = try await OnlineInspirationService(provider: provider).fetchResponse(for: request)

        XCTAssertTrue(response.results.isEmpty)
        XCTAssertEqual(response.healthSnapshot.status, .failed)
        XCTAssertEqual(response.healthSnapshot.totalResultCount, 0)
        XCTAssertEqual(response.healthSnapshot.providers.map(\.status), [.failed, .failed])
        XCTAssertEqual(response.healthSnapshot.providers.compactMap(\.message), ["HTTP 503", "HTTP 429"])
        XCTAssertEqual(response.sources, [.publicSources])
    }

    func testOnlineInspirationThumbnailCacheStoresAndEvictsLocalData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LensPilotOnlineInspiration-\(UUID().uuidString)", isDirectory: true)
        let cache = OnlineInspirationThumbnailCache(directoryURL: directory, maxCacheBytes: 4)
        let firstURL = URL(string: "https://example.test/first.jpg")!
        let secondURL = URL(string: "https://example.test/second.jpg")!

        try await cache.store(Data([1, 2, 3]), for: firstURL, maxObjectBytes: 10)
        let firstCachedData = try await cache.cachedData(for: firstURL)
        XCTAssertEqual(firstCachedData, Data([1, 2, 3]))

        try await Task.sleep(nanoseconds: 5_000_000)
        try await cache.store(Data([4, 5, 6]), for: secondURL, maxObjectBytes: 10)

        let evictedFirstData = try await cache.cachedData(for: firstURL)
        let secondCachedData = try await cache.cachedData(for: secondURL)
        XCTAssertNil(evictedFirstData)
        XCTAssertEqual(secondCachedData, Data([4, 5, 6]))

        try await cache.removeAll()
    }

    private func makeCreativeInterpretationFixture() throws -> (
        CreativeInterpretationPlan,
        OnlineInspirationHealthSnapshot
    ) {
        let engine = PersonalVisualLearningEngine()
        let prompt = "Give me a cinematic luxury portrait with online inspiration."
        let shotSpec = ShotSpecFactory().makeShotSpec(from: prompt, source: .text)
        let profile = PersonalVisualPreferenceProfile(
            consent: PersonalizationConsent(learningEnabled: true, onlineReferencesAllowed: true),
            totalEvents: 3,
            domainCounts: ["portrait": 3],
            styleAffinities: ["cinematic": 0.4],
            colorAffinities: ["warm_highlights_cool_shadows": 0.2],
            framingAffinities: ["environmental": 0.3],
            guidanceReasonAffinities: ["improve_face_light": 0.4],
            requirementAffinities: ["luxury": 0.3],
            onlineReferenceUsageCount: 1
        )
        let onlinePlan = try XCTUnwrap(engine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            consent: profile.consent
        ))
        let creativePlan = try XCTUnwrap(engine.makeCreativeInterpretationPlan(
            for: shotSpec,
            prompt: prompt,
            profile: profile,
            onlineReferencePlan: onlinePlan,
            consent: profile.consent
        ))
        let healthSnapshot = OnlineInspirationHealthSnapshot(
            planId: onlinePlan.id,
            source: .publicSources,
            providers: [
                OnlineInspirationProviderHealth.available(source: .wikimediaCommons, resultCount: 2),
                OnlineInspirationProviderHealth.available(source: .openverse, resultCount: 1)
            ]
        )

        return (creativePlan, healthSnapshot)
    }

    private final class OpenAIRequestRecorder: @unchecked Sendable {
        private(set) var request: URLRequest?
        let data: Data
        let statusCode: Int

        init(data: Data, statusCode: Int = 200) {
            self.data = data
            self.statusCode = statusCode
        }

        var transport: OpenAIReasoningTransport {
            { request in
                self.request = request
                return OpenAIReasoningHTTPResponse(data: self.data, statusCode: self.statusCode)
            }
        }
    }

    private final class LensPilotCreativeAPIRequestRecorder: @unchecked Sendable {
        private(set) var request: URLRequest?
        let data: Data
        let statusCode: Int

        init(data: Data, statusCode: Int = 200) {
            self.data = data
            self.statusCode = statusCode
        }

        var transport: LensPilotCreativeAPITransport {
            { request in
                self.request = request
                return LensPilotCreativeAPIHTTPResponse(data: self.data, statusCode: self.statusCode)
            }
        }
    }

    private struct FixedOnlineInspirationProvider: OnlineInspirationProvider {
        let source: OnlineInspirationRequest.Source
        let results: [OnlineInspirationResult]

        func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
            _ = request
            return results
        }
    }

    private struct FailingOnlineInspirationProvider: OnlineInspirationProvider {
        let source: OnlineInspirationRequest.Source
        let error: OnlineInspirationError

        func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
            _ = request
            throw error
        }
    }

    private static func referencePhoto(cloudAnalysisUsed: Bool, showCameraPopup: Bool) -> ReferencePhotoState {
        ReferencePhotoState(
            id: "reference_diagnostic_test",
            source: .photoLibrary,
            localAssetUri: "local://reference_diagnostic_test",
            thumbnailUri: "memory://reference_diagnostic_test/thumbnail",
            analysisStatus: .ready,
            extractedFeatures: ReferencePhotoFeatures(
                framing: "portrait",
                apparentFocalLength: "telephoto",
                cameraHeight: "eye_level",
                subjectScale: 0.6,
                poseHints: ["relaxed_shoulders"],
                lightingDirection: "front_soft",
                colorMood: "warm",
                depthStyle: "shallow",
                achievableTranslationNotes: ["Match light and framing on this phone."]
            ),
            display: .init(showCameraPopup: showCameraPopup, popupPosition: .topRight, viewerState: .collapsedPopup),
            privacy: .init(cloudAnalysisUsed: cloudAnalysisUsed, userConsentedToCloudAnalysis: cloudAnalysisUsed)
        )
    }

    private static func readyCalibrationReadinessReport() -> TargetMatchCalibrationManifest.CalibrationReadinessReport {
        TargetMatchCalibrationManifest.CalibrationReadinessReport(
            status: .ready,
            reviewedSampleCount: 24,
            targetRealCaptureCount: 24,
            missingSampleCount: 0,
            reviewedDomains: ["landscape", "lifestyle", "night", "portrait"],
            missingDomains: [],
            scenarioTargetCount: 3,
            scenarioCounts: Dictionary(
                uniqueKeysWithValues: CalibrationCaptureScenario.allCases.map { ($0.rawValue, $0.targetSampleCount) }
            ),
            missingScenarios: [],
            isReadyForProductionCalibration: true
        )
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

    private static func calibrationManifestData(
        singlePhoneOnly: Bool = true,
        backgroundClutterPenalty: Double = 0.55,
        requiredScenarios: [String]? = nil
    ) -> Data {
        let singlePhoneValue = singlePhoneOnly ? "true" : "false"
        let scenarioIds = requiredScenarios ?? CalibrationCaptureScenario.allCases.map(\.rawValue)
        let requiredScenarioValues = scenarioIds
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        let json = """
        {
          "version": "2026.08.17",
          "collectionPlan": {
            "singlePhoneOnly": \(singlePhoneValue),
            "realCaptureTargetCount": 24,
            "minimumBlindReviewers": 2,
            "requiredDomains": ["portrait", "landscape", "lifestyle", "night"],
            "requiredScenarios": [\(requiredScenarioValues)]
          },
          "targetMatchCalibration": {
            "horizonRollFullPenaltyDegrees": 12,
            "eyeLevelPitchFullPenaltyDegrees": 35,
            "highlightClippingPenalty": 0.8,
            "shadowClippingPenalty": 0.6,
            "backgroundClutterPenalty": \(backgroundClutterPenalty),
            "poleBehindHeadPenalty": 0.25,
            "dynamicRangeLightingPenalty": 0.2,
            "motionBlurPenalty": 1,
            "missingHorizonScore": 0.72,
            "missingFaceLightQuality": 0.65,
            "missingPoseScore": 0.72,
            "nonPortraitCameraAngleScore": 0.75
          },
          "samples": [
            {
              "id": "iphone_capture_unit_test",
              "sampleKind": "iphone_capture",
              "domain": "portrait",
              "captureMetadata": {
                "calibrationScenarioId": "clutter"
              },
              "blindPreference": {
                "reviewCount": 2,
                "preferredGuidanceReason": "reduce_clutter",
                "rankedWeaknesses": ["background", "lighting"],
                "notes": "Unit-test reviewed sample."
              }
            }
          ]
        }
        """

        return Data(json.utf8)
    }

    private static func guidanceAction(
        id: String,
        actor: GuidanceAction.Actor = .photographer,
        action: GuidanceAction.Action,
        magnitude: Double? = 0.4,
        unit: GuidanceAction.Unit? = .meter,
        direction: GuidanceAction.Direction? = nil,
        reason: GuidanceAction.Reason = .reduceClutter,
        expectedGain: Double = 0.16,
        priority: Int = 88
    ) -> GuidanceAction {
        GuidanceAction(
            id: id,
            actor: actor,
            action: action,
            magnitude: magnitude,
            unit: unit,
            direction: direction,
            confidence: 0.76,
            reason: reason,
            expectedGain: expectedGain,
            safetyQualifier: actor == .photographer ? .ifSafe : nil,
            priority: priority,
            ttlMs: 3_500,
            suppressOppositeUntilMs: 5_000
        )
    }
}
