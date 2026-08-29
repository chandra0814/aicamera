import Foundation

public enum OnlineInspirationError: Error, Equatable, Sendable {
    case unsafePlan
    case invalidSearchURL
    case invalidHTTPStatus(Int)
    case missingProviderData
    case thumbnailTooLarge(Int)
}

public struct OnlineInspirationRequest: Equatable, Sendable {
    public let planId: String
    public let queries: [String]
    public let perQueryLimit: Int
    public let source: Source
    public let privacy: Privacy

    public init(
        planId: String,
        queries: [String],
        perQueryLimit: Int = 4,
        source: Source = .publicSources,
        privacy: Privacy = Privacy()
    ) {
        self.planId = planId
        self.queries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.perQueryLimit = min(10, max(1, perQueryLimit))
        self.source = source
        self.privacy = privacy
    }

    public init(plan: OnlineReferencePlan, perQueryLimit: Int = 4, source: Source = .publicSources) throws {
        guard plan.privacy.singlePhoneOnly,
              plan.privacy.requiresUserConsent,
              !plan.privacy.sendsRawCameraFrame,
              !plan.privacy.sendsPrivatePhoto,
              !plan.privacy.sendsIdentityData
        else {
            throw OnlineInspirationError.unsafePlan
        }

        self.init(
            planId: plan.id,
            queries: plan.searchQueries,
            perQueryLimit: perQueryLimit,
            source: source,
            privacy: Privacy()
        )
    }
}

public extension OnlineInspirationRequest {
    enum Source: String, Codable, Sendable, Hashable {
        case publicSources = "public_sources"
        case wikimediaCommons = "wikimedia_commons"
        case openverse
    }

    struct Privacy: Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let requiresUserConsent: Bool
        public let sendsRawCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool

        public init(
            singlePhoneOnly: Bool = true,
            requiresUserConsent: Bool = true,
            sendsRawCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.requiresUserConsent = requiresUserConsent
            self.sendsRawCameraFrame = sendsRawCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
        }

        public var canUseOnlineProvider: Bool {
            singlePhoneOnly
                && requiresUserConsent
                && !sendsRawCameraFrame
                && !sendsPrivatePhoto
                && !sendsIdentityData
                && !sendsPreciseLocation
        }
    }
}

public struct OnlineInspirationResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let source: OnlineInspirationRequest.Source
    public let query: String
    public let title: String
    public let pageURL: URL
    public let thumbnailURL: URL?
    public let imageURL: URL?
    public let mimeType: String?
    public let license: String?
    public let creator: String?
    public let privacy: Privacy

    public init(
        id: String,
        source: OnlineInspirationRequest.Source,
        query: String,
        title: String,
        pageURL: URL,
        thumbnailURL: URL?,
        imageURL: URL?,
        mimeType: String?,
        license: String?,
        creator: String?,
        privacy: Privacy = Privacy()
    ) {
        self.id = id
        self.source = source
        self.query = query
        self.title = title
        self.pageURL = pageURL
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
        self.mimeType = mimeType
        self.license = license
        self.creator = creator
        self.privacy = privacy
    }
}

public extension OnlineInspirationResult {
    struct Privacy: Equatable, Sendable {
        public let publicSourceOnly: Bool
        public let derivedFromPromptOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let identityRecognitionAllowed: Bool

        public init(
            publicSourceOnly: Bool = true,
            derivedFromPromptOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            identityRecognitionAllowed: Bool = false
        ) {
            self.publicSourceOnly = publicSourceOnly
            self.derivedFromPromptOnly = derivedFromPromptOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.identityRecognitionAllowed = identityRecognitionAllowed
        }
    }
}

public struct OnlineInspirationProviderHealth: Identifiable, Codable, Equatable, Sendable {
    public let source: OnlineInspirationRequest.Source
    public let status: Status
    public let resultCount: Int
    public let checkedAt: Date
    public let message: String?
    public let privacy: Privacy

    public var id: String { source.rawValue }

