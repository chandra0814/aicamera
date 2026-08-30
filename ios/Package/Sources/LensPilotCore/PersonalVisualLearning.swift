import Foundation

public struct PersonalizationConsent: Codable, Equatable, Sendable {
    public static let disabled = PersonalizationConsent()
    public static let localLearningEnabled = PersonalizationConsent(learningEnabled: true)

    public let learningEnabled: Bool
    public let onlineReferencesAllowed: Bool
    public let cloudPersonalizationSyncAllowed: Bool

    public init(
        learningEnabled: Bool = false,
        onlineReferencesAllowed: Bool = false,
        cloudPersonalizationSyncAllowed: Bool = false
    ) {
        self.learningEnabled = learningEnabled
        self.onlineReferencesAllowed = onlineReferencesAllowed
        self.cloudPersonalizationSyncAllowed = cloudPersonalizationSyncAllowed
    }
}

public struct PersonalLearningEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let domain: CaptureDomain
    public let outcome: Outcome
    public let promptRequirements: [String]
    public let acceptedGuidanceReason: GuidanceAction.Reason?
    public let rejectedGuidanceReason: GuidanceAction.Reason?
    public let customerCorrectionReason: GuidanceAction.Reason?
    public let selectedStyle: ShotSpec.Name?
    public let selectedColorIntent: ShotSpec.ColorIntent?
    public let selectedFraming: ShotSpec.Framing?
    public let selectedTargetMatch: Double?
    public let userRating: Double?
    public let onlineReferenceUsed: Bool
    public let privacy: Privacy

    public init(
        id: String,
        timestamp: Date = Date(),
        domain: CaptureDomain,
        outcome: Outcome,
        promptRequirements: [String] = [],
        acceptedGuidanceReason: GuidanceAction.Reason? = nil,
        rejectedGuidanceReason: GuidanceAction.Reason? = nil,
        customerCorrectionReason: GuidanceAction.Reason? = nil,
        selectedStyle: ShotSpec.Name? = nil,
        selectedColorIntent: ShotSpec.ColorIntent? = nil,
        selectedFraming: ShotSpec.Framing? = nil,
        selectedTargetMatch: Double? = nil,
        userRating: Double? = nil,
        onlineReferenceUsed: Bool = false,
        privacy: Privacy = Privacy()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.domain = domain
        self.outcome = outcome
        self.promptRequirements = promptRequirements
        self.acceptedGuidanceReason = acceptedGuidanceReason
        self.rejectedGuidanceReason = rejectedGuidanceReason
        self.customerCorrectionReason = customerCorrectionReason
        self.selectedStyle = selectedStyle
        self.selectedColorIntent = selectedColorIntent
        self.selectedFraming = selectedFraming
        self.selectedTargetMatch = selectedTargetMatch
        self.userRating = userRating
        self.onlineReferenceUsed = onlineReferenceUsed
        self.privacy = privacy
    }
}

public extension PersonalLearningEvent {
    enum Outcome: String, Codable, Sendable {
        case acceptedGuidance = "accepted_guidance"
        case rejectedGuidance = "rejected_guidance"
        case selectedBestShot = "selected_best_shot"
        case savedResult = "saved_result"
        case sharedResult = "shared_result"
        case deletedResult = "deleted_result"
        case editedAfterCapture = "edited_after_capture"
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let identityRecognitionAllowed: Bool

        public init(
            singlePhoneOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            identityRecognitionAllowed: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.identityRecognitionAllowed = identityRecognitionAllowed
        }

        public var canLearnLocally: Bool {
            singlePhoneOnly && !storesRawPhoto && !uploadsLiveCameraFrame && !identityRecognitionAllowed
        }
    }
}

public struct PersonalVisualPreferenceProfile: Codable, Equatable, Sendable {
    public static func empty(consent: PersonalizationConsent = .disabled) -> PersonalVisualPreferenceProfile {
        PersonalVisualPreferenceProfile(consent: consent)
    }

