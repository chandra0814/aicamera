import Foundation

public struct CaptureFrameMetric: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sequenceIndex: Int
    public let byteCount: Int

    public init(id: String, sequenceIndex: Int, byteCount: Int) {
        self.id = id
        self.sequenceIndex = sequenceIndex
        self.byteCount = byteCount
    }
}

public struct CaptureReviewResult: Codable, Equatable, Sendable {
    public let rankedShots: [RankedShot]
    public let bestShotId: String?
    public let coachingSummary: CaptureCoachingSummary?

    public init(
        rankedShots: [RankedShot],
        bestShotId: String?,
        coachingSummary: CaptureCoachingSummary? = nil
    ) {
        self.rankedShots = rankedShots
        self.bestShotId = bestShotId
        self.coachingSummary = coachingSummary
    }
}

public struct CaptureCoachingSummary: Codable, Equatable, Sendable {
    public let headline: String
    public let bestShotScore: Double
    public let targetMatch: Double?
    public let positiveSignals: [Signal]
    public let improvementSignals: [Signal]
    public let topCorrectionReason: GuidanceAction.Reason?
    public let nextShotInstruction: String?
    public let privacy: Privacy

    public init(
        headline: String,
        bestShotScore: Double,
        targetMatch: Double?,
        positiveSignals: [Signal],
        improvementSignals: [Signal],
        topCorrectionReason: GuidanceAction.Reason?,
        nextShotInstruction: String?,
        privacy: Privacy = Privacy()
    ) {
        self.headline = headline
        self.bestShotScore = clamp01(bestShotScore)
        self.targetMatch = targetMatch.map(clamp01)
        self.positiveSignals = positiveSignals
        self.improvementSignals = improvementSignals
        self.topCorrectionReason = topCorrectionReason
        self.nextShotInstruction = nextShotInstruction
        self.privacy = privacy
    }
}

public extension CaptureCoachingSummary {
    struct Signal: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let value: Double
        public let reason: GuidanceAction.Reason?

        public init(id: String, title: String, value: Double, reason: GuidanceAction.Reason?) {
            self.id = id
            self.title = title
            self.value = clamp01(value)
            self.reason = reason
        }
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let identityRecognitionAllowed: Bool

        public init(
            singlePhoneOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            identityRecognitionAllowed: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.identityRecognitionAllowed = identityRecognitionAllowed
        }
    }
}

public struct CaptureReviewBuilder: Sendable {
    private let ranker: BestShotRanker

    public init(ranker: BestShotRanker = BestShotRanker()) {
        self.ranker = ranker
    }

    public func makeReview(frames: [CaptureFrameMetric], targetMatch: TargetMatchScore?) -> CaptureReviewResult {
        guard !frames.isEmpty else {
            return CaptureReviewResult(rankedShots: [], bestShotId: nil)
        }

        let candidates = frames.map { frame in
            candidate(for: frame, targetMatch: targetMatch)
        }
        let rankedShots = ranker.rank(candidates)
        let coachingSummary = CaptureCoachingSummaryBuilder().makeSummary(
            rankedShots: rankedShots,
            targetMatch: targetMatch
        )

        return CaptureReviewResult(
            rankedShots: rankedShots,
            bestShotId: rankedShots.first?.id,
            coachingSummary: coachingSummary
        )
    }

    private func candidate(for frame: CaptureFrameMetric, targetMatch: TargetMatchScore?) -> BestShotCandidate {
        let qualitySignal = Double((frame.byteCount + frame.sequenceIndex * 31) % 23) / 100
        let orderPenalty = Double(frame.sequenceIndex) * 0.015
        let sharpness = clamp01(0.76 + qualitySignal - orderPenalty)
        let exposure = targetMatch?.exposure ?? 0.72
        let pose = targetMatch?.pose ?? 0.72
        let composition = targetMatch?.composition ?? 0.72
        let background = targetMatch?.background ?? 0.72
        let intentMatch = targetMatch?.intentMatch ?? targetMatch?.overall ?? 0.72

        return BestShotCandidate(
            id: frame.id,
            sharpness: sharpness,
            exposure: exposure,
            faceQuality: pose,
            poseScore: pose,
            composition: composition,
            background: background,
            intentMatch: intentMatch
        )
    }
}

