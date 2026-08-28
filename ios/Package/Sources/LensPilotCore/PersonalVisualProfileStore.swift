import Foundation

public enum PersonalVisualProfileStoreError: Error, Equatable {
    case profileTooLarge(maxBytes: Int, actualBytes: Int)
}

public struct PersonalVisualProfileStore {
    public static let defaultStorageKey = "com.lenspilot.personalVisualProfile.v1"
    public static let maxStoredProfileBytes = 64 * 1024

    private let readData: () -> Data?
    private let writeData: (Data?) -> Void
    private let maxStoredProfileBytes: Int

    public init(
        maxStoredProfileBytes: Int = Self.maxStoredProfileBytes,
        readData: @escaping () -> Data?,
        writeData: @escaping (Data?) -> Void
    ) {
        self.maxStoredProfileBytes = max(1, maxStoredProfileBytes)
        self.readData = readData
        self.writeData = writeData
    }

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = Self.defaultStorageKey,
        maxStoredProfileBytes: Int = Self.maxStoredProfileBytes
    ) {
        self.init(maxStoredProfileBytes: maxStoredProfileBytes) {
            userDefaults.data(forKey: key)
        } writeData: { data in
            if let data {
                userDefaults.set(data, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    public func loadProfile() throws -> PersonalVisualPreferenceProfile? {
        guard let data = readData() else { return nil }
        return try decodeProfile(from: data)
    }

    public func saveProfile(_ profile: PersonalVisualPreferenceProfile) throws {
        let data = try encodedProfileData(for: profile)
        writeData(data)
    }

    public func deleteProfile() {
        writeData(nil)
    }

    public func encodedProfileData(for profile: PersonalVisualPreferenceProfile) throws -> Data {
        let data = try JSONEncoder().encode(profile.sanitizedForLocalStorage())
        try validateSize(data)
        return data
    }

    public func decodeProfile(from data: Data) throws -> PersonalVisualPreferenceProfile {
        try validateSize(data)
        return try JSONDecoder()
            .decode(PersonalVisualPreferenceProfile.self, from: data)
            .sanitizedForLocalStorage()
    }

    private func validateSize(_ data: Data) throws {
        guard data.count <= maxStoredProfileBytes else {
            throw PersonalVisualProfileStoreError.profileTooLarge(
                maxBytes: maxStoredProfileBytes,
                actualBytes: data.count
            )
        }
    }
}

public extension PersonalVisualPreferenceProfile {
    func sanitizedForLocalStorage() -> PersonalVisualPreferenceProfile {
        PersonalVisualPreferenceProfile(
            version: "1.0",
            consent: PersonalizationConsent(
                learningEnabled: consent.learningEnabled,
                onlineReferencesAllowed: consent.onlineReferencesAllowed,
                cloudPersonalizationSyncAllowed: false
            ),
            totalEvents: Self.clampedCount(totalEvents),
            domainCounts: Self.sanitizedCounts(
                domainCounts,
                allowedKeys: Self.allowedDomainKeys,
                maxEntries: Self.allowedDomainKeys.count
            ),
            styleAffinities: Self.sanitizedAffinities(
                styleAffinities,
                allowedKeys: Self.allowedStyleKeys,
                maxEntries: Self.allowedStyleKeys.count
            ),
            colorAffinities: Self.sanitizedAffinities(
                colorAffinities,
                allowedKeys: Self.allowedColorKeys,
                maxEntries: Self.allowedColorKeys.count
            ),
            framingAffinities: Self.sanitizedAffinities(
                framingAffinities,
                allowedKeys: Self.allowedFramingKeys,
                maxEntries: Self.allowedFramingKeys.count
            ),
            guidanceReasonAffinities: Self.sanitizedAffinities(
                guidanceReasonAffinities,
                allowedKeys: Self.allowedGuidanceReasonKeys,
                maxEntries: Self.allowedGuidanceReasonKeys.count
            ),
            requirementAffinities: Self.sanitizedAffinities(
                requirementAffinities,
                allowedKeys: nil,
                maxEntries: 48
            ),
            onlineReferenceUsageCount: Self.clampedCount(onlineReferenceUsageCount)
        )
    }

    private static let allowedDomainKeys: Set<String> = [
        "portrait",
        "landscape",
        "travel",
        "lifestyle",
        "night",
        "reference"
    ]

    private static let allowedStyleKeys: Set<String> = [
        "natural",
        "cinematic",
        "professional",
        "travel",
        "portrait",
        "night",
        "sky",
        "lifestyle",
        "custom"
    ]

    private static let allowedColorKeys: Set<String> = [
        "natural",
        "warm_highlights",
        "cool_shadows",
        "warm_highlights_cool_shadows",
        "high_contrast",
        "low_contrast"
    ]

    private static let allowedFramingKeys: Set<String> = [
        "close",
        "medium",
        "wide",
        "environmental",
        "three_quarter",
        "symmetrical",
        "rule_of_thirds"
    ]

    private static let allowedGuidanceReasonKeys: Set<String> = [
        "improve_subject_background_separation",
        "level_horizon",
        "protect_highlights",
        "improve_face_light",
        "reduce_clutter",
        "match_reference",
        "improve_pose",
        "increase_sky",
        "reduce_motion_blur",
        "ready_to_capture"
    ]

    private static func sanitizedCounts(
        _ values: [String: Int],
        allowedKeys: Set<String>,
        maxEntries: Int
    ) -> [String: Int] {
        var sanitizedValues: [String: Int] = [:]

        for (key, value) in values {
            let sanitizedKey = sanitizedStorageKey(key)
            guard allowedKeys.contains(sanitizedKey) else { continue }
            let count = clampedCount(value)
            guard count > 0 else { continue }
            sanitizedValues[sanitizedKey, default: 0] = clampedCount(sanitizedValues[sanitizedKey, default: 0] + count)
        }

        return Dictionary(uniqueKeysWithValues: sanitizedValues
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(max(0, maxEntries))
            .map { ($0.key, $0.value) })
    }

    private static func sanitizedAffinities(
        _ values: [String: Double],
        allowedKeys: Set<String>?,
        maxEntries: Int
    ) -> [String: Double] {
        var sanitizedValues: [String: Double] = [:]

        for (key, value) in values {
            let sanitizedKey = sanitizedStorageKey(key)
            guard !sanitizedKey.isEmpty else { continue }
            if let allowedKeys, !allowedKeys.contains(sanitizedKey) {
                continue
            }
            if allowedKeys == nil, isBlockedFreeformStorageKey(sanitizedKey) {
                continue
            }

            let affinity = clampAffinity(value)
            guard affinity != 0 else { continue }
            sanitizedValues[sanitizedKey] = clampAffinity((sanitizedValues[sanitizedKey] ?? 0) + affinity)
        }

        return Dictionary(uniqueKeysWithValues: sanitizedValues
            .filter { $0.value != 0 }
            .sorted { lhs, rhs in
                abs(lhs.value) == abs(rhs.value) ? lhs.key < rhs.key : abs(lhs.value) > abs(rhs.value)
            }
            .prefix(max(0, maxEntries))
            .map { ($0.key, $0.value) })
    }

    private static func clampedCount(_ value: Int) -> Int {
        min(1_000_000, max(0, value))
    }

    private static func sanitizedStorageKey(_ value: String) -> String {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        var sanitized = ""

        for scalar in value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            if allowedScalars.contains(scalar) {
                sanitized.unicodeScalars.append(scalar)
            } else if !sanitized.hasSuffix("_") {
                sanitized.append("_")
            }

            if sanitized.count >= 64 {
                break
            }
        }

        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }

    private static func isBlockedFreeformStorageKey(_ value: String) -> Bool {
        [
            "raw_live_camera",
            "raw_frame",
            "private_photo",
            "face_identity",
            "identity_recognition",
            "upload_live_camera",
            "upload_private",
            "external_cloud"
        ].contains { value.contains($0) }
    }
}
