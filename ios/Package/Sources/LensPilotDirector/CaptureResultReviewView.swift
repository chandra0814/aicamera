import LensPilotCore
import SwiftUI

public struct CaptureResultReviewView: View {
    private let rankedShots: [RankedShot]
    private let bestImage: Image?
    private let onLabelCalibration: (() -> Void)?
    private let onDone: () -> Void

    public init(
        rankedShots: [RankedShot],
        bestImage: Image? = nil,
        onLabelCalibration: (() -> Void)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.rankedShots = rankedShots
        self.bestImage = bestImage
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
        }
        .padding(18)
    }
}
