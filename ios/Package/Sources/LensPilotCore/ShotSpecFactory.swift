import Foundation

public protocol ShotSpecCreating: Sendable {
    func makeShotSpec(from intent: String, source: ShotSpec.Source) -> ShotSpec
}

public struct ShotSpecFactory: ShotSpecCreating {
    public init() {}

    public func makeShotSpec(from intent: String, source: ShotSpec.Source = .text) -> ShotSpec {
        let normalized = intent.lowercased()
        let isPortrait = normalized.contains("portrait") || normalized.contains("me") || normalized.contains("person")
        let isLandscape = normalized.contains("landscape") || normalized.contains("sky") || normalized.contains("sunset")
        let isNight = normalized.contains("night")
        let wantsCinematic = normalized.contains("cinematic") || normalized.contains("dramatic")
        let wantsSky = normalized.contains("sky") || normalized.contains("sunset")
        let wantsCleanBackground = normalized.contains("clean") || normalized.contains("background")

        let domain: CaptureDomain
        if isNight {
            domain = .night
        } else if isPortrait {
            domain = .portrait
        } else if isLandscape {
            domain = .landscape
        } else {
            domain = .lifestyle
        }

        return ShotSpec(
            id: "shot_\(UUID().uuidString.lowercased())",
            source: source,
            originalPrompt: intent,
            domain: domain,
            subject: .init(
                primary: isPortrait ? .person : (isLandscape ? .landscape : .unknown),
                count: isPortrait ? 1 : nil,
                priority: isLandscape ? .environment : .subject
            ),
            style: .init(
                name: wantsCinematic ? .cinematic : .natural,
                mood: wantsCinematic ? .dramatic : .bright,
                colorIntent: wantsCinematic ? .warmHighlightsCoolShadows : .natural,
                skinTreatment: isPortrait ? .natural : .none
            ),
            composition: .init(
                framing: isPortrait ? .environmental : .wide,
                headroom: isPortrait ? .balanced : nil,
                skyPriority: wantsSky ? .high : nil,
                backgroundPriority: wantsCleanBackground ? .clean : (wantsSky ? .sunset : .contextual),
                horizonPlacement: isLandscape ? .lowerThird : .auto
            ),
            cameraIntent: .init(
                targetLens: isPortrait ? .twoXIfAvailable : .wide,
                perspective: isPortrait ? .eyeLevel : .auto,
                exposureStrategy: wantsSky ? .protectHighlights : (isPortrait ? .prioritizeFaces : .balanced),
                focusStrategy: isPortrait ? .subjectEye : .auto,
                depthIntent: isPortrait ? .strongSubjectSeparation : .deepFocus
            ),
            constraints: .init(
                realityMode: .natural,
                cloudAllowed: false,
                generativeEditsAllowed: false,
                userSafetyStrictness: .conservative
            ),
            confidence: 0.72,
            missingInfo: []
        )
    }
}
