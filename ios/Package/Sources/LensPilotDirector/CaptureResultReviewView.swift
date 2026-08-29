import LensPilotCore
import SwiftUI

public struct CaptureResultReviewView: View {
    private let rankedShots: [RankedShot]
    private let bestImage: Image?
    private let onKeepResult: (() -> Void)?
    private let onRejectResult: (() -> Void)?
    private let onRejectWithReason: ((GuidanceAction.Reason) -> Void)?
    private let onLabelCalibration: (() -> Void)?
    private let onDone: () -> Void

    public init(
        rankedShots: [RankedShot],
        bestImage: Image? = nil,
        onKeepResult: (() -> Void)? = nil,
        onRejectResult: (() -> Void)? = nil,
        onRejectWithReason: ((GuidanceAction.Reason) -> Void)? = nil,
        onLabelCalibration: (() -> Void)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.rankedShots = rankedShots
        self.bestImage = bestImage
        self.onKeepResult = onKeepResult
        self.onRejectResult = onRejectResult
        self.onRejectWithReason = onRejectWithReason
        self.onLabelCalibration = onLabelCalibration
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Result")
                    .font(.headline)
                Spacer()
                if let onLabelCalibration {
                    Button(action: onLabelCalibration) {
                        Image(systemName: "tag")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Label calibration review")
                }
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close result review")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.88))
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)

                if let bestImage {
                    bestImage
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            VStack(spacing: 8) {
                ForEach(rankedShots) { shot in
                    HStack(spacing: 10) {
                        Image(systemName: shot.label == .best ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(shot.label == .best ? Color.green : Color.secondary)
                        Text(shot.label == .best ? "Best" : "Alternative")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(shot.score * 100))%")
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 10) {
                if let onRejectWithReason {
                    Menu {
                        ForEach(Self.feedbackReasons, id: \.rawValue) { reason in
                            Button {
                                onRejectWithReason(reason)
                            } label: {
                                Label(reason.feedbackTitle, systemImage: reason.feedbackIconName)
                            }
                        }

                        if let onRejectResult {
                            Button(role: .destructive, action: onRejectResult) {
                                Label("Not Sure", systemImage: "questionmark.circle")
                            }
                        }
                    } label: {
                        Label("Needs Work", systemImage: "hand.thumbsdown")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Tell LensPilot what needs work")
                } else if let onRejectResult {
                    Button(action: onRejectResult) {
                        Label("Needs Work", systemImage: "hand.thumbsdown")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Teach LensPilot this result needs work")
                }

                if let onKeepResult {
                    Button(action: onKeepResult) {
                        Label("Keep", systemImage: "hand.thumbsup.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Teach LensPilot this result is good")
                }
            }
        }
        .padding(18)
    }

    private static let feedbackReasons: [GuidanceAction.Reason] = [
        .improveFaceLight,
        .reduceClutter,
        .levelHorizon,
        .improvePose,
        .reduceMotionBlur,
        .protectHighlights,
        .matchReference,
        .increaseSky,
        .improveSubjectBackgroundSeparation
    ]
}

private extension GuidanceAction.Reason {
    var feedbackTitle: String {
        switch self {
        case .improveSubjectBackgroundSeparation:
            return "Framing"
        case .levelHorizon:
            return "Horizon"
        case .protectHighlights:
            return "Exposure"
        case .improveFaceLight:
            return "Lighting"
        case .reduceClutter:
            return "Background"
        case .matchReference:
            return "Reference Match"
        case .improvePose:
            return "Pose"
        case .increaseSky:
            return "More Sky"
        case .reduceMotionBlur:
            return "Sharpness"
        case .readyToCapture:
            return "Timing"
        }
    }

    var feedbackIconName: String {
        switch self {
        case .improveSubjectBackgroundSeparation:
            return "viewfinder"
        case .levelHorizon:
            return "gyroscope"
        case .protectHighlights:
            return "sun.max"
        case .improveFaceLight:
            return "light.max"
        case .reduceClutter:
            return "rectangle.compress.vertical"
        case .matchReference:
            return "photo.on.rectangle"
        case .improvePose:
            return "figure.stand"
        case .increaseSky:
            return "cloud.sun"
        case .reduceMotionBlur:
            return "camera.aperture"
        case .readyToCapture:
            return "timer"
        }
    }
}
