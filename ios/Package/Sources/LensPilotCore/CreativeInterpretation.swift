import Foundation

public enum CreativeInterpretationAdapterError: Error, Equatable, Sendable {
    case blockedByHealthGate([CreativeInterpretationProviderHealthGate.DeniedReason])
    case emptyProviderOutput
    case unsafeProviderResponse
}

public struct CreativeInterpretationProviderHealthGate: Codable, Equatable, Sendable {
    public let canRunProvider: Bool
    public let deniedReasons: [DeniedReason]
    public let providerHealthStatus: OnlineInspirationHealthSnapshot.Status?
    public let publicReferenceCount: Int
    public let payloadAudit: CreativeInterpretationPayloadAudit
    public let privacy: Privacy

    public init(
        canRunProvider: Bool,
        deniedReasons: [DeniedReason],
        providerHealthStatus: OnlineInspirationHealthSnapshot.Status?,
        publicReferenceCount: Int,
        payloadAudit: CreativeInterpretationPayloadAudit,
        privacy: Privacy
    ) {
        let uniqueDeniedReasons = Array(Set(deniedReasons)).sorted { $0.rawValue < $1.rawValue }

        self.canRunProvider = canRunProvider && uniqueDeniedReasons.isEmpty
        self.deniedReasons = uniqueDeniedReasons
        self.providerHealthStatus = providerHealthStatus
        self.publicReferenceCount = max(0, publicReferenceCount)
        self.payloadAudit = payloadAudit
        self.privacy = privacy
    }

    public static func make(
        for request: CreativeInterpretationRequest,
        healthSnapshot: OnlineInspirationHealthSnapshot?
    ) -> CreativeInterpretationProviderHealthGate {
        let privacy = Privacy(requestPrivacy: request.privacy, healthSnapshotPrivacy: healthSnapshot?.privacy)
        var deniedReasons: [DeniedReason] = []

        if !request.payloadAudit.safeToSend {
            deniedReasons.append(.unsafeRequestPayload)
        }

        guard let healthSnapshot else {
            deniedReasons.append(.missingProviderHealth)
            return CreativeInterpretationProviderHealthGate(
                canRunProvider: false,
                deniedReasons: deniedReasons,
                providerHealthStatus: nil,
                publicReferenceCount: 0,
                payloadAudit: request.payloadAudit,
                privacy: privacy
            )
        }

        if !privacy.isSafeForSinglePhoneProvider
            || !healthSnapshot.providers.allSatisfy({ isSafeProviderPrivacy($0.privacy) }) {
            deniedReasons.append(.unsafeProviderHealth)
        }

        switch healthSnapshot.status {
        case .available, .degraded:
            break
        case .empty:
            deniedReasons.append(.noPublicReferences)
        case .failed:
            deniedReasons.append(.providerUnavailable)
        }

        if healthSnapshot.totalResultCount <= 0 {
            deniedReasons.append(.noPublicReferences)
        }

        return CreativeInterpretationProviderHealthGate(
            canRunProvider: true,
            deniedReasons: deniedReasons,
            providerHealthStatus: healthSnapshot.status,
            publicReferenceCount: healthSnapshot.totalResultCount,
            payloadAudit: request.payloadAudit,
            privacy: privacy
        )
    }

    private static func isSafeProviderPrivacy(_ privacy: OnlineInspirationProviderHealth.Privacy) -> Bool {
        privacy.publicSourceOnly
            && privacy.derivedFromPromptOnly
            && !privacy.storesRawPhoto
            && !privacy.uploadsLiveCameraFrame
            && !privacy.sendsIdentityData
            && !privacy.sendsPreciseLocation
    }
}

public extension CreativeInterpretationProviderHealthGate {
    enum DeniedReason: String, Codable, Equatable, Sendable, Hashable {
        case unsafeRequestPayload = "unsafe_request_payload"
        case missingProviderHealth = "missing_provider_health"
        case unsafeProviderHealth = "unsafe_provider_health"
        case providerUnavailable = "provider_unavailable"
        case noPublicReferences = "no_public_references"
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let requiresUserConsent: Bool
        public let sendsRawCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool
        public let sendsRawLearningEvents: Bool

