import type { RealityMode } from "./contracts";

export interface NormalizedRectangle {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface GuidanceAction {
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

export interface ShotPlan {
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
    subjectBounds: NormalizedRectangle;
    horizonY?: number;
    crop: NormalizedRectangle;
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
