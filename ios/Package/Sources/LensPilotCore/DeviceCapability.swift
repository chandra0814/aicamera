import Foundation

public struct DeviceCapability: Codable, Equatable, Sendable {
    public let manufacturer: String
    public let model: String
    public let physicalCameras: [CameraCapability]
    public let rawSupported: Bool
    public let depthSupported: Bool
    public let manualExposureSupported: Bool
    public let manualFocusSupported: Bool
    public let manualWhiteBalanceSupported: Bool
    public let hdrSupported: Bool
    public let nightExtensionSupported: Bool
    public let portraitExtensionSupported: Bool
    public let stabilizationModes: [String]
    public let thermalClass: String?
    public let measuredCameraLatency: Double?

    public init(
        manufacturer: String,
        model: String,
        physicalCameras: [CameraCapability],
        rawSupported: Bool,
        depthSupported: Bool,
        manualExposureSupported: Bool,
        manualFocusSupported: Bool,
        manualWhiteBalanceSupported: Bool,
        hdrSupported: Bool,
        nightExtensionSupported: Bool,
        portraitExtensionSupported: Bool,
        stabilizationModes: [String],
        thermalClass: String?,
        measuredCameraLatency: Double?
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.physicalCameras = physicalCameras
        self.rawSupported = rawSupported
        self.depthSupported = depthSupported
        self.manualExposureSupported = manualExposureSupported
        self.manualFocusSupported = manualFocusSupported
        self.manualWhiteBalanceSupported = manualWhiteBalanceSupported
        self.hdrSupported = hdrSupported
        self.nightExtensionSupported = nightExtensionSupported
        self.portraitExtensionSupported = portraitExtensionSupported
        self.stabilizationModes = stabilizationModes
        self.thermalClass = thermalClass
        self.measuredCameraLatency = measuredCameraLatency
    }
}

public struct CameraCapability: Codable, Equatable, Sendable {
    public let id: String
    public let position: Position
    public let lensType: LensType
    public let minZoom: Double?
    public let maxZoom: Double?
    public let supportsFocusLock: Bool
    public let supportsExposureLock: Bool

    public init(
        id: String,
        position: Position,
        lensType: LensType,
        minZoom: Double?,
        maxZoom: Double?,
        supportsFocusLock: Bool,
        supportsExposureLock: Bool
    ) {
        self.id = id
        self.position = position
        self.lensType = lensType
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.supportsFocusLock = supportsFocusLock
        self.supportsExposureLock = supportsExposureLock
    }
}

public extension CameraCapability {
    enum Position: String, Codable, Sendable {
        case front
        case back
        case external
        case unknown
    }

    enum LensType: String, Codable, Sendable {
        case ultraWide = "ultra_wide"
        case wide
        case telephoto
        case trueDepth = "true_depth"
        case unknown
    }
}
