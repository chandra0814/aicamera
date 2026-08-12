import Combine
import Foundation
import LensPilotCore

@MainActor
public final class SinglePhoneDirectorState: ObservableObject {
    @Published public private(set) var referencePhoto: ReferencePhotoState?
    @Published public private(set) var primaryInstruction: String?
    @Published public private(set) var targetMatch: Double?
    @Published public private(set) var isReferenceViewerPresented = false

    public init() {}

    public func activateReferencePhoto(_ referencePhoto: ReferencePhotoState) {
        var next = referencePhoto
        next.display.showCameraPopup = true
        next.display.viewerState = .collapsedPopup
        self.referencePhoto = next
    }

    public func openReferenceViewer(mode: ReferencePhotoState.ViewerState = .fullReference) {
        guard var referencePhoto else { return }
        referencePhoto.display.viewerState = mode
        self.referencePhoto = referencePhoto
        isReferenceViewerPresented = true
    }

    public func closeReferenceViewer() {
        guard var referencePhoto else {
            isReferenceViewerPresented = false
            return
        }

        referencePhoto.display.viewerState = .collapsedPopup
        referencePhoto.display.showCameraPopup = true
        self.referencePhoto = referencePhoto
        isReferenceViewerPresented = false
    }

    public func clearReferencePhoto() {
        referencePhoto = nil
        isReferenceViewerPresented = false
    }

    public func updateGuidance(instruction: String?, targetMatch: Double?) {
        primaryInstruction = instruction
        self.targetMatch = targetMatch
    }
}
