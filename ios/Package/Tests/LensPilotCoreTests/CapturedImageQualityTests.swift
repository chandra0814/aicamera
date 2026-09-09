import LensPilotCore
import XCTest

final class CapturedImageQualityTests: XCTestCase {
    func testDetailAndClippingComeFromPixels() throws {
        let detailed = (0..<64).map { UInt8($0 % 2 == 0 ? 80 : 180) }
        let sharp = try XCTUnwrap(CapturedImageQuality.measure(luminance: detailed, width: 8, height: 8))
        let flat = try XCTUnwrap(CapturedImageQuality.measure(luminance: Array(repeating: 130, count: 64), width: 8, height: 8))
        let clipped = try XCTUnwrap(CapturedImageQuality.measure(luminance: Array(repeating: 255, count: 64), width: 8, height: 8))
        XCTAssertGreaterThan(sharp.sharpness, flat.sharpness)
        XCTAssertEqual(flat.exposure, 1)
        XCTAssertEqual(clipped.exposure, 0)
        XCTAssertTrue(sharp.isValid)
        XCTAssertNil(CapturedImageQuality.measure(luminance: [], width: 8, height: 8))
    }

    func testRankingIgnoresBytesAndOrderAndExcludesMissingMeasurements() throws {
        let quality = CapturedImageQuality(sharpness: 0.9, exposure: 0.9)
        let first = CaptureFrameMetric(id: "a", sequenceIndex: 0, byteCount: 1, quality: quality)
        let second = CaptureFrameMetric(id: "b", sequenceIndex: 100, byteCount: 999999, quality: quality)
        let missing = CaptureFrameMetric(id: "missing", sequenceIndex: 0, byteCount: 5000000)
        let review = CaptureReviewBuilder().makeReview(frames: [first, second, missing], targetMatch: nil)
        XCTAssertEqual(review.rankedShots.count, 2)
        XCTAssertEqual(review.rankedShots[0].score, review.rankedShots[1].score)
        let unavailable = CaptureReviewBuilder().makeReview(frames: [missing], targetMatch: nil)
        XCTAssertNil(unavailable.bestShotId)
        XCTAssertNil(unavailable.coachingSummary)
    }

    func testMeasuredSharpFrameBeatsBlurAndInvalidMetricsAreRejected() {
        let frames = [
            CaptureFrameMetric(id: "blur", sequenceIndex: 0, byteCount: 999999, quality: .init(sharpness: 0.1, exposure: 0.8)),
            CaptureFrameMetric(id: "sharp", sequenceIndex: 1, byteCount: 100, quality: .init(sharpness: 0.9, exposure: 0.8)),
            CaptureFrameMetric(id: "invalid", sequenceIndex: 2, byteCount: 999, quality: .init(sharpness: .nan, exposure: 1))
        ]
        let review = CaptureReviewBuilder().makeReview(frames: frames, targetMatch: nil)
        XCTAssertEqual(review.bestShotId, "sharp")
        XCTAssertEqual(review.rankedShots.count, 2)
    }
}
