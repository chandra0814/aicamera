import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(process.cwd(), "../..");
const readJson = (relativePath) => JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));
const clamp01 = (value) => Math.max(0, Math.min(1, value));
const average = (values) => clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);

const sceneState = readJson("tests/fixtures/portrait-scene-state.json");
const deviceCapability = readJson("tests/fixtures/iphone-device-capability.json");
const prompt = "Give me a cinematic portrait with natural skin and a clean background.";

const shotSpec = parseIntent(prompt);
const shotPlan = plan(shotSpec, sceneState, deviceCapability);
const guidanceAction = selectNextAction(shotPlan);
const targetMatch = scoreTargetMatch(shotSpec, shotPlan, sceneState);
const previewSafety = evaluatePreviewSafety(shotSpec, shotPlan);
const targetPreview = makeTargetPreview(shotSpec, shotPlan, targetMatch, previewSafety);
const previewAdjustments = validatePreviewAdjustments(deviceCapability);

assert(shotSpec.constraints.singlePhoneOnly === true, "ShotSpec must be single-phone only.");
assert(shotSpec.subject.identityRecognitionAllowed === false, "Identity recognition must stay disabled.");
assert(shotPlan.previewConfiguration.label === "capture_realistic", "Natural preview must be capture realistic.");
assert(targetPreview.label === previewSafety.label, "Target Preview must inherit the preview safety label.");
assert(targetPreview.estimatedAchievability === shotPlan.achievability.natural, "Natural Target Preview must use natural achievability.");
assert(targetPreview.privacy.singlePhoneOnly === true, "Target Preview must stay on one phone.");
assert(targetPreview.privacy.usesRawCameraFrameUpload === false, "Target Preview cannot upload raw live camera frames.");
assert(targetPreview.privacy.usesPrivatePhotoUpload === false, "Target Preview cannot upload private photos.");
assert(guidanceAction, "Pipeline should produce a guidance action.");
assert(guidanceAction.safetyQualifier === "if_safe" || guidanceAction.actor === "camera", "Movement guidance must include safety qualifier.");
assert(targetMatch.overall >= 0 && targetMatch.overall <= 1, "Target Match must be normalized.");

console.log(JSON.stringify({
  prompt,
  shotSpec: {
    domain: shotSpec.domain,
    style: shotSpec.style.name,
    singlePhoneOnly: shotSpec.constraints.singlePhoneOnly,
  },
  shotPlan: {
    recommendedLens: shotPlan.cameraControls.recommendedLens,
    naturalAchievability: shotPlan.achievability.natural,
    previewLabel: shotPlan.previewConfiguration.label,
  },
  targetPreview: {
    title: targetPreview.title,
    label: targetPreview.label,
    estimatedAchievability: targetPreview.estimatedAchievability,
    singlePhoneOnly: targetPreview.privacy.singlePhoneOnly,
  },
  previewAdjustments,
  guidanceAction,
  targetMatch,
}, null, 2));

