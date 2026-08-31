import Foundation

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
    case invalidHTTPStatus(Int)
    case apiError(String)
    case incompleteResponse(String)
    case missingResult
    case invalidProviderJSON
}

public struct LensPilotCreativeAPIHTTPResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public typealias LensPilotCreativeAPITransport = @Sendable (URLRequest) async throws -> LensPilotCreativeAPIHTTPResponse

public struct LensPilotCreativeInterpretationAPIProvider: HealthGatedCreativeInterpretationReasoningProvider {
    public static let defaultAPIVersion = "2026-08-31"

    public let provider: CreativeInterpretationRequest.Provider = .onlineReasoning

    private let apiURL: URL
    private let clientToken: String?
    private let timeoutSeconds: TimeInterval
    private let transport: LensPilotCreativeAPITransport

    public init(
        apiURL: URL,
        clientToken: String? = nil,
        timeoutSeconds: TimeInterval = 12,
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
        self.timeoutSeconds = max(3, timeoutSeconds)
        self.transport = transport ?? Self.urlSessionTransport
    }

    public static func configuredFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LensPilotCreativeInterpretationAPIProvider? {
        configured(
            apiURLValue: environment["LENSPILOT_CREATIVE_API_URL"],
            clientTokenValue: environment["LENSPILOT_CREATIVE_API_TOKEN"]
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
            clientTokenValue: bundle.object(forInfoDictionaryKey: "LENSPILOT_CREATIVE_API_TOKEN") as? String
        )
    }

    public static func configured(
        apiURLValue: String?,
        clientTokenValue: String?
    ) -> LensPilotCreativeInterpretationAPIProvider? {
        guard let rawURL = cleanedConfigValue(apiURLValue),
              let apiURL = URL(string: rawURL) else {
            return nil
        }

        return try? LensPilotCreativeInterpretationAPIProvider(
            apiURL: apiURL,
            clientToken: cleanedConfigValue(clientTokenValue)
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
        urlRequest.httpBody = body
        return urlRequest
    }

    public static func decodeProviderResult(from data: Data) throws -> CreativeInterpretationProviderResult {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw LensPilotCreativeInterpretationAPIProviderError.invalidProviderJSON
        }

        if let apiError = envelope.error {
            throw LensPilotCreativeInterpretationAPIProviderError.apiError(
                sanitizeError("\(apiError.code ?? "creative_api_error"): \(apiError.message ?? "Creative API failed")")
            )
        }

        if let status = envelope.status, status != "completed" {
            throw LensPilotCreativeInterpretationAPIProviderError.incompleteResponse(status)
        }

        guard let result = envelope.result else {
            throw LensPilotCreativeInterpretationAPIProviderError.missingResult
        }

        return result
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

    private static func isLocalDevelopmentHost(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }

    private static func sanitizeError(_ value: String) -> String {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(180))
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
    }
}
