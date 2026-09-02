import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LensPilotCreativeInterpretationAPIProviderError: Error, Equatable, Sendable {
    case missingAPIURL
    case invalidAPIURL
    case insecureAPIURL
    case missingHealthGate
    case unsafeRequest
    case unsafeHealthGate
    case requestEncodingFailed
    case requestSigningFailed
    case invalidHTTPStatus(Int)
    case apiError(String)
    case incompleteResponse(String)
    case missingResult
    case invalidProviderJSON
}

public extension LensPilotCreativeInterpretationAPIProviderError {
    var safeDiagnosticMessage: String {
        switch self {
        case .missingAPIURL:
            return "Creative API URL unavailable"
        case .invalidAPIURL:
            return "Creative API URL invalid"
        case .insecureAPIURL:
            return "Creative API must use HTTPS"
        case .missingHealthGate:
            return "Creative API request is not health-gated"
        case .unsafeRequest, .unsafeHealthGate:
            return "Unsafe creative API payload"
        case .requestEncodingFailed:
            return "Creative API request could not be prepared"
        case .requestSigningFailed:
            return "Creative API request could not be signed"
        case let .invalidHTTPStatus(statusCode):
            return statusCode == 429 ? "Creative provider is rate-limited" : "Creative API request failed (\(statusCode))"
        case let .apiError(message):
            if Self.isBillingBlockedMessage(message) {
                return "OpenAI credits exhausted"
            }
            if message.contains("openai_rate_limited") || message.contains("retryable") {
                return "Creative provider is rate-limited"
            }
            if message.contains("openai_authorization_failed") {
                return "Creative API authorization failed"
            }
            if message.contains("openai_model_unavailable") {
                return "Creative provider model unavailable"
            }
            return "Creative API response failed"
        case .incompleteResponse(_):
            return "Creative API response incomplete"
        case .missingResult, .invalidProviderJSON:
            return "Creative API response could not be read"
        }
    }

    var isProviderBillingBlocked: Bool {
        guard case let .apiError(message) = self else { return false }

        return Self.isBillingBlockedMessage(message)
    }

    private static func isBillingBlockedMessage(_ message: String) -> Bool {
        message.contains("openai_credit_balance_exhausted")
            || message.contains("credit_balance_exhausted")
            || message.contains("insufficient_quota")
            || message.contains("billing_blocked")
    }
}

public struct LensPilotCreativeAPIHTTPResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public struct LensPilotCreativeAPIConfigurationStatus: Codable, Equatable, Sendable {
    public let source: Source
    public let readiness: Readiness
    public let endpointHost: String?
    public let endpointPath: String?
    public let usesHTTPS: Bool
    public let hasClientToken: Bool
    public let hasSigningSecret: Bool
    public let allowsDirectOpenAIProvider: Bool
    public let warnings: [Warning]
    public let privacy: Privacy

    public init(
        source: Source,
        readiness: Readiness,
        endpointHost: String? = nil,
        endpointPath: String? = nil,
        usesHTTPS: Bool = false,
        hasClientToken: Bool = false,
        hasSigningSecret: Bool = false,
        allowsDirectOpenAIProvider: Bool = false,
        warnings: [Warning] = [],
        privacy: Privacy = Privacy()
    ) {
        self.source = source
        self.readiness = readiness
        self.endpointHost = endpointHost
        self.endpointPath = endpointPath
        self.usesHTTPS = usesHTTPS
        self.hasClientToken = hasClientToken
        self.hasSigningSecret = hasSigningSecret
        self.allowsDirectOpenAIProvider = allowsDirectOpenAIProvider
        self.warnings = warnings
        self.privacy = privacy
    }

    public static var offline: LensPilotCreativeAPIConfigurationStatus {
        LensPilotCreativeAPIConfigurationStatus(
            source: .none,
            readiness: .offline,
            warnings: [.missingAPIURL]
        )
    }
}

public extension LensPilotCreativeAPIConfigurationStatus {
    enum Source: String, Codable, Equatable, Sendable {
        case none
        case environment
        case bundle
    }

    enum Readiness: String, Codable, Equatable, Sendable {
        case offline
        case protected
        case needsProtection = "needs_protection"
        case blocked
    }