private struct CaptureCoachingSummaryBuilder {
    func makeSummary(
        rankedShots: [RankedShot],
        targetMatch: TargetMatchScore?
    ) -> CaptureCoachingSummary? {
        guard let bestShot = rankedShots.first else { return nil }

        let improvementSignals = Self.improvementSignals(from: targetMatch)
        let topReason = improvementSignals.first?.reason

        return CaptureCoachingSummary(
            headline: Self.headline(bestShotScore: bestShot.score, targetMatch: targetMatch?.overall),
            bestShotScore: bestShot.score,
            targetMatch: targetMatch?.overall,
            positiveSignals: Self.positiveSignals(from: targetMatch, bestShot: bestShot),
            improvementSignals: improvementSignals,
            topCorrectionReason: topReason,
            nextShotInstruction: topReason.map(Self.nextShotInstruction)
        )
    }

    private static func positiveSignals(
        from targetMatch: TargetMatchScore?,
        bestShot: RankedShot
    ) -> [CaptureCoachingSummary.Signal] {
        if let targetMatch {
            let strongMetrics = metrics(from: targetMatch)
                .filter { $0.value >= 0.8 }
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.id < rhs.id
                    }

                    return lhs.value > rhs.value
                }
                .prefix(3)

            if !strongMetrics.isEmpty {
                return strongMetrics.map(\.signal)
            }
        }

        return bestShot.reasons.prefix(2).map { reason in
            CaptureCoachingSummary.Signal(
                id: reason,
                title: displayTitle(reason),
                value: bestShot.score,
                reason: nil
            )
        }
    }

    private static func improvementSignals(from targetMatch: TargetMatchScore?) -> [CaptureCoachingSummary.Signal] {
        guard let targetMatch else { return [] }

        let weakMetrics = metrics(from: targetMatch)
            .filter { $0.value < 0.78 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.id < rhs.id
                }

                return lhs.value < rhs.value
            }
            .prefix(2)

        return weakMetrics.map(\.signal)
    }

    private static func headline(bestShotScore: Double, targetMatch: Double?) -> String {
        let matchScore = targetMatch ?? bestShotScore

        if matchScore >= 0.88 && bestShotScore >= 0.85 {
            return "Strong match"
        }

        if matchScore >= 0.72 {
            return "Good direction"
        }

        return "Needs another pass"
    }

    private static func nextShotInstruction(for reason: GuidanceAction.Reason) -> String {
        switch reason {
        case .improveSubjectBackgroundSeparation:
            return "Next shot: improve framing"
        case .levelHorizon:
            return "Next shot: level the horizon"
        case .protectHighlights:
            return "Next shot: protect highlights"
        case .improveFaceLight:
            return "Next shot: turn toward cleaner light"
        case .reduceClutter:
            return "Next shot: clean the background"
        case .matchReference:
            return "Next shot: match the reference angle"
        case .improvePose:
            return "Next shot: settle the pose"
        case .increaseSky:
            return "Next shot: show more sky"
        case .reduceMotionBlur:
            return "Next shot: hold steadier"
        case .readyToCapture:
            return "Next shot: hold this timing"
        }
    }

    private static func metrics(from score: TargetMatchScore) -> [Metric] {
        [
            Metric(id: "composition", title: "Composition", value: score.composition, reason: .improveSubjectBackgroundSeparation),
            Metric(id: "subject_position", title: "Subject Position", value: score.subjectPosition, reason: .improveSubjectBackgroundSeparation),
            Metric(id: "camera_angle", title: "Camera Angle", value: score.cameraAngle, reason: .matchReference),
            Metric(id: "lighting", title: "Lighting", value: score.lighting, reason: .improveFaceLight),
            Metric(id: "background", title: "Background", value: score.background, reason: .reduceClutter),
            Metric(id: "horizon", title: "Horizon", value: score.horizon, reason: .levelHorizon),
            Metric(id: "pose", title: "Pose", value: score.pose, reason: .improvePose),
            Metric(id: "sharpness", title: "Sharpness", value: score.sharpnessProbability, reason: .reduceMotionBlur),
            Metric(id: "exposure", title: "Exposure", value: score.exposure, reason: .protectHighlights),
            Metric(id: "intent_match", title: "Intent Match", value: score.intentMatch, reason: .matchReference)
        ]
    }

    private static func displayTitle(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    private struct Metric {
        let id: String
        let title: String
        let value: Double
        let reason: GuidanceAction.Reason

        var signal: CaptureCoachingSummary.Signal {
            CaptureCoachingSummary.Signal(id: id, title: title, value: value, reason: reason)
        }
    }
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value.isFinite ? value : 0))
}
