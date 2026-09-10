const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { test } = require("node:test");

const root = path.resolve(__dirname, "..");
// Compile before loading so type errors cannot silently run stale output.
execFileSync(process.execPath, [require.resolve("typescript/bin/tsc"), "-p", root], { stdio: "inherit" });
fs.writeFileSync(path.join(root, ".test-output/package.json"), JSON.stringify({ type: "commonjs" }));
const { CaptureReviewBuilder } = require("../.test-output/index.js");
const builder = new CaptureReviewBuilder();
const { PersonalVisualLearningEngine, emptyPersonalVisualPreferenceProfile,
  localLearningConsent, makePersonalVisualLearningInsight } = require("../.test-output/index.js");
const frame = (id, sharpness, exposure = 0.8) => ({
  id, sequenceIndex: 0, byteCount: 100, quality: { sharpness, exposure },
});

test("measured sharpness wins over file size and order", () => {
  const review = builder.makeReview([
    { ...frame("blur", 0.1), byteCount: 999999 },
    { ...frame("sharp", 0.9), sequenceIndex: 100 },
  ]);
  assert.equal(review.bestShotId, "sharp");
  assert.equal(review.rankedShots[0].label, "best");
});

test("byte count and order do not alter equal-quality scores", () => {
  const review = builder.makeReview([frame("a", 0.8), { ...frame("b", 0.8), byteCount: 999999, sequenceIndex: 900 }]);
  assert.equal(review.rankedShots[0].score, review.rankedShots[1].score);
});

test("empty, missing and invalid measurements produce no ranking or coaching", () => {
  for (const frames of [[], [{ id: "missing", sequenceIndex: 0, byteCount: 1 }],
    [frame("nan", NaN)], [frame("infinite", Infinity)], [frame("negative", -0.1)],
    [frame("over", 1.1)], [frame("badExposure", 0.8, NaN)], [frame("overExposure", 0.8, 1.1)]]) {
    const review = builder.makeReview(frames);
    assert.deepEqual(review.rankedShots, []);
    assert.equal(review.bestShotId, undefined);
    assert.equal(review.coachingSummary, undefined);
  }
});

test("valid frames survive invalid neighbors and ranking is capped at three", () => {
  const review = builder.makeReview([frame("invalid", NaN), frame("a", 0.1), frame("b", 0.3), frame("c", 0.7), frame("d", 1)]);
  assert.deepEqual(review.rankedShots.map((shot) => shot.id), ["d", "c", "b"]);
  assert.equal(review.coachingSummary.privacy.singlePhoneOnly, true);
  assert.equal(review.coachingSummary.privacy.uploadsLiveCameraFrame, false);
});

test("exposure contributes to selection and boundary measurements are accepted", () => {
  const review = builder.makeReview([frame("clipped", 0.8, 0), frame("unclipped", 0.8, 1)]);
  assert.equal(review.bestShotId, "unclipped");
  assert.equal(review.rankedShots.length, 2);
});

test("creative interpretation executes production helpers and honors consent", () => {
  const spec = JSON.parse(fs.readFileSync(path.join(root, "../../tests/fixtures/cinematic-portrait.shotspec.json"), "utf8"));
  const profile = emptyPersonalVisualPreferenceProfile({ ...localLearningConsent, onlineReferencesAllowed: true });
  const engine = new PersonalVisualLearningEngine();
  const plan = engine.makeCreativeInterpretationPlan(spec, "cinematic portrait inspiration", profile);
  assert.ok(plan.suggestions.length > 0);
  assert.ok(plan.inputSummary.includes("Scene: Portrait"));
  assert.equal(plan.privacy.sendsRawCameraFrame, false);
  assert.equal(engine.makeCreativeInterpretationPlan(spec, "inspiration", profile, undefined,
    { ...profile.consent, onlineReferencesAllowed: false }), undefined);
});

test("learning insight ranks aggregate choices and suppresses signals when disabled", () => {
  const profile = { ...emptyPersonalVisualPreferenceProfile(localLearningConsent), totalEvents: 5,
    domainCounts: { portrait: 5 }, styleAffinities: { cinematic: 0.6 } };
  const insight = makePersonalVisualLearningInsight(profile, 1);
  assert.equal(insight.status, "personalized");
  assert.equal(insight.topSignals[0].label, "Portrait");
  assert.equal(insight.topSignals.length, 1);
  const disabled = makePersonalVisualLearningInsight({ ...profile, consent: { ...profile.consent, learningEnabled: false } });
  assert.equal(disabled.status, "disabled");
  assert.deepEqual(disabled.topSignals, []);
  assert.deepEqual(disabled.guidanceBoosts, {});
});
