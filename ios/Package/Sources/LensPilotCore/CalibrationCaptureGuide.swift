import Foundation

public enum CalibrationCaptureScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape
    case sky
    case clutter
    case backlight
    case horizon
    case motion
    case night

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        case .sky:
            return "Sky"
        case .clutter:
            return "Clutter"
        case .backlight:
            return "Backlight"
        case .horizon:
            return "Horizon"
        case .motion:
            return "Motion"
        case .night:
            return "Night"
        }
    }

    public var prompt: String {
        switch self {
        case .portrait:
            return "Give me a cinematic portrait with natural skin and a clean background."
        case .landscape:
            return "Capture a wide landscape with strong composition and natural color."
        case .sky:
            return "Show more sky in a dramatic but realistic landscape photo."
        case .clutter:
            return "Give me a portrait with a cleaner background and less clutter."
        case .backlight:
            return "Make a backlit portrait with visible face detail and protected highlights."
        case .horizon:
            return "Capture a landscape with a level horizon and balanced framing."
        case .motion:
            return "Capture a lifestyle action photo with sharp subject detail."
        case .night:
            return "Capture a low-light night photo with stable sharp detail."
        }
    }

    public var domain: CalibrationSample.CalibrationDomain {
        switch self {
        case .portrait, .clutter, .backlight:
            return .portrait
        case .landscape, .sky, .horizon:
            return .landscape
        case .motion:
            return .lifestyle
        case .night:
            return .night
        }
    }

    public var preferredGuidanceReason: GuidanceAction.Reason {
        switch self {
        case .portrait:
            return .improveSubjectBackgroundSeparation
        case .landscape:
            return .readyToCapture
        case .sky:
            return .increaseSky
        case .clutter:
            return .reduceClutter
        case .backlight:
            return .improveFaceLight
        case .horizon:
            return .levelHorizon
        case .motion:
            return .reduceMotionBlur
        case .night:
            return .protectHighlights
        }
    }

    public var rankedWeaknesses: [CalibrationSample.CalibrationWeakness] {
        switch self {
        case .portrait:
            return [.subjectPosition, .lighting]
        case .landscape:
            return [.composition, .cameraAngle]
        case .sky:
            return [.composition, .exposure]
        case .clutter:
            return [.background, .composition]
        case .backlight:
            return [.lighting, .exposure]
        case .horizon:
            return [.horizon, .cameraAngle]
        case .motion:
            return [.sharpnessProbability, .pose]
        case .night:
            return [.exposure, .sharpnessProbability]
        }
    }

    public var targetSampleCount: Int { 3 }

    public var symbolName: String {
        switch self {
        case .portrait:
            return "person.crop.rectangle"
        case .landscape:
            return "mountain.2"
        case .sky:
            return "cloud.sun"
        case .clutter:
            return "rectangle.compress.vertical"
        case .backlight:
            return "sun.max"
        case .horizon:
            return "gyroscope"
        case .motion:
            return "figure.run"
        case .night:
            return "moon.stars"
        }
    }

    public var reviewNotes: String {
        "Guided calibration scenario: \(title)."
    }
}

public struct CalibrationCaptureQueueProgress: Codable, Equatable, Sendable {
    public let version: String
    public let activeScenarioId: String?
    public let completedCounts: [String: Int]

    public init(
        version: String = "1.0",
        activeScenarioId: String? = nil,
        completedCounts: [String: Int] = [:]
    ) {
        self.version = "1.0"
        self.activeScenarioId = activeScenarioId.flatMap { CalibrationCaptureScenario(rawValue: $0)?.rawValue }
        self.completedCounts = Self.sanitizedCompletedCounts(completedCounts)
    }

    public var activeScenario: CalibrationCaptureScenario? {
        activeScenarioId.flatMap(CalibrationCaptureScenario.init(rawValue:))
    }

    public var requiredSampleCount: Int {
        CalibrationCaptureScenario.allCases.reduce(0) { $0 + $1.targetSampleCount }
    }

    public var completedSampleCount: Int {
        CalibrationCaptureScenario.allCases.reduce(0) { $0 + completedCount(for: $1) }
    }

    public var completedScenarioCount: Int {
        CalibrationCaptureScenario.allCases.filter { isComplete($0) }.count
    }

