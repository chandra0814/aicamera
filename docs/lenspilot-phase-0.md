# LensPilot AI Phase 0

Development codename: LensPilot AI  
Positioning: AI Photography Director  
Tagline: Describe it. Preview it. Shoot it.

## A. MVP Product Requirements Document

### Target Users

- Everyday phone photographers who want better portraits, travel shots, lifestyle photos, and social images without learning photography terminology.
- Solo creators who need direction while shooting themselves, friends, products, cars, or travel scenes.
- Families and travelers who want simple, real-time guidance instead of post-capture editing complexity.
- Early adopters willing to compare AI-guided capture against native camera output.

### Core User Problems

- Users know the desired vibe but not the camera position, lens, exposure, framing, or pose needed to achieve it.
- Native camera apps expose powerful computational photography but rarely translate intent into real-time direction.
- AI photo apps often over-index on post-processing and can misrepresent what is physically achievable.
- Ordinary users struggle with cluttered backgrounds, bad horizons, awkward pose, weak lighting, and missed capture moments.

### Primary MVP Use Cases

- "Give me a cinematic portrait" while pointing at a person.
- "Take a professional photo of me with this background/car/place."
- "Make this landscape look cinematic" with sky/horizon guidance.
- "Show more sky" or "make it brighter" after seeing a target preview.
- "Take my photo like this" using a reference image translated into an achievable local target.

### Functional Requirements

- Single-phone operation: all capture, live analysis, reference viewing, guidance, preview, target match, burst selection, and final result generation must happen on the same phone the user is holding.
- Custom native camera on iOS and Android with preview, capture, zoom, focus, exposure, camera switching, and burst capture.
- Runtime `DeviceCapability` profiler based on API-reported camera, sensor, stabilization, depth, HDR, RAW, and manual-control support.
- Voice and text intent input converted into a strongly typed `ShotSpec`.
- Live scene analysis for people, pose, subject bounds, horizon, exposure, lighting, motion, background clutter, and basic scene category.
- Shot planner that maps `ShotSpec + SceneState + DeviceCapability + CameraState` into a `ShotPlan`.
- AI Shot Preview V1 using deterministic crop, exposure, tone, color, depth approximation, and composition overlays.
- Three explicit preview modes: Natural, Enhanced, Creative.
- One-action-at-a-time Live AI Director with arrows, voice, optional haptics, and state-machine hysteresis.
- Target Match score composed from calibrated sub-scores, never random confidence.
- Reference image mode with reference feature extraction, "Reference vs Your Target", ghost-frame guidance, and an on-camera reference thumbnail popup that opens the full reference image when selected.
- Burst capture and best-shot ranking with best plus alternatives.
- Privacy settings, cloud disclosure, consent controls, analytics opt-in, and delete controls.

### Non-Functional Requirements

- The MVP must not require a second phone, companion device, remote camera, or another user's screen.
- Camera should remain useful when AI is unavailable.
- Live camera feed remains on-device by default.
- No identity recognition, attractiveness scoring, race scoring, body reshaping, or face reshaping in MVP.
- Guidance inference target: less than 150 ms P95 for lightweight actions.
- Camera launch target: less than 1 second where realistic.
- Lightweight perception target: 15-30 FPS on supported flagship devices.
- UI should remain camera-first, with no more than one primary instruction visible.
- If a reference image is active, show it as a compact non-blocking popup/thumbnail on the camera screen; selecting the popup opens a larger reference viewer without stopping the camera session.
- Degrade gracefully on unsupported hardware.
- Collect only structured learning events with explicit consent.

### MVP Acceptance Criteria

