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

    public init(rankedShots: [RankedShot], bestShotId: String?) {
        self.rankedShots = rankedShots
        self.bestShotId = bestShotId
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

        return CaptureReviewResult(rankedShots: rankedShots, bestShotId: rankedShots.first?.id)
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

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value))
}
