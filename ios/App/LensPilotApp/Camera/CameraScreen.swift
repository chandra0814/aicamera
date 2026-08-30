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
    @State private var isCalibrationQueuePresented = false
    @State private var isPersonalizationSheetPresented = false
    @State private var isDiagnosticsSheetPresented = false
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
                coachingSummary: review.coachingSummary,
                onKeepResult: {
                    viewModel.keepLatestCaptureResult()
                },
                onRejectResult: {
                    viewModel.rejectLatestCaptureResult()
                },
                onRejectWithReason: { reason in
                    viewModel.rejectLatestCaptureResult(reason: reason)
                },
                onLabelCalibration: {
                    prepareCalibrationReviewDraft()
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
        .sheet(isPresented: $isDiagnosticsSheetPresented) {
            AiDiagnosticsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isCalibrationQueuePresented) {
            CalibrationCaptureQueueSheet(
                progress: viewModel.calibrationQueueProgress,
                activeScenario: viewModel.activeCalibrationScenario,
                onSelect: { scenario in
                    viewModel.selectCalibrationScenario(scenario)
                    calibrationReviewDraft.applyScenario(scenario)
                    isCalibrationQueuePresented = false
                },
                onReset: {
                    viewModel.resetCalibrationQueue()
                    calibrationReviewDraft = CalibrationReviewDraft()
                },
                onDone: {
                    isCalibrationQueuePresented = false
                }
            )
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

            Button {
                isDiagnosticsSheetPresented = true
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Open AI diagnostics")

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
            CalibrationQueueStatusButton(
                progress: viewModel.calibrationQueueProgress,
                activeScenario: viewModel.activeCalibrationScenario
            ) {
                isCalibrationQueuePresented = true
            }

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

                Menu {
                    ForEach(PreviewAdjustmentCommand.allCases) { command in
                        Button {
                            viewModel.applyPreviewAdjustment(command)
                        } label: {
                            Label(command.title, systemImage: command.iconName)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Adjust target preview")

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
                    prepareCalibrationReviewDraft()
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

    private func prepareCalibrationReviewDraft() {
        guard let scenario = viewModel.lastCalibrationScenario ?? viewModel.activeCalibrationScenario else { return }
        calibrationReviewDraft.applyScenario(scenario)
    }
}

private struct CalibrationQueueStatusButton: View {
    let progress: CalibrationCaptureQueueProgress
    let activeScenario: CalibrationCaptureScenario?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: activeScenario?.symbolName ?? "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeScenario?.title ?? "Calibration Queue")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text("\(progress.completedSampleCount)/\(progress.requiredSampleCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
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
        .accessibilityLabel("Open calibration capture queue")
    }

    private var subtitle: String {
        guard let activeScenario else {
            return "\(progress.completedScenarioCount) scenarios complete"
        }

        return "\(progress.completedCount(for: activeScenario))/\(activeScenario.targetSampleCount) samples"
    }
}

private struct CalibrationCaptureQueueSheet: View {
    let progress: CalibrationCaptureQueueProgress
    let activeScenario: CalibrationCaptureScenario?
    let onSelect: (CalibrationCaptureScenario) -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Progress") {
                    ProgressView(value: Double(progress.completedSampleCount), total: Double(progress.requiredSampleCount))
                    LabeledContent("Samples", value: "\(progress.completedSampleCount)/\(progress.requiredSampleCount)")
                    LabeledContent("Scenarios", value: "\(progress.completedScenarioCount)/\(CalibrationCaptureScenario.allCases.count)")
                }

                Section("Capture Queue") {
                    ForEach(CalibrationCaptureScenario.allCases) { scenario in
                        CalibrationCaptureScenarioRow(
                            scenario: scenario,
                            completedCount: progress.completedCount(for: scenario),
                            isActive: activeScenario == scenario,
                            isComplete: progress.isComplete(scenario)
                        ) {
                            onSelect(scenario)
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: onReset) {
                        Label("Reset Queue", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Calibration Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close calibration queue")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CalibrationCaptureScenarioRow: View {
    let scenario: CalibrationCaptureScenario
    let completedCount: Int
    let isActive: Bool
    let isComplete: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: scenario.symbolName)
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isComplete ? Color.green : Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(scenario.title)
                        .font(.subheadline.weight(.semibold))
                    Text(scenario.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(completedCount)/\(scenario.targetSampleCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    Image(systemName: isComplete ? "checkmark.circle.fill" : isActive ? "smallcircle.filled.circle" : "circle")
                        .foregroundStyle(isComplete ? Color.green : isActive ? Color.accentColor : Color.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(scenario.title) calibration scenario")
    }
}

private struct AiDiagnosticsSheet: View {
    @ObservedObject var viewModel: CameraScreenViewModel
    @Environment(\.dismiss) private var dismiss

    private var report: SinglePhoneAiDiagnosticsReport {
        viewModel.aiDiagnosticsReport
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Run") {
                    Button {
                        viewModel.runSinglePhoneAiDiagnostics()
                    } label: {
                        Label("Run Single-Phone AI Test", systemImage: "play.circle")
                    }

                    Button {
                        viewModel.runReferencePopupDiagnostic()
                    } label: {
                        Label("Test Reference Popup", systemImage: "plus.viewfinder")
                    }

                    Button {
                        viewModel.runCaptureCoachingDiagnostic()
                    } label: {
                        Label("Test Capture Coaching", systemImage: "checkmark.seal")
                    }

                    Button {
                        viewModel.runLocalLearningDiagnostic()
                    } label: {
                        Label("Record Local Learning Test", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(!viewModel.personalizationConsent.learningEnabled)

                    Button {
                        viewModel.fetchOnlineInspirationReferences()
                    } label: {
                        Label(viewModel.onlineInspirationLoadState.actionTitle, systemImage: viewModel.onlineInspirationLoadState.actionIcon)
                    }
                    .disabled(viewModel.onlineReferencePlan == nil || viewModel.onlineInspirationLoadState.isLoading)
                }

                Section("Status") {
                    LabeledContent("Overall", value: report.overallStatus.title)
                    LabeledContent("Last Run") {
                        if let diagnosticLastRunAt = viewModel.diagnosticLastRunAt {
                            Text(diagnosticLastRunAt, style: .time)
                        } else {
                            Text("Not Run")
                        }
                    }
                    LabeledContent("Message", value: viewModel.diagnosticMessage)

                    ForEach(report.checks) { check in
                        AiDiagnosticStatusRow(check: check)
                    }
                }

                if let plan = viewModel.creativeInterpretationPlan {
                    CreativeInterpretationPlanSection(plan: plan)
                }

                if let calibrationReadiness = viewModel.targetMatchCalibrationReadiness {
                    CalibrationReadinessDiagnosticsSection(report: calibrationReadiness) { scenario in
                        viewModel.selectCalibrationScenario(scenario)
                        dismiss()
                    }
                }

                if let healthSnapshot = viewModel.onlineInspirationHealthSnapshot {
                    Section("Source Health") {
                        LabeledContent("Status", value: healthSnapshot.status.title)
                        ForEach(healthSnapshot.providers) { health in
                            OnlineInspirationProviderHealthRow(health: health)
                        }
                    }
                }

                if let review = viewModel.diagnosticCaptureReview {
                    Section("Capture Coaching") {
                        if let summary = review.coachingSummary {
                            LabeledContent("Headline", value: summary.headline)
                            LabeledContent("Best Score", value: "\(Int((summary.bestShotScore * 100).rounded()))%")

                            if let nextShotInstruction = summary.nextShotInstruction {
                                Label(nextShotInstruction, systemImage: summary.topCorrectionReason?.diagnosticIconName ?? "sparkles")
                                    .font(.subheadline)
                            }

                            ForEach(summary.improvementSignals.prefix(2)) { signal in
                                HStack {
                                    Text(signal.title)
                                    Spacer()
                                    Text("\(Int((signal.value * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ForEach(review.rankedShots) { shot in
                            HStack {
                                Label(shot.label == .best ? "Best" : "Alternative", systemImage: shot.label == .best ? "checkmark.circle.fill" : "circle")
                                Spacer()
                                Text("\(Int((shot.score * 100).rounded()))%")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.clearAiDiagnostics()
                    } label: {
                        Label("Clear Diagnostics", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("AI Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close AI diagnostics")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CalibrationReadinessDiagnosticsSection: View {
    let report: TargetMatchCalibrationManifest.CalibrationReadinessReport
    let onSelectScenario: (CalibrationCaptureScenario) -> Void

    private var missingScenarioList: [CalibrationCaptureScenario] {
        report.missingScenarios.compactMap(CalibrationCaptureScenario.init(rawValue:))
    }

    var body: some View {
        Section("Calibration Readiness") {
            LabeledContent("Status", value: report.status.title)
            LabeledContent("Captures", value: "\(report.reviewedSampleCount)/\(report.targetRealCaptureCount)")

            if report.missingSampleCount > 0 {
                LabeledContent("Missing", value: "\(report.missingSampleCount)")
            }

            if !report.missingDomains.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Missing Domains")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(report.missingDomains, id: \.self) { domain in
                        Label(domain.capitalized, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            ForEach(missingScenarioList) { scenario in
                CalibrationReadinessScenarioRow(
                    scenario: scenario,
                    reviewedCount: report.scenarioCounts[scenario.rawValue] ?? 0,
                    targetCount: report.scenarioTargetCount
                )
            }

            if let nextScenario = report.nextMissingScenario {
                Button {
                    onSelectScenario(nextScenario)
                } label: {
                    Label("Select Next Capture", systemImage: nextScenario.symbolName)
                }
            }
        }
    }
}

private struct CalibrationReadinessScenarioRow: View {
    let scenario: CalibrationCaptureScenario
    let reviewedCount: Int
    let targetCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: scenario.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                    .font(.subheadline.weight(.semibold))
                Text(scenario.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text("\(reviewedCount)/\(targetCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(scenario.title) calibration readiness")
    }
}

private struct AiDiagnosticStatusRow: View {
    let check: SinglePhoneAiDiagnosticsReport.Check

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: check.status.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(check.status.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.subheadline.weight(.semibold))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(check.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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

                PersonalLearningInsightSection(insight: viewModel.personalLearningInsight)

                if let plan = viewModel.creativeInterpretationPlan {
                    CreativeInterpretationPlanSection(plan: plan)
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

                if let healthSnapshot = viewModel.onlineInspirationHealthSnapshot {
                    Section("Source Health") {
                        LabeledContent("Status", value: healthSnapshot.status.title)

                        ForEach(healthSnapshot.providers) { health in
                            OnlineInspirationProviderHealthRow(health: health)
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

private struct PersonalLearningInsightSection: View {
    let insight: PersonalVisualLearningInsight

    private var sortedGuidanceBoosts: [(key: String, value: Double)] {
        Array(insight.guidanceBoosts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(3))
    }

    var body: some View {
        Section("Learning Insight") {
            LabeledContent("Status", value: insight.status.title)
            LabeledContent("Source", value: "\(insight.eventCount) local events")
            Text(insight.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(insight.topSignals) { signal in
                PersonalLearningInsightSignalRow(signal: signal)
            }

            ForEach(sortedGuidanceBoosts, id: \.key) { boost in
                LabeledContent(boost.key.learnedSignalLabel, value: "+\(Int((boost.value * 100).rounded()))%")
            }
        }
    }
}

private struct PersonalLearningInsightSignalRow: View {
    let signal: PersonalVisualLearningInsight.Signal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: signal.category.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(signal.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(Int((signal.score * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(signal.category.title): \(signal.label)")
    }
}

private struct CreativeInterpretationPlanSection: View {
    let plan: CreativeInterpretationPlan

    private var payloadAudit: CreativeInterpretationPayloadAudit {
        CreativeInterpretationPayloadAudit.make(for: plan)
    }

    var body: some View {
        Section("Creative Plan") {
            LabeledContent("Reason", value: plan.reason.title)
            LabeledContent("Inputs", value: plan.allowedInputs.map(\.title).joined(separator: ", "))
            LabeledContent("Payload", value: payloadAudit.safeToSend ? "Safe" : "Blocked")

            ForEach(plan.inputSummary.prefix(4), id: \.self) { item in
                Label(item, systemImage: "text.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(plan.suggestions.prefix(5)) { suggestion in
                CreativeInterpretationSuggestionRow(suggestion: suggestion)
            }
        }
    }
}

private struct CreativeInterpretationSuggestionRow: View {
    let suggestion: CreativeInterpretationPlan.Suggestion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.category.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(suggestion.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(suggestion.category.title): \(suggestion.title)")
    }
}

private struct OnlineInspirationProviderHealthRow: View {
    let health: OnlineInspirationProviderHealth

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: health.status.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(health.status.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(health.source.title)
                    .font(.subheadline.weight(.semibold))

                if let message = health.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(health.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text("\(health.resultCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(health.resultCount) public references")
        }
        .padding(.vertical, 2)
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

    mutating func applyScenario(_ scenario: CalibrationCaptureScenario) {
        domain = scenario.domain
        preferredGuidanceReason = scenario.preferredGuidanceReason
        rankedWeaknesses = scenario.rankedWeaknesses
        notes = scenario.reviewNotes
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

    var diagnosticIconName: String {
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
            return "checkmark.circle"
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

private extension PersonalVisualLearningInsight.Status {
    var title: String {
        switch self {
        case .disabled:
            return "Off"
        case .warmingUp:
            return "Learning"
        case .personalized:
            return "Personalized"
        }
    }
}

private extension PersonalVisualLearningInsight.Category {
    var title: String {
        switch self {
        case .domain:
            return "Scene"
        case .style:
            return "Style"
        case .color:
            return "Color"
        case .framing:
            return "Framing"
        case .guidance:
            return "Action"
        case .requirement:
            return "Requirement"
        case .onlineReference:
            return "Online Reference"
        }
    }

    var iconName: String {
        switch self {
        case .domain:
            return "camera.metering.matrix"
        case .style:
            return "sparkles"
        case .color:
            return "camera.filters"
        case .framing:
            return "viewfinder"
        case .guidance:
            return "location.north.line"
        case .requirement:
            return "checklist"
        case .onlineReference:
            return "globe"
        }
    }
}

private extension String {
    var learnedSignalLabel: String {
        replacingOccurrences(of: "customer_correction_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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

private extension CreativeInterpretationPlan.Reason {
    var title: String {
        switch self {
        case .explicitUserRequest:
            return "Requested Brief"
        case .specializedStyle:
            return "Style Brief"
        case .onlineInspiration:
            return "Public Inspiration"
        case .learnedPreference:
            return "Learned Taste"
        }
    }
}

private extension CreativeInterpretationPlan.AllowedInput {
    var title: String {
        switch self {
        case .promptText:
            return "Prompt"
        case .shotSpecSummary:
            return "Shot Plan"
        case .learnedPreferenceSummary:
            return "Learning"
        case .publicReferenceSummary:
            return "References"
        case .deviceCapabilitySummary:
            return "Device"
        }
    }
}

private extension CreativeInterpretationPlan.Category {
    var title: String {
        switch self {
        case .lighting:
            return "Lighting"
        case .composition:
            return "Composition"
        case .lens:
            return "Lens"
        case .color:
            return "Color"
        case .reference:
            return "Reference"
        case .safety:
            return "Safety"
        }
    }

    var iconName: String {
        switch self {
        case .lighting:
            return "light.max"
        case .composition:
            return "viewfinder"
        case .lens:
            return "camera.aperture"
        case .color:
            return "camera.filters"
        case .reference:
            return "photo.on.rectangle"
        case .safety:
            return "checkmark.shield"
        }
    }
}

private extension SinglePhoneAiDiagnosticsReport.Status {
    var title: String {
        switch self {
        case .passed:
            return "Passed"
        case .attention:
            return "Check"
        case .blocked:
            return "Blocked"
        }
    }

    var iconName: String {
        switch self {
        case .passed:
            return "checkmark.circle.fill"
        case .attention:
            return "exclamationmark.circle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .passed:
            return .green
        case .attention:
            return .orange
        case .blocked:
            return .red
        }
    }
}

private extension TargetMatchCalibrationManifest.CalibrationReadinessStatus {
    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsMoreSamples:
            return "Needs Samples"
        }
    }
}

private extension OnlineInspirationHealthSnapshot.Status {
    var title: String {
        switch self {
        case .available:
            return "Available"
        case .degraded:
            return "Partial"
        case .empty:
            return "No Matches"
        case .failed:
            return "Unavailable"
        }
    }
}

private extension OnlineInspirationProviderHealth.Status {
    var title: String {
        switch self {
        case .available:
            return "Available"
        case .empty:
            return "No Matches"
        case .failed:
            return "Unavailable"
        }
    }

    var iconName: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .empty:
            return "magnifyingglass.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .green
        case .empty:
            return .secondary
        case .failed:
            return .orange
        }
    }
}

private extension OnlineInspirationRequest.Source {
    var title: String {
        switch self {
        case .publicSources:
            return "Public Sources"
        case .wikimediaCommons:
            return "Wikimedia Commons"
        case .openverse:
            return "Openverse"
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