    public let version: String
    public let consent: PersonalizationConsent
    public let totalEvents: Int
    public let domainCounts: [String: Int]
    public let styleAffinities: [String: Double]
    public let colorAffinities: [String: Double]
    public let framingAffinities: [String: Double]
    public let guidanceReasonAffinities: [String: Double]
    public let requirementAffinities: [String: Double]
    public let onlineReferenceUsageCount: Int

    public init(
        version: String = "1.0",
        consent: PersonalizationConsent = .disabled,
        totalEvents: Int = 0,
        domainCounts: [String: Int] = [:],
        styleAffinities: [String: Double] = [:],
        colorAffinities: [String: Double] = [:],
        framingAffinities: [String: Double] = [:],
        guidanceReasonAffinities: [String: Double] = [:],
        requirementAffinities: [String: Double] = [:],
        onlineReferenceUsageCount: Int = 0
    ) {
        self.version = version
        self.consent = consent
        self.totalEvents = max(0, totalEvents)
        self.domainCounts = domainCounts
        self.styleAffinities = styleAffinities.mapValues(Self.clampAffinity)
        self.colorAffinities = colorAffinities.mapValues(Self.clampAffinity)
        self.framingAffinities = framingAffinities.mapValues(Self.clampAffinity)
        self.guidanceReasonAffinities = guidanceReasonAffinities.mapValues(Self.clampAffinity)
        self.requirementAffinities = requirementAffinities.mapValues(Self.clampAffinity)
        self.onlineReferenceUsageCount = max(0, onlineReferenceUsageCount)
    }

    public func guidanceCalibration() -> GuidanceCalibration {
        guard consent.learningEnabled else { return .standard }

        let boosts = guidanceReasonAffinities.compactMapValues { affinity -> Double? in
            guard affinity > 0 else { return nil }
            return min(0.04, affinity * 0.04)
        }

        return GuidanceCalibration(globalReasonBoosts: boosts)
    }

    static func clampAffinity(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }
}

public struct PersonalVisualLearningInsight: Codable, Equatable, Sendable {
    public let status: Status
    public let headline: String
    public let eventCount: Int
    public let topSignals: [Signal]
    public let guidanceBoosts: [String: Double]
    public let onlineReferenceUsageCount: Int
    public let privacy: Privacy

    public init(
        status: Status,
        headline: String,
        eventCount: Int,
        topSignals: [Signal],
        guidanceBoosts: [String: Double],
        onlineReferenceUsageCount: Int,
        privacy: Privacy = Privacy()
    ) {
        self.status = status
        self.headline = headline
        self.eventCount = max(0, eventCount)
        self.topSignals = topSignals
        self.guidanceBoosts = guidanceBoosts.compactMapValues { boost in
            guard boost.isFinite, boost > 0 else { return nil }
            return min(0.08, boost)
        }
        self.onlineReferenceUsageCount = max(0, onlineReferenceUsageCount)
        self.privacy = privacy
    }
}

public extension PersonalVisualLearningInsight {
    enum Status: String, Codable, Equatable, Sendable {
        case disabled
        case warmingUp = "warming_up"
        case personalized
    }

    enum Category: String, Codable, Equatable, Sendable {
        case domain
        case style
        case color
        case framing
        case guidance
        case requirement
        case onlineReference = "online_reference"
    }

    struct Signal: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let category: Category
        public let label: String
        public let score: Double

        public init(id: String, category: Category, label: String, score: Double) {
            self.id = id
            self.category = category
            self.label = label
            self.score = min(1, max(0, score.isFinite ? score : 0))
        }
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let storesIdentityData: Bool
        public let cloudPersonalizationSyncAllowed: Bool

        public init(
            singlePhoneOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            storesIdentityData: Bool = false,
            cloudPersonalizationSyncAllowed: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.storesIdentityData = storesIdentityData
            self.cloudPersonalizationSyncAllowed = cloudPersonalizationSyncAllowed
        }
    }
}

