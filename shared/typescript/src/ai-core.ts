import type { DeviceCapability, ShotSpec } from "./contracts";
import type { GuidanceAction, NormalizedRectangle, ShotPlan } from "./planning";
import type { SceneState, SubjectObservation } from "./scene-state";

export type CaptureDomain = ShotSpec["domain"];
export type GuidanceReason = GuidanceAction["reason"];

export interface AiPipelineResult {
  shotSpec: ShotSpec;
  shotPlan: ShotPlan;
  targetPreview: TargetPreview;
  guidanceAction?: GuidanceAction;
  targetMatch: TargetMatchScore;
  previewSafety: PreviewSafety;
}

export interface TargetMatchCalibration {
  horizonRollFullPenaltyDegrees: number;
  eyeLevelPitchFullPenaltyDegrees: number;
  highlightClippingPenalty: number;
  shadowClippingPenalty: number;
  backgroundClutterPenalty: number;
  poleBehindHeadPenalty: number;
  dynamicRangeLightingPenalty: number;
  motionBlurPenalty: number;
  missingHorizonScore: number;
  missingFaceLightQuality: number;
  missingPoseScore: number;
  nonPortraitCameraAngleScore: number;
}

export interface GuidanceCalibration {
  globalReasonBoosts: Partial<Record<GuidanceReason, number>>;
  domainReasonBoosts: Partial<Record<CaptureDomain, Partial<Record<GuidanceReason, number>>>>;
}

export interface GuidanceStabilizerConfiguration {
  minimumHoldMs: number;
  completedActionMemoryMs: number;
}

export interface TargetMatchCalibrationManifest {
  version: string;
  collectionPlan: {
    singlePhoneOnly: boolean;
    realCaptureTargetCount: number;
    minimumBlindReviewers: number;
    requiredDomains: string[];
  };
  targetMatchCalibration: TargetMatchCalibration;
  samples: Array<{
    id: string;
    sampleKind: string;
    domain?: string;
    blindPreference?: {
      reviewCount: number;
      preferredGuidanceReason: string;
      rankedWeaknesses: string[];
      notes: string;
    };
  }>;
}

export const defaultTargetMatchCalibration: TargetMatchCalibration = {
  horizonRollFullPenaltyDegrees: 12,
  eyeLevelPitchFullPenaltyDegrees: 35,
  highlightClippingPenalty: 0.8,
  shadowClippingPenalty: 0.6,
  backgroundClutterPenalty: 0.55,
  poleBehindHeadPenalty: 0.25,
  dynamicRangeLightingPenalty: 0.2,
  motionBlurPenalty: 1,
  missingHorizonScore: 0.72,
  missingFaceLightQuality: 0.65,
  missingPoseScore: 0.72,
  nonPortraitCameraAngleScore: 0.75,
};

export const defaultGuidanceCalibration: GuidanceCalibration = {
  globalReasonBoosts: {},
  domainReasonBoosts: {},
};

export function targetMatchCalibrationFromManifest(manifest: TargetMatchCalibrationManifest): TargetMatchCalibration {
  if (!manifest.collectionPlan.singlePhoneOnly) {
    throw new Error("Target Match calibration must stay single-phone only.");
  }

  if (!manifest.collectionPlan.requiredDomains.length) {
    throw new Error("Target Match calibration requires at least one domain.");
  }

  if (!manifest.samples.length) {
    throw new Error("Target Match calibration requires at least one sample.");
  }

  validateTargetMatchCalibration(manifest.targetMatchCalibration);
  return { ...manifest.targetMatchCalibration };
}

export function guidanceCalibrationFromManifest(manifest: TargetMatchCalibrationManifest): GuidanceCalibration {
  const globalReasonBoosts: Partial<Record<GuidanceReason, number>> = {};
  const domainReasonBoosts: Partial<Record<CaptureDomain, Partial<Record<GuidanceReason, number>>>> = {};
  const minimumReviewers = Math.max(1, manifest.collectionPlan.minimumBlindReviewers);

  for (const sample of manifest.samples) {
    const preference = sample.blindPreference;
    if (sample.sampleKind !== "iphone_capture" || !preference || preference.reviewCount < minimumReviewers) {
      continue;
    }

    const reviewScale = Math.min(3, preference.reviewCount / minimumReviewers);
    addGuidanceBoost(preference.preferredGuidanceReason, sample.domain, 0.02 * reviewScale, globalReasonBoosts, domainReasonBoosts);

    preference.rankedWeaknesses.slice(0, 3).forEach((weakness, index) => {
      const reason = preferredReasonForWeakness(weakness);
      if (!reason) return;
      addGuidanceBoost(reason, sample.domain, 0.006 * reviewScale / (index + 1), globalReasonBoosts, domainReasonBoosts);
    });
  }

  return {
    globalReasonBoosts: clampBoosts(globalReasonBoosts),
    domainReasonBoosts: Object.fromEntries(
      Object.entries(domainReasonBoosts).map(([domain, boosts]) => [domain, clampBoosts(boosts ?? {})])
    ) as GuidanceCalibration["domainReasonBoosts"],
  };
}