    enum Warning: String, Codable, Equatable, Sendable {
        case missingAPIURL = "missing_api_url"
        case unresolvedBuildSetting = "unresolved_build_setting"
        case invalidAPIURL = "invalid_api_url"
        case insecureAPIURL = "insecure_api_url"
        case localDevelopmentAPIURL = "local_development_api_url"
        case missingClientToken = "missing_client_token"
        case missingSigningSecret = "missing_signing_secret"
        case directOpenAIProviderAllowed = "direct_openai_provider_allowed"
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let keepsOpenAIKeyOnServer: Bool
        public let acceptsClientOpenAIKey: Bool
        public let uploadsLiveCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool
        public let sendsRawLearningEvents: Bool

        public init(
            singlePhoneOnly: Bool = true,
            keepsOpenAIKeyOnServer: Bool = true,
            acceptsClientOpenAIKey: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false,
            sendsRawLearningEvents: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.keepsOpenAIKeyOnServer = keepsOpenAIKeyOnServer
            self.acceptsClientOpenAIKey = acceptsClientOpenAIKey
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
            self.sendsRawLearningEvents = sendsRawLearningEvents
        }
    }

    var isProtectedForProduction: Bool {
        readiness == .protected
    }

    var diagnosticDetail: String {
        switch readiness {
        case .protected:
            return "Signed backend ready"
        case .offline:
            return warnings.contains(.unresolvedBuildSetting) ? "Generated config missing" : "Offline camera mode"
        case .needsProtection:
            if warnings.contains(.localDevelopmentAPIURL) {
                return "Local backend only"
            }
            if warnings.contains(.missingSigningSecret) {
                return "Add request signing"
            }
            if warnings.contains(.missingClientToken) {
                return "Add phone auth"
            }
            return "Needs phone protection"
        case .blocked:
            if warnings.contains(.directOpenAIProviderAllowed) {
                return "Direct OpenAI enabled"
            }
            if warnings.contains(.insecureAPIURL) {
                return "HTTPS required"
            }
            if warnings.contains(.invalidAPIURL) {
                return "Invalid backend URL"
            }
            return "Unsafe backend config"
        }
    }
}

public typealias LensPilotCreativeAPITransport = @Sendable (URLRequest) async throws -> LensPilotCreativeAPIHTTPResponse

public struct LensPilotCreativeInterpretationAPIProvider: HealthGatedCreativeInterpretationReasoningProvider {
    public static let defaultAPIVersion = "2026-08-31"

    public let provider: CreativeInterpretationRequest.Provider = .onlineReasoning

    private let apiURL: URL
    private let clientToken: String?
    private let signingSecret: String?
    private let timeoutSeconds: TimeInterval
    private let clock: @Sendable () -> Date
    private let requestIDGenerator: @Sendable () -> String
    private let transport: LensPilotCreativeAPITransport

    public init(
        apiURL: URL,
        clientToken: String? = nil,
        signingSecret: String? = nil,
        timeoutSeconds: TimeInterval = 12,
        clock: @escaping @Sendable () -> Date = Date.init,
        requestIDGenerator: @escaping @Sendable () -> String = { UUID().uuidString },
        transport: LensPilotCreativeAPITransport? = nil
    ) throws {
        guard let scheme = apiURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = apiURL.host,
              !host.isEmpty else {
            throw LensPilotCreativeInterpretationAPIProviderError.invalidAPIURL
        }
        guard scheme == "https" || Self.isLocalDevelopmentHost(host) else {
            throw LensPilotCreativeInterpretationAPIProviderError.insecureAPIURL
        }

        self.apiURL = apiURL
        self.clientToken = Self.cleanedOptional(clientToken)
        self.signingSecret = Self.cleanedOptional(signingSecret)
        self.timeoutSeconds = max(3, timeoutSeconds)
        self.clock = clock
        self.requestIDGenerator = requestIDGenerator
        self.transport = transport ?? Self.urlSessionTransport
    }

    public static func configurationStatusFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LensPilotCreativeAPIConfigurationStatus {
        configurationStatus(
            apiURLValue: environment["LENSPILOT_CREATIVE_API_URL"],
            clientTokenValue: environment["LENSPILOT_CREATIVE_API_TOKEN"],
            signingSecretValue: environment["LENSPILOT_CREATIVE_API_SIGNING_SECRET"],
            directOpenAIProviderAllowed: allowsDirectOpenAIProvider(environment),
            source: .environment
        )
    }