function parseIntent(intent) {
  const normalized = intent.toLowerCase();
  const isPortrait = /\b(portrait|me|person|people|selfie)\b/.test(normalized);
  const isLandscape = /\b(landscape|sky|sunset|mountain|beach|cityscape|lake)\b/.test(normalized);
  const cinematic = /\b(cinematic|dramatic|movie|luxury)\b/.test(normalized);
  const moreDrama = /\b(more dramatic|more drama)\b/.test(normalized);
  const wantsCinematic = cinematic || moreDrama;
  const brighter = /\b(brighter|brighten|make it bright)\b/.test(normalized);
  const naturalColor = /\b(natural color|natural colour|colors natural|colours natural)\b/.test(normalized);
  const lessBackgroundBlur = /\b(less background blur|less blur|deep focus)\b/.test(normalized);
  const moreSky = /\b(sky|sunset|cloud|more sky|show more sky)\b/.test(normalized);
  const cleanBackground = /\b(clean|background|clutter)\b/.test(normalized);

  return {
    id: "shot_validation",
    version: "1.0",
    source: "text",
    originalPrompt: intent,
    domain: isPortrait ? "portrait" : isLandscape ? "landscape" : "lifestyle",
    subject: {
      primary: isPortrait ? "person" : isLandscape ? "landscape" : "unknown",
      count: isPortrait ? 1 : undefined,
      priority: isLandscape ? "environment" : "subject",
      identityRecognitionAllowed: false,
    },
    style: {
      name: wantsCinematic ? "cinematic" : "natural",
      mood: wantsCinematic && !brighter ? "dramatic" : "bright",
      colorIntent: naturalColor ? "natural" : wantsCinematic ? "warm_highlights_cool_shadows" : "natural",
      skinTreatment: isPortrait ? "natural" : "none",
    },
    composition: {
      framing: isPortrait ? "environmental" : "wide",
      headroom: isPortrait ? "balanced" : undefined,
      skyPriority: moreSky ? "high" : undefined,
      backgroundPriority: cleanBackground ? "clean" : "contextual",
      horizonPlacement: isLandscape ? "lower_third" : "auto",
    },
    cameraIntent: {
      targetLens: isPortrait ? "two_x_if_available" : "wide",
      perspective: isPortrait ? "eye_level" : "auto",
      exposureStrategy: moreSky ? "protect_highlights" : brighter ? "brighten" : isPortrait ? "prioritize_faces" : "balanced",
      focusStrategy: isPortrait ? "subject_eye" : "auto",
      depthIntent: lessBackgroundBlur ? "natural_depth" : isPortrait ? "strong_subject_separation" : "deep_focus",
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

function plan(shotSpec, sceneState, deviceCapability) {
  const recommendedLens = deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto") ? "telephoto" : "wide";
  const photographerChanges = [];
  const previewOperations = ["crop_simulation", "exposure_bias", "tone_preview", "composition_overlay"];

  if (shotSpec.composition.skyPriority === "high") previewOperations.push("sky_framing_guide");
  if (shotSpec.cameraIntent.exposureStrategy === "brighten") previewOperations.push("exposure_lift");
  if (shotSpec.cameraIntent.depthIntent === "natural_depth" || shotSpec.cameraIntent.depthIntent === "deep_focus") {
    previewOperations.push("deep_focus_preview");
  }

  if (Math.abs(sceneState.scene.horizon.rollDegrees) > 2.5) {
    photographerChanges.push(action("level_horizon", "photographer", sceneState.scene.horizon.rollDegrees > 0 ? "rotate_counterclockwise" : "rotate_clockwise", "level_horizon", 95, "if_safe"));
  }
  if (sceneState.background.clutterScore > 0.55 && sceneState.safety.movementGuidanceAllowed) {
    photographerChanges.push(action("reduce_background_clutter", "photographer", "move_left", "reduce_clutter", 88, "if_safe"));
  }
  if (shotSpec.composition.skyPriority === "high" && (sceneState.scene.sky?.visibleFraction ?? 0) < 0.35) {
    photographerChanges.push(action("increase_sky", "photographer", "lower_camera", "increase_sky", 86, "if_safe"));
  }

  return {
    id: "plan_validation",
    shotSpecId: shotSpec.id,
    achievability: {
      natural: 0.87,
      enhanced: 0.93,
      creative: 1,
      limitingFactors: [],
    },
    cameraControls: {
      recommendedLens,
      targetZoom: recommendedLens === "telephoto" ? 2 : 1,
      targetExposureBias: targetExposureBias(shotSpec, sceneState),
      targetFocusMode: "locked",
      targetWhiteBalance: "auto",
      stabilizationMode: "cinematic",
      captureFormat: "raw_plus_heif",
    },
    photographerChanges,
    subjectDirections: [],
    compositionTarget: {
      subjectBounds: targetSubjectBounds(shotSpec),
      horizonY: targetHorizonY(shotSpec),
      crop: { x: 0, y: 0, width: 1, height: 1 },
    },
    processingIntent: {
      realityMode: "natural",
      toneCurve: "cinematic_soft_contrast",
      colorTreatment: shotSpec.style.colorIntent ?? "natural",
      depthEffect: targetDepthEffect(shotSpec),
    },
    previewConfiguration: {
      label: "capture_realistic",
      operations: previewOperations,
    },
    capturePolicy: {
      mode: "burst",
      burstFrameCount: 5,
      trigger: "ready_assist",
      readinessThreshold: 0.92,
    },
  };
}

function action(id, actor, action, reason, priority, safetyQualifier) {
  return {
    id,
    actor,
    action,
    confidence: 0.8,
    reason,
    expectedGain: 0.14,
    safetyQualifier,
    priority,
    ttlMs: 3500,
    suppressOppositeUntilMs: 5000,
  };
}

function selectNextAction(shotPlan) {
  return [...shotPlan.photographerChanges, ...shotPlan.subjectDirections]
    .sort((a, b) => b.priority - a.priority)[0];
}

function targetSubjectBounds(shotSpec) {
  if (shotSpec.domain === "portrait" && shotSpec.composition.skyPriority === "high") {
    return { x: 0.33, y: 0.27, width: 0.34, height: 0.56 };
  }

  if (shotSpec.domain === "portrait") {
    return { x: 0.3, y: 0.18, width: 0.4, height: 0.66 };
  }

  return { x: 0.05, y: 0.05, width: 0.9, height: 0.9 };
}

function targetHorizonY(shotSpec) {
  if (shotSpec.composition.skyPriority === "high") {
    return shotSpec.domain === "portrait" ? 0.34 : 0.32;
  }

  return shotSpec.domain === "landscape" ? 0.38 : undefined;
}

function targetExposureBias(shotSpec, sceneState) {
  if (sceneState.scene.lighting.highlightClipping > 0.22) return -0.3;
  if (shotSpec.cameraIntent.exposureStrategy === "protect_highlights") return -0.3;
  if (shotSpec.cameraIntent.exposureStrategy === "brighten") return 0.3;
  return 0;
}

function targetDepthEffect(shotSpec) {
  if (shotSpec.cameraIntent.depthIntent === "natural_depth" || shotSpec.cameraIntent.depthIntent === "deep_focus") {
    return "natural";
  }

  return shotSpec.domain === "portrait" ? "portrait_if_available" : "natural";
}

function scoreTargetMatch(_shotSpec, shotPlan, sceneState) {
  const subject = sceneState.subjects[0];
  const target = shotPlan.compositionTarget.subjectBounds;
  const subjectPosition = rectSimilarity(subject.bounds, target);
  const horizon = clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / 12);
  const exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * 0.8 - sceneState.scene.lighting.shadowClipping * 0.6);
  const background = clamp01(1 - sceneState.background.clutterScore * 0.55 - sceneState.background.poleBehindHeadRisk * 0.25);
  const lighting = clamp01(sceneState.scene.lighting.faceLightQuality - sceneState.scene.lighting.dynamicRangeRisk * 0.2);
  const pose = sceneState.subjects[0].face.eyeOpenProbability;
  const sharpnessProbability = clamp01(1 - sceneState.motion.blurRisk);
  const composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore]);
  const cameraAngle = clamp01(1 - Math.abs(sceneState.cameraState.pitchDegrees) / 35);
  const intentMatch = average([composition, lighting, background, exposure]);
  const values = { composition, subjectPosition, cameraAngle, lighting, background, horizon, pose, sharpnessProbability, exposure, intentMatch };
  return { ...values, overall: average(Object.values(values)) };
}

