import type { CaptureDomain } from "./contracts";
import type { GuidanceAction } from "./planning";

export type CalibrationCaptureScenarioId =
  | "portrait"
  | "landscape"
  | "sky"
  | "clutter"
  | "backlight"
  | "horizon"
  | "motion"
  | "night";

export type CalibrationWeakness =
  | "composition"
  | "subjectPosition"
  | "cameraAngle"
  | "lighting"
  | "background"
  | "horizon"
  | "pose"
  | "sharpnessProbability"
  | "exposure"
  | "intentMatch";

export interface CalibrationCaptureScenario {
  id: CalibrationCaptureScenarioId;
  title: string;
  prompt: string;
  domain: CaptureDomain;
  preferredGuidanceReason: GuidanceAction["reason"];
  rankedWeaknesses: CalibrationWeakness[];
  targetSampleCount: number;
  symbolName: string;
  reviewNotes: string;
}

export interface CalibrationCaptureQueueProgress {
  version: "1.0";
  activeScenarioId?: CalibrationCaptureScenarioId;
  completedCounts: Partial<Record<CalibrationCaptureScenarioId, number>>;
}

export const calibrationCaptureScenarios: CalibrationCaptureScenario[] = [
  {
    id: "portrait",
    title: "Portrait",
    prompt: "Give me a cinematic portrait with natural skin and a clean background.",
    domain: "portrait",
    preferredGuidanceReason: "improve_subject_background_separation",
    rankedWeaknesses: ["subjectPosition", "lighting"],
    targetSampleCount: 3,
    symbolName: "person.crop.rectangle",
    reviewNotes: "Guided calibration scenario: Portrait.",
  },
  {
    id: "landscape",
    title: "Landscape",
    prompt: "Capture a wide landscape with strong composition and natural color.",
    domain: "landscape",
    preferredGuidanceReason: "ready_to_capture",
    rankedWeaknesses: ["composition", "cameraAngle"],
    targetSampleCount: 3,
    symbolName: "mountain.2",
    reviewNotes: "Guided calibration scenario: Landscape.",
  },
  {
    id: "sky",
    title: "Sky",
    prompt: "Show more sky in a dramatic but realistic landscape photo.",
    domain: "landscape",
    preferredGuidanceReason: "increase_sky",
    rankedWeaknesses: ["composition", "exposure"],
    targetSampleCount: 3,
    symbolName: "cloud.sun",
    reviewNotes: "Guided calibration scenario: Sky.",
  },
  {
    id: "clutter",
    title: "Clutter",
    prompt: "Give me a portrait with a cleaner background and less clutter.",
    domain: "portrait",
    preferredGuidanceReason: "reduce_clutter",
    rankedWeaknesses: ["background", "composition"],
    targetSampleCount: 3,
    symbolName: "rectangle.compress.vertical",
    reviewNotes: "Guided calibration scenario: Clutter.",
  },
  {
    id: "backlight",
    title: "Backlight",
    prompt: "Make a backlit portrait with visible face detail and protected highlights.",
    domain: "portrait",
    preferredGuidanceReason: "improve_face_light",
    rankedWeaknesses: ["lighting", "exposure"],
    targetSampleCount: 3,
    symbolName: "sun.max",
    reviewNotes: "Guided calibration scenario: Backlight.",
  },
  {
    id: "horizon",
    title: "Horizon",
    prompt: "Capture a landscape with a level horizon and balanced framing.",
    domain: "landscape",
    preferredGuidanceReason: "level_horizon",
    rankedWeaknesses: ["horizon", "cameraAngle"],
    targetSampleCount: 3,
    symbolName: "gyroscope",
    reviewNotes: "Guided calibration scenario: Horizon.",
  },
  {
    id: "motion",
    title: "Motion",
    prompt: "Capture a lifestyle action photo with sharp subject detail.",
    domain: "lifestyle",
    preferredGuidanceReason: "reduce_motion_blur",
    rankedWeaknesses: ["sharpnessProbability", "pose"],
    targetSampleCount: 3,
    symbolName: "figure.run",
    reviewNotes: "Guided calibration scenario: Motion.",
  },
  {
    id: "night",
    title: "Night",
    prompt: "Capture a low-light night photo with stable sharp detail.",
    domain: "night",
    preferredGuidanceReason: "protect_highlights",
    rankedWeaknesses: ["exposure", "sharpnessProbability"],
    targetSampleCount: 3,
    symbolName: "moon.stars",
    reviewNotes: "Guided calibration scenario: Night.",
  },
];

export function emptyCalibrationCaptureQueueProgress(): CalibrationCaptureQueueProgress {
  return {
    version: "1.0",
    completedCounts: {},
  };
}

export function selectCalibrationCaptureScenario(
  progress: CalibrationCaptureQueueProgress,
  scenarioId: CalibrationCaptureScenarioId
): CalibrationCaptureQueueProgress {
  return sanitizeCalibrationCaptureQueueProgress({
    ...progress,
    activeScenarioId: scenarioId,
  });
}

export function recordCalibrationCapture(
  progress: CalibrationCaptureQueueProgress,
  scenarioId: CalibrationCaptureScenarioId
): CalibrationCaptureQueueProgress {
  const scenario = scenarioById(scenarioId);
  const current = calibrationCaptureCompletedCount(progress, scenarioId);
  return sanitizeCalibrationCaptureQueueProgress({
    ...progress,
    completedCounts: {
      ...progress.completedCounts,
      [scenarioId]: Math.min(scenario.targetSampleCount, current + 1),
    },
  });
}

export function calibrationCaptureCompletedCount(
  progress: CalibrationCaptureQueueProgress,
  scenarioId: CalibrationCaptureScenarioId
): number {
  const scenario = scenarioById(scenarioId);
  const count = progress.completedCounts[scenarioId] ?? 0;
  return Math.min(scenario.targetSampleCount, Math.max(0, Math.trunc(count)));
}

export function calibrationCaptureRequiredSampleCount(): number {
  return calibrationCaptureScenarios.reduce((sum, scenario) => sum + scenario.targetSampleCount, 0);
}

export function calibrationCaptureCompletedSampleCount(
  progress: CalibrationCaptureQueueProgress
): number {
  return calibrationCaptureScenarios.reduce(
    (sum, scenario) => sum + calibrationCaptureCompletedCount(progress, scenario.id),
    0
  );
}

export function sanitizeCalibrationCaptureQueueProgress(
  progress: CalibrationCaptureQueueProgress
): CalibrationCaptureQueueProgress {
  const activeScenarioId = progress.activeScenarioId && scenarioExists(progress.activeScenarioId)
    ? progress.activeScenarioId
    : undefined;
  const completedCounts = Object.fromEntries(
    calibrationCaptureScenarios
      .map((scenario) => [scenario.id, calibrationCaptureCompletedCount(progress, scenario.id)] as const)
      .filter(([, count]) => count > 0)
  ) as CalibrationCaptureQueueProgress["completedCounts"];

  return {
    version: "1.0",
    activeScenarioId,
    completedCounts,
  };
}

function scenarioById(scenarioId: CalibrationCaptureScenarioId): CalibrationCaptureScenario {
  return calibrationCaptureScenarios.find((scenario) => scenario.id === scenarioId) ?? calibrationCaptureScenarios[0];
}

function scenarioExists(scenarioId: string): scenarioId is CalibrationCaptureScenarioId {
  return calibrationCaptureScenarios.some((scenario) => scenario.id === scenarioId);
}