    public init(
        source: OnlineInspirationRequest.Source,
        status: Status,
        resultCount: Int,
        checkedAt: Date = Date(),
        message: String? = nil,
        privacy: Privacy = Privacy()
    ) {
        self.source = source
        self.status = status
        self.resultCount = max(0, resultCount)
        self.checkedAt = checkedAt
        self.privacy = privacy

        if let message {
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            self.message = trimmedMessage.isEmpty ? nil : trimmedMessage
        } else {
            self.message = nil
        }
    }

    public static func available(
        source: OnlineInspirationRequest.Source,
        resultCount: Int,
        checkedAt: Date = Date()
    ) -> OnlineInspirationProviderHealth {
        OnlineInspirationProviderHealth(
            source: source,
            status: resultCount > 0 ? .available : .empty,
            resultCount: resultCount,
            checkedAt: checkedAt
        )
    }

    public static func failed(
        source: OnlineInspirationRequest.Source,
        error: Error,
        checkedAt: Date = Date()
    ) -> OnlineInspirationProviderHealth {
        OnlineInspirationProviderHealth(
            source: source,
            status: .failed,
            resultCount: 0,
            checkedAt: checkedAt,
            message: failureMessage(for: error)
        )
    }

    public static func failureMessage(for error: Error) -> String {
        guard let inspirationError = error as? OnlineInspirationError else {
            return "Provider request failed"
        }

        switch inspirationError {
        case .unsafePlan:
            return "Blocked by privacy safeguards"
        case .invalidSearchURL:
            return "Invalid search URL"
        case let .invalidHTTPStatus(statusCode):
            return "HTTP \(statusCode)"
        case .missingProviderData:
            return "Missing provider data"
        case .thumbnailTooLarge(_):
            return "Response too large"
        }
    }
}

public extension OnlineInspirationProviderHealth {
    enum Status: String, Codable, Equatable, Sendable {
        case available
        case empty
        case failed
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let publicSourceOnly: Bool
        public let derivedFromPromptOnly: Bool
        public let storesRawPhoto: Bool
        public let uploadsLiveCameraFrame: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool

        public init(
            publicSourceOnly: Bool = true,
            derivedFromPromptOnly: Bool = true,
            storesRawPhoto: Bool = false,
            uploadsLiveCameraFrame: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false
        ) {
            self.publicSourceOnly = publicSourceOnly
            self.derivedFromPromptOnly = derivedFromPromptOnly
            self.storesRawPhoto = storesRawPhoto
            self.uploadsLiveCameraFrame = uploadsLiveCameraFrame
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
        }
    }
}

public struct OnlineInspirationHealthSnapshot: Codable, Equatable, Sendable {
    public let planId: String
    public let source: OnlineInspirationRequest.Source
    public let status: Status
    public let checkedAt: Date
    public let totalResultCount: Int
    public let providers: [OnlineInspirationProviderHealth]
    public let privacy: Privacy

    public init(
        planId: String,
        source: OnlineInspirationRequest.Source,
        providers: [OnlineInspirationProviderHealth],
        checkedAt: Date = Date(),
        status: Status? = nil,
        privacy: Privacy = Privacy()
    ) {
        self.planId = planId
        self.source = source
        self.providers = providers
        self.checkedAt = checkedAt
        self.status = status ?? Self.aggregateStatus(for: providers)
        self.totalResultCount = providers.reduce(0) { $0 + $1.resultCount }
        self.privacy = privacy
    }

    private static func aggregateStatus(for providers: [OnlineInspirationProviderHealth]) -> Status {
        guard !providers.isEmpty else { return .empty }

        let hasAvailableProvider = providers.contains { $0.status == .available }
        let hasFailedProvider = providers.contains { $0.status == .failed }

        if hasAvailableProvider && hasFailedProvider { return .degraded }
        if hasAvailableProvider { return .available }
        if hasFailedProvider { return .failed }
        return .empty
    }
}

public extension OnlineInspirationHealthSnapshot {
    enum Status: String, Codable, Equatable, Sendable {
        case available
        case degraded
        case empty
        case failed
    }

    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let requiresUserConsent: Bool
        public let sendsRawCameraFrame: Bool
        public let sendsPrivatePhoto: Bool
        public let sendsIdentityData: Bool
        public let sendsPreciseLocation: Bool