function evaluatePreviewSafety(shotSpec, shotPlan) {
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

function makeTargetPreview(shotSpec, shotPlan, targetMatch, previewSafety) {
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
    estimatedAchievability: previewSafety.label === "ai_enhancement_required"
      ? shotPlan.achievability.creative
      : previewSafety.label === "enhanced_realistic"
        ? shotPlan.achievability.enhanced
        : shotPlan.achievability.natural,
    subjectBounds: shotPlan.compositionTarget.subjectBounds,
    horizonY: shotPlan.compositionTarget.horizonY,
    crop: shotPlan.compositionTarget.crop,
    lens: shotPlan.cameraControls.recommendedLens,
    targetZoom: shotPlan.cameraControls.targetZoom,
    exposureBias: shotPlan.cameraControls.targetExposureBias,
    toneCurve: shotPlan.processingIntent.toneCurve,
    colorTreatment: shotPlan.processingIntent.colorTreatment,
    depthEffect: shotPlan.processingIntent.depthEffect,
    operations: [...new Set([...previewSafety.allowedOperations, ...shotPlan.previewConfiguration.operations])],
    targetMatchAtPreview: targetMatch.overall,
    disclosure: previewSafety.userFacingDisclosure,
    requiresGenerativeEnhancement: previewSafety.label === "ai_enhancement_required",
    privacy: {
      singlePhoneOnly: true,
      usesRawCameraFrameUpload: false,
      usesPrivatePhotoUpload: false,
    },
  };
}

