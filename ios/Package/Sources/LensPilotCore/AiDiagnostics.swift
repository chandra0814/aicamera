import Foundation

public struct SinglePhoneAiDiagnosticsReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let overallStatus: Status
    public let checks: [Check]
    public let privacy: Privacy

    public init(
        generatedAt: Date = Date(),
        checks: [Check],
        overallStatus: Status? = nil,
        privacy: Privacy = Privacy()
    ) {
        self.generatedAt = generatedAt
        self.overallStatus = overallStatus ?? Self.aggregateStatus(for: checks)
        self.checks = checks
        self.privacy = privacy
    }

    public static func make(
        hasShotPlan: Bool,
        referencePhoto: ReferencePhotoState?,
        onlineReferencePlan: OnlineReferencePlan?,
        creativeInterpretationPlan: CreativeInterpretationPlan? = nil,
        creativeAPIConfigurationStatus: LensPilotCreativeAPIConfigurationStatus = .offline,
        onlineInspirationHealthSnapshot: OnlineInspirationHealthSnapshot?,
        calibrationReadinessReport: TargetMatchCalibrationManifest.CalibrationReadinessReport? = nil,
        personalProfile: PersonalVisualPreferenceProfile,
        personalProfileStoreProtection: PersonalVisualProfileStorageProtection = .localFile,
        captureCoachingSummary: CaptureCoachingSummary?,
        generatedAt: Date = Date()
    ) -> SinglePhoneAiDiagnosticsReport {
        SinglePhoneAiDiagnosticsReport(
            generatedAt: generatedAt,
            checks: [
                shotPlanningCheck(hasShotPlan: hasShotPlan),
                referencePopupCheck(referencePhoto: referencePhoto),
                onlineReferencePlanCheck(onlineReferencePlan),
                creativeInterpretationCheck(creativeInterpretationPlan),
                creativeAPIConfigurationCheck(creativeAPIConfigurationStatus),
                onlineProviderHealthCheck(onlineInspirationHealthSnapshot),
                calibrationReadinessCheck(calibrationReadinessReport),
                localLearningCheck(profile: personalProfile),
                learningStoreCheck(profile: personalProfile, protection: personalProfileStoreProtection),
                captureCoachingCheck(captureCoachingSummary)
            ]
        )
    }

    private static func creativeInterpretationCheck(_ plan: CreativeInterpretationPlan?) -> Check {
        guard let plan else {
            return Check(
                id: "creative_interpretation",
                title: "Creative Plan",
                status: .attention,
                detail: "Not triggered"
            )
        }

        let payloadAudit = CreativeInterpretationPayloadAudit.make(for: plan)
        let detail: String
        if payloadAudit.safeToSend {
            detail = "\(payloadAudit.suggestionCount) suggestions"
        } else {
            detail = payloadAudit.deniedReasons.first?.rawValue.replacingOccurrences(of: "_", with: " ")
                ?? "Unsafe payload"
        }

        return Check(
            id: "creative_interpretation",
            title: "Creative Plan",
            status: payloadAudit.safeToSend ? .passed : .blocked,
            detail: detail
        )
    }

    private static func creativeAPIConfigurationCheck(
        _ configuration: LensPilotCreativeAPIConfigurationStatus
    ) -> Check {
        let privacy = configuration.privacy
        guard privacy.singlePhoneOnly,
              privacy.keepsOpenAIKeyOnServer,
              !privacy.acceptsClientOpenAIKey,
              !privacy.uploadsLiveCameraFrame,
              !privacy.sendsPrivatePhoto,
              !privacy.sendsIdentityData,
              !privacy.sendsPreciseLocation,
              !privacy.sendsRawLearningEvents
        else {
            return Check(
                id: "creative_api_configuration",
                title: "Creative API",
                status: .blocked,
                detail: "Unsafe API privacy"
            )
        }

        let status: Status
        switch configuration.readiness {
        case .protected:
            status = .passed
        case .offline, .needsProtection:
            status = .attention
        case .blocked:
            status = .blocked
        }

        return Check(
            id: "creative_api_configuration",
            title: "Creative API",
            status: status,
            detail: configuration.diagnosticDetail
        )
    }

    private static func aggregateStatus(for checks: [Check]) -> Status {
        if checks.contains(where: { $0.status == .blocked }) {
            return .blocked
        }

        if checks.contains(where: { $0.status == .attention }) {
            return .attention
        }

        return .passed
    }

    private static func shotPlanningCheck(hasShotPlan: Bool) -> Check {
        Check(
            id: "shot_planning",
            title: "Shot Planning",
            status: hasShotPlan ? .passed : .attention,
            detail: hasShotPlan ? "Ready" : "Run a prompt first"
        )
    }

    private static func referencePopupCheck(referencePhoto: ReferencePhotoState?) -> Check {
        guard let referencePhoto else {
            return Check(
                id: "reference_popup",
                title: "Reference Popup",
                status: .attention,
                detail: "No reference active"
            )
        }

        guard !referencePhoto.privacy.cloudAnalysisUsed else {
            return Check(
                id: "reference_popup",
                title: "Reference Popup",
                status: .blocked,
                detail: "Cloud analysis detected"
            )
        }

        return Check(
            id: "reference_popup",
            title: "Reference Popup",
            status: referencePhoto.display.showCameraPopup ? .passed : .attention,
            detail: referencePhoto.display.showCameraPopup ? "Popup visible" : "Popup hidden"
        )
    }

    private static func onlineReferencePlanCheck(_ plan: OnlineReferencePlan?) -> Check {
        guard let plan else {
            return Check(
                id: "online_reference_plan",
                title: "Online Plan",
                status: .attention,
                detail: "Not enabled"
            )
        }

        let isSafe = plan.privacy.singlePhoneOnly
            && plan.privacy.requiresUserConsent
            && !plan.privacy.sendsRawCameraFrame
            && !plan.privacy.sendsPrivatePhoto
            && !plan.privacy.sendsIdentityData

        return Check(
            id: "online_reference_plan",
            title: "Online Plan",
            status: isSafe ? .passed : .blocked,
            detail: "\(plan.searchQueries.count) public queries"
        )
    }

    private static func onlineProviderHealthCheck(_ snapshot: OnlineInspirationHealthSnapshot?) -> Check {
        guard let snapshot else {
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .attention,
                detail: "Not checked"
            )
        }

        guard snapshot.privacy.singlePhoneOnly,
              !snapshot.privacy.sendsRawCameraFrame,
              !snapshot.privacy.sendsPrivatePhoto,
              !snapshot.privacy.sendsIdentityData,
              !snapshot.privacy.sendsPreciseLocation
        else {
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .blocked,
                detail: "Unsafe provider payload"
            )
        }

        switch snapshot.status {
        case .available:
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .passed,
                detail: "\(snapshot.totalResultCount) public references"
            )
        case .degraded:
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .attention,
                detail: "Partial results"
            )
        case .empty:
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .attention,
                detail: "No matches"
            )
        case .failed:
            return Check(
                id: "online_provider_health",
                title: "Source Health",
                status: .attention,
                detail: "Unavailable"
            )
        }
    }

    private static func localLearningCheck(profile: PersonalVisualPreferenceProfile) -> Check {
        guard profile.consent.learningEnabled else {
            return Check(
                id: "local_learning",
                title: "Local Learning",
                status: .attention,
                detail: "Off"
            )
        }

        return Check(
            id: "local_learning",
            title: "Local Learning",
            status: profile.totalEvents > 0 ? .passed : .attention,
            detail: "\(profile.totalEvents) events"
        )
    }

    private static func calibrationReadinessCheck(
        _ report: TargetMatchCalibrationManifest.CalibrationReadinessReport?
    ) -> Check {
        guard let report else {
            return Check(
                id: "calibration_readiness",
                title: "Calibration Data",
                status: .attention,
                detail: "Manifest unavailable"
            )
        }

        if report.isReadyForProductionCalibration {
            return Check(
                id: "calibration_readiness",
                title: "Calibration Data",
                status: .passed,
                detail: "\(report.reviewedSampleCount)/\(report.targetRealCaptureCount) captures"
            )
        }

        let detail: String
        if report.missingSampleCount > 0 {
            detail = "Need \(report.missingSampleCount) captures"
        } else if !report.missingScenarios.isEmpty {
            detail = "Missing \(report.missingScenarios.count) scenarios"
        } else {
            detail = "Missing \(report.missingDomains.count) domains"
        }

        return Check(
            id: "calibration_readiness",
            title: "Calibration Data",
            status: .attention,
            detail: detail
        )
    }

    private static func learningStoreCheck(
        profile: PersonalVisualPreferenceProfile,
        protection: PersonalVisualProfileStorageProtection
    ) -> Check {
        guard profile.consent.learningEnabled else {
            return Check(
                id: "learning_store",
                title: "Learning Store",
                status: .attention,
                detail: "Learning off"
            )
        }

        return Check(
            id: "learning_store",
            title: "Learning Store",
            status: protection.isEncryptedAtRest ? .passed : .attention,
            detail: protection.isEncryptedAtRest ? "Keychain encrypted" : "Local file fallback"
        )
    }

    private static func captureCoachingCheck(_ summary: CaptureCoachingSummary?) -> Check {
        guard let summary else {
            return Check(
                id: "capture_coaching",
                title: "Capture Coaching",
                status: .attention,
                detail: "Not run"
            )
        }

        let isSafe = summary.privacy.singlePhoneOnly
            && !summary.privacy.storesRawPhoto
            && !summary.privacy.uploadsLiveCameraFrame
            && !summary.privacy.identityRecognitionAllowed

        return Check(
            id: "capture_coaching",
            title: "Capture Coaching",
            status: isSafe ? .passed : .blocked,
            detail: summary.headline
        )
    }
}

public extension SinglePhoneAiDiagnosticsReport {
    enum Status: String, Codable, Equatable, Sendable {
        case passed
        case attention
        case blocked
    }

    struct Check: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let status: Status
        public let detail: String

        public init(id: String, title: String, status: Status, detail: String) {
            self.id = id
            self.title = title
            self.status = status
            self.detail = detail
        }
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool

        public init(
            singlePhoneOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
        }
    }
}
