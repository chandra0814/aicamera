import AVFoundation
import Combine
import Foundation
import LensPilotCamera
import LensPilotCore
import LensPilotDirector
import LensPilotVision

@MainActor
final class CameraScreenViewModel: ObservableObject {
    let camera = CameraSessionController()
    let directorState = SinglePhoneDirectorState()

    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var deviceCapability: DeviceCapability?
    @Published private(set) var currentShotSpec: ShotSpec?
    @Published private(set) var currentShotPlan: ShotPlan?
    @Published private(set) var latestSceneDebugState: SceneDebugState?
    @Published var intentText = "Give me a cinematic portrait"
    @Published var usesFrontCameraForSelfShot = false
    @Published var lastCaptureData: Data?
    @Published var errorMessage: String?

    private let capabilityProfiler = DeviceCapabilityProfiler()
    private let aiCore = LensPilotAiCore()
    private let sceneStateBuilder = SceneStateBuilder()
    private let frameAnalyzer = FrameAnalyzer()
    private let photoCaptureController = PhotoCaptureController()
    private lazy var frameAnalysisCoordinator = CameraFrameAnalysisCoordinator(analyzer: frameAnalyzer)
    private var isFrameAnalysisConnected = false

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

    func stop() {
        camera.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        isFrameAnalysisConnected = false
        Task {
            await camera.stop()
        }
    }

    func toggleSelfShotCamera() {
        usesFrontCameraForSelfShot.toggle()
        Task {
            await configureCamera()
        }
    }

    func makePlanFromIntent() {
        runAi(sceneState: currentSceneState())
    }

    private func handleSceneDebugState(_ debugState: SceneDebugState) {
        latestSceneDebugState = debugState
        runAi(sceneState: sceneState(from: debugState))
    }

    private func runAi(sceneState: SceneState) {
        let capability = deviceCapability ?? fallbackCapability()
        let result = aiCore.run(
            prompt: intentText,
            sceneState: sceneState,
            deviceCapability: capability
        )

        currentShotSpec = result.shotSpec
        currentShotPlan = result.shotPlan
        directorState.updateGuidance(
            instruction: result.guidanceAction.map(Self.instructionText),
            targetMatch: result.targetMatch.overall
        )
    }

    func activateMockReference() {
        let reference = ReferencePhotoState(
            id: "ref_local_preview",
            source: .photoLibrary,
            localAssetUri: "ph://selected-reference",
            thumbnailUri: "cache://selected-reference-thumb.jpg",
            analysisStatus: .ready,
            extractedFeatures: ReferencePhotoFeatures(
                framing: "Environmental portrait",
                apparentFocalLength: "50mm equivalent",
                cameraHeight: "eye_level",
                subjectScale: 0.42,
                poseHints: ["Angle shoulders slightly", "Turn face toward light"],
                lightingDirection: "front-left",
                colorMood: "warm highlights with natural skin",
                depthStyle: "moderate separation",
                achievableTranslationNotes: ["Use camera angle and framing first."]
            ),
            display: .init(showCameraPopup: true, popupPosition: .topRight, viewerState: .collapsedPopup),
            privacy: .init(cloudAnalysisUsed: false, userConsentedToCloudAnalysis: false)
        )
        directorState.activateReferencePhoto(reference)
    }

    func capture() {
        Task {
            do {
                lastCaptureData = try await photoCaptureController.capturePhoto(using: camera.photoOutput)
            } catch {
                errorMessage = "Capture failed: \(error.localizedDescription)"
            }
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