- A user can launch the camera, enter/speak an intent, see a target plan, receive one clear live instruction, capture a burst, and choose the best result.
- The complete shooting loop succeeds on one physical phone: intent input, camera preview, reference popup, guidance, preview, capture, best-shot selection, and final result.
- In reference mode, a selected reference image appears as a small popup on the live camera screen, and tapping it opens a full reference view with a clear return path to the camera.
- Device profiler correctly identifies available lenses, supported controls, depth, HDR, stabilization, and capture formats on the MVP device matrix.
- Natural preview never requires generative edits; Creative preview is labeled as requiring post-capture AI enhancement.
- Target Match sub-scores are derived from actual scene/camera metrics.
- A small blind study shows LensPilot-guided results preferred over native-camera control in at least 65% of comparable MVP scenarios.

## B. System Architecture

```text
Mobile Apps
  iOS Native Runtime
  Android Native Runtime
  Single-Phone User Experience
  Shared Schemas
  Local Preference Store
  On-device CV/ML Runtime

Camera Layer
  Native Camera Session
  Device Capability Profiler
  Frame Sampler
  Capture Controller
  Burst Controller
  Camera Telemetry

AI Layer
  Intent Engine
  Scene Understanding
  Shot Planner
  Guidance Policy
  Target Match Engine
  Best-Shot Ranker
  Preview Engine

Backend
  Auth
  User Preferences
  Shot Intelligence API
  Preview API
  Model Configuration
  Feature Flags
  Analytics
  Experiments
  Evaluation

Cloud AI
  LLM/VLM reasoning
  High-fidelity creative preview
  Reference-image deep analysis
  Personalization sync

Data/Security
  Consent Gateway
  Minimal structured telemetry
  Encrypted transport
  Retention policy
  Delete/export controls
```

MVP deployment should be modular but simple: one backend API with clear internal domains, not many operational microservices.

Single-phone constraint: LensPilot is not a two-phone director/camera system. The active phone owns the camera session, analyzes its own live frames, shows the reference popup, displays guidance, captures the burst, ranks the result, and presents the final image. Cloud services may assist only for opt-in reasoning, configuration, creative preview, or sync; they must not become a required live-camera dependency.

## C. AI Architecture

### Computer Vision

- Person, face box, pose, segmentation, horizon, sky, scene category, object/clutter detection, motion, exposure map, blur likelihood.
- Reason: high-frequency, privacy-sensitive, latency-critical perception belongs on-device.

### Deterministic Algorithms

- Rule-based ShotSpec normalization, camera capability gating, horizon geometry, subject box scoring, crop simulation, exposure histograms, target-match aggregation, guidance hysteresis.
- Reason: deterministic components are debuggable, testable, fast, and less likely to hallucinate.

### Classical ML / On-Device Models

- Pose, segmentation, aesthetic sub-scores, scene classification, face/eye quality without identity, depth approximation where hardware depth is unavailable.
- Reason: repeated lightweight inference at 1-30 FPS.

### Multimodal Models

- Event-triggered reference image analysis, complex style interpretation, unusual scene understanding, creative feasibility reasoning.
- Reason: useful for semantic interpretation but too expensive and privacy-sensitive for continuous raw-frame processing.

### LLM

- Natural-language intent parsing, ShotSpec completion, explanation text, plan adjustment commands.
- Reason: converts user language into structured photographic intent. It must be schema-constrained and capability-aware.

### Generative AI

- Creative preview V2, sky/background replacement, relighting, object removal, optional post-capture edits.
- Reason: valuable but not a physical camera promise. Must be labeled Creative and require consent/cloud disclosure where applicable.

## D. iOS Architecture

### Frameworks

- Swift, SwiftUI, AVFoundation, Vision, Core ML, Core Image, Metal, Photos, Speech, Core Motion, Combine/Swift Concurrency.

### Modules

