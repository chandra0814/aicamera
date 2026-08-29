import Foundation

#if canImport(Security)
import Security
#endif

public enum PersonalVisualProfileStoreError: Error, Equatable {
    case profileTooLarge(maxBytes: Int, actualBytes: Int)
    case keychainReadFailed(status: Int32)
    case keychainWriteFailed(status: Int32)
    case keychainDeleteFailed(status: Int32)
}

public enum PersonalVisualProfileStorageProtection: String, Codable, Equatable, Sendable {
    case localFile = "local_file"
    case keychainEncryptedThisDeviceOnly = "keychain_encrypted_this_device_only"

    public var isEncryptedAtRest: Bool {
        self == .keychainEncryptedThisDeviceOnly
    }
}

public struct PersonalVisualProfileStore {
    public static let defaultStorageKey = "com.lenspilot.personalVisualProfile.v1"
    public static let defaultKeychainService = "com.lenspilot.personalVisualProfile"
    public static let defaultKeychainAccount = "profile.v1"
    public static let maxStoredProfileBytes = 64 * 1024

    public let protection: PersonalVisualProfileStorageProtection

    private let readData: () throws -> Data?
    private let writeData: (Data?) throws -> Void
    private let maxStoredProfileBytes: Int

    public init(
        maxStoredProfileBytes: Int = Self.maxStoredProfileBytes,
        protection: PersonalVisualProfileStorageProtection = .localFile,
        readData: @escaping () throws -> Data?,
        writeData: @escaping (Data?) throws -> Void
    ) {
        self.maxStoredProfileBytes = max(1, maxStoredProfileBytes)
        self.protection = protection
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

    public static func defaultSecureStore(
        userDefaults: UserDefaults = .standard,
        key: String = Self.defaultStorageKey,
        keychainService: String = Self.defaultKeychainService,
        keychainAccount: String = Self.defaultKeychainAccount,
        maxStoredProfileBytes: Int = Self.maxStoredProfileBytes
    ) -> PersonalVisualProfileStore {
        let effectiveMaxStoredProfileBytes = max(1, maxStoredProfileBytes)
        #if canImport(Security)
        let keychainStore = PersonalVisualProfileKeychainDataStore(
            service: keychainService,
            account: keychainAccount
        )

        return PersonalVisualProfileStore(
            maxStoredProfileBytes: effectiveMaxStoredProfileBytes,
            protection: .keychainEncryptedThisDeviceOnly
        ) {
            if let keychainData = try keychainStore.readData() {
                return keychainData
            }

            guard let legacyData = userDefaults.data(forKey: key) else { return nil }
            guard legacyData.count <= effectiveMaxStoredProfileBytes else {
                throw PersonalVisualProfileStoreError.profileTooLarge(
                    maxBytes: effectiveMaxStoredProfileBytes,
                    actualBytes: legacyData.count
                )
            }
            try keychainStore.writeData(legacyData)
            userDefaults.removeObject(forKey: key)
            return legacyData
        } writeData: { data in
            try keychainStore.writeData(data)
            userDefaults.removeObject(forKey: key)
        }
        #else
        return PersonalVisualProfileStore(
            userDefaults: userDefaults,
            key: key,
            maxStoredProfileBytes: effectiveMaxStoredProfileBytes
        )
        #endif
    }

    public func loadProfile() throws -> PersonalVisualPreferenceProfile? {
        guard let data = try readData() else { return nil }
        return try decodeProfile(from: data)
    }

    public func saveProfile(_ profile: PersonalVisualPreferenceProfile) throws {
        let data = try encodedProfileData(for: profile)
        try writeData(data)
    }

    public func deleteProfile() {
        try? deleteProfileThrowing()
    }

    public func deleteProfileThrowing() throws {
        try writeData(nil)
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

#if canImport(Security)
private struct PersonalVisualProfileKeychainDataStore {
    let service: String
    let account: String

    func readData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw PersonalVisualProfileStoreError.keychainReadFailed(status: status)
        }

        return item as? Data
    }

    func writeData(_ data: Data?) throws {
        guard let data else {
            try deleteData()
            return
        }

        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw PersonalVisualProfileStoreError.keychainWriteFailed(status: status)
        }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PersonalVisualProfileStoreError.keychainWriteFailed(status: addStatus)
        }
    }

    private func deleteData() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PersonalVisualProfileStoreError.keychainDeleteFailed(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
#endif

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