public extension PersonalVisualPreferenceProfile {
    func learningInsight(maxSignals: Int = 8) -> PersonalVisualLearningInsight {
        let guidanceBoosts = guidanceCalibration().globalReasonBoosts
        let signals = Array(learningSignals().prefix(max(0, maxSignals)))
        let status = learningInsightStatus(hasSignals: !signals.isEmpty)

        return PersonalVisualLearningInsight(
            status: status,
            headline: learningInsightHeadline(for: status),
            eventCount: totalEvents,
            topSignals: signals,
            guidanceBoosts: guidanceBoosts,
            onlineReferenceUsageCount: onlineReferenceUsageCount
        )
    }

    private func learningInsightStatus(hasSignals: Bool) -> PersonalVisualLearningInsight.Status {
        guard consent.learningEnabled else { return .disabled }
        guard totalEvents >= 3, hasSignals else { return .warmingUp }
        return .personalized
    }

    private func learningInsightHeadline(for status: PersonalVisualLearningInsight.Status) -> String {
        switch status {
        case .disabled:
            return "Local learning is off"
        case .warmingUp:
            return totalEvents == 0
                ? "Ready to learn from local choices"
                : "Learning from \(totalEvents) local events"
        case .personalized:
            return "Personalized from \(totalEvents) local events"
        }
    }

    private func learningSignals() -> [PersonalVisualLearningInsight.Signal] {
        var signals: [PersonalVisualLearningInsight.Signal] = []

        if let domainSignal = topCountSignal(
            in: domainCounts,
            category: .domain,
            eventCount: totalEvents
        ) {
            signals.append(domainSignal)
        }

        appendTopAffinitySignal(from: styleAffinities, category: .style, to: &signals)
        appendTopAffinitySignal(from: colorAffinities, category: .color, to: &signals)
        appendTopAffinitySignal(from: framingAffinities, category: .framing, to: &signals)
        appendTopAffinitySignal(from: guidanceReasonAffinities, category: .guidance, to: &signals)
        appendTopAffinitySignal(from: requirementAffinities, category: .requirement, to: &signals)

        if onlineReferenceUsageCount > 0 {
            signals.append(PersonalVisualLearningInsight.Signal(
                id: "online_reference_public_inspiration",
                category: .onlineReference,
                label: "Public Inspiration",
                score: min(1, Double(onlineReferenceUsageCount) / Double(max(1, totalEvents)))
            ))
        }

        return signals.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.label < rhs.label
            }

            return lhs.score > rhs.score
        }
    }

    private func topCountSignal(
        in values: [String: Int],
        category: PersonalVisualLearningInsight.Category,
        eventCount: Int
    ) -> PersonalVisualLearningInsight.Signal? {
        guard let topValue = values
            .filter({ $0.value > 0 })
            .max(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            })
        else {
            return nil
        }

        return PersonalVisualLearningInsight.Signal(
            id: "\(category.rawValue)_\(topValue.key)",
            category: category,
            label: Self.displayLabel(for: topValue.key),
            score: min(1, Double(topValue.value) / Double(max(1, eventCount)))
        )
    }

    private func appendTopAffinitySignal(
        from affinities: [String: Double],
        category: PersonalVisualLearningInsight.Category,
        to signals: inout [PersonalVisualLearningInsight.Signal]
    ) {
        guard let topAffinity = affinities
            .filter({ $0.value > 0 })
            .max(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            })
        else {
            return
        }

        signals.append(PersonalVisualLearningInsight.Signal(
            id: "\(category.rawValue)_\(topAffinity.key)",
            category: category,
            label: Self.displayLabel(for: topAffinity.key),
            score: topAffinity.value
        ))
    }

    private static func displayLabel(for key: String) -> String {
        let normalizedKey: String
        if key.hasPrefix("customer_correction_") {
            normalizedKey = String(key.dropFirst("customer_correction_".count))
        } else {
            normalizedKey = key
        }

        return normalizedKey
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

public struct OnlineReferencePlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let reason: Reason
    public let searchQueries: [String]
    public let allowedInputs: [AllowedInput]
    public let mustNotSend: [String]
    public let userDisclosure: String
    public let privacy: Privacy

    public init(
        id: String,
        reason: Reason,
        searchQueries: [String],
        allowedInputs: [AllowedInput],
        mustNotSend: [String],
        userDisclosure: String,
        privacy: Privacy
    ) {
        self.id = id
        self.reason = reason
        self.searchQueries = searchQueries
        self.allowedInputs = allowedInputs
        self.mustNotSend = mustNotSend
        self.userDisclosure = userDisclosure
        self.privacy = privacy
    }
}

