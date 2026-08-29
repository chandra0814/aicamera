import AVFoundation
import Combine
import Foundation
import LensPilotCamera
import LensPilotCore
import LensPilotDirector
import LensPilotVision

struct CaptureReviewPresentation: Identifiable {
    let id: String
    let bestPhotoData: Data
    let rankedShots: [RankedShot]
}

private struct AiCoreConfiguration: Sendable {
    let targetMatchCalibration: TargetMatchCalibration
    let guidanceCalibration: GuidanceCalibration
}

enum OnlineInspirationLoadState: Equatable {
    case idle
    case loading
    case loaded(Int)
    case failed(String)
}

enum PreviewAdjustmentCommand: String, CaseIterable, Identifiable {
    case brighter
    case moreSky
    case lessBackgroundBlur
    case naturalColor
    case moreDrama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brighter:
            return "Brighter"
        case .moreSky:
            return "More Sky"
        case .lessBackgroundBlur:
            return "Less Background Blur"
        case .naturalColor:
            return "Natural Color"
        case .moreDrama:
            return "More Drama"
        }
    }

    var instruction: String {
        switch self {
        case .brighter:
            return "Make it brighter."
        case .moreSky:
            return "Show more sky."
        case .lessBackgroundBlur:
            return "Use less background blur."
        case .naturalColor:
            return "Keep colors natural."
        case .moreDrama:
            return "Make it more dramatic."
        }
    }

    var iconName: String {
        switch self {
        case .brighter:
            return "sun.max"
        case .moreSky:
            return "cloud.sun"
        case .lessBackgroundBlur:
            return "circle.dashed"
        case .naturalColor:
            return "camera.filters"
        case .moreDrama:
            return "theatermasks"
        }
    }
}

@MainActor
final class CameraScreenViewModel: ObservableObject {
    let camera = CameraSessionController()
    let directorState = SinglePhoneDirectorState()

    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var deviceCapability: DeviceCapability?
    @Published private(set) var currentShotSpec: ShotSpec?
    @Published private(set) var currentShotPlan: ShotPlan?
    @Published private(set) var currentTargetPreview: TargetPreview?
    @Published private(set) var currentTargetMatch: TargetMatchScore?
    @Published private(set) var latestSceneDebugState: SceneDebugState?
    @Published private(set) var referenceImageData: Data?
    @Published private(set) var captureReview: CaptureReviewPresentation?
    @Published private(set) var lastCalibrationCandidate: CalibrationSample?
    @Published private(set) var activeCalibrationScenario: CalibrationCaptureScenario?
    @Published private(set) var lastCalibrationScenario: CalibrationCaptureScenario?
    @Published private(set) var calibrationQueueProgress = CalibrationCaptureQueueProgress()
    @Published private(set) var personalizationConsent: PersonalizationConsent
    @Published private(set) var personalProfile: PersonalVisualPreferenceProfile
    @Published private(set) var onlineReferencePlan: OnlineReferencePlan?
    @Published private(set) var onlineInspirationResults: [OnlineInspirationResult] = []
    @Published private(set) var onlineInspirationThumbnailData: [String: Data] = [:]
    @Published private(set) var onlineInspirationLoadState: OnlineInspirationLoadState = .idle
    @Published private(set) var speechIntentState: SpeechIntentState = .idle
    @Published private(set) var speechIntentTranscript = ""
    @Published private(set) var isCapturing = false
    @Published var intentText = "Give me a cinematic portrait"
    @Published var usesFrontCameraForSelfShot = false
    @Published var lastCaptureData: Data?
    @Published var errorMessage: String?

