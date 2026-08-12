import AVFoundation
import Foundation

public protocol PhotoCapturing {
    func capturePhoto(using output: AVCapturePhotoOutput) async throws -> Data
}

public final class PhotoCaptureController: NSObject, PhotoCapturing {
    private var continuation: CheckedContinuation<Data, Error>?

    public override init() {
        super.init()
    }

    public func capturePhoto(using output: AVCapturePhotoOutput) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let settings = AVCapturePhotoSettings()
            if #available(iOS 13.0, macOS 13.0, *) {
                settings.photoQualityPrioritization = .quality
            }

            #if os(iOS)
            if output.availablePhotoCodecTypes.contains(.hevc) {
                settings.embeddedThumbnailPhotoFormat = [
                    AVVideoCodecKey: AVVideoCodecType.jpeg
                ]
            }
            #endif

            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension PhotoCaptureController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: PhotoCaptureError.missingPhotoData)
            continuation = nil
            return
        }

        continuation?.resume(returning: data)
        continuation = nil
    }
}

public enum PhotoCaptureError: Error, Equatable {
    case missingPhotoData
}
