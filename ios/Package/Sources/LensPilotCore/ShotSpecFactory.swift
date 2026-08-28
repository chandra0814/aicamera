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
        let wantsMoreDrama = normalized.contains("more dramatic") || normalized.contains("more drama")
        let wantsCinematic = normalized.contains("cinematic") || normalized.contains("dramatic") || wantsMoreDrama
        let wantsBrighter = normalized.contains("brighter") || normalized.contains("brighten") || normalized.contains("make it bright")
        let wantsNaturalColor = normalized.contains("natural color") || normalized.contains("natural colour") || normalized.contains("colors natural") || normalized.contains("colours natural")
        let wantsLessBackgroundBlur = normalized.contains("less background blur") || normalized.contains("less blur") || normalized.contains("deep focus")
        let wantsSky = normalized.contains("sky") || normalized.contains("sunset") || normalized.contains("more sky") || normalized.contains("show more sky")
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
                mood: wantsCinematic && !wantsBrighter ? .dramatic : .bright,
                colorIntent: wantsNaturalColor ? .natural : (wantsCinematic ? .warmHighlightsCoolShadows : .natural),
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
                exposureStrategy: wantsSky ? .protectHighlights : (wantsBrighter ? .brighten : (isPortrait ? .prioritizeFaces : .balanced)),
                focusStrategy: isPortrait ? .subjectEye : .auto,
                depthIntent: wantsLessBackgroundBlur ? .naturalDepth : (isPortrait ? .strongSubjectSeparation : .deepFocus)
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
