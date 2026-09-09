import Foundation

public enum SceneEvidencePolicy {
    public static let maximumAge: TimeInterval = 3

    public static func accepts(frameId: String, timestamp: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return !frameId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && frameId != "placeholder_frame"
            && age.isFinite && age >= 0 && age < maximumAge
    }
}