export function aiCoreFromCalibrationManifest(manifest: TargetMatchCalibrationManifest): LensPilotAiCore {
  return new LensPilotAiCore(
    targetMatchCalibrationFromManifest(manifest),
    guidanceCalibrationFromManifest(manifest)
  );
}

export interface TargetMatchScore {
  composition: number;
  subjectPosition: number;
  cameraAngle: number;
  lighting: number;
  background: number;
  horizon: number;
  pose: number;
  sharpnessProbability: number;
  exposure: number;
  intentMatch: number;
  overall: number;
}

export interface PreviewSafety {
  label: "capture_realistic" | "enhanced_realistic" | "ai_enhancement_required";
  userFacingDisclosure?: string;
  allowedOperations: string[];
}

export interface TargetPreview {
  id: string;
  shotSpecId: string;
  shotPlanId: string;
  title: string;
  subtitle: string;
  label: ShotPlan["previewConfiguration"]["label"];
  estimatedAchievability: number;
  subjectBounds: NormalizedRectangle;
  horizonY?: number;
  crop: NormalizedRectangle;
  lens: string;
  targetZoom: number;
  exposureBias?: number;
  toneCurve: ShotPlan["processingIntent"]["toneCurve"];
  colorTreatment: string;
  depthEffect: ShotPlan["processingIntent"]["depthEffect"];
  operations: string[];
  targetMatchAtPreview: number;
  disclosure?: string;
  requiresGenerativeEnhancement: boolean;
  privacy: {
    singlePhoneOnly: true;
    usesRawCameraFrameUpload: false;
    usesPrivatePhotoUpload: false;
  };
}

export interface BestShotCandidate {
  id: string;
  sharpness: number;
  exposure: number;
  faceQuality?: number;
  poseScore?: number;
  composition: number;
  background: number;
  intentMatch: number;
}

export interface RankedShot {
  id: string;
  score: number;
  label: "best" | "alternative";
  reasons: string[];
}

export class IntentEngine {
  parseIntent(prompt: string): ShotSpec {
    const normalized = prompt.toLowerCase();
    const isPortrait = /\b(portrait|me|person|people|selfie)\b/.test(normalized);
    const isLandscape = /\b(landscape|sky|sunset|mountain|beach|cityscape|lake)\b/.test(normalized);
    const isNight = /\b(night|low light|dark)\b/.test(normalized);
    const cinematic = /\b(cinematic|dramatic|movie|luxury)\b/.test(normalized);
    const moreSky = /\b(sky|sunset|cloud)\b/.test(normalized);
    const cleanBackground = /\b(clean|background|clutter)\b/.test(normalized);

    return {
      id: `shot_${cryptoId()}`,
      version: "1.0",
      source: "text",
      originalPrompt: prompt,
      domain: isNight ? "night" : isPortrait ? "portrait" : isLandscape ? "landscape" : "lifestyle",
      subject: {
        primary: isPortrait ? "person" : isLandscape ? "landscape" : "unknown",
        count: isPortrait ? 1 : undefined,
        priority: isLandscape ? "environment" : "subject",
        identityRecognitionAllowed: false,
      },
      style: {
        name: cinematic ? "cinematic" : "natural",
        mood: cinematic ? "dramatic" : "bright",
        colorIntent: cinematic ? "warm_highlights_cool_shadows" : "natural",
        skinTreatment: isPortrait ? "natural" : "none",
      },
      composition: {
        framing: isPortrait ? "environmental" : "wide",
        headroom: isPortrait ? "balanced" : undefined,
        skyPriority: moreSky ? "high" : undefined,
        backgroundPriority: cleanBackground ? "clean" : moreSky ? "sunset" : "contextual",
        horizonPlacement: isLandscape ? "lower_third" : "auto",
      },
      cameraIntent: {
        targetLens: isPortrait ? "two_x_if_available" : "wide",
        perspective: isPortrait ? "eye_level" : "auto",
        exposureStrategy: moreSky ? "protect_highlights" : isPortrait ? "prioritize_faces" : "balanced",
        focusStrategy: isPortrait ? "subject_eye" : "auto",
        depthIntent: isPortrait ? "strong_subject_separation" : "deep_focus",
      },
      constraints: {
        realityMode: "natural",
        cloudAllowed: false,
        generativeEditsAllowed: false,
        userSafetyStrictness: "conservative",
        singlePhoneOnly: true,
      },
      confidence: 0.72,
      missingInfo: [],
    };
  }
}