- `CameraEngine`: owns `AVCaptureSession`, inputs, outputs, lens switching, zoom, focus, exposure, capture.
- `DeviceCapabilityEngine`: inspects `AVCaptureDevice`, formats, depth, stabilization, RAW, HDR, manual controls, latency.
- `VisionEngine`: receives sampled frames, runs Vision/Core ML pipelines, returns `SceneState`.
- `ShotIntelligence`: intent parser, ShotSpec normalizer, ShotPlanner, target match.
- `DirectorEngine`: action priority, state machine, hysteresis, voice/haptic dispatch.
- `PreviewEngine`: deterministic preview V1 using crop/tone/depth approximation.
- `CaptureEngine`: burst orchestration, quality scoring, final asset write.
- `PrivacyAndConsent`: permissions, cloud disclosure, analytics consent.

### Threading and Pipeline

- Main actor: SwiftUI state and lightweight UI updates.
- Camera session queue: AVFoundation configuration and capture.
- Vision queue: frame sampling, CV/ML inference, scene state publication.
- Planning queue: ShotPlan and GuidanceAction generation.
- GPU path: Core Image/Metal preview transforms and overlays.

### Performance Strategy

- Multi-rate scheduling: preview 30/60 FPS, pose 15-30 FPS, segmentation 10-20 FPS, scene classification 2-5 FPS, aesthetic scoring 1-5 FPS, LLM/VLM only on user or event trigger.
- Drop stale frames instead of queueing them.
- Thermal-aware model throttling.
- Prefer Apple Neural Engine/Core ML where available, but gate by runtime profiling.

## E. Android Architecture

### Frameworks

- Kotlin, Jetpack Compose, CameraX, Camera2 interop, Camera Extensions, MediaPipe, ML Kit, TFLite/ONNX Runtime Mobile, Android Speech APIs, SensorManager, RenderScript replacement paths via GPU/OpenGL/Vulkan where needed.

### Modules

- `camera-runtime`: CameraX preview, image analysis, image capture, video disabled for MVP.
- `camera2-controls`: optional manual exposure/focus/WB, focal lengths, sensor info, stream configs.
- `capability-profiler`: CameraCharacteristics, extensions, RAW, depth, stabilization, supported sizes/FPS.
- `vision-runtime`: MediaPipe/ML Kit/TFLite pipelines.
- `shot-intelligence`: shared schema bindings plus Android planner implementation.
- `director-ui`: Compose overlays, arrows, ghost frame, target match, mode controls.
- `capture-quality`: burst selection, blur/exposure/pose/composition ranking.
- `privacy-consent`: permissions, local/cloud boundary, analytics opt-in.

### Fragmentation Strategy

- Use CameraX for broad reliability.
- Use Camera2 only behind capability checks and feature flags.
- Maintain device-lab profiles for MVP devices, but never branch only by brand.
- Runtime capability gates decide which controls are offered.
- Disable manual-control promises when unsupported.

### Performance Strategy

- Use `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`.
- Maintain model quality tiers: high, balanced, battery saver.
- Run low-latency models on NNAPI/GPU delegates only after runtime validation.
- Monitor thermal state and reduce inference frequency before camera UX degrades.

## F. ShotSpec Schema