function validatePreviewAdjustments(deviceCapability) {
  const basePlan = plan(parseIntent("Give me a cinematic portrait."), sceneState, deviceCapability);
  const moreSkySpec = parseIntent("Give me a cinematic portrait. Show more sky.");
  const moreSkyPlan = plan(moreSkySpec, sceneState, deviceCapability);
  const brighterSpec = parseIntent("Take a natural lifestyle photo. Make it brighter.");
  const brighterPlan = plan(brighterSpec, sceneState, deviceCapability);
  const lessBlurSpec = parseIntent("Give me a cinematic portrait. Use less background blur.");
  const lessBlurPlan = plan(lessBlurSpec, sceneState, deviceCapability);
  const naturalColorSpec = parseIntent("Give me a cinematic portrait. Keep colors natural.");

  assert(moreSkySpec.composition.skyPriority === "high", "More-sky command must raise sky priority.");
  assert(moreSkyPlan.compositionTarget.horizonY === 0.34, "More-sky portrait preview must expose a target horizon.");
  assert(moreSkyPlan.compositionTarget.subjectBounds.y > basePlan.compositionTarget.subjectBounds.y, "More-sky command must lower the subject target.");
  assert(moreSkyPlan.compositionTarget.subjectBounds.height < basePlan.compositionTarget.subjectBounds.height, "More-sky command must reduce subject target height.");
  assert(moreSkyPlan.previewConfiguration.operations.includes("sky_framing_guide"), "More-sky command must add sky framing guide.");

  assert(brighterSpec.cameraIntent.exposureStrategy === "brighten", "Brighter command must use brighten exposure strategy.");
  assert(brighterPlan.cameraControls.targetExposureBias === 0.3, "Brighter command must lift exposure when highlights are safe.");
  assert(brighterPlan.previewConfiguration.operations.includes("exposure_lift"), "Brighter command must add exposure lift.");

  assert(lessBlurSpec.cameraIntent.depthIntent === "natural_depth", "Less-background-blur command must use natural depth.");
  assert(lessBlurPlan.processingIntent.depthEffect === "natural", "Less-background-blur command must avoid portrait blur preview.");
  assert(lessBlurPlan.previewConfiguration.operations.includes("deep_focus_preview"), "Less-background-blur command must add deep-focus preview.");

  assert(naturalColorSpec.style.name === "cinematic", "Natural-color command must preserve cinematic style.");
  assert(naturalColorSpec.style.colorIntent === "natural", "Natural-color command must preserve natural colors.");
  assert(naturalColorSpec.constraints.singlePhoneOnly === true, "Preview commands must stay single-phone.");
  assert(naturalColorSpec.constraints.cloudAllowed === false, "Preview commands must not require cloud.");
  assert(naturalColorSpec.constraints.generativeEditsAllowed === false, "Preview commands must not require generative edits.");

  return ["more_sky", "brighter", "less_background_blur", "natural_color"];
}

function displayTitle(value) {
  return value
    .split("_")
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(" ");
}

function formatZoom(value) {
  return Math.abs(Math.round(value) - value) < 0.05 ? `${Math.round(value)}x` : `${value.toFixed(1)}x`;
}

function rectSimilarity(a, b) {
  const centerDistance = Math.hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2));
  const sizeDistance = Math.abs(a.width * a.height - b.width * b.height);
  return clamp01(1 - centerDistance * 1.8 - sizeDistance);
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}