export class ShotPlanner {
  plan(shotSpec: ShotSpec, sceneState: SceneState, deviceCapability: DeviceCapability): ShotPlan {
    const primarySubject = sceneState.subjects[0];
    const recommendedLens = recommendLens(shotSpec, deviceCapability);
    const natural = achievability(shotSpec, sceneState, deviceCapability);
    const movementAllowed = sceneState.safety.movementGuidanceAllowed;
    const cleanDirection = sceneState.background.cleanerDirection;
    const photographerChanges: GuidanceAction[] = [];

    if (sceneState.scene.horizon && Math.abs(sceneState.scene.horizon.rollDegrees) > 2.5) {
      photographerChanges.push(makeAction({
        id: "level_horizon",
        actor: "photographer",
        action: sceneState.scene.horizon.rollDegrees > 0 ? "rotate_counterclockwise" : "rotate_clockwise",
        magnitude: Math.abs(sceneState.scene.horizon.rollDegrees),
        unit: "degree",
        confidence: sceneState.scene.horizon.confidence,
        reason: "level_horizon",
        expectedGain: 0.14,
        safetyQualifier: "if_safe",
        priority: 95,
      }));
    }

    if (sceneState.background.clutterScore > 0.55 && movementAllowed && cleanDirection && cleanDirection !== "unknown") {
      photographerChanges.push(makeAction({
        id: "reduce_background_clutter",
        actor: "photographer",
        action: cleanDirection === "left" ? "move_left" : cleanDirection === "right" ? "move_right" : cleanDirection === "forward" ? "move_forward" : "if_safe_move",
        magnitude: 0.4,
        unit: "meter",
        direction: cleanDirection === "left" || cleanDirection === "right" ? cleanDirection : undefined,
        confidence: 0.76,
        reason: "reduce_clutter",
        expectedGain: 0.16,
        safetyQualifier: "if_safe",
        priority: 88,
      }));
    }

    if (sceneState.motion.blurRisk > 0.55) {
      photographerChanges.push(makeAction({
        id: "hold_steady",
        actor: "photographer",
        action: "hold_steady",
        confidence: 0.82,
        reason: "reduce_motion_blur",
        expectedGain: 0.18,
        priority: 90,
      }));
    }

    if (sceneState.scene.lighting.highlightClipping > 0.22) {
      photographerChanges.push(makeAction({
        id: "protect_highlights",
        actor: "camera",
        action: "adjust_exposure",
        magnitude: -0.3,
        unit: "ev",
        confidence: 0.8,
        reason: "protect_highlights",
        expectedGain: 0.12,
        priority: 82,
      }));
    }

    const subjectDirections = subjectGuidance(shotSpec, primarySubject, sceneState);

    return {
      id: `plan_${cryptoId()}`,
      shotSpecId: shotSpec.id,
      achievability: {
        natural,
        enhanced: clamp01(natural + 0.08),
        creative: clamp01(natural + 0.15),
        limitingFactors: limitingFactors(shotSpec, sceneState, deviceCapability),
      },
      cameraControls: {
        recommendedLens,
        targetZoom: recommendedLens === "telephoto" ? 2 : 1,
        targetExposureBias: sceneState.scene.lighting.highlightClipping > 0.22 ? -0.3 : 0,
        targetFocusMode: deviceCapability.manualFocusSupported ? "locked" : "auto",
        targetWhiteBalance: "auto",
        stabilizationMode: deviceCapability.stabilizationModes.includes("cinematic") ? "cinematic" : deviceCapability.stabilizationModes[0],
        captureFormat: deviceCapability.rawSupported ? "raw_plus_heif" : "heif",
      },
      photographerChanges,
      subjectDirections,
      compositionTarget: {
        subjectBounds: targetSubjectBounds(shotSpec, primarySubject),
        horizonY: shotSpec.domain === "landscape" ? 0.38 : undefined,
        crop: { x: 0, y: 0, width: 1, height: 1 },
      },
      processingIntent: {
        realityMode: shotSpec.constraints.realityMode,
        toneCurve: shotSpec.style.name === "cinematic" ? "cinematic_soft_contrast" : "natural",
        colorTreatment: shotSpec.style.colorIntent ?? "natural",
        depthEffect: shotSpec.domain === "portrait" ? "portrait_if_available" : "natural",
      },
      previewConfiguration: previewConfiguration(shotSpec),
      capturePolicy: {
        mode: "burst",
        burstFrameCount: 5,
        trigger: "ready_assist",
        readinessThreshold: 0.92,
      },
    };
  }
}

export class GuidancePolicy {
  constructor(private readonly calibration: GuidanceCalibration = defaultGuidanceCalibration) {}