```typescript
type RealityMode = "natural" | "enhanced" | "creative";
type CaptureDomain = "portrait" | "landscape" | "travel" | "lifestyle" | "night" | "reference";

interface ShotSpec {
  id: string;
  version: "1.0";
  source: "text" | "voice" | "preset" | "reference_image" | "hybrid";
  originalPrompt?: string;
  domain: CaptureDomain;
  subject: {
    primary: "person" | "people" | "landscape" | "vehicle" | "object" | "unknown";
    count?: number;
    priority: "subject" | "environment" | "balanced";
    identityRecognitionAllowed: false;
  };
  style: {
    name: "natural" | "cinematic" | "professional" | "travel" | "portrait" | "night" | "sky" | "lifestyle" | "custom";
    mood?: "bright" | "dramatic" | "soft" | "luxury" | "documentary" | "moody";
    colorIntent?: "natural" | "warm_highlights" | "cool_shadows" | "warm_highlights_cool_shadows" | "high_contrast" | "low_contrast";
    skinTreatment?: "natural" | "soft_but_realistic" | "none";
  };
  composition: {
    framing: "close" | "medium" | "wide" | "environmental" | "three_quarter" | "symmetrical" | "rule_of_thirds";
    headroom?: "minimal" | "balanced" | "more_space";
    skyPriority?: "low" | "medium" | "high";
    backgroundPriority?: "clean" | "contextual" | "dramatic" | "sunset" | "architecture" | "nature";
    horizonPlacement?: "lower_third" | "center" | "upper_third" | "auto";
  };
  cameraIntent: {
    targetLens?: "ultra_wide" | "wide" | "two_x_if_available" | "telephoto_if_available" | "auto";
    perspective?: "eye_level" | "low_angle" | "high_angle" | "straight_on" | "auto";
    exposureStrategy?: "protect_highlights" | "prioritize_faces" | "balanced" | "night_stability";
    focusStrategy?: "subject_eye" | "subject_center" | "hyperfocal" | "auto";
    depthIntent?: "natural_depth" | "strong_subject_separation" | "deep_focus" | "auto";
  };
  constraints: {
    realityMode: RealityMode;
    cloudAllowed: boolean;
    generativeEditsAllowed: boolean;
    userSafetyStrictness: "standard" | "conservative";
  };
  confidence: number;
  missingInfo: string[];
}
```

## G. SceneState Schema

```typescript
interface SceneState {
  timestamp: string;
  frameId: string;
  cameraState: CameraState;
  deviceThermal?: "nominal" | "fair" | "serious" | "critical";
  scene: {
    category: "portrait" | "landscape" | "cityscape" | "beach" | "mountain" | "indoor" | "night" | "unknown";
    confidence: number;
    lighting: LightingState;
    horizon?: HorizonState;
    sky?: SkyState;
  };
  subjects: SubjectObservation[];
  background: BackgroundState;
  motion: {
    cameraShake: number;
    subjectMotion: number;
    blurRisk: number;
  };
  composition: {
    subjectPlacementScore: number;
    headroomScore?: number;
    balanceScore: number;
    leadingLinesScore?: number;
    negativeSpaceScore?: number;
  };
  safety: {
    hazards: Array<"road" | "traffic" | "stairs" | "edge" | "water" | "obstacle" | "unknown">;
    movementGuidanceAllowed: boolean;
    confidence: number;
  };
}

interface CameraState {
  lensId: string;
  focalLength35mmEquivalent?: number;
  zoomFactor: number;
  exposureBias?: number;
  iso?: number;
  shutterSpeed?: number;
  whiteBalance?: number;
  focusDistance?: number;
  orientation: "portrait" | "landscape_left" | "landscape_right";
  rollDegrees: number;
  pitchDegrees?: number;
}

interface SubjectObservation {
  id: string;
  type: "person" | "face" | "vehicle" | "animal" | "object";
  bounds: Rect;
  segmentationAvailable: boolean;
  pose?: PoseState;
  face?: FaceQualityState;
  distanceEstimateMeters?: number;
  confidence: number;
}
```

### Reference Photo UI State

```typescript
interface ReferencePhotoState {
  id: string;
  source: "photo_library" | "camera_capture" | "shared_file";
  localAssetUri: string;
  thumbnailUri: string;
  analysisStatus: "not_started" | "analyzing" | "ready" | "failed";
  extractedFeatures?: ReferencePhotoFeatures;
  display: {
    showCameraPopup: boolean;
    popupPosition: "top_left" | "top_right" | "bottom_left" | "bottom_right";
    viewerState: "collapsed_popup" | "full_reference" | "reference_vs_target";
  };
  privacy: {
    cloudAnalysisUsed: boolean;
    userConsentedToCloudAnalysis: boolean;
  };
}

interface ReferencePhotoFeatures {
  framing: string;
  apparentFocalLength?: string;
  cameraHeight?: "low" | "eye_level" | "high" | "unknown";
  subjectScale?: number;
  poseHints: string[];
  lightingDirection?: string;
  colorMood?: string;
  depthStyle?: string;
  achievableTranslationNotes: string[];
}
```

