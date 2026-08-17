import Foundation

public struct TargetPreview: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let shotSpecId: String
    public let shotPlanId: String
    public let title: String
    public let subtitle: String
    public let label: ShotPlan.Label
    public let estimatedAchievability: Double
    public let subjectBounds: NormalizedRectangle
    public let horizonY: Double?
    public let crop: NormalizedRectangle
    public let lens: String
    public let targetZoom: Double
    public let exposureBias: Double?
    public let toneCurve: ShotPlan.ToneCurve
    public let colorTreatment: String
    public let depthEffect: ShotPlan.DepthEffect
    public let operations: [String]
    public let targetMatchAtPreview: Double
    public let disclosure: String?
    public let requiresGenerativeEnhancement: Bool
    public let privacy: Privacy

    public init(
        id: String,
        shotSpecId: String,
        shotPlanId: String,
        title: String,
        subtitle: String,
        label: ShotPlan.Label,
        estimatedAchievability: Double,
        subjectBounds: NormalizedRectangle,
        horizonY: Double?,
        crop: NormalizedRectangle,
        lens: String,
        targetZoom: Double,
        exposureBias: Double?,
        toneCurve: ShotPlan.ToneCurve,
        colorTreatment: String,
        depthEffect: ShotPlan.DepthEffect,
        operations: [String],
        targetMatchAtPreview: Double,
        disclosure: String?,
        requiresGenerativeEnhancement: Bool,
        privacy: Privacy
    ) {
        self.id = id
        self.shotSpecId = shotSpecId
        self.shotPlanId = shotPlanId
        self.title = title
        self.subtitle = subtitle
        self.label = label
        self.estimatedAchievability = clamp01(estimatedAchievability)
        self.subjectBounds = subjectBounds
        self.horizonY = horizonY
        self.crop = crop
        self.lens = lens
        self.targetZoom = targetZoom
        self.exposureBias = exposureBias
        self.toneCurve = toneCurve
        self.colorTreatment = colorTreatment
        self.depthEffect = depthEffect
        self.operations = uniqueNonEmpty(operations)
        self.targetMatchAtPreview = clamp01(targetMatchAtPreview)
        self.disclosure = disclosure
        self.requiresGenerativeEnhancement = requiresGenerativeEnhancement
        self.privacy = privacy
    }
}

public extension TargetPreview {
    struct Privacy: Codable, Equatable, Sendable {
        public let singlePhoneOnly: Bool
        public let usesRawCameraFrameUpload: Bool
        public let usesPrivatePhotoUpload: Bool

        public init(
            singlePhoneOnly: Bool,
            usesRawCameraFrameUpload: Bool,
            usesPrivatePhotoUpload: Bool
        ) {
            self.singlePhoneOnly = singlePhoneOnly
            self.usesRawCameraFrameUpload = usesRawCameraFrameUpload
            self.usesPrivatePhotoUpload = usesPrivatePhotoUpload
        }
    }
}

public struct TargetPreviewEngine: Sendable {
    public init() {}

    public func makePreview(
        shotSpec: ShotSpec,
        shotPlan: ShotPlan,
        targetMatch: TargetMatchScore,
        previewSafety: PreviewSafety
    ) -> TargetPreview {
        TargetPreview(
            id: "preview_\(shotPlan.id)",
            shotSpecId: shotSpec.id,
            shotPlanId: shotPlan.id,
            title: "\(displayTitle(shotSpec.style.name.rawValue)) \(displayTitle(shotSpec.domain.rawValue))",
            subtitle: subtitle(for: shotPlan),
            label: previewSafety.label,
            estimatedAchievability: achievability(for: previewSafety.label, shotPlan: shotPlan),
            subjectBounds: shotPlan.compositionTarget.subjectBounds,
            horizonY: shotPlan.compositionTarget.horizonY,
            crop: shotPlan.compositionTarget.crop,
            lens: shotPlan.cameraControls.recommendedLens,
            targetZoom: shotPlan.cameraControls.targetZoom,
            exposureBias: shotPlan.cameraControls.targetExposureBias,
            toneCurve: shotPlan.processingIntent.toneCurve,
            colorTreatment: shotPlan.processingIntent.colorTreatment,
            depthEffect: shotPlan.processingIntent.depthEffect,
            operations: previewSafety.allowedOperations + shotPlan.previewConfiguration.operations,
            targetMatchAtPreview: targetMatch.overall,
            disclosure: previewSafety.userFacingDisclosure,
            requiresGenerativeEnhancement: previewSafety.label == .aiEnhancementRequired,
            privacy: TargetPreview.Privacy(
                singlePhoneOnly: shotSpec.constraints.singlePhoneOnly,
                usesRawCameraFrameUpload: false,
                usesPrivatePhotoUpload: false
            )
        )
    }

    private func achievability(for label: ShotPlan.Label, shotPlan: ShotPlan) -> Double {
        switch label {
        case .captureRealistic:
            return shotPlan.achievability.natural
        case .enhancedRealistic:
            return shotPlan.achievability.enhanced
        case .aiEnhancementRequired:
            return shotPlan.achievability.creative
        }
    }

    private func subtitle(for shotPlan: ShotPlan) -> String {
        [
            "\(displayTitle(shotPlan.cameraControls.recommendedLens)) \(formatZoom(shotPlan.cameraControls.targetZoom))",
            displayTitle(shotPlan.processingIntent.toneCurve.rawValue),
            displayTitle(shotPlan.processingIntent.depthEffect.rawValue)
        ].joined(separator: " | ")
    }

    private func displayTitle(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    private func formatZoom(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))x"
        }

        return String(format: "%.1fx", value)
    }
}

private func clamp01(_ value: Double) -> Double {
    min(1, max(0, value.isFinite ? value : 0))
}

private func uniqueNonEmpty(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
        seen.insert(trimmed)
        result.append(trimmed)
    }

    return result
}
