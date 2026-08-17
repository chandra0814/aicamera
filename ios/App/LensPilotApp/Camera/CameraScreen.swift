import Foundation
import LensPilotCamera
import LensPilotCore
import LensPilotDirector
import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CameraScreen: View {
    @StateObject private var viewModel = CameraScreenViewModel()
    @State private var selectedReferenceItem: PhotosPickerItem?
    @State private var isCalibrationReviewPresented = false
    @State private var isPersonalizationSheetPresented = false
    @State private var calibrationReviewDraft = CalibrationReviewDraft()

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
                bestImage: image(from: review.bestPhotoData),
                onLabelCalibration: {
                    viewModel.dismissCaptureReview()
                    DispatchQueue.main.async {
                        isCalibrationReviewPresented = true
                    }
                }
            ) {
                viewModel.dismissCaptureReview()
            }
        }
        .sheet(isPresented: $isCalibrationReviewPresented) {
            CalibrationReviewLabelingSheet(
                draft: $calibrationReviewDraft,
                reviewImage: lastCaptureImage,
                exportJSON: {
                    viewModel.makeReviewedCalibrationSampleExport(review: calibrationReviewDraft.makeReviewLabel())
                },
                onDone: {
                    isCalibrationReviewPresented = false
                }
            )
        }
        .sheet(isPresented: $isPersonalizationSheetPresented) {
            PersonalVisualAiSettingsSheet(viewModel: viewModel)
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

            Button {
                isPersonalizationSheetPresented = true
            } label: {
                Image(systemName: viewModel.personalizationConsent.learningEnabled ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Open Personal Visual AI settings")

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
            if let plan = viewModel.onlineReferencePlan {
                OnlineInspirationStatusButton(plan: plan) {
                    isPersonalizationSheetPresented = true
                }
            }

            HStack(spacing: 8) {
                TextField("Describe the photo", text: $viewModel.intentText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)

                Button {
                    viewModel.toggleSpeechIntentInput()
                } label: {
                    Image(systemName: viewModel.speechIntentState.iconName)
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(
                            viewModel.speechIntentState.isActive
                                ? Color.white.opacity(0.9)
                                : Color.black.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .foregroundStyle(viewModel.speechIntentState.isActive ? Color.black : Color.white)
                .accessibilityLabel(viewModel.speechIntentState.accessibilityLabel)
                .disabled(!viewModel.speechIntentState.allowsToggle)

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

            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedReferenceItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Add reference photo")

                ShareLink(item: viewModel.makeCalibrationSampleExport()) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Export calibration sample")

                Button {
                    isCalibrationReviewPresented = true
                } label: {
                    Image(systemName: "tag")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Label calibration review")
                .disabled(viewModel.lastCalibrationCandidate == nil)
                .opacity(viewModel.lastCalibrationCandidate == nil ? 0.45 : 1)

                Button {
                    viewModel.capture()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 64, height: 64)
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
                        .frame(width: 42, height: 42)
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

    private var lastCaptureImage: Image? {
        guard let data = viewModel.lastCaptureData else {
            return nil
        }

        return image(from: data)
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

private struct OnlineInspirationStatusButton: View {
    let plan: OnlineReferencePlan
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.reason.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(plan.searchQueries.count) public queries ready")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open online inspiration details")
    }
}

private struct PersonalVisualAiSettingsSheet: View {
    @ObservedObject var viewModel: CameraScreenViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.personalizationConsent.learningEnabled },
                        set: { viewModel.setLocalPersonalLearningEnabled($0) }
                    )) {
                        Label("Local Learning", systemImage: "iphone")
                    }

                    Toggle(isOn: Binding(
                        get: { viewModel.personalizationConsent.onlineReferencesAllowed },
                        set: { viewModel.setOnlineInspirationEnabled($0) }
                    )) {
                        Label("Online Inspiration", systemImage: "globe")
                    }
                }

                Section("Profile") {
                    LabeledContent("Events", value: "\(viewModel.personalProfile.totalEvents)")
                    LabeledContent("Top Style", value: viewModel.personalProfile.topStyleLabel)
                    LabeledContent("Top Framing", value: viewModel.personalProfile.topFramingLabel)
                    LabeledContent("Top Guidance", value: viewModel.personalProfile.topGuidanceLabel)
                    LabeledContent("Online References", value: "\(viewModel.personalProfile.onlineReferenceUsageCount)")
                }

                if let plan = viewModel.onlineReferencePlan {
                    Section("Online Plan") {
                        LabeledContent("Reason", value: plan.reason.title)
                        LabeledContent("Inputs", value: plan.allowedInputs.map(\.title).joined(separator: ", "))

                        Button {
                            viewModel.fetchOnlineInspirationReferences()
                        } label: {
                            Label(viewModel.onlineInspirationLoadState.actionTitle, systemImage: viewModel.onlineInspirationLoadState.actionIcon)
                        }
                        .disabled(viewModel.onlineInspirationLoadState.isLoading)

                        ForEach(plan.searchQueries.prefix(3), id: \.self) { query in
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text(query)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if viewModel.onlineInspirationLoadState.isLoading {
                    Section("Public References") {
                        HStack {
                            ProgressView()
                            Text("Loading")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if viewModel.onlineInspirationLoadState.isLoadedEmpty {
                    Section("Public References") {
                        Label("No matches", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                } else if let message = viewModel.onlineInspirationLoadState.failureMessage {
                    Section("Public References") {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.onlineInspirationResults.isEmpty {
                    Section("Public References") {
                        ForEach(viewModel.onlineInspirationResults.prefix(6)) { result in
                            OnlineInspirationResultRow(
                                result: result,
                                thumbnailImage: thumbnailImage(for: result)
                            ) {
                                viewModel.useOnlineInspirationReference(result)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.resetPersonalVisualLearning()
                    } label: {
                        Label("Delete Learned Profile", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Personal Visual AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Personal Visual AI settings")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func thumbnailImage(for result: OnlineInspirationResult) -> Image? {
        #if canImport(UIKit)
        guard
            let data = viewModel.cachedOnlineInspirationThumbnailData(for: result),
            let uiImage = UIImage(data: data)
        else {
            return nil
        }

        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}

private struct OnlineInspirationResultRow: View {
    let result: OnlineInspirationResult
    let thumbnailImage: Image?
    let onUseReference: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color.secondary.opacity(0.12)

                if let thumbnailImage {
                    thumbnailImage
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(result.license ?? "Public source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Link(destination: result.pageURL) {
                Image(systemName: "arrow.up.right.square")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open public source")

            Button(action: onUseReference) {
                Image(systemName: "plus.viewfinder")
                    .font(.headline)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use as reference popup")
        }
        .padding(.vertical, 4)
    }
}

private struct CalibrationReviewDraft {
    var domain = CalibrationSample.CalibrationDomain.portrait
    var reviewCount = 2
    var preferredGuidanceReason = GuidanceAction.Reason.reduceClutter
    var rankedWeaknesses: [CalibrationSample.CalibrationWeakness] = [.background, .lighting]
    var notes = ""

    mutating func toggleWeakness(_ weakness: CalibrationSample.CalibrationWeakness) {
        if let index = rankedWeaknesses.firstIndex(of: weakness) {
            guard rankedWeaknesses.count > 1 else { return }
            rankedWeaknesses.remove(at: index)
        } else {
            rankedWeaknesses.append(weakness)
        }
    }

    func makeReviewLabel() -> CalibrationSample.ReviewLabel {
        CalibrationSample.ReviewLabel(
            domain: domain,
            reviewCount: reviewCount,
            preferredGuidanceReason: preferredGuidanceReason,
            rankedWeaknesses: rankedWeaknesses,
            notes: notes
        )
    }
}

private struct CalibrationReviewLabelingSheet: View {
    @Binding var draft: CalibrationReviewDraft
    let reviewImage: Image?
    let exportJSON: () -> String
    let onDone: () -> Void

    private let guidanceReasons: [GuidanceAction.Reason] = [
        .reduceClutter,
        .improveFaceLight,
        .levelHorizon,
        .protectHighlights,
        .reduceMotionBlur,
        .improvePose,
        .matchReference,
        .readyToCapture
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.88))
                            .aspectRatio(4.0 / 5.0, contentMode: .fit)

                        if let reviewImage {
                            reviewImage
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 48, weight: .regular))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                Section {
                    Picker("Domain", selection: $draft.domain) {
                        ForEach(CalibrationSample.CalibrationDomain.allCases, id: \.self) { domain in
                            Text(domain.title).tag(domain)
                        }
                    }

                    Stepper(value: $draft.reviewCount, in: 2...8) {
                        Text("Blind reviews: \(draft.reviewCount)")
                    }

                    Picker("Preferred fix", selection: $draft.preferredGuidanceReason) {
                        ForEach(guidanceReasons, id: \.self) { reason in
                            Text(reason.title).tag(reason)
                        }
                    }
                }

                Section("Ranked Weaknesses") {
                    ForEach(CalibrationSample.CalibrationWeakness.allCases, id: \.self) { weakness in
                        Button {
                            draft.toggleWeakness(weakness)
                        } label: {
                            HStack {
                                Text(weakness.title)
                                Spacer()
                                if let index = draft.rankedWeaknesses.firstIndex(of: weakness) {
                                    Text("#\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ShareLink(item: exportJSON()) {
                        Label("Export reviewed sample", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Blind Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close calibration review")
                }
            }
        }
    }
}

private extension CalibrationSample.CalibrationDomain {
    var title: String {
        switch self {
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        case .lifestyle:
            return "Lifestyle"
        case .night:
            return "Night"
        }
    }
}

private extension CalibrationSample.CalibrationWeakness {
    var title: String {
        switch self {
        case .composition:
            return "Composition"
        case .subjectPosition:
            return "Subject position"
        case .cameraAngle:
            return "Camera angle"
        case .lighting:
            return "Lighting"
        case .background:
            return "Background"
        case .horizon:
            return "Horizon"
        case .pose:
            return "Pose"
        case .sharpnessProbability:
            return "Sharpness"
        case .exposure:
            return "Exposure"
        case .intentMatch:
            return "Intent match"
        }
    }
}

private extension GuidanceAction.Reason {
    var title: String {
        switch self {
        case .improveSubjectBackgroundSeparation:
            return "Improve separation"
        case .levelHorizon:
            return "Level horizon"
        case .protectHighlights:
            return "Protect highlights"
        case .improveFaceLight:
            return "Improve face light"
        case .reduceClutter:
            return "Reduce clutter"
        case .matchReference:
            return "Match reference"
        case .improvePose:
            return "Improve pose"
        case .increaseSky:
            return "Increase sky"
        case .reduceMotionBlur:
            return "Reduce motion blur"
        case .readyToCapture:
            return "Ready to capture"
        }
    }
}

private extension PersonalVisualPreferenceProfile {
    var topStyleLabel: String {
        topAffinityLabel(in: styleAffinities)
    }

    var topFramingLabel: String {
        topAffinityLabel(in: framingAffinities)
    }

    var topGuidanceLabel: String {
        topAffinityLabel(in: guidanceReasonAffinities)
    }

    func topAffinityLabel(in affinities: [String: Double]) -> String {
        guard let key = affinities
            .filter({ $0.value > 0 })
            .max(by: { $0.value < $1.value })?
            .key
        else {
            return "None"
        }

        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension OnlineReferencePlan.Reason {
    var title: String {
        switch self {
        case .explicitUserRequest:
            return "Requested Inspiration"
        case .specializedStyle:
            return "Style Inspiration"
        case .insufficientPersonalHistory:
            return "New Preference"
        }
    }
}

private extension OnlineReferencePlan.AllowedInput {
    var title: String {
        switch self {
        case .promptText:
            return "Prompt"
        case .shotSpecSummary:
            return "Shot Plan"
        case .deviceCapabilitySummary:
            return "Device"
        }
    }
}

private extension OnlineInspirationLoadState {
    var actionTitle: String {
        switch self {
        case .idle:
            return "Fetch Public References"
        case .loading:
            return "Fetching"
        case let .loaded(count):
            return count > 0 ? "Refresh Public References" : "Try Again"
        case .failed:
            return "Try Again"
        }
    }

    var actionIcon: String {
        switch self {
        case .loading:
            return "hourglass"
        case .loaded:
            return "arrow.clockwise"
        case .failed:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .idle:
            return "globe"
        }
    }

    var isLoading: Bool {
        self == .loading
    }

    var isLoadedEmpty: Bool {
        if case .loaded(0) = self {
            return true
        }

        return false
    }

    var failureMessage: String? {
        if case let .failed(message) = self {
            return message
        }

        return nil
    }
}

private extension SpeechIntentState {
    var iconName: String {
        switch self {
        case .idle, .unavailable, .failed:
            return "mic"
        case .requestingPermission, .finalizing:
            return "hourglass"
        case .listening:
            return "mic.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .requestingPermission, .listening, .finalizing:
            return true
        case .idle, .unavailable, .failed:
            return false
        }
    }

    var allowsToggle: Bool {
        switch self {
        case .requestingPermission, .finalizing:
            return false
        case .idle, .listening, .unavailable, .failed:
            return true
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .listening:
            return "Stop voice request"
        case .requestingPermission:
            return "Requesting voice permission"
        case .finalizing:
            return "Finalizing voice request"
        case .idle, .unavailable, .failed:
            return "Start voice request"
        }
    }
}