  selectNextAction(shotPlan: ShotPlan, domain?: CaptureDomain): GuidanceAction | undefined {
    const candidates = [...shotPlan.photographerChanges, ...shotPlan.subjectDirections]
      .filter((action) => action.confidence >= 0.55 && action.expectedGain >= 0.04)
      .sort((a, b) => actionScore(b, this.calibration, domain) - actionScore(a, this.calibration, domain));

    return candidates[0];
  }
}

export class GuidanceStabilizer {
  private activeAction?: GuidanceAction;
  private activeUntilMs = 0;
  private minimumHoldUntilMs = 0;
  private readonly suppressedActionUntilMs: Partial<Record<GuidanceAction["action"], number>> = {};
  private readonly completedActionUntilMs: Record<string, number> = {};

  constructor(
    private readonly configuration: GuidanceStabilizerConfiguration = {
      minimumHoldMs: 1_200,
      completedActionMemoryMs: 2_500,
    }
  ) {}

  reset(): void {
    this.activeAction = undefined;
    this.activeUntilMs = 0;
    this.minimumHoldUntilMs = 0;
    clearRecord(this.suppressedActionUntilMs);
    clearRecord(this.completedActionUntilMs);
  }

  stabilize(proposedAction: GuidanceAction | undefined, nowMs = Date.now()): GuidanceAction | undefined {
    this.expireMemory(nowMs);

    if (!proposedAction) {
      this.clearActive();
      return undefined;
    }

    if (isReadyAction(proposedAction) && this.activeAction && !isReadyAction(this.activeAction)) {
      this.rememberCompleted(this.activeAction, nowMs);
      this.begin(proposedAction, nowMs);
      return proposedAction;
    }

    if (this.isCompleted(proposedAction, nowMs)) {
      if (this.activeAction && isReadyAction(this.activeAction) && this.isActive(nowMs)) {
        return this.activeAction;
      }
      return undefined;
    }

    if (this.isSuppressed(proposedAction.action, nowMs)) {
      if (this.activeAction && this.isActive(nowMs)) {
        return this.activeAction;
      }
      return undefined;
    }

    if (this.activeAction && this.isActive(nowMs) && sameInstruction(this.activeAction, proposedAction)) {
      this.begin(proposedAction, nowMs);
      return proposedAction;
    }

    if (
      this.activeAction &&
      this.isActive(nowMs) &&
      this.minimumHoldUntilMs > nowMs &&
      !canInterrupt(proposedAction, this.activeAction)
    ) {
      return this.activeAction;
    }

    this.begin(proposedAction, nowMs);
    return proposedAction;
  }

  private begin(action: GuidanceAction, nowMs: number): void {
    this.activeAction = action;
    this.activeUntilMs = nowMs + Math.max(0, action.ttlMs);
    this.minimumHoldUntilMs = nowMs + Math.min(Math.max(0, this.configuration.minimumHoldMs), Math.max(0, action.ttlMs));

    const oppositeAction = oppositeGuidanceAction(action.action);
    if (oppositeAction) {
      this.suppressedActionUntilMs[oppositeAction] = nowMs + Math.max(0, action.suppressOppositeUntilMs);
    }
  }

  private rememberCompleted(action: GuidanceAction, nowMs: number): void {
    if (isReadyAction(action)) return;
    this.completedActionUntilMs[completedActionKey(action)] = nowMs + Math.max(0, this.configuration.completedActionMemoryMs);
  }

  private expireMemory(nowMs: number): void {
    expireRecord(this.suppressedActionUntilMs, nowMs);
    expireRecord(this.completedActionUntilMs, nowMs);

    if (!this.isActive(nowMs)) {
      this.clearActive();
    }
  }

  private clearActive(): void {
    this.activeAction = undefined;
    this.activeUntilMs = 0;
    this.minimumHoldUntilMs = 0;
  }

  private isActive(nowMs: number): boolean {
    return this.activeUntilMs > nowMs;
  }

  private isSuppressed(action: GuidanceAction["action"], nowMs: number): boolean {
    return (this.suppressedActionUntilMs[action] ?? 0) > nowMs;
  }

  private isCompleted(action: GuidanceAction, nowMs: number): boolean {
    return (this.completedActionUntilMs[completedActionKey(action)] ?? 0) > nowMs;
  }
}

export class TargetMatchEngine {
  constructor(private readonly calibration: TargetMatchCalibration = defaultTargetMatchCalibration) {}

