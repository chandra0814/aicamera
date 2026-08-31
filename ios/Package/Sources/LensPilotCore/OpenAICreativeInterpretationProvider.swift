import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAICreativeInterpretationProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case unsafeRequest
    case requestEncodingFailed
    case invalidHTTPStatus(Int)
    case apiError(String)
    case incompleteResponse(String)
    case missingOutputText
    case invalidProviderJSON
}

public struct OpenAIReasoningHTTPResponse: Equatable, Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public typealias OpenAIReasoningTransport = @Sendable (URLRequest) async throws -> OpenAIReasoningHTTPResponse

public struct OpenAICreativeInterpretationProvider: CreativeInterpretationReasoningProvider {
    public static let defaultModel = "gpt-5.6-luna"
    public static let defaultAPIURL = URL(string: "https://api.openai.com/v1/responses")!

    public let provider: CreativeInterpretationRequest.Provider = .onlineReasoning

    private let apiKey: String
    private let model: String
    private let apiURL: URL
    private let timeoutSeconds: TimeInterval
    private let allowsWebSearch: Bool
    private let transport: OpenAIReasoningTransport

    public init(
        apiKey: String,
        model: String = Self.defaultModel,
        apiURL: URL = Self.defaultAPIURL,
        timeoutSeconds: TimeInterval = 12,
        allowsWebSearch: Bool = true,
        transport: OpenAIReasoningTransport? = nil
    ) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAICreativeInterpretationProviderError.missingAPIKey
        }
        guard !trimmedModel.isEmpty else {
            throw OpenAICreativeInterpretationProviderError.requestEncodingFailed
        }

        self.apiKey = trimmedKey
        self.model = trimmedModel
        self.apiURL = apiURL
        self.timeoutSeconds = max(3, timeoutSeconds)
        self.allowsWebSearch = allowsWebSearch
        self.transport = transport ?? Self.urlSessionTransport
    }

    public static func configuredFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> OpenAICreativeInterpretationProvider? {
        guard let apiKey = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        let model = environment["LENSPILOT_OPENAI_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultModel
        let webSearchSetting = environment["LENSPILOT_OPENAI_WEB_SEARCH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowsWebSearch = !["0", "false", "no", "off"].contains(webSearchSetting ?? "")

        return try? OpenAICreativeInterpretationProvider(
            apiKey: apiKey,
            model: resolvedModel,
            allowsWebSearch: allowsWebSearch
        )
    }

    public func interpret(request: CreativeInterpretationRequest) async throws -> CreativeInterpretationProviderResult {
        guard request.payloadAudit.safeToSend,
              request.privacy.isSafeForSinglePhoneCreativeReasoning else {
            throw OpenAICreativeInterpretationProviderError.unsafeRequest
        }

        let urlRequest = try makeURLRequest(for: request)
        let response = try await transport(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenAICreativeInterpretationProviderError.invalidHTTPStatus(response.statusCode)
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

    public func makeURLRequest(for request: CreativeInterpretationRequest) throws -> URLRequest {
        let payload = makeResponsesPayload(for: request)
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            throw OpenAICreativeInterpretationProviderError.requestEncodingFailed
        }

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        return urlRequest
    }

    public func makeResponsesPayload(for request: CreativeInterpretationRequest) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "instructions": Self.instructions,
            "input": Self.inputText(from: request),
            "store": false,
            "max_output_tokens": min(640, max(96, request.maxResponseWords * 3)),
            "reasoning": [
                "effort": "low"
            ],
            "text": [
                "format": Self.responseFormat
            ],
            "metadata": [
                "lenspilot_plan_id": String(request.planId.prefix(64)),
                "lenspilot_provider": request.provider.rawValue,
                "lenspilot_payload": "audited_text_only"
            ]
        ]

        if allowsWebSearch {
            payload["tools"] = [
                [
                    "type": "web_search"
                ]
            ]
            payload["tool_choice"] = "auto"
            payload["max_tool_calls"] = 2
        }

        return payload
    }

    public static func decodeProviderResult(from data: Data) throws -> CreativeInterpretationProviderResult {
        let envelope: ResponsesEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        } catch {
            throw OpenAICreativeInterpretationProviderError.invalidProviderJSON
        }

        if let apiError = envelope.error {
            throw OpenAICreativeInterpretationProviderError.apiError(
                sanitizeError("\(apiError.code ?? "api_error"): \(apiError.message ?? "OpenAI response failed")")
            )
        }

        if let status = envelope.status, status != "completed" {
            throw OpenAICreativeInterpretationProviderError.incompleteResponse(status)
        }

        guard let outputText = envelope.outputText ?? envelope.firstOutputText,
              let outputData = outputText.data(using: .utf8) else {
            throw OpenAICreativeInterpretationProviderError.missingOutputText
        }

        let decoded: ProviderJSON
        do {
            decoded = try JSONDecoder().decode(ProviderJSON.self, from: outputData)
        } catch {
            throw OpenAICreativeInterpretationProviderError.invalidProviderJSON
        }

        return CreativeInterpretationProviderResult(
            headline: decoded.headline,
            guidance: decoded.guidance
        )
    }

    private static let urlSessionTransport: OpenAIReasoningTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return OpenAIReasoningHTTPResponse(
            data: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
        )
    }

    private static let instructions = """
    You are LensPilot AI's photography reasoning provider. Return only JSON matching the schema. Use only the audited text summary and public-reference context in the request. Do not ask for or mention uploading live camera frames, private photos, identity data, precise location, raw learning events, EXIF, base64, or photo bytes. Keep guidance capture-realistic, concise, and useful for one phone in the user's hand. Do not promise generated edits, object removal, sky replacement, or a synthetic final image.
    """

    private static func inputText(from request: CreativeInterpretationRequest) -> String {
        let summary = request.inputSummary
            .prefix(8)
            .map { "- \($0)" }
            .joined(separator: "\n")
        let suggestions = request.suggestionBriefs
            .prefix(6)
            .map { "- \($0)" }
            .joined(separator: "\n")
        let allowedInputs = request.allowedInputs
            .map(\.rawValue)
            .joined(separator: ", ")

        return """
        LensPilot creative interpretation request.
        Plan id: \(request.planId)
        Allowed input classes: \(allowedInputs)
        Max response words: \(request.maxResponseWords)

        Safe input summary:
        \(summary)

        Candidate capture guidance:
        \(suggestions)

        Return a short headline and 2-4 capture-realistic guidance strings.
        """
    }

    private static var responseFormat: [String: Any] {
        [
            "type": "json_schema",
            "name": "lenspilot_creative_interpretation",
            "strict": true,
            "schema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "headline": [
                        "type": "string",
                        "maxLength": 96
                    ],
                    "guidance": [
                        "type": "array",
                        "minItems": 2,
                        "maxItems": 4,
                        "items": [
                            "type": "string",
                            "maxLength": 180
                        ]
                    ]
                ],
                "required": ["headline", "guidance"]
            ]
        ]
    }

    private static func sanitizeError(_ value: String) -> String {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(180))
    }
}

private struct ResponsesEnvelope: Decodable {
    let status: String?
    let outputText: String?
    let output: [OutputItem]?
    let error: APIError?

    var firstOutputText: String? {
        output?
            .lazy
            .compactMap { item in
                item.content?.first(where: { $0.type == "output_text" })?.text
            }
            .first
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case outputText = "output_text"
        case output
        case error
    }

    struct OutputItem: Decodable {
        let type: String?
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String?
        let text: String?
    }

    struct APIError: Decodable {
        let code: String?
        let message: String?
    }
}

private struct ProviderJSON: Decodable {
    let headline: String
    let guidance: [String]
}