    public static func configurationStatusFromBundle(
        _ bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LensPilotCreativeAPIConfigurationStatus {
        let environmentStatus = configurationStatusFromEnvironment(environment)
        if environmentStatus.source != .none || environmentStatus.allowsDirectOpenAIProvider {
            return environmentStatus
        }

        return configurationStatus(
            apiURLValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_URL") as? String,
            clientTokenValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_TOKEN") as? String,
            signingSecretValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_SIGNING_SECRET") as? String,
            directOpenAIProviderAllowed: environmentStatus.allowsDirectOpenAIProvider,
            source: .bundle
        )
    }

    public static func configurationStatus(
        apiURLValue: String?,
        clientTokenValue: String?,
        signingSecretValue: String? = nil,
        directOpenAIProviderAllowed: Bool = false,
        source: LensPilotCreativeAPIConfigurationStatus.Source
    ) -> LensPilotCreativeAPIConfigurationStatus {
        var warnings: [LensPilotCreativeAPIConfigurationStatus.Warning] = []
        if directOpenAIProviderAllowed {
            warnings.append(.directOpenAIProviderAllowed)
        }
        if containsUnresolvedBuildSetting(apiURLValue)
            || containsUnresolvedBuildSetting(clientTokenValue)
            || containsUnresolvedBuildSetting(signingSecretValue) {
            warnings.append(.unresolvedBuildSetting)
        }

        guard let rawURL = cleanedConfigValue(apiURLValue) else {
            warnings.append(.missingAPIURL)
            return LensPilotCreativeAPIConfigurationStatus(
                source: cleanedOptional(apiURLValue) == nil ? .none : source,
                readiness: directOpenAIProviderAllowed ? .blocked : .offline,
                allowsDirectOpenAIProvider: directOpenAIProviderAllowed,
                warnings: warnings
            )
        }

        guard let apiURL = URL(string: rawURL),
              let scheme = apiURL.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = apiURL.host,
              !host.isEmpty else {
            warnings.append(.invalidAPIURL)
            return LensPilotCreativeAPIConfigurationStatus(
                source: source,
                readiness: .blocked,
                allowsDirectOpenAIProvider: directOpenAIProviderAllowed,
                warnings: warnings
            )
        }

        let usesHTTPS = scheme == "https"
        let isLocalDevelopmentAPI = !usesHTTPS && isLocalDevelopmentHost(host)
        if isLocalDevelopmentAPI {
            warnings.append(.localDevelopmentAPIURL)
        } else if !usesHTTPS {
            warnings.append(.insecureAPIURL)
        }

        let hasClientToken = cleanedConfigValue(clientTokenValue) != nil
        let hasSigningSecret = cleanedConfigValue(signingSecretValue) != nil
        if !hasClientToken {
            warnings.append(.missingClientToken)
        }
        if !hasSigningSecret {
            warnings.append(.missingSigningSecret)
        }

        let readiness: LensPilotCreativeAPIConfigurationStatus.Readiness
        if directOpenAIProviderAllowed || warnings.contains(.insecureAPIURL) {
            readiness = .blocked
        } else if usesHTTPS && hasClientToken && hasSigningSecret {
            readiness = .protected
        } else {
            readiness = .needsProtection
        }

        return LensPilotCreativeAPIConfigurationStatus(
            source: source,
            readiness: readiness,
            endpointHost: host,
            endpointPath: normalizedSigningPath(apiURL.path),
            usesHTTPS: usesHTTPS,
            hasClientToken: hasClientToken,
            hasSigningSecret: hasSigningSecret,
            allowsDirectOpenAIProvider: directOpenAIProviderAllowed,
            warnings: warnings
        )
    }

    public static func allowsDirectOpenAIProvider(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let setting = environment["LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(setting ?? "")
    }

    public static func configuredFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LensPilotCreativeInterpretationAPIProvider? {
        configured(
            apiURLValue: environment["LENSPILOT_CREATIVE_API_URL"],
            clientTokenValue: environment["LENSPILOT_CREATIVE_API_TOKEN"],
            signingSecretValue: environment["LENSPILOT_CREATIVE_API_SIGNING_SECRET"]
        )
    }

    public static func configuredFromBundle(
        _ bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LensPilotCreativeInterpretationAPIProvider? {
        if let environmentProvider = configuredFromEnvironment(environment) {
            return environmentProvider
        }

        return configured(
            apiURLValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_URL") as? String,
            clientTokenValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_TOKEN") as? String,
            signingSecretValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_SIGNING_SECRET") as? String
        )
    }

    public static func configured(
        apiURLValue: String?,
        clientTokenValue: String?,
        signingSecretValue: String? = nil
    ) -> LensPilotCreativeInterpretationAPIProvider? {
        guard let rawURL = cleanedConfigValue(apiURLValue),
              let apiURL = URL(string: rawURL) else {
            return nil
        }

        return try? LensPilotCreativeInterpretationAPIProvider(
            apiURL: apiURL,
            clientToken: cleanedConfigValue(clientTokenValue),
            signingSecret: cleanedConfigValue(signingSecretValue)
        )
    }

    public func interpret(request: CreativeInterpretationRequest) async throws -> CreativeInterpretationProviderResult {
        throw LensPilotCreativeInterpretationAPIProviderError.missingHealthGate
    }

    public func interpret(
        request: CreativeInterpretationRequest,
        healthGate: CreativeInterpretationProviderHealthGate
    ) async throws -> CreativeInterpretationProviderResult {
        guard request.payloadAudit.safeToSend,
              request.privacy.isSafeForSinglePhoneCreativeReasoning else {
            throw LensPilotCreativeInterpretationAPIProviderError.unsafeRequest
        }
        guard healthGate.canRunProvider,
              healthGate.payloadAudit.safeToSend,
              healthGate.privacy.isSafeForSinglePhoneProvider else {
            throw LensPilotCreativeInterpretationAPIProviderError.unsafeHealthGate
        }

        let urlRequest = try makeURLRequest(for: request, healthGate: healthGate)
        let response = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            if let apiError = Self.decodeAPIError(from: response.data) {
                throw apiError
            }
            throw LensPilotCreativeInterpretationAPIProviderError.invalidHTTPStatus(response.statusCode)
        }

        let result = try Self.decodeProviderResult(from: response.data)
        guard !result.guidance.isEmpty else {
            throw CreativeInterpretationAdapterError.emptyProviderOutput
        }
        guard result.isSafeForSinglePhoneCreativeReasoning else {
            throw CreativeInterpretationAdapterError.unsafeProviderResponse
        }

        return result
    }

    public func makeURLRequest(
        for request: CreativeInterpretationRequest,
        healthGate: CreativeInterpretationProviderHealthGate
    ) throws -> URLRequest {
        let envelope = RequestEnvelope(
            request: request,
            healthGate: healthGate,
            client: ClientEnvelope(platform: "ios")
        )

        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(envelope) else {
            throw LensPilotCreativeInterpretationAPIProviderError.requestEncodingFailed
        }

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("ios", forHTTPHeaderField: "X-LensPilot-Client")
        if let clientToken {
            urlRequest.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        }
        if let signingSecret {
            let requestID = requestIDGenerator()
            let timestampMilliseconds = Int64((clock().timeIntervalSince1970 * 1000).rounded(.down))
            let signature = try Self.makeRequestSignature(
                secret: signingSecret,
                method: "POST",
                path: apiURL.path,
                timestampMilliseconds: timestampMilliseconds,
                requestID: requestID,
                body: body
            )
            urlRequest.setValue(requestID, forHTTPHeaderField: "X-LensPilot-Request-Id")
            urlRequest.setValue(String(timestampMilliseconds), forHTTPHeaderField: "X-LensPilot-Timestamp")
            urlRequest.setValue(signature, forHTTPHeaderField: "X-LensPilot-Signature")
        }
        urlRequest.httpBody = body
        return urlRequest
    }

    static func makeRequestSignature(
        secret: String,
        method: String,
        path: String,
        timestampMilliseconds: Int64,
        requestID: String,
        body: Data
    ) throws -> String {
        #if canImport(CryptoKit)
        guard let secretData = cleanedOptional(secret).map({ Data($0.utf8) }),
              !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LensPilotCreativeInterpretationAPIProviderError.requestSigningFailed
        }

        let bodyDigest = SHA256.hash(data: body)
        let bodyHash = Data(bodyDigest).map { String(format: "%02x", $0) }.joined()
        let canonical = [
            "v1",
            method.uppercased(),
            normalizedSigningPath(path),
            String(timestampMilliseconds),
            requestID,
            bodyHash
        ].joined(separator: "\n")
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: secretData)
        )