public extension OnlineReferencePlan {
    enum Reason: String, Codable, Sendable {
        case explicitUserRequest = "explicit_user_request"
        case specializedStyle = "specialized_style"
        case insufficientPersonalHistory = "insufficient_personal_history"
    }

    enum AllowedInput: String, Codable, Sendable {
        case promptText = "prompt_text"
        case shotSpecSummary = "shot_spec_summary"
        case deviceCapabilitySummary = "device_capability_summary"
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let requiresUserConsent: Bool
        public let sendsRawCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool

        public init(
            singlePhoneOnly: Bool = true,
            requiresUserConsent: Bool = true,
            sendsRawCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.requiresUserConsent = requiresUserConsent
            self.sendsRawCameraFrame = sendsRawCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
        }
    }
}

public struct CreativeInterpretationPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let reason: Reason
    public let inputSummary: [String]
    public let suggestions: [Suggestion]
    public let allowedInputs: [AllowedInput]
    public let mustNotSend: [String]
    public let userDisclosure: String
    public let privacy: Privacy

    public init(
        id: String,
        reason: Reason,
        inputSummary: [String],
        suggestions: [Suggestion],
        allowedInputs: [AllowedInput],
        mustNotSend: [String],
        userDisclosure: String,
        privacy: Privacy = Privacy()
    ) {
        self.id = id
        self.reason = reason
        self.inputSummary = inputSummary
        self.suggestions = suggestions
        self.allowedInputs = allowedInputs
        self.mustNotSend = mustNotSend
        self.userDisclosure = userDisclosure
        self.privacy = privacy
    }
}

public extension CreativeInterpretationPlan {
    enum Reason: String, Codable, Equatable, Sendable {
        case explicitUserRequest = "explicit_user_request"
        case specializedStyle = "specialized_style"
        case onlineInspiration = "online_inspiration"
        case learnedPreference = "learned_preference"
    }

    enum AllowedInput: String, Codable, Equatable, Sendable {
        case promptText = "prompt_text"
        case shotSpecSummary = "shot_spec_summary"
        case learnedPreferenceSummary = "learned_preference_summary"
        case publicReferenceSummary = "public_reference_summary"
        case deviceCapabilitySummary = "device_capability_summary"
    }

    enum Category: String, Codable, Equatable, Sendable {
        case lighting
        case composition
        case lens
        case color
        case reference
        case safety
    }

    struct Suggestion: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let category: Category
        public let title: String
        public let instruction: String

        public init(id: String, category: Category, title: String, instruction: String) {
            self.id = id
            self.category = category
            self.title = title
            self.instruction = instruction
        }
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let requiresUserConsent: Bool
        public let sendsRawCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool
        public let sendsRawLearningEvents: Bool
        public let allowsGenerativeOutput: Bool

        public init(
            singlePhoneOnly: Bool = true,
            requiresUserConsent: Bool = true,
            sendsRawCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false,
            sendsRawLearningEvents: Bool = false,
            allowsGenerativeOutput: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.requiresUserConsent = requiresUserConsent
            self.sendsRawCameraFrame = sendsRawCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
            self.sendsRawLearningEvents = sendsRawLearningEvents
            self.allowsGenerativeOutput = allowsGenerativeOutput
        }

        public var isSafeForSinglePhoneCreativeReasoning: Bool {
            singlePhoneOnly
                && requiresUserConsent
                && !sendsRawCameraFrame
                && !sendsPrivatePhoto
                && !sendsIdentityData
                && !sendsPreciseLocation
                && !sendsRawLearningEvents
                && !allowsGenerativeOutput
        }
    }
}

public struct PersonalVisualLearningEngine: Sendable {
    public init() {}