Reference UI behavior:

- When the user selects a reference photo, the camera returns to live view and shows a compact thumbnail popup above the lower control area.
- The popup must never hide the capture button, primary guidance action, Target Match, or safety warnings.
- Tapping the popup opens a full-screen or large sheet reference viewer with two modes: `Reference` and `Reference vs Your Target`.
- Closing the viewer returns to the live camera with the reference still active.
- If the app has not completed reference analysis, the popup can show progress, but the camera must remain usable.

## H. ShotPlan Schema

```typescript
interface ShotPlan {
  id: string;
  shotSpecId: string;
  achievability: {
    natural: number;
    enhanced: number;
    creative: number;
    limitingFactors: string[];
  };
  cameraControls: {
    recommendedLens: string;
    targetZoom: number;
    targetExposureBias?: number;
    targetFocusMode: "auto" | "locked" | "manual_if_available";
    targetWhiteBalance?: "auto" | "daylight" | "cloudy" | "warm" | "cool" | "manual_if_available";
    stabilizationMode?: string;
    captureFormat: "heif" | "jpeg" | "raw_plus_heif";
  };
  photographerChanges: GuidanceAction[];
  subjectDirections: GuidanceAction[];
  compositionTarget: {
    subjectBounds: Rect;
    horizonY?: number;
    ghostFrame?: GhostFrame;
    crop: Rect;
  };
  processingIntent: {
    realityMode: RealityMode;
    toneCurve: "natural" | "cinematic_soft_contrast" | "high_dynamic_range" | "night_noise_control";
    colorTreatment: string;
    depthEffect: "none" | "natural" | "portrait_if_available" | "post_depth_blur";
  };
  previewConfiguration: {
    label: "capture_realistic" | "enhanced_realistic" | "ai_enhancement_required";
    operations: string[];
  };
  capturePolicy: {
    mode: "single" | "burst";
    burstFrameCount?: number;
    trigger: "manual" | "ready_assist" | "auto_when_stable";
    readinessThreshold: number;
  };
}
```

## I. GuidanceAction Schema

```typescript
interface GuidanceAction {
  id: string;
  actor: "photographer" | "subject" | "camera" | "processing";
  action:
    | "move_left"
    | "move_right"
    | "move_forward"
    | "move_backward"
    | "raise_camera"
    | "lower_camera"
    | "rotate_clockwise"
    | "rotate_counterclockwise"
    | "switch_lens"
    | "adjust_zoom"
    | "adjust_exposure"
    | "turn_shoulders"
    | "turn_face"
    | "hold_steady"
    | "capture_now"
    | "if_safe_move";
  magnitude?: number;
  unit?: "meter" | "centimeter" | "degree" | "zoom_factor" | "ev";
  direction?: "left" | "right" | "up" | "down" | "toward_light" | "away_from_background";
  confidence: number;
  reason:
    | "improve_subject_background_separation"
    | "level_horizon"
    | "protect_highlights"
    | "improve_face_light"
    | "reduce_clutter"
    | "match_reference"
    | "improve_pose"
    | "increase_sky"
    | "reduce_motion_blur"
    | "ready_to_capture";
  expectedGain: number;
  safetyQualifier?: "if_safe" | "do_not_move";
  priority: number;
  ttlMs: number;
  suppressOppositeUntilMs: number;
}
```

## J. Development Roadmap

### Sprint 0: Architecture and Contracts

- Finalize schemas, privacy policy, capture domains, target-match score definitions, device matrix, benchmark protocol.
- Deliver schema package, sample fixtures, and product success metrics.

### Sprint 1: Native Camera Foundation

- iOS and Android preview, permissions, capture, camera switching, zoom, tap focus/exposure, telemetry.
- Device capability profiler on both platforms.

