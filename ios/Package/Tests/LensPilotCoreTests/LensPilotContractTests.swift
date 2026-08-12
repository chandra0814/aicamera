import XCTest
@testable import LensPilotCore

final class LensPilotContractTests: XCTestCase {
    func testShotSpecDefaultsToSinglePhoneOnly() {
        let spec = ShotSpec(
            id: "shot_test_001",
            source: .text,
            originalPrompt: "Give me a cinematic portrait.",
            domain: .portrait,
            subject: .init(primary: .person, count: 1, priority: .subject),
            style: .init(
                name: .cinematic,
                mood: .dramatic,
                colorIntent: .warmHighlightsCoolShadows,
                skinTreatment: .natural
            ),
            composition: .init(
                framing: .environmental,
                headroom: .balanced,
                skyPriority: nil,
                backgroundPriority: .clean,
                horizonPlacement: .auto
            ),
            cameraIntent: .init(
                targetLens: .twoXIfAvailable,
                perspective: .eyeLevel,
                exposureStrategy: .prioritizeFaces,
                focusStrategy: .subjectEye,
                depthIntent: .strongSubjectSeparation
            ),
            constraints: .init(
                realityMode: .natural,
                cloudAllowed: false,
                generativeEditsAllowed: false,
                userSafetyStrictness: .conservative
            ),
            confidence: 0.89,
            missingInfo: []
        )

        XCTAssertTrue(spec.constraints.singlePhoneOnly)
        XCTAssertFalse(spec.subject.identityRecognitionAllowed)
    }

    func testReferencePhotoPopupOpensFullViewerOnSameDevice() {
        var state = ReferencePhotoState(
            id: "ref_test_001",
            source: .photoLibrary,
            localAssetUri: "ph://asset",
            thumbnailUri: "cache://thumb.jpg",
            analysisStatus: .ready,
            extractedFeatures: nil,
            display: .init(
                showCameraPopup: true,
                popupPosition: .topRight,
                viewerState: .collapsedPopup
            ),
            privacy: .init(cloudAnalysisUsed: false, userConsentedToCloudAnalysis: false)
        )

        XCTAssertTrue(state.display.showCameraPopup)
        XCTAssertEqual(state.display.viewerState, .collapsedPopup)

        state.display.viewerState = .fullReference

        XCTAssertEqual(state.display.viewerState, .fullReference)
        XCTAssertFalse(state.privacy.cloudAnalysisUsed)
    }
}