  score(shotSpec: ShotSpec, shotPlan: ShotPlan, sceneState: SceneState): TargetMatchScore {
    const subject = sceneState.subjects[0];
    const target = shotPlan.compositionTarget.subjectBounds;
    const subjectPosition = subject ? rectSimilarity(subject.bounds, target) : 0.25;
    const horizon = sceneState.scene.horizon ? clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / Math.max(this.calibration.horizonRollFullPenaltyDegrees, 0.001)) : this.calibration.missingHorizonScore;
    const exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * this.calibration.highlightClippingPenalty - sceneState.scene.lighting.shadowClipping * this.calibration.shadowClippingPenalty);
    const background = clamp01(1 - sceneState.background.clutterScore * this.calibration.backgroundClutterPenalty - sceneState.background.poleBehindHeadRisk * this.calibration.poleBehindHeadPenalty);
    const lighting = clamp01((sceneState.scene.lighting.faceLightQuality ?? this.calibration.missingFaceLightQuality) - sceneState.scene.lighting.dynamicRangeRisk * this.calibration.dynamicRangeLightingPenalty);
    const pose = clamp01(subject?.face?.eyeOpenProbability ?? this.calibration.missingPoseScore);
    const sharpnessProbability = clamp01(1 - sceneState.motion.blurRisk * this.calibration.motionBlurPenalty);
    const composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore]);
    const cameraAngle = shotSpec.cameraIntent.perspective === "eye_level" ? clamp01(1 - Math.abs(sceneState.cameraState.pitchDegrees ?? 0) / Math.max(this.calibration.eyeLevelPitchFullPenaltyDegrees, 0.001)) : this.calibration.nonPortraitCameraAngleScore;
    const intentMatch = average([composition, lighting, background, exposure]);

    const scores = {
      composition,
      subjectPosition,
      cameraAngle,
      lighting,
      background,
      horizon,
      pose,
      sharpnessProbability,
      exposure,
      intentMatch,
    };

    return { ...scores, overall: average(Object.values(scores)) };
  }
}

export class PreviewSafetyEngine {
  evaluate(shotSpec: ShotSpec, shotPlan: ShotPlan): PreviewSafety {
    if (shotSpec.constraints.realityMode === "creative" || shotSpec.constraints.generativeEditsAllowed) {
      return {
        label: "ai_enhancement_required",
        userFacingDisclosure: "AI enhancement required after capture.",
        allowedOperations: ["generative_relight", "object_removal", "background_modification"],
      };
    }

    if (shotSpec.constraints.realityMode === "enhanced") {
      return {
        label: "enhanced_realistic",
        allowedOperations: ["crop", "tone", "color", "hdr", "depth_approximation", ...shotPlan.previewConfiguration.operations],
      };
    }

    return {
      label: "capture_realistic",
      allowedOperations: ["crop", "exposure", "white_balance", "focus", "lens", "tone", "composition_overlay"],
    };
  }
}

export class TargetPreviewEngine {
  makePreview(
    shotSpec: ShotSpec,
    shotPlan: ShotPlan,
    targetMatch: TargetMatchScore,
    previewSafety: PreviewSafety
  ): TargetPreview {
    return {
      id: `preview_${shotPlan.id}`,
      shotSpecId: shotSpec.id,
      shotPlanId: shotPlan.id,
      title: `${displayTitle(shotSpec.style.name)} ${displayTitle(shotSpec.domain)}`,
      subtitle: [
        `${displayTitle(shotPlan.cameraControls.recommendedLens)} ${formatZoom(shotPlan.cameraControls.targetZoom)}`,
        displayTitle(shotPlan.processingIntent.toneCurve),
        displayTitle(shotPlan.processingIntent.depthEffect),
      ].join(" | "),
      label: previewSafety.label,
      estimatedAchievability: achievabilityForPreviewLabel(previewSafety.label, shotPlan),
      subjectBounds: shotPlan.compositionTarget.subjectBounds,
      horizonY: shotPlan.compositionTarget.horizonY,
      crop: shotPlan.compositionTarget.crop,
      lens: shotPlan.cameraControls.recommendedLens,
      targetZoom: shotPlan.cameraControls.targetZoom,
      exposureBias: shotPlan.cameraControls.targetExposureBias,
      toneCurve: shotPlan.processingIntent.toneCurve,
      colorTreatment: shotPlan.processingIntent.colorTreatment,
      depthEffect: shotPlan.processingIntent.depthEffect,
      operations: uniqueNonEmpty([...previewSafety.allowedOperations, ...shotPlan.previewConfiguration.operations]),
      targetMatchAtPreview: clamp01(targetMatch.overall),
      disclosure: previewSafety.userFacingDisclosure,
      requiresGenerativeEnhancement: previewSafety.label === "ai_enhancement_required",
      privacy: {
        singlePhoneOnly: true,
        usesRawCameraFrameUpload: false,
        usesPrivatePhotoUpload: false,
      },
    };
  }
}