### Sprint 2: Live Vision Debug

- Person/face box without identity, pose, horizon, exposure histogram, motion, background clutter heuristics.
- Debug overlays and telemetry capture.

### Sprint 3: Intent to ShotSpec

- Text input, preset styles, deterministic ShotSpec normalization, schema validation, fallback presets.

### Sprint 4: Shot Planner V1

- SceneState + ShotSpec + DeviceCapability to ShotPlan.
- Lens, exposure, framing, sky, background, and portrait rules.

### Sprint 5: Live Director V1

- One-action guidance, arrows, target areas, haptics, voice, hysteresis, safety qualifiers.

### Sprint 6: Preview V1

- Capture-realistic preview with crop/framing/exposure/tone/depth approximation.
- Natural/Enhanced/Creative labels.

### Sprint 7: Target Match and Readiness

- Sub-scores, overall target match, ready state, calibration logging.

### Sprint 8: Reference Mode

- Reference feature extraction, achievable translation, ghost frame.

### Sprint 9: Burst and Best Shot

- Burst capture, blur/exposure/composition/pose ranking, best plus two alternatives.

### Sprint 10: Pilot Benchmark

- Blind A/B testing workflow, analytics consent, internal dataset, regression suite.

## K. Repository Structure

```text
lenspilot/
├── ios/
│   ├── LensPilotApp/
│   ├── CameraEngine/
│   ├── VisionEngine/
│   ├── ShotIntelligence/
│   ├── DirectorEngine/
│   └── Tests/
├── android/
│   ├── app/
│   ├── camera-runtime/
│   ├── vision-runtime/
│   ├── shot-intelligence/
│   ├── director-ui/
│   └── tests/
├── backend/
│   ├── api/
│   ├── auth/
│   ├── shot-intelligence/
│   ├── preview/
│   ├── personalization/
│   ├── analytics/
│   └── experiments/
├── ai/
│   ├── models/
│   ├── pipelines/
│   ├── evaluation/
│   ├── prompts/
│   └── notebooks/
├── shared/
│   ├── typescript/
│   ├── kotlin/
│   └── swift/
├── schemas/
│   ├── shotspec.schema.json
│   ├── scenestate.schema.json
│   ├── shotplan.schema.json
│   └── guidanceaction.schema.json
├── experiments/
├── benchmarks/
├── infrastructure/
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── privacy/
│   └── security/
└── tests/
    ├── fixtures/
    ├── contract/
    └── evaluation/
```

## L. Top 15 Technical Risks

1. Real-time guidance latency exceeds user tolerance on older phones.
2. Camera pipeline instability from native API differences and device fragmentation.
3. Preview overpromises achievable physical results.
4. Target Match scores are uncalibrated and lose user trust.
5. Background/clutter recommendations cause oscillating or annoying guidance.
6. Battery drain and thermal throttling degrade the camera experience.
7. On-device models underperform in low light, backlight, or crowded scenes.
8. Manual controls vary widely across Android devices.
9. Reference mode creates unrealistic expectations.
10. Safety guidance cannot reliably detect environmental hazards.
11. Voice UX is noisy, delayed, or awkward in public use.
12. Best-shot ranker optimizes technical quality while missing user intent.
13. Privacy claims get ahead of actual cloud behavior.
14. Benchmark dataset fails to represent real users and conditions.
15. Product becomes a feature-heavy camera instead of an intent-to-direction loop.

## M. MVP Device Matrix

### iPhone

- Primary: iPhone 17 Pro, iPhone 17 Pro Max, iPhone 16 Pro, iPhone 16 Pro Max.
- Secondary: iPhone 15 Pro, iPhone 15 Pro Max, iPhone 17, iPhone 16.
- Rationale: recent Pro devices provide strong camera systems, LiDAR on Pro models, advanced ISP/Neural Engine capacity, and enough user distribution for early premium testing. Apple lists iPhone 17 Pro as introduced in 2025 with A19 Pro, 48MP Pro Fusion cameras, ProRAW, Night mode, depth/portrait features, and LiDAR.

