import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

public protocol FrameAnalyzing: Sendable {
    func analyze(sampleBuffer: CMSampleBuffer) async -> SceneDebugState?
}

public actor FrameAnalyzer: FrameAnalyzing {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func analyze(sampleBuffer: CMSampleBuffer) async -> SceneDebugState? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let startedAt = Date()
        let personBounds = await detectPeople(in: pixelBuffer)
        let exposureWarning = exposureWarning(for: pixelBuffer)
        let latencyMs = Date().timeIntervalSince(startedAt) * 1000

        return SceneDebugState(
            frameId: UUID().uuidString,
            timestamp: startedAt,
            personBounds: personBounds,
            horizonY: nil,
            exposureWarning: exposureWarning,
            frameLatencyMs: latencyMs
        )
    }

    private func detectPeople(in pixelBuffer: CVPixelBuffer) async -> [NormalizedRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectHumanRectanglesRequest { request, _ in
                let observations = (request.results as? [VNHumanObservation]) ?? []
                let rects = observations.map { observation in
                    NormalizedRect(
                        x: observation.boundingBox.origin.x,
                        y: observation.boundingBox.origin.y,
                        width: observation.boundingBox.size.width,
                        height: observation.boundingBox.size.height
                    )
                }
                continuation.resume(returning: rects)
            }

            request.upperBodyOnly = false

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func exposureWarning(for pixelBuffer: CVPixelBuffer) -> ExposureWarning {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return .balanced
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent

        guard
            let outputImage = filter.outputImage,
            let average = averageRGBA(from: outputImage)
        else {
            return .balanced
        }

        let luminance = 0.2126 * average.r + 0.7152 * average.g + 0.0722 * average.b

        if luminance < 0.18 {
            return .underexposed
        }

        if luminance > 0.82 {
            return .clippedHighlights
        }

        return .balanced
    }

    private func averageRGBA(from image: CIImage) -> (r: Double, g: Double, b: Double, a: Double)? {
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            image,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            r: Double(bitmap[0]) / 255,
            g: Double(bitmap[1]) / 255,
            b: Double(bitmap[2]) / 255,
            a: Double(bitmap[3]) / 255
        )
    }
}
