export interface SceneState {
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

export interface CameraState {
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

export interface LightingState {
  exposureMean: number;
  highlightClipping: number;
  shadowClipping: number;
  faceLightQuality?: number;
  direction?: "front" | "front_left" | "front_right" | "side" | "backlit" | "unknown";
  dynamicRangeRisk: number;
}

export interface HorizonState {
  y: number;
  rollDegrees: number;
  confidence: number;
}

export interface SkyState {
  visibleFraction: number;
  sunsetLikelihood: number;
  cloudInterest: number;
  highlightRisk: number;
}

export interface SubjectObservation {
  id: string;
  type: "person" | "face" | "vehicle" | "animal" | "object";
  bounds: NormalizedRect;
  segmentationAvailable: boolean;
  pose?: PoseState;
  face?: FaceQualityState;
  distanceEstimateMeters?: number;
  confidence: number;
}

export interface PoseState {
  shouldersAngleDegrees?: number;
  faceYawDegrees?: number;
  eyeLineConfidence?: number;
  handAwkwardnessRisk?: number;
}

export interface FaceQualityState {
  eyeOpenProbability?: number;
  expressionStability?: number;
  sharpnessProbability?: number;
  skinExposureScore?: number;
}

export interface BackgroundState {
  clutterScore: number;
  brightDistractionScore: number;
  poleBehindHeadRisk: number;
  randomPeopleRisk: number;
  horizonIntersectionRisk: number;
  cleanerDirection?: "left" | "right" | "forward" | "backward" | "unknown";
}

export interface NormalizedRect {
  x: number;
  y: number;
  width: number;
  height: number;
}
