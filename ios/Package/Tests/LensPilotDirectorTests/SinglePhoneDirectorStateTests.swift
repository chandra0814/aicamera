import LensPilotCore
import LensPilotDirector
import XCTest

final class SinglePhoneDirectorStateTests: XCTestCase {
    @MainActor
    func testReferencePopupSelectionOpensFullReferenceOnSamePhone() throws {
        let state = SinglePhoneDirectorState()
        let incomingReference = Self.referencePhoto(
            showCameraPopup: false,
            viewerState: .referenceVsTarget
        )

        state.activateReferencePhoto(incomingReference)

        let popupReference = try XCTUnwrap(state.referencePhoto)
        XCTAssertTrue(popupReference.display.showCameraPopup)
        XCTAssertEqual(popupReference.display.viewerState, .collapsedPopup)
        XCTAssertEqual(popupReference.localAssetUri, "local://same-phone-reference")
        XCTAssertFalse(popupReference.privacy.cloudAnalysisUsed)
        XCTAssertFalse(state.isReferenceViewerPresented)

        state.openReferenceViewer()

        let openedReference = try XCTUnwrap(state.referencePhoto)
        XCTAssertTrue(state.isReferenceViewerPresented)
        XCTAssertEqual(openedReference.display.viewerState, .fullReference)
        XCTAssertEqual(openedReference.localAssetUri, "local://same-phone-reference")
        XCTAssertFalse(openedReference.privacy.cloudAnalysisUsed)
    }

    @MainActor
    func testClosingFullReferenceReturnsToPopupOnSamePhone() throws {
        let state = SinglePhoneDirectorState()

        state.activateReferencePhoto(Self.referencePhoto())
        state.openReferenceViewer()
        state.closeReferenceViewer()

        let referencePhoto = try XCTUnwrap(state.referencePhoto)
        XCTAssertFalse(state.isReferenceViewerPresented)
        XCTAssertTrue(referencePhoto.display.showCameraPopup)
        XCTAssertEqual(referencePhoto.display.viewerState, .collapsedPopup)
        XCTAssertEqual(referencePhoto.localAssetUri, "local://same-phone-reference")
    }

    private static func referencePhoto(
        showCameraPopup: Bool = true,
        viewerState: ReferencePhotoState.ViewerState = .collapsedPopup
    ) -> ReferencePhotoState {
        ReferencePhotoState(
            id: "same_phone_reference_test",
            source: .photoLibrary,
            localAssetUri: "local://same-phone-reference",
            thumbnailUri: "memory://same-phone-reference/thumbnail",
            analysisStatus: .ready,
            extractedFeatures: ReferencePhotoFeatures(
                framing: "portrait",
                apparentFocalLength: "telephoto",
                cameraHeight: "eye_level",
                subjectScale: 0.6,
                poseHints: ["relaxed_shoulders"],
                lightingDirection: "front_soft",
                colorMood: "warm",
                depthStyle: "shallow",
                achievableTranslationNotes: ["Open and compare this reference on the same phone."]
            ),
            display: .init(
                showCameraPopup: showCameraPopup,
                popupPosition: .topRight,
                viewerState: viewerState
            ),
            privacy: .init(
                cloudAnalysisUsed: false,
                userConsentedToCloudAnalysis: false
            )
        )
    }
}