    public func updatedProfile(
        from profile: PersonalVisualPreferenceProfile,
        with event: PersonalLearningEvent,
        consent: PersonalizationConsent? = nil
    ) -> PersonalVisualPreferenceProfile {
        let activeConsent = consent ?? profile.consent

        guard activeConsent.learningEnabled, event.privacy.canLearnLocally else {
            return PersonalVisualPreferenceProfile(
                version: profile.version,
                consent: activeConsent,
                totalEvents: profile.totalEvents,
                domainCounts: profile.domainCounts,
                styleAffinities: profile.styleAffinities,
                colorAffinities: profile.colorAffinities,
                framingAffinities: profile.framingAffinities,
                guidanceReasonAffinities: profile.guidanceReasonAffinities,
                requirementAffinities: profile.requirementAffinities,
                onlineReferenceUsageCount: profile.onlineReferenceUsageCount
            )
        }

        let signal = outcomeSignal(for: event)
        var domainCounts = profile.domainCounts
        var styleAffinities = profile.styleAffinities
        var colorAffinities = profile.colorAffinities
        var framingAffinities = profile.framingAffinities
        var guidanceReasonAffinities = profile.guidanceReasonAffinities
        var requirementAffinities = profile.requirementAffinities

        domainCounts[event.domain.rawValue, default: 0] += 1

        if let selectedStyle = event.selectedStyle {
            bump(&styleAffinities, key: selectedStyle.rawValue, amount: 0.06 * signal)
        }

        if let selectedColorIntent = event.selectedColorIntent {
            bump(&colorAffinities, key: selectedColorIntent.rawValue, amount: 0.05 * signal)
        }

        if let selectedFraming = event.selectedFraming {
            bump(&framingAffinities, key: selectedFraming.rawValue, amount: 0.05 * signal)
        }

        for requirement in event.promptRequirements {
            bump(&requirementAffinities, key: requirement, amount: 0.04 * signal)
        }

        if let acceptedGuidanceReason = event.acceptedGuidanceReason {
            bump(&guidanceReasonAffinities, key: acceptedGuidanceReason.rawValue, amount: 0.08 * max(0.25, signal))
        }

        if let rejectedGuidanceReason = event.rejectedGuidanceReason {
            bump(&guidanceReasonAffinities, key: rejectedGuidanceReason.rawValue, amount: -0.08 * max(0.25, abs(signal)))
        }

        if let customerCorrectionReason = event.customerCorrectionReason {
            let correctionSignal = max(0.4, abs(signal))
            bump(&guidanceReasonAffinities, key: customerCorrectionReason.rawValue, amount: 0.10 * correctionSignal)
            bump(&requirementAffinities, key: "customer_correction_\(customerCorrectionReason.rawValue)", amount: 0.05 * correctionSignal)
        }

        return PersonalVisualPreferenceProfile(
            version: profile.version,
            consent: activeConsent,
            totalEvents: profile.totalEvents + 1,
            domainCounts: domainCounts,
            styleAffinities: styleAffinities,
            colorAffinities: colorAffinities,
            framingAffinities: framingAffinities,
            guidanceReasonAffinities: guidanceReasonAffinities,
            requirementAffinities: requirementAffinities,
            onlineReferenceUsageCount: profile.onlineReferenceUsageCount + (event.onlineReferenceUsed ? 1 : 0)
        )
    }