    private let capabilityProfiler = DeviceCapabilityProfiler()
    private let targetMatchCalibration: TargetMatchCalibration
    private let reviewedGuidanceCalibration: GuidanceCalibration
    private let sceneStateBuilder = SceneStateBuilder()
    private let frameAnalyzer = FrameAnalyzer()
    private let photoCaptureController = PhotoCaptureController()
    private let captureReviewBuilder = CaptureReviewBuilder()
    private let calibrationSampleExporter = CalibrationSampleExporter()
    private let calibrationSamplePromoter = CalibrationSamplePromoter()
    private let personalLearningEngine = PersonalVisualLearningEngine()
    private let onlineInspirationService = OnlineInspirationService()
    private let onlineInspirationThumbnailCache = OnlineInspirationThumbnailCache()
    private let speechIntentController = SpeechIntentController()
    private var guidanceStabilizer = GuidanceStabilizer()
    private lazy var frameAnalysisCoordinator = CameraFrameAnalysisCoordinator(analyzer: frameAnalyzer)
    private var isFrameAnalysisConnected = false
    private var latestGuidanceAction: GuidanceAction?
    private var hasLoadedOnlineInspiration = false
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(calibrationData: CameraScreenViewModel.bundledCalibrationData())
    }

    init(calibrationData: Data?) {
        let configuration = CameraScreenViewModel.makeAiCoreConfiguration(calibrationData: calibrationData)
        let storedProfile = CameraScreenViewModel.loadPersonalProfile()
        let storedCalibrationQueueProgress = CameraScreenViewModel.loadCalibrationQueueProgress()
        self.targetMatchCalibration = configuration.targetMatchCalibration
        self.reviewedGuidanceCalibration = configuration.guidanceCalibration
        self.calibrationQueueProgress = storedCalibrationQueueProgress
        self.activeCalibrationScenario = storedCalibrationQueueProgress.activeScenario
        self.personalizationConsent = storedProfile?.consent ?? .disabled
        self.personalProfile = storedProfile ?? .empty(consent: .disabled)
        bindSpeechIntentController()
    }

    func start() {
        Task {
            authorizationState = camera.authorizationState()
            if authorizationState == .notDetermined {
                let granted = await camera.requestAccess()
                authorizationState = granted ? .authorized : .denied
            }

            guard authorizationState == .authorized else {
                errorMessage = "Camera permission is required."
                return
            }

            await configureCamera()
            connectFrameAnalysisIfNeeded()
            deviceCapability = capabilityProfiler.profileCurrentDevice()
            makePlanFromIntent()
            await camera.start()
        }
    }

    nonisolated private static func bundledCalibrationData() -> Data? {
        guard let url = Bundle.main.url(forResource: "target-match-calibration", withExtension: "json") else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    nonisolated private static func makeAiCoreConfiguration(calibrationData: Data?) -> AiCoreConfiguration {
        guard let calibrationData else {
            return AiCoreConfiguration(targetMatchCalibration: .standard, guidanceCalibration: .standard)
        }

        do {
            let manifest = try TargetMatchCalibrationManifest.decode(from: calibrationData)
            return AiCoreConfiguration(
                targetMatchCalibration: manifest.targetMatchCalibration,
                guidanceCalibration: manifest.makeGuidanceCalibration()
            )
        } catch {
            return AiCoreConfiguration(targetMatchCalibration: .standard, guidanceCalibration: .standard)
        }
    }

    func stop() {
        speechIntentController.stopListening()
        camera.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        isFrameAnalysisConnected = false
        Task {
            await camera.stop()
        }
    }

    func toggleSelfShotCamera() {
        usesFrontCameraForSelfShot.toggle()
        guidanceStabilizer.reset()
        Task {
            await configureCamera()
        }
    }

    func makePlanFromIntent() {
        if speechIntentController.isListening {
            speechIntentController.stopListening()
        }
        guidanceStabilizer.reset()
        runAi(sceneState: currentSceneState())
    }

    func applyPreviewAdjustment(_ command: PreviewAdjustmentCommand) {
        let trimmedIntent = intentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIntent = trimmedIntent.lowercased()
        let normalizedInstruction = command.instruction
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if !normalizedIntent.contains(normalizedInstruction) {
            intentText = trimmedIntent.isEmpty ? command.instruction : "\(trimmedIntent) \(command.instruction)"
        }

        makePlanFromIntent()
    }

    func toggleSpeechIntentInput() {
        if speechIntentController.isListening {
            speechIntentController.stopListening(commitTranscript: true)
            return
        }

        Task {
            await speechIntentController.startListening()
        }
    }

    func setLocalPersonalLearningEnabled(_ isEnabled: Bool) {
        applyPersonalizationConsent(
            PersonalizationConsent(
                learningEnabled: isEnabled,
                onlineReferencesAllowed: personalizationConsent.onlineReferencesAllowed,
                cloudPersonalizationSyncAllowed: false
            )
        )
    }

    func setOnlineInspirationEnabled(_ isEnabled: Bool) {
        applyPersonalizationConsent(
            PersonalizationConsent(
                learningEnabled: personalizationConsent.learningEnabled,
                onlineReferencesAllowed: isEnabled,
                cloudPersonalizationSyncAllowed: false
            )
        )
    }

    func resetPersonalVisualLearning() {
        personalProfile = .empty(consent: personalizationConsent)
        persistPersonalProfile()
        guidanceStabilizer.reset()
        runAi(sceneState: currentSceneState())
    }

    func selectCalibrationScenario(_ scenario: CalibrationCaptureScenario) {
        activeCalibrationScenario = scenario
        calibrationQueueProgress = calibrationQueueProgress.selecting(scenario)
        persistCalibrationQueueProgress()
        intentText = scenario.prompt
        makePlanFromIntent()
    }

    func resetCalibrationQueue() {
        activeCalibrationScenario = nil
        lastCalibrationScenario = nil
        calibrationQueueProgress = calibrationQueueProgress.reset()
        persistCalibrationQueueProgress()
    }

    func fetchOnlineInspirationReferences() {
        guard let plan = onlineReferencePlan else {
            onlineInspirationResults = []
            onlineInspirationLoadState = .idle
            return
        }

        guard onlineInspirationLoadState != .loading else { return }

        let planId = plan.id
        onlineInspirationLoadState = .loading
        Task {
            do {
                let response = try await onlineInspirationService.fetchReferences(for: plan, perQueryLimit: 3)
                guard onlineReferencePlan?.id == planId else { return }
                onlineInspirationResults = response.results
                onlineInspirationThumbnailData = [:]
                hasLoadedOnlineInspiration = !response.results.isEmpty
                onlineInspirationLoadState = .loaded(response.results.count)
                warmOnlineInspirationThumbnailCache(for: response.results, planId: planId)
            } catch {
                guard onlineReferencePlan?.id == planId else { return }
                onlineInspirationResults = []
                onlineInspirationThumbnailData = [:]
                hasLoadedOnlineInspiration = false
                onlineInspirationLoadState = .failed("Public references unavailable")
                errorMessage = "Online inspiration failed. Camera guidance still works offline."
            }
        }
    }

    func useOnlineInspirationReference(_ result: OnlineInspirationResult) {
        guard let url = result.thumbnailURL ?? result.imageURL else {
            errorMessage = "Online reference image is unavailable."
            return
        }

        Task {
            do {
                let data = try await onlineInspirationThumbnailCache.data(for: url, maxObjectBytes: 6_000_000)
                onlineInspirationThumbnailData[result.id] = data

                activateReferencePhoto(
                    imageData: data,
                    source: .sharedFile,
                    localAssetUri: result.pageURL.absoluteString,
                    notes: ["Public reference loaded on this phone. Match its light, angle, and framing."]
                )
                hasLoadedOnlineInspiration = true
                recordPersonalLearningEvent(
                    outcome: .acceptedGuidance,
                    acceptedGuidanceReason: .matchReference,
                    onlineReferenceUsed: true
                )
            } catch {
                errorMessage = "Online reference could not be loaded."
            }
        }
    }

    func cachedOnlineInspirationThumbnailData(for result: OnlineInspirationResult) -> Data? {
        onlineInspirationThumbnailData[result.id]
    }

    private func handleSceneDebugState(_ debugState: SceneDebugState) {
        latestSceneDebugState = debugState
        runAi(sceneState: sceneState(from: debugState))
    }

    private func bindSpeechIntentController() {
        speechIntentController.$state
            .sink { [weak self] state in
                self?.speechIntentState = state
            }
            .store(in: &cancellables)

        speechIntentController.$transcript
            .sink { [weak self] transcript in
                self?.speechIntentTranscript = transcript

                guard !transcript.isEmpty else { return }
                self?.intentText = transcript
            }
            .store(in: &cancellables)

        speechIntentController.onFinalTranscript = { [weak self] transcript in
            guard let self, !transcript.isEmpty else { return }
            self.intentText = transcript
            self.makePlanFromIntent()
        }

        speechIntentController.onFailure = { [weak self] message in
            self?.errorMessage = message
        }
    }

    private func runAi(sceneState: SceneState) {
        let capability = deviceCapability ?? fallbackCapability()
        let result = makePersonalizedAiCore().run(
            prompt: intentText,
            sceneState: sceneState,
            deviceCapability: capability
        )

        currentShotSpec = result.shotSpec
        currentShotPlan = result.shotPlan
        currentTargetPreview = result.targetPreview
        currentTargetMatch = result.targetMatch
        refreshOnlineReferencePlan(for: result.shotSpec)
        let guidanceAction = guidanceStabilizer.stabilize(result.guidanceAction)
        latestGuidanceAction = guidanceAction
        directorState.updateGuidance(
            instruction: guidanceAction.map(Self.instructionText),
            targetMatch: result.targetMatch.overall,
            targetPreview: result.targetPreview
        )
    }

    func activateReferencePhoto(imageData: Data, assetIdentifier: String?) {
        let referenceId = "ref_\(UUID().uuidString.lowercased())"
        let assetPath = assetIdentifier.map { "ph://\($0)" } ?? "local://\(referenceId)"
        activateReferencePhoto(
            imageData: imageData,
            source: .photoLibrary,
            localAssetUri: assetPath,
            notes: ["Reference loaded on this phone. Match it with camera angle, light, and framing."]
        )
    }

    func failReferencePhotoLoad(_ error: Error? = nil) {
        if let error {
            errorMessage = "Reference photo failed: \(error.localizedDescription)"
        } else {
            errorMessage = "Reference photo could not be loaded."
        }
    }

    private func activateReferencePhoto(
        imageData: Data,
        source: ReferencePhotoState.Source,
        localAssetUri: String,
        notes: [String]
    ) {
        referenceImageData = imageData
        guidanceStabilizer.reset()
        let referenceId = "ref_\(UUID().uuidString.lowercased())"
        let reference = ReferencePhotoState(
            id: referenceId,
            source: source,
            localAssetUri: localAssetUri,
            thumbnailUri: "memory://\(referenceId)/thumbnail",
            analysisStatus: .ready,
            extractedFeatures: ReferencePhotoFeatures(
                framing: nil,
                apparentFocalLength: nil,
                cameraHeight: nil,
                subjectScale: nil,
                poseHints: [],
                lightingDirection: nil,
                colorMood: nil,
                depthStyle: nil,
                achievableTranslationNotes: notes
            ),
            display: .init(showCameraPopup: true, popupPosition: .topRight, viewerState: .collapsedPopup),
            privacy: .init(cloudAnalysisUsed: false, userConsentedToCloudAnalysis: false)
        )
        directorState.activateReferencePhoto(reference)
    }

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureReview = nil
        lastCaptureData = nil
        lastCalibrationCandidate = nil
        lastCalibrationScenario = nil

        Task {
            defer {
                isCapturing = false
            }

            do {
                let burstCount = currentShotPlan?.capturePolicy.burstFrameCount ?? 1
                let frames = try await photoCaptureController.captureBurst(count: burstCount, using: camera.photoOutput)
                presentCaptureReview(for: frames)
            } catch {
                errorMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    func dismissCaptureReview() {
        captureReview = nil
    }

    func keepLatestCaptureResult() {
        recordPersonalLearningEvent(
            outcome: .savedResult,
            acceptedGuidanceReason: latestGuidanceAction?.reason,
            userRating: 5,
            onlineReferenceUsed: hasLoadedOnlineInspiration
        )
        captureReview = nil
    }

    func rejectLatestCaptureResult(reason: GuidanceAction.Reason? = nil) {
        recordPersonalLearningEvent(
            outcome: .rejectedGuidance,
            rejectedGuidanceReason: reason == nil ? latestGuidanceAction?.reason : nil,
            customerCorrectionReason: reason,
            userRating: 1,
            onlineReferenceUsed: hasLoadedOnlineInspiration
        )
        captureReview = nil
    }

    func makeCalibrationSampleExport() -> String {
        let sample = makeCalibrationCandidate()

        do {
            return try calibrationSampleExporter.encodeJSONString(sample)
        } catch {
            return #"{"error":"calibration_sample_encoding_failed"}"#
        }
    }

    func makeReviewedCalibrationSampleExport(review: CalibrationSample.ReviewLabel) -> String {
        let candidate = lastCalibrationCandidate ?? makeCalibrationCandidate()

        do {
            let reviewedSample = try calibrationSamplePromoter.makeReviewedSample(from: candidate, review: review)
            return try calibrationSampleExporter.encodeJSONString(reviewedSample)
        } catch {
            return #"{"error":"calibration_review_encoding_failed"}"#
        }
    }

    private func makeCalibrationCandidate() -> CalibrationSample {
        let sceneState = currentSceneState()
        let capability = deviceCapability ?? fallbackCapability()
        let result = makePersonalizedAiCore().run(
            prompt: intentText,
            sceneState: sceneState,
            deviceCapability: capability
        )
        let sample = calibrationSampleExporter.makeCandidate(
            prompt: intentText,
            sceneState: sceneState,
            deviceCapability: capability,
            aiResult: result,
            usesFrontCameraForSelfShot: usesFrontCameraForSelfShot,
            referencePhotoActive: referenceImageData != nil,
            calibrationScenario: lastCalibrationScenario ?? activeCalibrationScenario
        )
        return sample
    }

    private func presentCaptureReview(for frames: [Data]) {
        guard !frames.isEmpty else {
            errorMessage = "Capture did not return a photo."
            return
        }

        let frameMetrics = frames.enumerated().map { index, data in
            CaptureFrameMetric(
                id: "capture_\(index + 1)",
                sequenceIndex: index,
                byteCount: data.count
            )
        }
        let review = captureReviewBuilder.makeReview(frames: frameMetrics, targetMatch: currentTargetMatch)
        let bestShotId = review.bestShotId ?? frameMetrics[0].id
        let bestIndex = frameMetrics.firstIndex { $0.id == bestShotId } ?? 0
        let bestPhotoData = frames[bestIndex]

        lastCaptureData = bestPhotoData
        lastCalibrationCandidate = makeCalibrationCandidate()
        recordCalibrationQueueCaptureIfNeeded()
        captureReview = CaptureReviewPresentation(
            id: "review_\(UUID().uuidString.lowercased())",
            bestPhotoData: bestPhotoData,
            rankedShots: review.rankedShots
        )
        recordPersonalLearningEvent(
            outcome: .selectedBestShot,
            acceptedGuidanceReason: latestGuidanceAction?.reason,
            onlineReferenceUsed: hasLoadedOnlineInspiration
        )
    }

    private func makePersonalizedAiCore() -> LensPilotAiCore {
        LensPilotAiCore(
            targetMatchCalibration: targetMatchCalibration,
            guidanceCalibration: mergedGuidanceCalibration()
        )
    }

    private func mergedGuidanceCalibration() -> GuidanceCalibration {
        let personalGuidance = personalProfile.guidanceCalibration()
        var globalReasonBoosts = reviewedGuidanceCalibration.globalReasonBoosts

        for (reason, boost) in personalGuidance.globalReasonBoosts {
            globalReasonBoosts[reason, default: 0] += boost
        }

        return GuidanceCalibration(
            globalReasonBoosts: globalReasonBoosts,
            domainReasonBoosts: reviewedGuidanceCalibration.domainReasonBoosts
        )
    }

    private func applyPersonalizationConsent(_ consent: PersonalizationConsent) {
        personalizationConsent = consent
        personalProfile = PersonalVisualPreferenceProfile(
            version: personalProfile.version,
            consent: consent,
            totalEvents: personalProfile.totalEvents,
            domainCounts: personalProfile.domainCounts,
            styleAffinities: personalProfile.styleAffinities,
            colorAffinities: personalProfile.colorAffinities,
            framingAffinities: personalProfile.framingAffinities,
            guidanceReasonAffinities: personalProfile.guidanceReasonAffinities,
            requirementAffinities: personalProfile.requirementAffinities,
            onlineReferenceUsageCount: personalProfile.onlineReferenceUsageCount
        )
        persistPersonalProfile()
        guidanceStabilizer.reset()
        runAi(sceneState: currentSceneState())
    }

    private func recordPersonalLearningEvent(
        outcome: PersonalLearningEvent.Outcome,
        acceptedGuidanceReason: GuidanceAction.Reason? = nil,
        rejectedGuidanceReason: GuidanceAction.Reason? = nil,
        customerCorrectionReason: GuidanceAction.Reason? = nil,
        userRating: Double? = nil,
        onlineReferenceUsed: Bool = false
    ) {
        guard let shotSpec = currentShotSpec else { return }

        let event = PersonalLearningEvent(
            id: "usage_\(UUID().uuidString.lowercased())",
            domain: shotSpec.domain,
            outcome: outcome,
            promptRequirements: promptRequirements(for: shotSpec, prompt: intentText),
            acceptedGuidanceReason: acceptedGuidanceReason,
            rejectedGuidanceReason: rejectedGuidanceReason,
            customerCorrectionReason: customerCorrectionReason,
            selectedStyle: shotSpec.style.name,
            selectedColorIntent: shotSpec.style.colorIntent,
            selectedFraming: shotSpec.composition.framing,
            selectedTargetMatch: currentTargetMatch?.overall,
            userRating: userRating,
            onlineReferenceUsed: onlineReferenceUsed
        )
        let updatedProfile = personalLearningEngine.updatedProfile(
            from: personalProfile,
            with: event,
            consent: personalizationConsent
        )
        guard updatedProfile != personalProfile else { return }

        personalProfile = updatedProfile
        persistPersonalProfile()
        guidanceStabilizer.reset()
        runAi(sceneState: currentSceneState())
    }

    private func refreshOnlineReferencePlan(for shotSpec: ShotSpec?) {
        guard let shotSpec else {
            onlineReferencePlan = nil
            onlineInspirationResults = []
            onlineInspirationThumbnailData = [:]
            onlineInspirationLoadState = .idle
            hasLoadedOnlineInspiration = false
            return
        }

        let nextPlan = personalLearningEngine.makeOnlineReferencePlan(
            for: shotSpec,
            prompt: intentText,
            profile: personalProfile,
            consent: personalizationConsent
        )
        if nextPlan != onlineReferencePlan {
            onlineInspirationResults = []
            onlineInspirationThumbnailData = [:]
            onlineInspirationLoadState = .idle
            hasLoadedOnlineInspiration = false
        }
        onlineReferencePlan = nextPlan
    }

    private func warmOnlineInspirationThumbnailCache(for results: [OnlineInspirationResult], planId: String) {
        Task {
            for result in results.prefix(6) {
                guard onlineReferencePlan?.id == planId else { return }
                guard let url = result.thumbnailURL ?? result.imageURL else { continue }

                if let data = try? await onlineInspirationThumbnailCache.data(for: url, maxObjectBytes: 1_500_000) {
                    guard onlineReferencePlan?.id == planId else { return }
                    onlineInspirationThumbnailData[result.id] = data
                }
            }
        }
    }

    private func promptRequirements(for shotSpec: ShotSpec, prompt: String) -> [String] {
        let normalizedPrompt = prompt.lowercased()
        var requirements = [
            shotSpec.domain.rawValue,
            shotSpec.style.name.rawValue,
            shotSpec.composition.framing.rawValue
        ]

        if let colorIntent = shotSpec.style.colorIntent {
            requirements.append(colorIntent.rawValue)
        }

        if let backgroundPriority = shotSpec.composition.backgroundPriority {
            requirements.append("\(backgroundPriority.rawValue)_background")
        }

        let promptRequirements = [
            ("cinematic", "cinematic"),
            ("professional", "professional"),
            ("luxury", "luxury"),
            ("clean", "clean_background"),
            ("background", "background"),
            ("selfie", "self_shot"),
            ("night", "night"),
            ("sunset", "sunset"),
            ("reference", "reference_match"),
            ("online", "online_inspiration"),
            ("inspiration", "online_inspiration")
        ]

        for (term, requirement) in promptRequirements where normalizedPrompt.contains(term) {
            requirements.append(requirement)
        }

        return uniqueNonEmpty(requirements)
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    private static func loadPersonalProfile() -> PersonalVisualPreferenceProfile? {
        try? PersonalVisualProfileStore().loadProfile()
    }

    private static func loadCalibrationQueueProgress() -> CalibrationCaptureQueueProgress {
        (try? CalibrationCaptureQueueStore().loadProgress()) ?? CalibrationCaptureQueueProgress()
    }

    private func persistPersonalProfile() {
        let sanitizedProfile = personalProfile.sanitizedForLocalStorage()
        personalProfile = sanitizedProfile

        do {
            try PersonalVisualProfileStore().saveProfile(sanitizedProfile)
        } catch {
            errorMessage = "Personal learning profile could not be saved."
        }
    }

    private func recordCalibrationQueueCaptureIfNeeded() {
        guard let activeCalibrationScenario else { return }

        lastCalibrationScenario = activeCalibrationScenario
        calibrationQueueProgress = calibrationQueueProgress.recordingCapture(for: activeCalibrationScenario)
        persistCalibrationQueueProgress()
    }

    private func persistCalibrationQueueProgress() {
        let sanitizedProgress = calibrationQueueProgress.sanitizedForLocalStorage()
        calibrationQueueProgress = sanitizedProgress
        activeCalibrationScenario = sanitizedProgress.activeScenario

        do {
            try CalibrationCaptureQueueStore().saveProgress(sanitizedProgress)
        } catch {
            errorMessage = "Calibration queue progress could not be saved."
        }
    }

    private func connectFrameAnalysisIfNeeded() {
        guard !isFrameAnalysisConnected else { return }

        frameAnalysisCoordinator.onSceneDebugState = { [weak self] debugState in
            self?.handleSceneDebugState(debugState)
        }
        camera.videoDataOutput.setSampleBufferDelegate(
            frameAnalysisCoordinator,
            queue: frameAnalysisCoordinator.sampleBufferQueue
        )
        isFrameAnalysisConnected = true
    }

    private func configureCamera() async {
        do {
            try await camera.configure(position: usesFrontCameraForSelfShot ? .front : .back)
        } catch {
            errorMessage = "Camera setup failed: \(error.localizedDescription)"
        }
    }

    private static func instructionText(for action: GuidanceAction) -> String {
        switch action.action {
        case .moveLeft:
            return action.safetyQualifier == .ifSafe ? "If safe, move slightly left" : "Move slightly left"
        case .moveRight:
            return action.safetyQualifier == .ifSafe ? "If safe, move slightly right" : "Move slightly right"
        case .raiseCamera:
            return "Raise camera slightly"
        case .lowerCamera:
            return "Lower camera slightly"
        case .rotateClockwise:
            return action.safetyQualifier == .ifSafe ? "If safe, rotate slightly right" : "Rotate slightly right"
        case .rotateCounterclockwise:
            return action.safetyQualifier == .ifSafe ? "If safe, rotate slightly left" : "Rotate slightly left"
        case .adjustExposure:
            return "Lower exposure to protect highlights"
        case .holdSteady:
            return "Hold steady"
        case .captureNow:
            return "Perfect. Capture now"
        default:
            return "Adjust framing"
        }
    }

    private func fallbackCapability() -> DeviceCapability {
        DeviceCapability(
            manufacturer: "Apple",
            model: "Unknown iPhone",
            physicalCameras: [
                .init(
                    id: "fallback_back_wide",
                    position: .back,
                    lensType: .wide,
                    minZoom: 1,
                    maxZoom: 5,
                    supportsFocusLock: true,
                    supportsExposureLock: true
                ),
                .init(
                    id: "fallback_front_wide",
                    position: .front,
                    lensType: .wide,
                    minZoom: 1,
                    maxZoom: 1,
                    supportsFocusLock: true,
                    supportsExposureLock: true
                )
            ],
            rawSupported: false,
            depthSupported: false,
            manualExposureSupported: false,
            manualFocusSupported: true,
            manualWhiteBalanceSupported: false,
            hdrSupported: true,
            nightExtensionSupported: false,
            portraitExtensionSupported: false,
            stabilizationModes: ["standard"],
            thermalClass: nil,
            measuredCameraLatency: nil
        )
    }

    private func currentSceneState() -> SceneState {
        guard let latestSceneDebugState else {
            return placeholderSceneState()
        }

        return sceneState(from: latestSceneDebugState)
    }

    private func sceneState(from debugState: SceneDebugState) -> SceneState {
        sceneStateBuilder.makeSceneState(
            from: debugState,
            usesFrontCameraForSelfShot: usesFrontCameraForSelfShot
        )
    }

    private func placeholderSceneState() -> SceneState {
        SceneState(
            timestamp: Date(),
            frameId: "placeholder_frame",
            cameraState: LiveCameraState(
                lensId: usesFrontCameraForSelfShot ? "front_wide" : "back_wide",
                focalLength35mmEquivalent: usesFrontCameraForSelfShot ? 24 : 26,
                zoomFactor: 1,
                exposureBias: 0,
                orientation: .portrait,
                rollDegrees: 3.8,
                pitchDegrees: 4
            ),
            deviceThermal: .nominal,
            scene: SceneSummary(
                category: .portrait,
                confidence: 0.82,
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
                    id: "subject_placeholder",
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
}