        public init(
            singlePhoneOnly: Bool = true,
            requiresUserConsent: Bool = true,
            sendsRawCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false,
            sendsRawLearningEvents: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.requiresUserConsent = requiresUserConsent
            self.sendsRawCameraFrame = sendsRawCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
            self.sendsRawLearningEvents = sendsRawLearningEvents
        }

        public init(
            requestPrivacy: CreativeInterpretationPlan.Privacy,
            healthSnapshotPrivacy: OnlineInspirationHealthSnapshot.Privacy?
        ) {
            self.init(
                singlePhoneOnly: requestPrivacy.singlePhoneOnly && (healthSnapshotPrivacy?.singlePhoneOnly ?? true),
                requiresUserConsent: requestPrivacy.requiresUserConsent && (healthSnapshotPrivacy?.requiresUserConsent ?? true),
                sendsRawCameraFrame: requestPrivacy.sendsRawCameraFrame || (healthSnapshotPrivacy?.sendsRawCameraFrame ?? false),
                sendsPrivatePhoto: requestPrivacy.sendsPrivatePhoto || (healthSnapshotPrivacy?.sendsPrivatePhoto ?? false),
                sendsIdentityData: requestPrivacy.sendsIdentityData || (healthSnapshotPrivacy?.sendsIdentityData ?? false),
                sendsPreciseLocation: requestPrivacy.sendsPreciseLocation || (healthSnapshotPrivacy?.sendsPreciseLocation ?? false),
                sendsRawLearningEvents: requestPrivacy.sendsRawLearningEvents
            )
        }

        public var isSafeForSinglePhoneProvider: Bool {
            singlePhoneOnly
                && requiresUserConsent
                && !sendsRawCameraFrame
                && !sendsPrivatePhoto
                && !sendsIdentityData
                && !sendsPreciseLocation
                && !sendsRawLearningEvents
        }
    }
}

public struct CreativeInterpretationProviderResult: Codable, Equatable, Sendable {
    public let headline: String
    public let guidance: [String]