    public func makeCreativeInterpretationPlan(
        for shotSpec: ShotSpec,
        prompt: String,
        profile: PersonalVisualPreferenceProfile,
        onlineReferencePlan: OnlineReferencePlan? = nil,
        consent: PersonalizationConsent? = nil
    ) -> CreativeInterpretationPlan? {
        let activeConsent = consent ?? profile.consent
        guard activeConsent.onlineReferencesAllowed else { return nil }

        let normalizedPrompt = prompt.lowercased()
        let explicitCreativeRequest = containsAny(
            normalizedPrompt,
            terms: ["creative", "interpret", "brief", "inspiration", "reference", "online", "trend", "make it look", "style"]
        )
        let specializedStyle = shotSpec.style.name != .natural
            || shotSpec.style.mood != nil
            || containsAny(normalizedPrompt, terms: ["cinematic", "professional", "luxury", "dramatic", "moody", "instagram"])
        let hasLearnedSignals = activeConsent.learningEnabled
            && profile.totalEvents >= 3
            && !profile.learningInsight(maxSignals: 3).topSignals.isEmpty

        guard explicitCreativeRequest || specializedStyle || onlineReferencePlan != nil || hasLearnedSignals else {
            return nil
        }

        let reason: CreativeInterpretationPlan.Reason
        if explicitCreativeRequest {
            reason = .explicitUserRequest
        } else if onlineReferencePlan != nil {
            reason = .onlineInspiration
        } else if hasLearnedSignals {
            reason = .learnedPreference
        } else {
            reason = .specializedStyle
        }

        var allowedInputs: [CreativeInterpretationPlan.AllowedInput] = [
            .promptText,
            .shotSpecSummary,
            .deviceCapabilitySummary
        ]
        if hasLearnedSignals {
            allowedInputs.append(.learnedPreferenceSummary)
        }
        if onlineReferencePlan != nil {
            allowedInputs.append(.publicReferenceSummary)
        }

        return CreativeInterpretationPlan(
            id: "creative_interpretation_\(shotSpec.id)",
            reason: reason,
            inputSummary: creativeInputSummary(
                for: shotSpec,
                prompt: normalizedPrompt,
                profile: profile,
                includeLearnedSignals: hasLearnedSignals,
                includePublicReferences: onlineReferencePlan != nil
            ),
            suggestions: creativeSuggestions(
                for: shotSpec,
                prompt: normalizedPrompt,
                profile: profile,
                includeLearnedSignals: hasLearnedSignals,
                includePublicReferences: onlineReferencePlan != nil
            ),
            allowedInputs: allowedInputs,
            mustNotSend: [
                "raw_live_camera_feed",
                "private_photo",
                "face_identity",
                "precise_location_without_consent",
                "raw_learning_events"
            ],
            userDisclosure: "LensPilot can interpret the shot using prompt, plan, learned aggregate preferences, and public-reference summaries only. It will not upload your live camera feed or private photos.",
            privacy: .init()
        )
    }

    public func makeOnlineReferencePlan(
        for shotSpec: ShotSpec,
        prompt: String,
        profile: PersonalVisualPreferenceProfile,
        consent: PersonalizationConsent? = nil
    ) -> OnlineReferencePlan? {
        let activeConsent = consent ?? profile.consent
        guard activeConsent.onlineReferencesAllowed else { return nil }

        let normalizedPrompt = prompt.lowercased()
        let explicitReferenceRequest = containsAny(normalizedPrompt, terms: ["reference", "inspiration", "like this", "online", "trend"])
        let specializedStyle = shotSpec.style.name != .natural || containsAny(normalizedPrompt, terms: ["instagram", "luxury", "professional", "cinematic"])
        let needsHistory = profile.totalEvents < 3 && specializedStyle

        guard explicitReferenceRequest || specializedStyle || needsHistory else { return nil }

        let reason: OnlineReferencePlan.Reason
        if explicitReferenceRequest {
            reason = .explicitUserRequest
        } else if needsHistory {
            reason = .insufficientPersonalHistory
        } else {
            reason = .specializedStyle
        }

        let searchQueries = uniqueNonEmpty([
            "\(shotSpec.style.name.rawValue) \(shotSpec.domain.rawValue) phone photography reference",
            "\(shotSpec.domain.rawValue) \(shotSpec.composition.framing.rawValue) \(shotSpec.composition.backgroundPriority?.rawValue ?? "clean") photography ideas",
            compactPromptQuery(from: normalizedPrompt)
        ])

        return OnlineReferencePlan(
            id: "online_reference_\(shotSpec.id)",
            reason: reason,
            searchQueries: searchQueries,
            allowedInputs: [.promptText, .shotSpecSummary, .deviceCapabilitySummary],
            mustNotSend: ["raw_live_camera_feed", "private_photo", "face_identity", "precise_location_without_consent"],
            userDisclosure: "LensPilot can look up public inspiration using your prompt, but it will not upload your live camera feed or private photos.",
            privacy: .init()
        )
    }

