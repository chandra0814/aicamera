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

    func testTargetMatchCalibrationManifestRejectsNonSinglePhonePlan() {
        XCTAssertThrowsError(try TargetMatchCalibrationManifest.decode(
            from: Self.calibrationManifestData(singlePhoneOnly: false)
        )) { error in
            XCTAssertEqual(error as? TargetMatchCalibrationManifestError, .singlePhoneCalibrationRequired)
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
        backgroundClutterPenalty: Double = 0.55
    ) -> Data {
        let singlePhoneValue = singlePhoneOnly ? "true" : "false"
        let json = """
        {
          "version": "2026.08.17",
          "collectionPlan": {
            "singlePhoneOnly": \(singlePhoneValue),
            "realCaptureTargetCount": 24,
            "minimumBlindReviewers": 2,
            "requiredDomains": ["portrait", "landscape", "lifestyle", "night"]
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
