import LensPilotDirector
import SwiftUI

struct ReferenceViewer: View {
    @ObservedObject var state: SinglePhoneDirectorState

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.86))
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)

                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 24)

                if let notes = state.referencePhoto?.extractedFeatures?.achievableTranslationNotes, !notes.isEmpty {
                    Text(notes[0])
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
            .navigationTitle("Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        state.closeReferenceViewer()
                    }
                }
            }
        }
    }
}