### Google Pixel

- Primary: Pixel 11 Pro, Pixel 11 Pro XL, Pixel 10 Pro, Pixel 10 Pro XL.
- Secondary: Pixel 10, Pixel 9 Pro, Pixel 9 Pro XL.
- Rationale: Pixel devices are useful for Android camera AI testing and Camera2/CameraX behavior. Google lists Pixel 10 Pro XL with LTPO OLED, high brightness, 16 GB RAM, and current Pixel hardware support; current reports say Pixel 11/11 Pro/11 Pro XL launched on August 12, 2026, so they should be added to the forward-looking lab as soon as physical test units are available.

### Samsung Galaxy

- Primary: Galaxy S26 Ultra, Galaxy S26+, Galaxy S26, Galaxy S25 Ultra.
- Secondary: Galaxy S25/S25+, Galaxy Z Fold/Flip only after slab-phone MVP is stable.
- Rationale: Samsung flagships represent the largest Android fragmentation target and have broad camera stacks. Samsung's current Galaxy S26 page lists S26, S26+, and S26 Ultra, including a 6.9-inch Ultra and 6.3/6.7-inch base/plus variants.

### Explicit MVP Exclusions

- Budget Android phones for initial development.
- Foldables as primary targets.
- Devices without stable CameraX/ImageAnalysis performance.
- Any device where camera preview quality regresses due to AI overlays.

## N. Prototype Plan

### Smallest Credible Prototype

Build one native platform first, preferably iOS Pro-class devices, with one controlled domain: outdoor portrait with background cleanup and sky/composition guidance. The prototype must run end-to-end on one phone only; no second phone, remote display, paired camera, or companion capture device is allowed.

Prototype flow:

1. Launch custom camera.
2. User selects or types "cinematic portrait".
3. App detects person, horizon/sky, exposure, subject placement, and clutter.
4. App generates ShotSpec and ShotPlan locally with deterministic rules.
5. App displays one instruction at a time, such as "Move slightly left" or "Lower camera."
6. Target Match updates from measurable geometric/exposure changes.
7. App captures a short burst when readiness is high.
8. Best-shot selection ranks burst frames.
9. Test compares native camera baseline against LensPilot-guided result with blind raters.

Single-phone UX note: when the user is photographing themselves, MVP guidance should use the front camera, voice prompts, haptics, timer/auto-capture, and on-screen overlays on that same device rather than assuming another person or second device is present.

### First Implementation Milestone

Milestone 1: iOS Camera + Capability + Scene Debug Prototype.

Deliverables:

- SwiftUI camera preview using AVFoundation.
- Camera permission flow.
- Capture, camera switching, zoom, tap focus/exposure.
- DeviceCapability JSON export.
- Live frame sampler.
- Vision person detection and horizon/exposure debug metrics.
- Debug overlay for subject bounds, horizon, exposure warning, and frame latency.
- Fixture-based tests for DeviceCapability serialization and ShotSpec schema validation.

Success criteria:

- Runs reliably on at least two target iPhones.
- Camera remains smooth with debug vision enabled.
- Exports enough telemetry to start building Shot Planner V1.
- No cloud dependency for live camera analysis.

## Source Notes

- Apple Support iPhone 17 Pro technical specifications: https://support.apple.com/en-us/125090
- Apple iPhone comparison page: https://www.apple.com/iphone/compare/
- Google Pixel hardware technical specifications: https://support.google.com/pixelphone/answer/7158570
- Samsung Galaxy S26 series page: https://www.samsung.com/us/smartphones/galaxy-s26/
- Current Pixel 11 launch reporting was used only as a forward-looking device-matrix signal because official support pages may lag launch-day availability.
