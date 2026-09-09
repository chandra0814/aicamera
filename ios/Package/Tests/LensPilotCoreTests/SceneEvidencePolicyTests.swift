import Foundation
import LensPilotCore
import XCTest

final class SceneEvidencePolicyTests: XCTestCase {
    func testRejectsMissingAndSyntheticEvidence() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(SceneEvidencePolicy.accepts(frameId: "", timestamp: now, now: now))
        XCTAssertFalse(SceneEvidencePolicy.accepts(frameId: "  ", timestamp: now, now: now))
        XCTAssertFalse(SceneEvidencePolicy.accepts(frameId: "placeholder_frame", timestamp: now, now: now))
    }

    func testFreshEvidenceExpiresAndFutureEvidenceIsRejected() {
        let timestamp = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(SceneEvidencePolicy.accepts(frameId: "real", timestamp: timestamp, now: timestamp))
        XCTAssertTrue(SceneEvidencePolicy.accepts(frameId: "real", timestamp: timestamp, now: timestamp.addingTimeInterval(2.99)))
        XCTAssertFalse(SceneEvidencePolicy.accepts(frameId: "real", timestamp: timestamp, now: timestamp.addingTimeInterval(3)))
        XCTAssertFalse(SceneEvidencePolicy.accepts(frameId: "real", timestamp: timestamp, now: timestamp.addingTimeInterval(-1)))
    }
}