    public init(headline: String, guidance: [String]) {
        self.headline = Self.cleanedText(headline, maxLength: 96)
        self.guidance = guidance
            .map { Self.cleanedText($0, maxLength: 180) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { $0 }
    }

    private static func cleanedText(_ value: String, maxLength: Int) -> String {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else { return collapsed }

        return String(collapsed.prefix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol CreativeInterpretationReasoningProvider: Sendable {
    var provider: CreativeInterpretationRequest.Provider { get }
    func interpret(request: CreativeInterpretationRequest) async throws -> CreativeInterpretationProviderResult
}

public struct CreativeInterpretationHeuristicProvider: CreativeInterpretationReasoningProvider {
    public let provider: CreativeInterpretationRequest.Provider

    public init(provider: CreativeInterpretationRequest.Provider = .onlineReasoning) {
        self.provider = provider
    }

    public func interpret(request: CreativeInterpretationRequest) async throws -> CreativeInterpretationProviderResult {
        guard request.payloadAudit.safeToSend else {
            throw CreativeInterpretationError.unsafePlan(request.payloadAudit.deniedReasons)
        }

        let guidance = Self.guidance(from: request)
        guard !guidance.isEmpty else {
            throw CreativeInterpretationAdapterError.emptyProviderOutput
        }

        return CreativeInterpretationProviderResult(
            headline: provider == .onlineReasoning ? "Provider-Ready Creative Brief" : "Local Creative Brief",
            guidance: guidance
        )
    }

    private static func guidance(from request: CreativeInterpretationRequest) -> [String] {
        var remainingWords = request.maxResponseWords
        var guidance: [String] = []
        let briefs = prioritizedBriefs(from: request)

        for brief in briefs where remainingWords > 0 {
            let words = brief.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else { continue }

            let wordCount = min(words.count, remainingWords)
            guidance.append(words.prefix(wordCount).joined(separator: " "))
            remainingWords -= wordCount
        }

        return guidance
    }

    private static func prioritizedBriefs(from request: CreativeInterpretationRequest) -> [String] {
        guard let safetyBrief = request.suggestionBriefs.first(where: {
            $0.localizedCaseInsensitiveContains("Capture-Realistic")
        }) else {
            return Array(request.suggestionBriefs.prefix(4))
        }

        let primaryBriefs = request.suggestionBriefs
            .filter { $0 != safetyBrief }
            .prefix(3)
        return Array(primaryBriefs) + [safetyBrief]
    }
}

public struct CreativeInterpretationResponse: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let planId: String
    public let provider: CreativeInterpretationRequest.Provider
    public let status: Status
    public let headline: String
    public let guidance: [String]
    public let maxResponseWords: Int
    public let generatedAt: Date
    public let payloadAudit: CreativeInterpretationPayloadAudit
    public let healthGate: CreativeInterpretationProviderHealthGate
    public let privacy: Privacy

    public init(
        planId: String,
        provider: CreativeInterpretationRequest.Provider,
        status: Status = .completed,
        result: CreativeInterpretationProviderResult,
        maxResponseWords: Int,
        generatedAt: Date = Date(),
        payloadAudit: CreativeInterpretationPayloadAudit,
        healthGate: CreativeInterpretationProviderHealthGate,
        privacy: Privacy = Privacy()
    ) {
        self.id = "creative_interpretation_response_\(planId)_\(provider.rawValue)"
        self.planId = planId
        self.provider = provider
        self.status = status
        self.headline = result.headline
        self.guidance = result.guidance
        self.maxResponseWords = min(240, max(40, maxResponseWords))
        self.generatedAt = generatedAt
        self.payloadAudit = payloadAudit
        self.healthGate = healthGate
        self.privacy = privacy
    }
}

public extension CreativeInterpretationResponse {
    enum Status: String, Codable, Equatable, Sendable {
        case completed
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let usesAuditedPayload: Bool
        public let usesProviderHealthGate: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool
        public let sendsRawLearningEvents: Bool
        public let allowsGenerativeImageOutput: Bool

        public init(
            singlePhoneOnly: Bool = true,
            usesAuditedPayload: Bool = true,
            usesProviderHealthGate: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false,
            sendsRawLearningEvents: Bool = false,
            allowsGenerativeImageOutput: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.usesAuditedPayload = usesAuditedPayload
            self.usesProviderHealthGate = usesProviderHealthGate
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
            self.sendsRawLearningEvents = sendsRawLearningEvents
            self.allowsGenerativeImageOutput = allowsGenerativeImageOutput
        }

        public var isSafeForSinglePhoneCreativeReasoning: Bool {
            singlePhoneOnly
                && usesAuditedPayload
                && usesProviderHealthGate
                && !storesRawPhoto
                && !uploadsLiveCameraFrame
                && !sendsPrivatePhoto
                && !sendsIdentityData
                && !sendsPreciseLocation
                && !sendsRawLearningEvents
                && !allowsGenerativeImageOutput
        }
    }
}

public struct HealthGatedCreativeInterpretationAdapter: Sendable {
    private let provider: any CreativeInterpretationReasoningProvider

    public init(provider: any CreativeInterpretationReasoningProvider = CreativeInterpretationHeuristicProvider()) {
        self.provider = provider
    }

    public func interpret(
        for plan: CreativeInterpretationPlan,
        providerHealthSnapshot: OnlineInspirationHealthSnapshot?,
        maxResponseWords: Int = 120,
        generatedAt: Date = Date()
    ) async throws -> CreativeInterpretationResponse {
        let request = try CreativeInterpretationRequest(
            plan: plan,
            provider: provider.provider,
            maxResponseWords: maxResponseWords
        )
        let healthGate = CreativeInterpretationProviderHealthGate.make(
            for: request,
            healthSnapshot: providerHealthSnapshot
        )

        guard healthGate.canRunProvider else {
            throw CreativeInterpretationAdapterError.blockedByHealthGate(healthGate.deniedReasons)
        }

        let result = try await provider.interpret(request: request)
        guard !result.guidance.isEmpty else {
            throw CreativeInterpretationAdapterError.emptyProviderOutput
        }

        let response = CreativeInterpretationResponse(
            planId: request.planId,
            provider: request.provider,
            result: result,
            maxResponseWords: request.maxResponseWords,
            generatedAt: generatedAt,
            payloadAudit: request.payloadAudit,
            healthGate: healthGate
        )

        guard response.privacy.isSafeForSinglePhoneCreativeReasoning else {
            throw CreativeInterpretationAdapterError.unsafeProviderResponse
        }

        return response
    }
}