    private func outcomeSignal(for event: PersonalLearningEvent) -> Double {
        var signal: Double
        switch event.outcome {
        case .acceptedGuidance, .selectedBestShot, .savedResult:
            signal = 0.7
        case .sharedResult:
            signal = 0.9
        case .editedAfterCapture:
            signal = 0.2
        case .rejectedGuidance:
            signal = -0.5
        case .deletedResult:
            signal = -0.8
        }

        if let userRating = event.userRating {
            signal += (min(5, max(1, userRating)) - 3) / 4
        }

        if let selectedTargetMatch = event.selectedTargetMatch {
            signal += (min(1, max(0, selectedTargetMatch)) - 0.75) * 0.6
        }

        return min(1, max(-1, signal))
    }

    private func creativeInputSummary(
        for shotSpec: ShotSpec,
        prompt: String,
        profile: PersonalVisualPreferenceProfile,
        includeLearnedSignals: Bool,
        includePublicReferences: Bool
    ) -> [String] {
        var summary = [
            "Scene: \(displayLabel(for: shotSpec.domain.rawValue))",
            "Style: \(displayLabel(for: shotSpec.style.name.rawValue))",
            "Framing: \(displayLabel(for: shotSpec.composition.framing.rawValue))"
        ]

        if let colorIntent = shotSpec.style.colorIntent {
            summary.append("Color: \(displayLabel(for: colorIntent.rawValue))")
        }

        let promptSummary = compactPromptQuery(from: prompt)
        if !promptSummary.isEmpty {
            summary.append("Prompt: \(promptSummary)")
        }

        if includeLearnedSignals,
           let topSignal = profile.learningInsight(maxSignals: 1).topSignals.first {
            summary.append("Learned: \(topSignal.label)")
        }

        if includePublicReferences {
            summary.append("References: Public inspiration summaries")
        }

        return uniqueNonEmpty(summary)
    }