        public init(
            singlePhoneOnly: Bool = true,
            requiresUserConsent: Bool = true,
            sendsRawCameraFrame: Bool = false,
            sendsPrivatePhoto: Bool = false,
            sendsIdentityData: Bool = false,
            sendsPreciseLocation: Bool = false
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.requiresUserConsent = requiresUserConsent
            self.sendsRawCameraFrame = sendsRawCameraFrame
            self.sendsPrivatePhoto = sendsPrivatePhoto
            self.sendsIdentityData = sendsIdentityData
            self.sendsPreciseLocation = sendsPreciseLocation
        }

        public init(requestPrivacy: OnlineInspirationRequest.Privacy) {
            self.init(
                singlePhoneOnly: requestPrivacy.singlePhoneOnly,
                requiresUserConsent: requestPrivacy.requiresUserConsent,
                sendsRawCameraFrame: requestPrivacy.sendsRawCameraFrame,
                sendsPrivatePhoto: requestPrivacy.sendsPrivatePhoto,
                sendsIdentityData: requestPrivacy.sendsIdentityData,
                sendsPreciseLocation: requestPrivacy.sendsPreciseLocation
            )
        }
    }
}

public struct OnlineInspirationResponse: Equatable, Sendable {
    public let planId: String
    public let source: OnlineInspirationRequest.Source
    public let sources: [OnlineInspirationRequest.Source]
    public let results: [OnlineInspirationResult]
    public let healthSnapshot: OnlineInspirationHealthSnapshot

    public init(
        planId: String,
        source: OnlineInspirationRequest.Source,
        results: [OnlineInspirationResult],
        sources: [OnlineInspirationRequest.Source]? = nil,
        healthSnapshot: OnlineInspirationHealthSnapshot? = nil
    ) {
        let resolvedSources = sources ?? Self.uniqueSources(from: results, fallback: [source])
        self.planId = planId
        self.source = source
        self.sources = resolvedSources
        self.results = results
        self.healthSnapshot = healthSnapshot ?? OnlineInspirationHealthSnapshot(
            planId: planId,
            source: source,
            providers: Self.providerHealth(from: results, sources: resolvedSources)
        )
    }

    private static func uniqueSources(
        from results: [OnlineInspirationResult],
        fallback: [OnlineInspirationRequest.Source]
    ) -> [OnlineInspirationRequest.Source] {
        var seen: Set<OnlineInspirationRequest.Source> = []
        var sources: [OnlineInspirationRequest.Source] = []

        for result in results where !seen.contains(result.source) {
            seen.insert(result.source)
            sources.append(result.source)
        }

        return sources.isEmpty ? fallback : sources
    }

    private static func providerHealth(
        from results: [OnlineInspirationResult],
        sources: [OnlineInspirationRequest.Source]
    ) -> [OnlineInspirationProviderHealth] {
        let checkedAt = Date()
        let groupedResults = Dictionary(grouping: results, by: \.source)

        return sources.map { source in
            let resultCount = groupedResults[source]?.count ?? 0
            return OnlineInspirationProviderHealth.available(
                source: source,
                resultCount: resultCount,
                checkedAt: checkedAt
            )
        }
    }
}

public struct OnlineInspirationRanker: Sendable {
    public init() {}