export class BestShotRanker {
  rank(candidates: BestShotCandidate[]): RankedShot[] {
    return candidates
      .map((candidate) => {
        const score = average([
          candidate.sharpness,
          candidate.exposure,
          candidate.faceQuality ?? 0.7,
          candidate.poseScore ?? 0.7,
          candidate.composition,
          candidate.background,
          candidate.intentMatch,
        ]);

        return {
          id: candidate.id,
          score,
          label: "alternative" as const,
          reasons: shotReasons(candidate),
        };
      })
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
      .map((shot, index) => ({ ...shot, label: index === 0 ? "best" : "alternative" }));
  }
}

export class LensPilotAiCore {
  private readonly intentEngine = new IntentEngine();
  private readonly shotPlanner = new ShotPlanner();
  private readonly previewSafetyEngine = new PreviewSafetyEngine();
  private readonly targetPreviewEngine = new TargetPreviewEngine();
  private readonly guidancePolicy: GuidancePolicy;
  private readonly targetMatchEngine: TargetMatchEngine;

  constructor(
    targetMatchCalibration: TargetMatchCalibration = defaultTargetMatchCalibration,
    guidanceCalibration: GuidanceCalibration = defaultGuidanceCalibration
  ) {
    this.guidancePolicy = new GuidancePolicy(guidanceCalibration);
    this.targetMatchEngine = new TargetMatchEngine(targetMatchCalibration);
  }

  run(prompt: string, sceneState: SceneState, deviceCapability: DeviceCapability): AiPipelineResult {
    const shotSpec = this.intentEngine.parseIntent(prompt);
    const shotPlan = this.shotPlanner.plan(shotSpec, sceneState, deviceCapability);
    const guidanceAction = this.guidancePolicy.selectNextAction(shotPlan, shotSpec.domain);
    const targetMatch = this.targetMatchEngine.score(shotSpec, shotPlan, sceneState);
    const previewSafety = this.previewSafetyEngine.evaluate(shotSpec, shotPlan);
    const targetPreview = this.targetPreviewEngine.makePreview(shotSpec, shotPlan, targetMatch, previewSafety);

    return { shotSpec, shotPlan, targetPreview, guidanceAction, targetMatch, previewSafety };
  }
}

function makeAction(input: Omit<GuidanceAction, "ttlMs" | "suppressOppositeUntilMs"> & Partial<Pick<GuidanceAction, "ttlMs" | "suppressOppositeUntilMs">>): GuidanceAction {
  return {
    ttlMs: 3500,
    suppressOppositeUntilMs: 5000,
    ...input,
  };
}

function recommendLens(shotSpec: ShotSpec, deviceCapability: DeviceCapability): string {
  if (
    shotSpec.cameraIntent.targetLens === "two_x_if_available" &&
    deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto" || (camera.maxZoom ?? 1) >= 2)
  ) {
    return "telephoto";
  }

  if (
    shotSpec.cameraIntent.targetLens === "ultra_wide" &&
    deviceCapability.physicalCameras.some((camera) => camera.lensType === "ultra_wide")
  ) {
    return "ultra_wide";
  }

  return "wide";
}

function achievability(shotSpec: ShotSpec, sceneState: SceneState, deviceCapability: DeviceCapability): number {
  let score = 0.72;
  score += sceneState.safety.movementGuidanceAllowed ? 0.05 : -0.05;
  score += sceneState.scene.confidence * 0.08;
  score += deviceCapability.depthSupported && shotSpec.domain === "portrait" ? 0.06 : 0;
  score -= sceneState.scene.lighting.dynamicRangeRisk * 0.08;
  score -= sceneState.motion.blurRisk * 0.08;
  return clamp01(score);
}

function limitingFactors(shotSpec: ShotSpec, sceneState: SceneState, deviceCapability: DeviceCapability): string[] {
  const factors: string[] = [];
  if (!sceneState.safety.movementGuidanceAllowed) factors.push("movement_guidance_limited_by_safety");
  if (sceneState.scene.lighting.dynamicRangeRisk > 0.65) factors.push("high_dynamic_range_scene");
  if (sceneState.motion.blurRisk > 0.55) factors.push("motion_blur_risk");
  if (shotSpec.domain === "portrait" && !deviceCapability.depthSupported) factors.push("hardware_depth_unavailable");
  if (shotSpec.cameraIntent.targetLens === "two_x_if_available" && !deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto" || (camera.maxZoom ?? 1) >= 2)) {
    factors.push("true_telephoto_unavailable");
  }
  return factors;
}

function subjectGuidance(shotSpec: ShotSpec, subject: SubjectObservation | undefined, sceneState: SceneState): GuidanceAction[] {
  if (shotSpec.domain !== "portrait" || !subject) return [];

  const actions: GuidanceAction[] = [];
  if ((sceneState.scene.lighting.faceLightQuality ?? 0.7) < 0.55) {
    actions.push(makeAction({
      id: "turn_toward_light",
      actor: "subject",
      action: "turn_face",
      magnitude: 10,
      unit: "degree",
      direction: "toward_light",
      confidence: 0.68,
      reason: "improve_face_light",
      expectedGain: 0.12,
      priority: 72,
    }));
  }

  return actions;
}

