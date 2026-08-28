export type RealityMode = "natural" | "enhanced" | "creative";
export type CaptureDomain = "portrait" | "landscape" | "travel" | "lifestyle" | "night" | "reference";

export interface ShotSpec {
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
    exposureStrategy?: "protect_highlights" | "prioritize_faces" | "balanced" | "brighten" | "night_stability";
    focusStrategy?: "subject_eye" | "subject_center" | "hyperfocal" | "auto";
    depthIntent?: "natural_depth" | "strong_subject_separation" | "deep_focus" | "auto";
  };
  constraints: {
    realityMode: RealityMode;
    cloudAllowed: boolean;
    generativeEditsAllowed: boolean;
    userSafetyStrictness: "standard" | "conservative";
    singlePhoneOnly: true;
  };
  confidence: number;
  missingInfo: string[];
}

export interface ReferencePhotoState {
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

export interface ReferencePhotoFeatures {
  framing?: string;
  apparentFocalLength?: string;
  cameraHeight?: "low" | "eye_level" | "high" | "unknown";
  subjectScale?: number;
  poseHints?: string[];
  lightingDirection?: string;
  colorMood?: string;
  depthStyle?: string;
  achievableTranslationNotes?: string[];
}

export interface DeviceCapability {
  manufacturer: string;
  model: string;
  physicalCameras: CameraCapability[];
  rawSupported: boolean;
  depthSupported: boolean;
  manualExposureSupported: boolean;
  manualFocusSupported: boolean;
  manualWhiteBalanceSupported: boolean;
  hdrSupported: boolean;
  nightExtensionSupported: boolean;
  portraitExtensionSupported: boolean;
  stabilizationModes: string[];
  thermalClass?: string;
  measuredCameraLatency?: number;
}

export interface CameraCapability {
  id: string;
  position: "front" | "back" | "external" | "unknown";
  lensType: "ultra_wide" | "wide" | "telephoto" | "true_depth" | "unknown";
  minZoom?: number;
  maxZoom?: number;
  supportsFocusLock?: boolean;
  supportsExposureLock?: boolean;
}
