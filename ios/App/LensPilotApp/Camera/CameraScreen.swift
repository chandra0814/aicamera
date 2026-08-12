import LensPilotCamera
import LensPilotDirector
import SwiftUI

struct CameraScreen: View {
    @StateObject private var viewModel = CameraScreenViewModel()

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            CameraOverlayChrome(state: viewModel.directorState)

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
            ReferenceViewer(state: viewModel.directorState)
        }
        .task {
            viewModel.start()
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
                Button {
                    viewModel.activateMockReference()
                } label: {
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
                    Circle()
                        .fill(.white)
                        .frame(width: 74, height: 74)
                        .overlay(
                            Circle()
                                .stroke(.black.opacity(0.55), lineWidth: 3)
                                .padding(6)
                        )
                }
                .accessibilityLabel("Capture photo")

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
}
