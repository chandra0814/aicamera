import Foundation
import LensPilotCamera
import LensPilotDirector
import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CameraScreen: View {
    @StateObject private var viewModel = CameraScreenViewModel()
    @State private var selectedReferenceItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            CameraOverlayChrome(state: viewModel.directorState, referenceThumbnail: referenceImage)

            VStack {
                topBar
                Spacer()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(.black)
        .sheet(isPresented: Binding(
            get: { viewModel.directorState.isReferenceViewerPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.directorState.closeReferenceViewer()
                }
            }
        )) {
            ReferenceViewer(state: viewModel.directorState, referenceImage: referenceImage)
        }
        .sheet(item: Binding<CaptureReviewPresentation?>(
            get: { viewModel.captureReview },
            set: { review in
                if case .none = review {
                    viewModel.dismissCaptureReview()
                }
            }
        )) { review in
            CaptureResultReviewView(
                rankedShots: review.rankedShots,
                bestImage: image(from: review.bestPhotoData)
            ) {
                viewModel.dismissCaptureReview()
            }
        }
        .task {
            viewModel.start()
        }
        .onChange(of: selectedReferenceItem) { _, item in
            Task {
                await activateReferencePhoto(from: item)
                selectedReferenceItem = nil
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleSelfShotCamera()
            } label: {
                Image(systemName: viewModel.usesFrontCameraForSelfShot ? "person.crop.square" : "camera.rotate")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Switch single phone camera")

            Spacer()

            Text("Single Phone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Describe the photo", text: $viewModel.intentText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)

                Button {
                    viewModel.makePlanFromIntent()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.black)
                .accessibilityLabel("Create shot plan")
            }

            HStack(spacing: 16) {
                PhotosPicker(selection: $selectedReferenceItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Add reference photo")

                Button {
                    viewModel.capture()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 74, height: 74)
                            .overlay(
                                Circle()
                                    .stroke(.black.opacity(0.55), lineWidth: 3)
                                    .padding(6)
                            )

                        if viewModel.isCapturing {
                            ProgressView()
                                .tint(.black)
                        }
                    }
                }
                .accessibilityLabel("Capture photo")
                .disabled(viewModel.isCapturing)
                .opacity(viewModel.isCapturing ? 0.78 : 1)

                Button {
                    viewModel.directorState.updateGuidance(instruction: "Hold steady", targetMatch: 0.92)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Simulate ready state")
            }
        }
    }

    private var referenceImage: Image? {
        #if canImport(UIKit)
        guard
            let data = viewModel.referenceImageData,
            let uiImage = UIImage(data: data)
        else {
            return nil
        }

        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }

    @MainActor
    private func activateReferencePhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                viewModel.failReferencePhotoLoad()
                return
            }

            viewModel.activateReferencePhoto(imageData: imageData, assetIdentifier: item.itemIdentifier)
        } catch {
            viewModel.failReferencePhotoLoad(error)
        }
    }

    private func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else {
            return nil
        }

        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
