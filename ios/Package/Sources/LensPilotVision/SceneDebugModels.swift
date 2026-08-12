import Foundation

public struct SceneDebugState: Equatable, Sendable {
    public let frameId: String
    public let timestamp: Date
    public let personBounds: [NormalizedRect]
    public let horizonY: Double?
    public let exposureWarning: ExposureWarning?
    public let frameLatencyMs: Double?

    public init(
        frameId: String,
        timestamp: Date,
        personBounds: [NormalizedRect],
        horizonY: Double?,
        exposureWarning: ExposureWarning?,
        frameLatencyMs: Double?
    ) {
        self.frameId = frameId
        self.timestamp = timestamp
        self.personBounds = personBounds
        self.horizonY = horizonY
        self.exposureWarning = exposureWarning
        self.frameLatencyMs = frameLatencyMs
    }
}

public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum ExposureWarning: String, Equatable, Sendable {
    case underexposed
    case clippedHighlights = "clipped_highlights"
    case balanced
}