    public var progressFraction: Double {
        guard requiredSampleCount > 0 else { return 0 }
        return Double(completedSampleCount) / Double(requiredSampleCount)
    }

    public func completedCount(for scenario: CalibrationCaptureScenario) -> Int {
        completedCounts[scenario.rawValue] ?? 0
    }

    public func isComplete(_ scenario: CalibrationCaptureScenario) -> Bool {
        completedCount(for: scenario) >= scenario.targetSampleCount
    }

    public func selecting(_ scenario: CalibrationCaptureScenario) -> CalibrationCaptureQueueProgress {
        CalibrationCaptureQueueProgress(activeScenarioId: scenario.rawValue, completedCounts: completedCounts)
    }

    public func recordingCapture(for scenario: CalibrationCaptureScenario) -> CalibrationCaptureQueueProgress {
        var nextCounts = completedCounts
        let nextCount = min(scenario.targetSampleCount, completedCount(for: scenario) + 1)
        nextCounts[scenario.rawValue] = nextCount
        return CalibrationCaptureQueueProgress(activeScenarioId: activeScenarioId, completedCounts: nextCounts)
    }

    public func reset() -> CalibrationCaptureQueueProgress {
        CalibrationCaptureQueueProgress()
    }

    public func sanitizedForLocalStorage() -> CalibrationCaptureQueueProgress {
        CalibrationCaptureQueueProgress(activeScenarioId: activeScenarioId, completedCounts: completedCounts)
    }

    private static func sanitizedCompletedCounts(_ counts: [String: Int]) -> [String: Int] {
        var sanitized: [String: Int] = [:]

        for scenario in CalibrationCaptureScenario.allCases {
            let count = min(scenario.targetSampleCount, max(0, counts[scenario.rawValue] ?? 0))
            guard count > 0 else { continue }
            sanitized[scenario.rawValue] = count
        }

        return sanitized
    }
}

public enum CalibrationCaptureQueueStoreError: Error, Equatable, Sendable {
    case progressTooLarge(maxBytes: Int, actualBytes: Int)
}

public struct CalibrationCaptureQueueStore {
    public static let defaultStorageKey = "com.lenspilot.calibrationCaptureQueue.v1"
    public static let maxStoredProgressBytes = 8 * 1024

    private let readData: () -> Data?
    private let writeData: (Data?) -> Void
    private let maxStoredProgressBytes: Int

    public init(
        maxStoredProgressBytes: Int = Self.maxStoredProgressBytes,
        readData: @escaping () -> Data?,
        writeData: @escaping (Data?) -> Void
    ) {
        self.maxStoredProgressBytes = max(1, maxStoredProgressBytes)
        self.readData = readData
        self.writeData = writeData
    }

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = Self.defaultStorageKey,
        maxStoredProgressBytes: Int = Self.maxStoredProgressBytes
    ) {
        self.init(maxStoredProgressBytes: maxStoredProgressBytes) {
            userDefaults.data(forKey: key)
        } writeData: { data in
            if let data {
                userDefaults.set(data, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    public func loadProgress() throws -> CalibrationCaptureQueueProgress? {
        guard let data = readData() else { return nil }
        return try decodeProgress(from: data)
    }

    public func saveProgress(_ progress: CalibrationCaptureQueueProgress) throws {
        let data = try encodedProgressData(for: progress)
        writeData(data)
    }

    public func deleteProgress() {
        writeData(nil)
    }

    public func encodedProgressData(for progress: CalibrationCaptureQueueProgress) throws -> Data {
        let data = try JSONEncoder().encode(progress.sanitizedForLocalStorage())
        try validateSize(data)
        return data
    }

    public func decodeProgress(from data: Data) throws -> CalibrationCaptureQueueProgress {
        try validateSize(data)
        return try JSONDecoder()
            .decode(CalibrationCaptureQueueProgress.self, from: data)
            .sanitizedForLocalStorage()
    }

    private func validateSize(_ data: Data) throws {
        guard data.count <= maxStoredProgressBytes else {
            throw CalibrationCaptureQueueStoreError.progressTooLarge(
                maxBytes: maxStoredProgressBytes,
                actualBytes: data.count
            )
        }
    }
}