    public func rank(
        _ results: [OnlineInspirationResult],
        for request: OnlineInspirationRequest
    ) -> [OnlineInspirationResult] {
        var queryOrder: [String: Int] = [:]
        for (index, query) in request.queries.enumerated() {
            let key = query.lowercased()
            if queryOrder[key] == nil {
                queryOrder[key] = index
            }
        }
        let queryTokens = Set(request.queries.flatMap(Self.tokens))

        let ranked = results
            .enumerated()
            .map { item in
                ScoredResult(
                    result: item.element,
                    originalIndex: item.offset,
                    score: score(
                        item.element,
                        originalIndex: item.offset,
                        queryOrder: queryOrder,
                        queryTokens: queryTokens
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.originalIndex < rhs.originalIndex
                }

                return lhs.score > rhs.score
            }

        return diversify(ranked).map(\.result)
    }

    private func diversify(_ ranked: [ScoredResult]) -> [ScoredResult] {
        var selectedIds: Set<String> = []
        var selectedSources: Set<OnlineInspirationRequest.Source> = []
        var diversified: [ScoredResult] = []

        for item in ranked where !selectedSources.contains(item.result.source) {
            selectedSources.insert(item.result.source)
            selectedIds.insert(item.result.id)
            diversified.append(item)
        }

        for item in ranked where !selectedIds.contains(item.result.id) {
            selectedIds.insert(item.result.id)
            diversified.append(item)
        }

        return diversified
    }

    private func score(
        _ result: OnlineInspirationResult,
        originalIndex: Int,
        queryOrder: [String: Int],
        queryTokens: Set<String>
    ) -> Double {
        let resultTokens = Set(Self.tokens("\(result.title) \(result.query)"))
        let overlap = queryTokens.isEmpty
            ? 0
            : Double(resultTokens.intersection(queryTokens).count) / Double(queryTokens.count)
        let queryPosition = queryOrder[result.query.lowercased()].map { max(0, 1.0 - Double($0) * 0.18) } ?? 0
        let title = result.title.lowercased()
        let mimeType = result.mimeType?.lowercased() ?? ""

        var score = queryPosition + overlap * 1.4 - Double(originalIndex) * 0.001

        if result.thumbnailURL != nil { score += 0.35 }
        if result.imageURL != nil { score += 0.2 }
        if result.license?.isEmpty == false { score += 0.12 }
        if result.creator?.isEmpty == false { score += 0.08 }

        if mimeType == "image/jpeg" || mimeType == "image/png" || mimeType == "image/webp" {
            score += 0.25
        } else if mimeType == "image/svg+xml" {
            score -= 0.45
        }

        if containsAny(title, terms: ["portrait", "photo", "photograph", "camera", "street", "landscape", "travel", "cinematic"]) {
            score += 0.2
        }

        if containsAny(title, terms: ["logo", "icon", "diagram", "map", "flag", "seal", "coat of arms"]) {
            score -= 0.35
        }

        return score
    }

    private static func tokens(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private func containsAny(_ value: String, terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private struct ScoredResult {
        let result: OnlineInspirationResult
        let originalIndex: Int
        let score: Double
    }
}

public actor OnlineInspirationThumbnailCache {
    private let directoryURL: URL
    private let maxCacheBytes: Int
    private let fileManager: FileManager

    public init(
        directoryURL: URL? = nil,
        maxCacheBytes: Int = 24_000_000,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.maxCacheBytes = max(1, maxCacheBytes)

        if let directoryURL {
            self.directoryURL = directoryURL
        } else if let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.directoryURL = cacheRoot.appendingPathComponent("LensPilotOnlineInspiration", isDirectory: true)
        } else {
            self.directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("LensPilotOnlineInspiration", isDirectory: true)
        }
    }

    public func cachedData(for url: URL) throws -> Data? {
        let fileURL = cacheFileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    public func data(for url: URL, maxObjectBytes: Int = 2_000_000) async throws -> Data {
        if let cachedData = try cachedData(for: url) {
            return cachedData
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw OnlineInspirationError.invalidHTTPStatus(httpResponse.statusCode)
        }

        try store(data, for: url, maxObjectBytes: maxObjectBytes)
        return data
    }

    public func store(_ data: Data, for url: URL, maxObjectBytes: Int = 2_000_000) throws {
        guard data.count <= maxObjectBytes else {
            throw OnlineInspirationError.thumbnailTooLarge(data.count)
        }

        try ensureDirectoryExists()
        try data.write(to: cacheFileURL(for: url), options: [.atomic])
        try pruneIfNeeded()
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func cacheFileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent("\(stableHash(for: url.absoluteString)).bin")
    }

    private func stableHash(for value: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash = hash ^ UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func pruneIfNeeded() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        var cacheFiles = files.compactMap { fileURL -> CacheFile? in
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }

            return CacheFile(
                url: fileURL,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                byteCount: values.fileSize ?? 0
            )
        }
        var totalBytes = cacheFiles.reduce(0) { $0 + $1.byteCount }
        guard totalBytes > maxCacheBytes else { return }

        cacheFiles.sort { $0.modifiedAt < $1.modifiedAt }
        for file in cacheFiles where totalBytes > maxCacheBytes {
            try? fileManager.removeItem(at: file.url)
            totalBytes -= file.byteCount
        }
    }

    private struct CacheFile {
        let url: URL
        let modifiedAt: Date
        let byteCount: Int
    }
}

public struct OnlineInspirationProviderFetchOutcome: Equatable, Sendable {
    public let results: [OnlineInspirationResult]
    public let providerHealth: [OnlineInspirationProviderHealth]

    public init(results: [OnlineInspirationResult], providerHealth: [OnlineInspirationProviderHealth]) {
        self.results = results
        self.providerHealth = providerHealth
    }
}

public protocol OnlineInspirationProvider: Sendable {
    var source: OnlineInspirationRequest.Source { get }
    func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult]
}

public protocol OnlineInspirationHealthReportingProvider: OnlineInspirationProvider {
    func fetchReferencesWithHealth(for request: OnlineInspirationRequest) async throws -> OnlineInspirationProviderFetchOutcome
}

public struct OnlineInspirationService: Sendable {
    private let provider: any OnlineInspirationProvider
    private let ranker: OnlineInspirationRanker