function targetSubjectBounds(shotSpec: ShotSpec, subject?: SubjectObservation): NormalizedRectangle {
  if (shotSpec.domain === "portrait") return { x: 0.3, y: 0.18, width: 0.4, height: 0.66 };
  return subject?.bounds ?? { x: 0.05, y: 0.05, width: 0.9, height: 0.9 };
}

function previewConfiguration(shotSpec: ShotSpec): ShotPlan["previewConfiguration"] {
  if (shotSpec.constraints.realityMode === "creative") {
    return { label: "ai_enhancement_required", operations: ["creative_preview", "explicit_disclosure"] };
  }

  return {
    label: shotSpec.constraints.realityMode === "enhanced" ? "enhanced_realistic" : "capture_realistic",
    operations: ["crop_simulation", "exposure_bias", "tone_preview", "composition_overlay"],
  };
}

function actionScore(action: GuidanceAction, calibration: GuidanceCalibration, domain?: CaptureDomain): number {
  const ease = action.actor === "camera" ? 0.95 : action.safetyQualifier === "if_safe" ? 0.72 : 0.8;
  const interactionCost = action.actor === "subject" ? 0.08 : 0.04;
  const safetyRisk = action.safetyQualifier === "if_safe" ? 0.08 : 0;
  return action.expectedGain * action.confidence * ease - interactionCost - safetyRisk + action.priority / 1000 + guidanceBoost(action, calibration, domain);
}

function isReadyAction(action: GuidanceAction): boolean {
  return action.reason === "ready_to_capture" || action.action === "capture_now";
}

function sameInstruction(lhs: GuidanceAction, rhs: GuidanceAction): boolean {
  return lhs.actor === rhs.actor &&
    lhs.action === rhs.action &&
    lhs.reason === rhs.reason &&
    lhs.direction === rhs.direction;
}

function canInterrupt(proposedAction: GuidanceAction, activeAction: GuidanceAction): boolean {
  if (proposedAction.actor === "camera" && activeAction.actor !== "camera") return true;
  if (proposedAction.reason === "reduce_motion_blur" && activeAction.reason !== "reduce_motion_blur") return true;
  if (proposedAction.priority >= activeAction.priority + 12) return true;
  return proposedAction.expectedGain >= activeAction.expectedGain + 0.08;
}

function oppositeGuidanceAction(action: GuidanceAction["action"]): GuidanceAction["action"] | undefined {
  switch (action) {
    case "move_left":
      return "move_right";
    case "move_right":
      return "move_left";
    case "move_forward":
      return "if_safe_move";
    case "move_backward":
    case "if_safe_move":
      return "move_forward";
    case "raise_camera":
      return "lower_camera";
    case "lower_camera":
      return "raise_camera";
    case "rotate_clockwise":
      return "rotate_counterclockwise";
    case "rotate_counterclockwise":
      return "rotate_clockwise";
    default:
      return undefined;
  }
}

function completedActionKey(action: GuidanceAction): string {
  return [
    action.actor,
    action.action,
    action.reason,
    action.direction ?? "none",
  ].join("|");
}

function clearRecord(record: object): void {
  for (const key of Object.keys(record)) {
    delete (record as Record<string, unknown>)[key];
  }
}

function expireRecord(record: object, nowMs: number): void {
  for (const [key, value] of Object.entries(record as Record<string, number | undefined>)) {
    if ((value ?? 0) <= nowMs) {
      delete (record as Record<string, unknown>)[key];
    }
  }
}

function rectSimilarity(a: NormalizedRectangle, b: NormalizedRectangle): number {
  const centerDistance = Math.hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2));
  const sizeDistance = Math.abs(a.width * a.height - b.width * b.height);
  return clamp01(1 - centerDistance * 1.8 - sizeDistance);
}

function shotReasons(candidate: BestShotCandidate): string[] {
  const reasons: string[] = [];
  if (candidate.sharpness > 0.82) reasons.push("sharp");
  if (candidate.exposure > 0.8) reasons.push("well_exposed");
  if ((candidate.faceQuality ?? 0) > 0.8) reasons.push("good_face_quality");
  if (candidate.composition > 0.8) reasons.push("strong_composition");
  if (candidate.intentMatch > 0.8) reasons.push("matches_intent");
  return reasons.length ? reasons : ["balanced_result"];
}

function achievabilityForPreviewLabel(label: ShotPlan["previewConfiguration"]["label"], shotPlan: ShotPlan): number {
  if (label === "enhanced_realistic") return clamp01(shotPlan.achievability.enhanced);
  if (label === "ai_enhancement_required") return clamp01(shotPlan.achievability.creative);
  return clamp01(shotPlan.achievability.natural);
}