        return "v1=\(Data(authenticationCode).base64URLEncodedString())"
        #else
        throw LensPilotCreativeInterpretationAPIProviderError.requestSigningFailed
        #endif
    }

    public static func decodeProviderResult(from data: Data) throws -> CreativeInterpretationProviderResult {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw LensPilotCreativeInterpretationAPIProviderError.invalidProviderJSON
        }

        if let apiError = envelope.error {
            throw makeAPIError(from: apiError)
        }

        if let status = envelope.status, status != "completed" {
            throw LensPilotCreativeInterpretationAPIProviderError.incompleteResponse(status)
        }

        guard let result = envelope.result else {
            throw LensPilotCreativeInterpretationAPIProviderError.missingResult
        }

        return result
    }

    private static func decodeAPIError(from data: Data) -> LensPilotCreativeInterpretationAPIProviderError? {
        guard let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
              let apiError = envelope.error else {
            return nil
        }

        return makeAPIError(from: apiError)
    }

    private static func makeAPIError(from apiError: ResponseEnvelope.APIError) -> LensPilotCreativeInterpretationAPIProviderError {
        var safeParts = [apiError.code ?? "creative_api_error"]
        if let providerStatus = apiError.providerStatus {
            safeParts.append("provider_status_\(providerStatus)")
        }
        if let providerErrorCode = apiError.providerErrorCode {
            safeParts.append(providerErrorCode)
        }
        if let providerErrorType = apiError.providerErrorType {
            safeParts.append(providerErrorType)
        }
        if apiError.blockedByBilling == true {
            safeParts.append("billing_blocked")
        }
        if apiError.retryable == true {
            safeParts.append("retryable")
        }
        safeParts.append(apiError.message ?? "Creative API failed")

        return LensPilotCreativeInterpretationAPIProviderError.apiError(
            sanitizeError(safeParts.joined(separator: ": "))
        )
    }

    private static let urlSessionTransport: LensPilotCreativeAPITransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return LensPilotCreativeAPIHTTPResponse(
            data: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
        )
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func cleanedConfigValue(_ value: String?) -> String? {
        guard let cleaned = cleanedOptional(value),
              !cleaned.contains("$("),
              !cleaned.contains("${") else {
            return nil
        }
        return cleaned
    }

    private static func containsUnresolvedBuildSetting(_ value: String?) -> Bool {
        guard let cleaned = cleanedOptional(value) else { return false }
        return cleaned.contains("$(") || cleaned.contains("${")
    }

    private static func isLocalDevelopmentHost(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }

    private static func normalizedSigningPath(_ path: String) -> String {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let withSlash = cleaned.hasPrefix("/") ? cleaned : "/\(cleaned)"
        let trimmed = withSlash.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? "/" : trimmed
    }

    private static func sanitizeError(_ value: String) -> String {
        let collapsed = redactSecretLikeTokens(value)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(180))
    }

    private static func redactSecretLikeTokens(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                let normalized = token.lowercased()
                if normalized.contains("openai_api_key")
                    || normalized.hasPrefix("sk-")
                    || normalized.contains("=sk-")
                    || normalized.contains(":sk-")
                    || normalized.contains("sk-proj-") {
                    return "[redacted]"
                }

                return String(token)
            }
            .joined(separator: " ")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct RequestEnvelope: Encodable {
    let apiVersion: String
    let request: CreativeInterpretationRequest
    let healthGate: CreativeInterpretationProviderHealthGate
    let client: ClientEnvelope

    init(
        apiVersion: String = LensPilotCreativeInterpretationAPIProvider.defaultAPIVersion,
        request: CreativeInterpretationRequest,
        healthGate: CreativeInterpretationProviderHealthGate,
        client: ClientEnvelope
    ) {
        self.apiVersion = apiVersion
        self.request = request
        self.healthGate = healthGate
        self.client = client
    }
}

private struct ClientEnvelope: Codable, Equatable, Sendable {
    let platform: String
}

private struct ResponseEnvelope: Decodable {
    let status: String?
    let provider: CreativeInterpretationRequest.Provider?
    let result: CreativeInterpretationProviderResult?
    let error: APIError?

    struct APIError: Decodable {
        let code: String?
        let message: String?
        let providerStatus: Int?
        let providerErrorType: String?
        let providerErrorCode: String?
        let providerErrorParam: String?
        let retryable: Bool?
        let blockedByBilling: Bool?
    }
}
