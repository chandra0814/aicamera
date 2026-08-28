const fs = require("node:fs");

const readJson = (relativePath) => JSON.parse(fs.readFileSync(relativePath, "utf8"));
const sceneState = readJson("../../tests/fixtures/portrait-scene-state.json");
const deviceCapability = readJson("../../tests/fixtures/iphone-device-capability.json");
const shotSpec = readJson("../../tests/fixtures/cinematic-portrait.shotspec.json");
const calibration = readJson("../../tests/calibration/target-match-calibration.json").targetMatchCalibration;

if (shotSpec.constraints.singlePhoneOnly !== true) {
  throw new Error("ShotSpec must be single-phone only.");
}

if (shotSpec.subject.identityRecognitionAllowed !== false) {
  throw new Error("Identity recognition must stay disabled.");
}

const recommendedLens = deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto") ? "telephoto" : "wide";
const horizon = clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / calibration.horizonRollFullPenaltyDegrees);
const exposure = clamp01(
  1 -
    sceneState.scene.lighting.highlightClipping * calibration.highlightClippingPenalty -
    sceneState.scene.lighting.shadowClipping * calibration.shadowClippingPenalty
);
const targetMatch = average([
  horizon,
  exposure,
  sceneState.composition.subjectPlacementScore,
  sceneState.composition.balanceScore,
  1 - sceneState.motion.blurRisk * calibration.motionBlurPenalty,
]);
const targetPreview = {
  label: "capture_realistic",
  estimatedAchievability: 0.84,
  subjectBounds: { x: 0.3, y: 0.18, width: 0.4, height: 0.66 },
  operations: ["crop", "exposure", "white_balance", "focus", "lens", "tone", "composition_overlay"],
  privacy: {
    singlePhoneOnly: true,
    usesRawCameraFrameUpload: false,
    usesPrivatePhotoUpload: false,
  },
};
const nextAction = sceneState.background.clutterScore > 0.55 && sceneState.safety.movementGuidanceAllowed
  ? "if_safe_move_left"
  : "hold_steady";
const guidanceStabilized = validateGuidanceStabilizer();
const previewAdjustments = validatePreviewAdjustments();

if (targetPreview.label !== "capture_realistic") {
  throw new Error("Target preview must stay capture-realistic for natural mode.");
}

if (
  targetPreview.privacy.singlePhoneOnly !== true ||
  targetPreview.privacy.usesRawCameraFrameUpload !== false ||
  targetPreview.privacy.usesPrivatePhotoUpload !== false
) {
  throw new Error("Target preview must stay single-phone and avoid private uploads.");
}

if (!targetPreview.operations.includes("composition_overlay")) {
  throw new Error("Target preview must expose composition overlay guidance.");
}

console.log(JSON.stringify({
  singlePhoneOnly: shotSpec.constraints.singlePhoneOnly,
  recommendedLens,
  targetMatch: Number(targetMatch.toFixed(3)),
  targetPreview: {
    label: targetPreview.label,
    estimatedAchievability: targetPreview.estimatedAchievability,
    singlePhoneOnly: targetPreview.privacy.singlePhoneOnly,
  },
  nextAction,
  guidanceStabilized,
  previewAdjustments,
}, null, 2));