    public init(
        provider: any OnlineInspirationProvider = PublicSourceInspirationProvider(),
        ranker: OnlineInspirationRanker = OnlineInspirationRanker()
    ) {
        self.provider = provider
        self.ranker = ranker
    }

    public func fetchReferences(
        for plan: OnlineReferencePlan,
        perQueryLimit: Int = 4
    ) async throws -> OnlineInspirationResponse {
        let request = try OnlineInspirationRequest(plan: plan, perQueryLimit: perQueryLimit)
        return try await fetchResponse(for: request)
    }

    public func fetchResponse(for request: OnlineInspirationRequest) async throws -> OnlineInspirationResponse {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        if let provider = provider as? any OnlineInspirationHealthReportingProvider {
            let outcome = try await provider.fetchReferencesWithHealth(for: request)
            let rankedResults = ranker.rank(outcome.results, for: request)
            let healthSnapshot = OnlineInspirationHealthSnapshot(
                planId: request.planId,
                source: request.source,
                providers: outcome.providerHealth,
                privacy: .init(requestPrivacy: request.privacy)
            )
            return OnlineInspirationResponse(
                planId: request.planId,
                source: request.source,
                results: rankedResults,
                healthSnapshot: healthSnapshot
            )
        }

        let results = try await fetchReferences(for: request)
        let healthSnapshot = OnlineInspirationHealthSnapshot(
            planId: request.planId,
            source: request.source,
            providers: [
                OnlineInspirationProviderHealth.available(
                    source: provider.source,
                    resultCount: results.count
                )
            ],
            privacy: .init(requestPrivacy: request.privacy)
        )
        return OnlineInspirationResponse(
            planId: request.planId,
            source: request.source,
            results: results,
            healthSnapshot: healthSnapshot
        )
    }

    public func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        let results = try await provider.fetchReferences(for: request)
        return ranker.rank(results, for: request)
    }
}

public struct PublicSourceInspirationProvider: OnlineInspirationHealthReportingProvider {
    private let providers: [any OnlineInspirationProvider]

    public init(
        providers: [any OnlineInspirationProvider] = [
            WikimediaCommonsInspirationProvider(),
            OpenverseInspirationProvider()
        ]
    ) {
        self.providers = providers
    }

    public var source: OnlineInspirationRequest.Source { .publicSources }

    public func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
        let outcome = try await fetchReferencesWithHealth(for: request)
        if !outcome.results.isEmpty || outcome.providerHealth.isEmpty || !outcome.providerHealth.allSatisfy({ $0.status == .failed }) {
            return outcome.results
        }

