import type { DeviceCapability, ShotSpec } from "./contracts";
import type { GuidanceAction, NormalizedRectangle, ShotPlan } from "./planning";
import type { SceneState, SubjectObservation } from "./scene-state";

export interface AiPipelineResult {
  shotSpec: ShotSpec;
  shotPlan: ShotPlan;
  guidanceAction?: GuidanceAction;
  targetMatch: TargetMatchScore;
  previewSafety: PreviewSafety;
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
  selectNextAction(shotPlan: ShotPlan): GuidanceAction | undefined {
    const candidates = [...shotPlan.photographerChanges, ...shotPlan.subjectDirections]
      .filter((action) => action.confidence >= 0.55 && action.expectedGain >= 0.04)
      .sort((a, b) => actionScore(b) - actionScore(a));

    return candidates[0];
  }
}

export class TargetMatchEngine {
  score(shotSpec: ShotSpec, shotPlan: ShotPlan, sceneState: SceneState): TargetMatchScore {
    const subject = sceneState.subjects[0];
    const target = shotPlan.compositionTarget.subjectBounds;
    const subjectPosition = subject ? rectSimilarity(subject.bounds, target) : 0.25;
    const horizon = sceneState.scene.horizon ? clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / 12) : 0.72;
    const exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * 0.8 - sceneState.scene.lighting.shadowClipping * 0.6);
    const background = clamp01(1 - sceneState.background.clutterScore * 0.55 - sceneState.background.poleBehindHeadRisk * 0.25);
    const lighting = clamp01((sceneState.scene.lighting.faceLightQuality ?? 0.65) - sceneState.scene.lighting.dynamicRangeRisk * 0.2);
    const pose = clamp01(subject?.face?.eyeOpenProbability ?? 0.72);
    const sharpnessProbability = clamp01(1 - sceneState.motion.blurRisk);
    const composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore]);
    const cameraAngle = shotSpec.cameraIntent.perspective === "eye_level" ? clamp01(1 - Math.abs(sceneState.cameraState.pitchDegrees ?? 0) / 35) : 0.75;
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
  private readonly guidancePolicy = new GuidancePolicy();
  private readonly targetMatchEngine = new TargetMatchEngine();
  private readonly previewSafetyEngine = new PreviewSafetyEngine();

  run(prompt: string, sceneState: SceneState, deviceCapability: DeviceCapability): AiPipelineResult {
    const shotSpec = this.intentEngine.parseIntent(prompt);
    const shotPlan = this.shotPlanner.plan(shotSpec, sceneState, deviceCapability);
    const guidanceAction = this.guidancePolicy.selectNextAction(shotPlan);
    const targetMatch = this.targetMatchEngine.score(shotSpec, shotPlan, sceneState);
    const previewSafety = this.previewSafetyEngine.evaluate(shotSpec, shotPlan);

    return { shotSpec, shotPlan, guidanceAction, targetMatch, previewSafety };
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

function actionScore(action: GuidanceAction): number {
  const ease = action.actor === "camera" ? 0.95 : action.safetyQualifier === "if_safe" ? 0.72 : 0.8;
  const interactionCost = action.actor === "subject" ? 0.08 : 0.04;
  const safetyRisk = action.safetyQualifier === "if_safe" ? 0.08 : 0;
  return action.expectedGain * action.confidence * ease - interactionCost - safetyRisk + action.priority / 1000;
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

function average(values: number[]): number {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function cryptoId(): string {
  return Math.random().toString(36).slice(2, 10);
}