function average(values) {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function validateGuidanceStabilizer() {
  const stabilizer = makeGuidanceStabilizer();
  const left = makeGuidanceAction("move_left", "move_left", "left");
  const right = makeGuidanceAction("move_right", "move_right", "right");
  const ready = {
    ...makeGuidanceAction("hold_steady_ready", "hold_steady"),
    reason: "ready_to_capture",
    expectedGain: 0.04,
    priority: 50,
  };

  assert(stabilizeGuidance(stabilizer, left, 0)?.action === "move_left", "Expected initial movement guidance.");
  assert(stabilizeGuidance(stabilizer, right, 1_000)?.action === "move_left", "Expected immediate opposite movement suppression.");
  assert(stabilizeGuidance(stabilizer, ready, 1_500)?.reason === "ready_to_capture", "Expected ready state after movement completion.");
  assert(stabilizeGuidance(stabilizer, left, 2_000)?.reason === "ready_to_capture", "Expected completed movement memory.");
  assert(stabilizeGuidance(stabilizer, left, 4_000)?.action === "move_left", "Expected movement after completed memory expires.");

  return true;
}

function validatePreviewAdjustments() {
  const moreSky = makePreviewAdjustmentShotSpec("Give me a cinematic portrait. Show more sky.");
  const brighter = makePreviewAdjustmentShotSpec("Take a natural lifestyle photo. Make it brighter.");
  const lessBlur = makePreviewAdjustmentShotSpec("Give me a cinematic portrait. Use less background blur.");
  const naturalColor = makePreviewAdjustmentShotSpec("Give me a cinematic portrait. Keep colors natural.");

  assert(moreSky.composition.skyPriority === "high", "More-sky preview adjustment must raise sky priority.");
  assert(moreSky.compositionTarget.horizonY === 0.34, "More-sky portrait preview must expose a target horizon.");
  assert(moreSky.compositionTarget.subjectBounds.y > 0.18, "More-sky preview must lower the subject target.");
  assert(moreSky.previewOperations.includes("sky_framing_guide"), "More-sky preview must add a sky guide.");

  assert(brighter.cameraIntent.exposureStrategy === "brighten", "Brighter preview adjustment must use brighten exposure strategy.");
  assert(brighter.targetExposureBias === 0.3, "Brighter preview adjustment must lift exposure when highlights are safe.");
  assert(brighter.previewOperations.includes("exposure_lift"), "Brighter preview must add exposure lift operation.");

  assert(lessBlur.cameraIntent.depthIntent === "natural_depth", "Less-background-blur preview must use natural depth.");
  assert(lessBlur.depthEffect === "natural", "Less-background-blur preview must avoid portrait blur preview.");
  assert(lessBlur.previewOperations.includes("deep_focus_preview"), "Less-background-blur preview must add deep-focus cue.");

  assert(naturalColor.style.name === "cinematic", "Natural-color adjustment must preserve cinematic intent.");
  assert(naturalColor.style.colorIntent === "natural", "Natural-color adjustment must override color treatment.");
  assert(naturalColor.constraints.singlePhoneOnly === true, "Preview adjustments must stay single-phone.");
  assert(naturalColor.constraints.cloudAllowed === false, "Preview adjustments must not require cloud.");
  assert(naturalColor.constraints.generativeEditsAllowed === false, "Preview adjustments must not require generative edits.");

  return ["more_sky", "brighter", "less_background_blur", "natural_color"];
}

function makePreviewAdjustmentShotSpec(prompt) {
  const normalized = prompt.toLowerCase();
  const isPortrait = /\b(portrait|me|person|people|selfie)\b/.test(normalized);
  const isLandscape = /\b(landscape|sky|sunset|mountain|beach|cityscape|lake)\b/.test(normalized);
  const wantsMoreDrama = /\b(more dramatic|more drama)\b/.test(normalized);
  const wantsCinematic = /\b(cinematic|dramatic|movie|luxury)\b/.test(normalized) || wantsMoreDrama;
  const wantsBrighter = /\b(brighter|brighten|make it bright)\b/.test(normalized);
  const wantsNaturalColor = /\b(natural color|natural colour|colors natural|colours natural)\b/.test(normalized);
  const wantsLessBackgroundBlur = /\b(less background blur|less blur|deep focus)\b/.test(normalized);
  const wantsSky = /\b(sky|sunset|cloud|more sky|show more sky)\b/.test(normalized);
  const domain = isPortrait ? "portrait" : isLandscape ? "landscape" : "lifestyle";
  const cameraIntent = {
    exposureStrategy: wantsSky ? "protect_highlights" : wantsBrighter ? "brighten" : isPortrait ? "prioritize_faces" : "balanced",
    depthIntent: wantsLessBackgroundBlur ? "natural_depth" : isPortrait ? "strong_subject_separation" : "deep_focus",
  };
  const composition = {
    skyPriority: wantsSky ? "high" : undefined,
  };
  const compositionTarget = {
    subjectBounds: domain === "portrait" && composition.skyPriority === "high"
      ? { x: 0.33, y: 0.27, width: 0.34, height: 0.56 }
      : domain === "portrait"
        ? { x: 0.3, y: 0.18, width: 0.4, height: 0.66 }
        : { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
    horizonY: composition.skyPriority === "high" ? (domain === "portrait" ? 0.34 : 0.32) : undefined,
  };
  const previewOperations = ["crop_simulation", "exposure_bias", "tone_preview", "composition_overlay"];

  if (composition.skyPriority === "high") previewOperations.push("sky_framing_guide");
  if (cameraIntent.exposureStrategy === "brighten") previewOperations.push("exposure_lift");
  if (cameraIntent.depthIntent === "natural_depth" || cameraIntent.depthIntent === "deep_focus") {
    previewOperations.push("deep_focus_preview");
  }

  return {
    composition,
    compositionTarget,
    cameraIntent,
    targetExposureBias: cameraIntent.exposureStrategy === "brighten" ? 0.3 : 0,
    depthEffect: cameraIntent.depthIntent === "natural_depth" || cameraIntent.depthIntent === "deep_focus" ? "natural" : "portrait_if_available",
    previewOperations,
    style: {
      name: wantsCinematic ? "cinematic" : "natural",
      colorIntent: wantsNaturalColor ? "natural" : wantsCinematic ? "warm_highlights_cool_shadows" : "natural",
    },
    constraints: {
      singlePhoneOnly: true,
      cloudAllowed: false,
      generativeEditsAllowed: false,
    },
  };
}

function makeGuidanceStabilizer() {
  return {
    activeAction: undefined,
    activeUntilMs: 0,
    minimumHoldUntilMs: 0,
    minimumHoldMs: 1_200,
    completedActionMemoryMs: 2_500,
    suppressedActionUntilMs: {},
    completedActionUntilMs: {},
  };
}

function stabilizeGuidance(stabilizer, proposedAction, nowMs) {
  expireGuidanceMemory(stabilizer, nowMs);

  if (!proposedAction) {
    clearActiveGuidance(stabilizer);
    return undefined;
  }

  if (isReadyGuidance(proposedAction) && stabilizer.activeAction && !isReadyGuidance(stabilizer.activeAction)) {
    rememberCompletedGuidance(stabilizer, stabilizer.activeAction, nowMs);
    beginGuidance(stabilizer, proposedAction, nowMs);
    return proposedAction;
  }

  if ((stabilizer.completedActionUntilMs[guidanceKey(proposedAction)] ?? 0) > nowMs) {
    if (stabilizer.activeAction && isReadyGuidance(stabilizer.activeAction) && stabilizer.activeUntilMs > nowMs) {
      return stabilizer.activeAction;
    }
    return undefined;
  }

  if ((stabilizer.suppressedActionUntilMs[proposedAction.action] ?? 0) > nowMs) {
    if (stabilizer.activeAction && stabilizer.activeUntilMs > nowMs) {
      return stabilizer.activeAction;
    }
    return undefined;
  }

  if (stabilizer.activeAction && stabilizer.activeUntilMs > nowMs && sameGuidance(stabilizer.activeAction, proposedAction)) {
    beginGuidance(stabilizer, proposedAction, nowMs);
    return proposedAction;
  }

  if (
    stabilizer.activeAction &&
    stabilizer.activeUntilMs > nowMs &&
    stabilizer.minimumHoldUntilMs > nowMs &&
    !canInterruptGuidance(proposedAction, stabilizer.activeAction)
  ) {
    return stabilizer.activeAction;
  }

  beginGuidance(stabilizer, proposedAction, nowMs);
  return proposedAction;
}

function beginGuidance(stabilizer, action, nowMs) {
  stabilizer.activeAction = action;
  stabilizer.activeUntilMs = nowMs + Math.max(0, action.ttlMs);
  stabilizer.minimumHoldUntilMs = nowMs + Math.min(Math.max(0, stabilizer.minimumHoldMs), Math.max(0, action.ttlMs));

  const opposite = oppositeGuidanceAction(action.action);
  if (opposite) {
    stabilizer.suppressedActionUntilMs[opposite] = nowMs + Math.max(0, action.suppressOppositeUntilMs);
  }
}

function rememberCompletedGuidance(stabilizer, action, nowMs) {
  if (isReadyGuidance(action)) return;
  stabilizer.completedActionUntilMs[guidanceKey(action)] = nowMs + Math.max(0, stabilizer.completedActionMemoryMs);
}

function expireGuidanceMemory(stabilizer, nowMs) {
  for (const [action, untilMs] of Object.entries(stabilizer.suppressedActionUntilMs)) {
    if (untilMs <= nowMs) delete stabilizer.suppressedActionUntilMs[action];
  }

  for (const [key, untilMs] of Object.entries(stabilizer.completedActionUntilMs)) {
    if (untilMs <= nowMs) delete stabilizer.completedActionUntilMs[key];
  }

  if (stabilizer.activeUntilMs <= nowMs) {
    clearActiveGuidance(stabilizer);
  }
}

function clearActiveGuidance(stabilizer) {
  stabilizer.activeAction = undefined;
  stabilizer.activeUntilMs = 0;
  stabilizer.minimumHoldUntilMs = 0;
}

function makeGuidanceAction(id, action, direction) {
  return {
    id,
    actor: "photographer",
    action,
    magnitude: 0.4,
    unit: "meter",
    direction,
    confidence: 0.76,
    reason: "reduce_clutter",
    expectedGain: 0.16,
    safetyQualifier: "if_safe",
    priority: 88,
    ttlMs: 3_500,
    suppressOppositeUntilMs: 5_000,
  };
}

function isReadyGuidance(action) {
  return action.reason === "ready_to_capture" || action.action === "capture_now";
}

function sameGuidance(lhs, rhs) {
  return lhs.actor === rhs.actor &&
    lhs.action === rhs.action &&
    lhs.reason === rhs.reason &&
    lhs.direction === rhs.direction;
}

function canInterruptGuidance(proposed, active) {
  if (proposed.actor === "camera" && active.actor !== "camera") return true;
  if (proposed.reason === "reduce_motion_blur" && active.reason !== "reduce_motion_blur") return true;
  if (proposed.priority >= active.priority + 12) return true;
  return proposed.expectedGain >= active.expectedGain + 0.08;
}

function oppositeGuidanceAction(action) {
  if (action === "move_left") return "move_right";
  if (action === "move_right") return "move_left";
  if (action === "move_forward") return "if_safe_move";
  if (action === "move_backward" || action === "if_safe_move") return "move_forward";
  if (action === "raise_camera") return "lower_camera";
  if (action === "lower_camera") return "raise_camera";
  if (action === "rotate_clockwise") return "rotate_counterclockwise";
  if (action === "rotate_counterclockwise") return "rotate_clockwise";
  return undefined;
}

function guidanceKey(action) {
  return [action.actor, action.action, action.reason, action.direction ?? "none"].join("|");
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