        throw OnlineInspirationError.missingProviderData
    }

    public func fetchReferencesWithHealth(for request: OnlineInspirationRequest) async throws -> OnlineInspirationProviderFetchOutcome {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        var results: [OnlineInspirationResult] = []
        var providerHealth: [OnlineInspirationProviderHealth] = []
        var seenPageURLs: Set<URL> = []
        var seenImageURLs: Set<URL> = []

        for provider in providers {
            do {
                let checkedAt = Date()
                let providerResults = try await provider.fetchReferences(for: request)
                var acceptedResultCount = 0
                for result in providerResults {
                    guard !seenPageURLs.contains(result.pageURL) else { continue }
                    if let imageURL = result.imageURL, seenImageURLs.contains(imageURL) { continue }

                    seenPageURLs.insert(result.pageURL)
                    if let imageURL = result.imageURL {
                        seenImageURLs.insert(imageURL)
                    }
                    results.append(result)
                    acceptedResultCount += 1
                }
                providerHealth.append(
                    OnlineInspirationProviderHealth.available(
                        source: provider.source,
                        resultCount: acceptedResultCount,
                        checkedAt: checkedAt
                    )
                )
            } catch {
                providerHealth.append(
                    OnlineInspirationProviderHealth.failed(
                        source: provider.source,
                        error: error
                    )
                )
            }
        }

        return OnlineInspirationProviderFetchOutcome(results: results, providerHealth: providerHealth)
    }
}

public struct WikimediaCommonsInspirationProvider: OnlineInspirationProvider {
    private let apiURL: URL

    public init(apiURL: URL = URL(string: "https://commons.wikimedia.org/w/api.php")!) {
        self.apiURL = apiURL
    }

    public var source: OnlineInspirationRequest.Source { .wikimediaCommons }

    public func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        var results: [OnlineInspirationResult] = []
        var seenPageURLs: Set<URL> = []

        for query in request.queries.prefix(3) {
            let url = try makeSearchURL(query: query, limit: request.perQueryLimit)
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw OnlineInspirationError.invalidHTTPStatus(httpResponse.statusCode)
            }

            for result in try decodeSearchResponse(data, query: query, planId: request.planId) {
                guard !seenPageURLs.contains(result.pageURL) else { continue }
                seenPageURLs.insert(result.pageURL)
                results.append(result)
            }
        }

        return results
    }

    public func makeSearchURL(query: String, limit: Int) throws -> URL {
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw OnlineInspirationError.invalidSearchURL
        }

        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "\(min(10, max(1, limit)))"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|mime|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "640"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "origin", value: "*")
        ]

        guard let url = components.url else {
            throw OnlineInspirationError.invalidSearchURL
        }

        return url
    }

    public func decodeSearchResponse(_ data: Data, query: String, planId: String) throws -> [OnlineInspirationResult] {
        _ = planId
        let response = try JSONDecoder().decode(WikimediaCommonsSearchResponse.self, from: data)
        let pages = response.query?.pages ?? []

        return pages
            .sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
            .compactMap { page in
                guard let imageInfo = page.imageinfo?.first else { return nil }
                guard imageInfo.mime?.hasPrefix("image/") == true else { return nil }
                guard let pageURLString = imageInfo.descriptionurl,
                      let pageURL = URL(string: pageURLString)
                else { return nil }

                let imageURL = imageInfo.url.flatMap(URL.init(string:))
                let thumbnailURL = imageInfo.thumburl.flatMap(URL.init(string:))
                guard imageURL != nil || thumbnailURL != nil else { return nil }

                return OnlineInspirationResult(
                    id: "wikimedia_commons_\(page.pageid)",
                    source: .wikimediaCommons,
                    query: query,
                    title: page.title.removingFilePrefix,
                    pageURL: pageURL,
                    thumbnailURL: thumbnailURL,
                    imageURL: imageURL,
                    mimeType: imageInfo.mime,
                    license: imageInfo.extmetadata?["LicenseShortName"]?.value?.plainMetadataValue,
                    creator: imageInfo.extmetadata?["Artist"]?.value?.plainMetadataValue
                )
            }
    }
}

public struct OpenverseInspirationProvider: OnlineInspirationProvider {
    private let apiURL: URL