function displayTitle(value: string): string {
  return value
    .split("_")
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(" ");
}

function formatZoom(value: number): string {
  return Math.abs(Math.round(value) - value) < 0.05 ? `${Math.round(value)}x` : `${value.toFixed(1)}x`;
}

function uniqueNonEmpty(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function average(values: number[]): number {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function addGuidanceBoost(
  reason: string,
  domain: string | undefined,
  amount: number,
  globalReasonBoosts: Partial<Record<GuidanceReason, number>>,
  domainReasonBoosts: Partial<Record<CaptureDomain, Partial<Record<GuidanceReason, number>>>>
): void {
  if (!isGuidanceReason(reason)) return;

  if (domain && isCaptureDomain(domain)) {
    domainReasonBoosts[domain] ??= {};
    domainReasonBoosts[domain]![reason] = (domainReasonBoosts[domain]![reason] ?? 0) + amount;
  } else {
    globalReasonBoosts[reason] = (globalReasonBoosts[reason] ?? 0) + amount;
  }
}

function guidanceBoost(action: GuidanceAction, calibration: GuidanceCalibration, domain?: CaptureDomain): number {
  const globalBoost = calibration.globalReasonBoosts[action.reason] ?? 0;
  const domainBoost = domain ? calibration.domainReasonBoosts[domain]?.[action.reason] ?? 0 : 0;
  return clampBoost(globalBoost + domainBoost);
}

function clampBoost(value: number): number {
  return Math.max(0, Math.min(0.08, Number.isFinite(value) ? value : 0));
}

function clampBoosts(boosts: Partial<Record<GuidanceReason, number>>): Partial<Record<GuidanceReason, number>> {
  return Object.fromEntries(
    Object.entries(boosts).map(([reason, boost]) => [reason, clampBoost(boost)])
  ) as Partial<Record<GuidanceReason, number>>;
}

function preferredReasonForWeakness(weakness: string): GuidanceReason | undefined {
  switch (weakness) {
    case "background":
      return "reduce_clutter";
    case "horizon":
      return "level_horizon";
    case "lighting":
      return "improve_face_light";
    case "exposure":
      return "protect_highlights";
    case "pose":
      return "improve_pose";
    case "sharpnessProbability":
      return "reduce_motion_blur";
    case "composition":
    case "subjectPosition":
      return "improve_subject_background_separation";
    case "cameraAngle":
    case "intentMatch":
      return "match_reference";
    default:
      return undefined;
  }
}

function isGuidanceReason(value: string): value is GuidanceReason {
  return [
    "improve_subject_background_separation",
    "level_horizon",
    "protect_highlights",
    "improve_face_light",
    "reduce_clutter",
    "match_reference",
    "improve_pose",
    "increase_sky",
    "reduce_motion_blur",
    "ready_to_capture",
  ].includes(value);
}

function isCaptureDomain(value: string): value is CaptureDomain {
  return ["portrait", "landscape", "travel", "lifestyle", "night", "reference"].includes(value);
}

function validateTargetMatchCalibration(calibration: TargetMatchCalibration): void {
  requirePositive(calibration.horizonRollFullPenaltyDegrees, "horizonRollFullPenaltyDegrees");
  requirePositive(calibration.eyeLevelPitchFullPenaltyDegrees, "eyeLevelPitchFullPenaltyDegrees");
  requireRange(calibration.highlightClippingPenalty, "highlightClippingPenalty", 0, 2);
  requireRange(calibration.shadowClippingPenalty, "shadowClippingPenalty", 0, 2);
  requireRange(calibration.backgroundClutterPenalty, "backgroundClutterPenalty", 0, 2);
  requireRange(calibration.poleBehindHeadPenalty, "poleBehindHeadPenalty", 0, 2);
  requireRange(calibration.dynamicRangeLightingPenalty, "dynamicRangeLightingPenalty", 0, 2);
  requireRange(calibration.motionBlurPenalty, "motionBlurPenalty", 0, 2);
  requireRange(calibration.missingHorizonScore, "missingHorizonScore", 0, 1);
  requireRange(calibration.missingFaceLightQuality, "missingFaceLightQuality", 0, 1);
  requireRange(calibration.missingPoseScore, "missingPoseScore", 0, 1);
  requireRange(calibration.nonPortraitCameraAngleScore, "nonPortraitCameraAngleScore", 0, 1);
}

function requirePositive(value: number, label: string): void {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${label} must be positive.`);
  }
}

function requireRange(value: number, label: string, min: number, max: number): void {
  if (!Number.isFinite(value) || value < min || value > max) {
    throw new Error(`${label} must be between ${min} and ${max}.`);
  }
}

function cryptoId(): string {
  return Math.random().toString(36).slice(2, 10);
}