    private func creativeSuggestions(
        for shotSpec: ShotSpec,
        prompt: String,
        profile: PersonalVisualPreferenceProfile,
        includeLearnedSignals: Bool,
        includePublicReferences: Bool
    ) -> [CreativeInterpretationPlan.Suggestion] {
        var suggestions: [CreativeInterpretationPlan.Suggestion] = []

        func append(_ suggestion: CreativeInterpretationPlan.Suggestion) {
            guard !suggestions.contains(where: { $0.id == suggestion.id }) else { return }
            suggestions.append(suggestion)
        }

        switch shotSpec.style.name {
        case .cinematic:
            append(CreativeInterpretationPlan.Suggestion(
                id: "cinematic_side_light",
                category: .lighting,
                title: "Shape the Light",
                instruction: "Favor side light or backlight, then keep face detail readable."
            ))
            append(CreativeInterpretationPlan.Suggestion(
                id: "cinematic_color_separation",
                category: .color,
                title: "Separate Color",
                instruction: "Look for warm highlights with cooler shadow separation."
            ))
        case .professional:
            append(CreativeInterpretationPlan.Suggestion(
                id: "professional_clean_lines",
                category: .composition,
                title: "Clean the Frame",
                instruction: "Keep the background simple and vertical lines straight."
            ))
        case .travel:
            append(CreativeInterpretationPlan.Suggestion(
                id: "travel_place_cue",
                category: .composition,
                title: "Keep the Place Cue",
                instruction: "Include one recognizable location detail without crowding the subject."
            ))
        case .night:
            append(CreativeInterpretationPlan.Suggestion(
                id: "night_stability",
                category: .lighting,
                title: "Stabilize the Shot",
                instruction: "Use bright edges or signage, then hold the phone steady before capture."
            ))
        case .sky:
            append(CreativeInterpretationPlan.Suggestion(
                id: "sky_highlight_guard",
                category: .composition,
                title: "Protect the Sky",
                instruction: "Place the horizon low enough for sky drama while protecting highlights."
            ))
        case .portrait, .lifestyle:
            append(CreativeInterpretationPlan.Suggestion(
                id: "portrait_subject_space",
                category: .lens,
                title: "Give Subject Space",
                instruction: "Step back slightly for flattering perspective and cleaner separation."
            ))
        case .natural, .custom:
            break
        }

        if let mood = shotSpec.style.mood {
            switch mood {
            case .dramatic, .moody:
                append(CreativeInterpretationPlan.Suggestion(
                    id: "mood_shadow_control",
                    category: .lighting,
                    title: "Use Shadows",
                    instruction: "Let shadows add shape, but keep the main subject easy to read."
                ))
            case .luxury:
                append(CreativeInterpretationPlan.Suggestion(
                    id: "mood_luxury_polish",
                    category: .color,
                    title: "Polish the Palette",
                    instruction: "Choose clean textures, warm highlights, and fewer background colors."
                ))
            case .bright, .soft:
                append(CreativeInterpretationPlan.Suggestion(
                    id: "mood_soft_light",
                    category: .lighting,
                    title: "Soften Contrast",
                    instruction: "Find open shade or window light so skin and highlights stay gentle."
                ))
            case .documentary:
                append(CreativeInterpretationPlan.Suggestion(
                    id: "mood_documentary_context",
                    category: .composition,
                    title: "Keep Context",
                    instruction: "Leave enough environment in frame to explain the moment."
                ))
            }
        }

        if shotSpec.subject.primary == .person || shotSpec.subject.primary == .people {
            append(CreativeInterpretationPlan.Suggestion(
                id: "person_face_priority",
                category: .lighting,
                title: "Prioritize Face Light",
                instruction: "Turn the subject toward cleaner light before refining background."
            ))
        }

        if shotSpec.composition.skyPriority == .high {
            append(CreativeInterpretationPlan.Suggestion(
                id: "composition_more_sky",
                category: .composition,
                title: "Leave Sky Room",
                instruction: "Tilt just enough to add sky while keeping the subject anchored."
            ))
        }

        if includePublicReferences || containsAny(prompt, terms: ["reference", "inspiration", "online", "trend"]) {
            append(CreativeInterpretationPlan.Suggestion(
                id: "reference_compare_public_sources",
                category: .reference,
                title: "Compare References",
                instruction: "Use public references for light, angle, and framing cues only."
            ))
        }

        if includeLearnedSignals,
           let topSignal = profile.learningInsight(maxSignals: 1).topSignals.first {
            append(CreativeInterpretationPlan.Suggestion(
                id: "learned_preference_\(topSignal.id)",
                category: .composition,
                title: "Respect Learned Taste",
                instruction: "Blend the learned \(topSignal.label.lowercased()) preference into this shot."
            ))
        }

        let safetySuggestion = CreativeInterpretationPlan.Suggestion(
            id: "capture_realistic_boundary",
            category: .safety,
            title: "Stay Capture-Realistic",
            instruction: "Treat this as a camera brief; avoid promising generated edits in preview."
        )
        append(safetySuggestion)

        let requiredSuggestionIds: Set<String> = [
            "reference_compare_public_sources",
            safetySuggestion.id
        ]
        let requiredSuggestions = suggestions.filter { requiredSuggestionIds.contains($0.id) }
        let optionalSuggestions = suggestions.filter { !requiredSuggestionIds.contains($0.id) }
        return Array(optionalSuggestions.prefix(max(0, 6 - requiredSuggestions.count))) + requiredSuggestions
    }

    private func bump(_ values: inout [String: Double], key: String, amount: Double) {
        guard !key.isEmpty, amount.isFinite else { return }
        values[key] = PersonalVisualPreferenceProfile.clampAffinity((values[key] ?? 0) + amount)
    }

    private func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func compactPromptQuery(from prompt: String) -> String {
        prompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(10)
            .joined(separator: " ")
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }

    private func displayLabel(for key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