    public init(apiURL: URL = URL(string: "https://api.openverse.engineering/v1/images/")!) {
        self.apiURL = apiURL
    }

    public var source: OnlineInspirationRequest.Source { .openverse }

    public func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        var results: [OnlineInspirationResult] = []
        var seenPageURLs: Set<URL> = []

        for query in request.queries.prefix(3) {
            let url = try makeSearchURL(query: query, limit: request.perQueryLimit)
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw OnlineInspirationError.invalidHTTPStatus(httpResponse.statusCode)
            }

            for result in try decodeSearchResponse(data, query: query, planId: request.planId) {
                guard !seenPageURLs.contains(result.pageURL) else { continue }
                seenPageURLs.insert(result.pageURL)
                results.append(result)
            }
        }

        return results
    }

    public func makeSearchURL(query: String, limit: Int) throws -> URL {
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw OnlineInspirationError.invalidSearchURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "\(min(10, max(1, limit)))"),
            URLQueryItem(name: "mature", value: "false")
        ]

        guard let url = components.url else {
            throw OnlineInspirationError.invalidSearchURL
        }

        return url
    }

    public func decodeSearchResponse(_ data: Data, query: String, planId: String) throws -> [OnlineInspirationResult] {
        _ = planId
        let response = try JSONDecoder().decode(OpenverseSearchResponse.self, from: data)

        return (response.results ?? []).compactMap { item in
            guard item.mature != true else { return nil }
            guard let id = item.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
            let imageURL = item.url.flatMap(URL.init(string:))
            let thumbnailURL = item.thumbnail.flatMap(URL.init(string:))
            guard imageURL != nil || thumbnailURL != nil else { return nil }

            let pageURL = item.foreign_landing_url
                .flatMap(URL.init(string:))
                ?? item.frontend_url.flatMap(URL.init(string:))
                ?? imageURL
            guard let pageURL else { return nil }

            return OnlineInspirationResult(
                id: "openverse_\(id)",
                source: .openverse,
                query: query,
                title: item.cleanedTitle,
                pageURL: pageURL,
                thumbnailURL: thumbnailURL,
                imageURL: imageURL,
                mimeType: inferredMimeType(from: imageURL ?? thumbnailURL),
                license: licenseLabel(license: item.license, version: item.license_version),
                creator: item.creator?.plainMetadataValue
            )
        }
    }

    private func licenseLabel(license: String?, version: String?) -> String? {
        guard let license = license?.trimmingCharacters(in: .whitespacesAndNewlines), !license.isEmpty else {
            return nil
        }

        let normalized = license.lowercased()
        if normalized == "pdm" { return "Public Domain Mark" }
        if normalized == "cc0" { return "CC0" }

        if let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty {
            return "CC \(license.uppercased()) \(version)"
        }

        return "CC \(license.uppercased())"
    }

    private func inferredMimeType(from url: URL?) -> String? {
        switch url?.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }
}

private struct WikimediaCommonsSearchResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let pages: [Page]
    }

    struct Page: Decodable {
        let pageid: Int
        let index: Int?
        let title: String
        let imageinfo: [ImageInfo]?
    }

    struct ImageInfo: Decodable {
        let url: String?
        let thumburl: String?
        let descriptionurl: String?
        let mime: String?
        let extmetadata: [String: MetadataValue]?
    }

    struct MetadataValue: Decodable {
        let value: String?
    }
}

private struct OpenverseSearchResponse: Decodable {
    let results: [ImageResult]?

    struct ImageResult: Decodable {
        let id: String?
        let title: String?
        let foreign_landing_url: String?
        let frontend_url: String?
        let url: String?
        let thumbnail: String?
        let license: String?
        let license_version: String?
        let creator: String?
        let mature: Bool?

        var cleanedTitle: String {
            let title = title?.plainMetadataValue ?? ""
            return title.isEmpty ? "Openverse public reference" : title
        }
    }
}

private extension String {
    var removingFilePrefix: String {
        if hasPrefix("File:") {
            return String(dropFirst("File:".count))
        }

        return self
    }

    var plainMetadataValue: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
