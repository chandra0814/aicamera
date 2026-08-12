import AVFoundation
import Foundation
import LensPilotCore
#if canImport(UIKit)
import UIKit
#endif

public protocol DeviceCapabilityProfiling {
    func profileCurrentDevice() -> DeviceCapability
}

public final class DeviceCapabilityProfiler: DeviceCapabilityProfiling {
    public init() {}

    public func profileCurrentDevice() -> DeviceCapability {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices
        let cameras = devices.map(Self.mapCameraCapability)
        let videoDevices = devices.filter { $0.hasMediaType(.video) }
        let formats = videoDevices.flatMap(\.formats)
        let stabilizationModes = Self.supportedStabilizationModes(formats: formats)

        let depthSupported = formats.contains { !$0.supportedDepthDataFormats.isEmpty }

        return DeviceCapability(
            manufacturer: "Apple",
            model: Self.deviceModelName,
            physicalCameras: cameras,
            rawSupported: AVCapturePhotoOutput().availableRawPhotoPixelFormatTypes.isEmpty == false,
            depthSupported: depthSupported,
            manualExposureSupported: videoDevices.contains { $0.isExposureModeSupported(.custom) },
            manualFocusSupported: videoDevices.contains { $0.isFocusModeSupported(.locked) },
            manualWhiteBalanceSupported: videoDevices.contains { $0.isWhiteBalanceModeSupported(.locked) },
            hdrSupported: formats.contains { $0.isVideoHDRSupported },
            nightExtensionSupported: false,
            portraitExtensionSupported: depthSupported,
            stabilizationModes: stabilizationModes,
            thermalClass: ProcessInfo.processInfo.thermalState.lensPilotName,
            measuredCameraLatency: nil
        )
    }

    private static func mapCameraCapability(_ device: AVCaptureDevice) -> CameraCapability {
        CameraCapability(
            id: device.uniqueID,
            position: device.position.lensPilotPosition,
            lensType: device.deviceType.lensPilotLensType,
            minZoom: Double(device.minAvailableVideoZoomFactor),
            maxZoom: Double(device.maxAvailableVideoZoomFactor),
            supportsFocusLock: device.isFocusModeSupported(.locked),
            supportsExposureLock: device.isExposureModeSupported(.locked) || device.isExposureModeSupported(.custom)
        )
    }

    private static func supportedStabilizationModes(formats: [AVCaptureDevice.Format]) -> [String] {
        let modes = formats.flatMap { format in
            AVCaptureVideoStabilizationMode.allCases.filter { mode in
                format.isVideoStabilizationModeSupported(mode)
            }
        }
        .map(\.lensPilotName)

        return Array(Set(modes)).sorted()
    }
}

private extension DeviceCapabilityProfiler {
    static var deviceModelName: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}

private extension AVCaptureDevice.Position {
    var lensPilotPosition: CameraCapability.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        case .unspecified:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

private extension AVCaptureDevice.DeviceType {
    var lensPilotLensType: CameraCapability.LensType {
        switch self {
        case .builtInUltraWideCamera:
            return .ultraWide
        case .builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera:
            return .wide
        case .builtInTelephotoCamera:
            return .telephoto
        case .builtInTrueDepthCamera:
            return .trueDepth
        default:
            return .unknown
        }
    }
}

private extension AVCaptureVideoStabilizationMode {
    static var allCases: [AVCaptureVideoStabilizationMode] {
        [.off, .standard, .cinematic, .cinematicExtended, .auto]
    }

    var lensPilotName: String {
        switch self {
        case .off:
            return "off"
        case .standard:
            return "standard"
        case .cinematic:
            return "cinematic"
        case .cinematicExtended:
            return "cinematic_extended"
        case .auto:
            return "auto"
        @unknown default:
            return "unknown"
        }
    }
}

private extension ProcessInfo.ThermalState {
    var lensPilotName: String {
        switch self {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
