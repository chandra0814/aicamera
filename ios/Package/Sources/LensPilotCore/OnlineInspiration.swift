import Foundation

public enum OnlineInspirationError: Error, Equatable, Sendable {
    case unsafePlan
    case invalidSearchURL
    case invalidHTTPStatus(Int)
    case missingProviderData
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
        source: Source = .wikimediaCommons,
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

    public init(plan: OnlineReferencePlan, perQueryLimit: Int = 4, source: Source = .wikimediaCommons) throws {
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
    enum Source: String, Codable, Sendable {
        case wikimediaCommons = "wikimedia_commons"
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

public struct OnlineInspirationResponse: Equatable, Sendable {
    public let planId: String
    public let source: OnlineInspirationRequest.Source
    public let results: [OnlineInspirationResult]

    public init(planId: String, source: OnlineInspirationRequest.Source, results: [OnlineInspirationResult]) {
        self.planId = planId
        self.source = source
        self.results = results
    }
}

public protocol OnlineInspirationProvider: Sendable {
    func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult]
}

public struct OnlineInspirationService: Sendable {
    private let provider: any OnlineInspirationProvider

    public init(provider: any OnlineInspirationProvider = WikimediaCommonsInspirationProvider()) {
        self.provider = provider
    }

    public func fetchReferences(
        for plan: OnlineReferencePlan,
        perQueryLimit: Int = 4
    ) async throws -> OnlineInspirationResponse {
        let request = try OnlineInspirationRequest(plan: plan, perQueryLimit: perQueryLimit)
        let results = try await fetchReferences(for: request)
        return OnlineInspirationResponse(planId: request.planId, source: request.source, results: results)
    }

    public func fetchReferences(for request: OnlineInspirationRequest) async throws -> [OnlineInspirationResult] {
        guard request.privacy.canUseOnlineProvider else {
            throw OnlineInspirationError.unsafePlan
        }

        return try await provider.fetchReferences(for: request)
    }
}

public struct WikimediaCommonsInspirationProvider: OnlineInspirationProvider {
    private let apiURL: URL

    public init(apiURL: URL = URL(string: "https://commons.wikimedia.org/w/api.php")!) {
        self.apiURL = apiURL
    }

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
