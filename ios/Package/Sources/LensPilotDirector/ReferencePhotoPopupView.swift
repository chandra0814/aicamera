import LensPilotCore
import SwiftUI

public struct ReferencePhotoPopupView: View {
    private let referencePhoto: ReferencePhotoState
    private let thumbnail: Image?
    private let onSelect: () -> Void

    public init(referencePhoto: ReferencePhotoState, thumbnail: Image? = nil, onSelect: @escaping () -> Void) {
        self.referencePhoto = referencePhoto
        self.thumbnail = thumbnail
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.45))
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)

                    if let thumbnail {
                        thumbnail
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 72, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    statusIndicator
                        .padding(5)
                }

                Text("Reference")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(8)
            .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open reference photo")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch referencePhoto.analysisStatus {
        case .notStarted:
            Circle().fill(.gray).frame(width: 8, height: 8)
        case .analyzing:
            ProgressView().controlSize(.mini).tint(.white)
        case .ready:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        }
    }
}

public struct CameraOverlayChrome: View {
    @ObservedObject private var state: SinglePhoneDirectorState
    private let referenceThumbnail: Image?

    public init(state: SinglePhoneDirectorState, referenceThumbnail: Image? = nil) {
        self.state = state
        self.referenceThumbnail = referenceThumbnail
    }

    public var body: some View {
        ZStack {
            if let targetPreview = state.targetPreview {
                TargetCompositionGuideView(targetPreview: targetPreview)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Spacer()
                    if let referencePhoto = state.referencePhoto, referencePhoto.display.showCameraPopup {
                        ReferencePhotoPopupView(referencePhoto: referencePhoto, thumbnail: referenceThumbnail) {
                            state.openReferenceViewer()
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer()

                VStack(spacing: 10) {
                    if let targetPreview = state.targetPreview {
                        TargetPreviewPanelView(targetPreview: targetPreview)
                    }

                    if let instruction = state.primaryInstruction {
                        Text(instruction)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let targetMatch = state.targetMatch {
                        Text("Target Match \(Int(targetMatch * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.bottom, 128)
            }
        }
    }
}

private struct TargetCompositionGuideView: View {
    let targetPreview: TargetPreview

    var body: some View {
        GeometryReader { proxy in
            let bounds = targetPreview.subjectBounds
            let guideWidth = proxy.size.width * bounds.width
            let guideHeight = proxy.size.height * bounds.height
            let centerX = proxy.size.width * (bounds.x + bounds.width / 2)
            let centerY = proxy.size.height * (bounds.y + bounds.height / 2)

            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(width: guideWidth, height: guideHeight)
                .position(x: centerX, y: centerY)

            if let horizonY = targetPreview.horizonY {
                Rectangle()
                    .fill(.white.opacity(0.62))
                    .frame(height: 1)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * horizonY)
            }
        }
    }
}

private struct TargetPreviewPanelView: View {
    let targetPreview: TargetPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(targetPreview.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int(targetPreview.estimatedAchievability * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Text(targetPreview.label.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(targetPreview.label.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))

                Text(targetPreview.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }

            if let disclosure = targetPreview.disclosure {
                Text(disclosure)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }
}

private extension ShotPlan.Label {
    var shortTitle: String {
        switch self {
        case .captureRealistic:
            return "Natural"
        case .enhancedRealistic:
            return "Enhanced"
        case .aiEnhancementRequired:
            return "Creative"
        }
    }

    var tint: Color {
        switch self {
        case .captureRealistic:
            return .green
        case .enhancedRealistic:
            return .blue
        case .aiEnhancementRequired:
            return .yellow
        }
    }
}
