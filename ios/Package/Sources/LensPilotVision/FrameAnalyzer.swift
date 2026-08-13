import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

public struct AnalyzableFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    public init?(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        self.pixelBuffer = pixelBuffer
    }
}

public protocol FrameAnalyzing: Sendable {
    func analyze(frame: AnalyzableFrame) async -> SceneDebugState?
}

public actor FrameAnalyzer: FrameAnalyzing {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var previousMotionReference: MotionReference?

    public init() {}

    public func analyze(frame: AnalyzableFrame) async -> SceneDebugState? {
        let pixelBuffer = frame.pixelBuffer
        let startedAt = Date()
        let luminanceSample = luminanceSample(for: pixelBuffer)
        let personBounds = await detectPeople(in: pixelBuffer)
        let exposureWarning = exposureWarning(for: pixelBuffer)
        let faceMetrics = await detectFaceMetrics(in: pixelBuffer, exposureWarning: exposureWarning)
        let poseMetrics = await detectPoseMetrics(in: pixelBuffer)
        let segmentationAvailable: Bool
        if personBounds.isEmpty {
            segmentationAvailable = false
        } else {
            segmentationAvailable = await detectPersonSegmentation(in: pixelBuffer)
        }
        let horizon = luminanceSample.flatMap(horizonMetric)
        let latencyMs = Date().timeIntervalSince(startedAt) * 1000
        let motion = motionMetric(
            from: luminanceSample,
            personBounds: personBounds,
            timestamp: startedAt,
            latencyMs: latencyMs
        )

        return SceneDebugState(
            frameId: UUID().uuidString,
            timestamp: startedAt,
            personBounds: personBounds,
            horizonY: horizon?.y,
            horizon: horizon,
            exposureWarning: exposureWarning,
            faceMetrics: faceMetrics,
            poseMetrics: poseMetrics,
            segmentationAvailable: segmentationAvailable,
            motion: motion,
            frameLatencyMs: latencyMs
        )
    }

    private func detectPeople(in pixelBuffer: CVPixelBuffer) async -> [NormalizedRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectHumanRectanglesRequest { request, _ in
                let observations = (request.results as? [VNHumanObservation]) ?? []
                let rects = observations.map { observation in
                    self.normalizedRect(from: observation.boundingBox)
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

    private func detectFaceMetrics(in pixelBuffer: CVPixelBuffer, exposureWarning: ExposureWarning) async -> [FaceDebugMetric] {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, _ in
                let observations = (request.results as? [VNFaceObservation]) ?? []
                let metrics = observations.map { observation in
                    self.faceMetric(from: observation, exposureWarning: exposureWarning)
                }
                continuation.resume(returning: metrics)
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func detectPoseMetrics(in pixelBuffer: CVPixelBuffer) async -> [PoseDebugMetric] {
        await withCheckedContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, _ in
                let observations = (request.results as? [VNHumanBodyPoseObservation]) ?? []
                let metrics = observations.compactMap { observation in
                    self.poseMetric(from: observation)
                }
                continuation.resume(returning: metrics)
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func detectPersonSegmentation(in pixelBuffer: CVPixelBuffer) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { request, _ in
                let masks = (request.results as? [VNPixelBufferObservation]) ?? []
                continuation.resume(returning: !masks.isEmpty)
            }
            request.qualityLevel = .fast
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
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

    private func luminanceSample(for pixelBuffer: CVPixelBuffer, width: Int = 32, height: Int = 24) -> LuminanceSample? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let resized = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / extent.width,
                y: CGFloat(height) / extent.height
            )
        )
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        ciContext.render(
            resized,
            toBitmap: &bitmap,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var values: [Double] = []
        values.reserveCapacity(width * height)
        stride(from: 0, to: bitmap.count, by: 4).forEach { offset in
            let r = Double(bitmap[offset]) / 255
            let g = Double(bitmap[offset + 1]) / 255
            let b = Double(bitmap[offset + 2]) / 255
            values.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }

        return LuminanceSample(width: width, height: height, values: values)
    }

    private func horizonMetric(from sample: LuminanceSample) -> HorizonDebugMetric? {
        guard sample.width >= 8, sample.height >= 6 else {
            return nil
        }

        let rowAverages = (0..<sample.height).map { rowAverage(in: sample, row: $0, xRange: 0..<sample.width) }
        let rowEdges = (1..<sample.height).map { row in
            abs(rowAverages[row] - rowAverages[row - 1])
        }

        guard let strongestEdge = rowEdges.enumerated().max(by: { $0.element < $1.element }),
              strongestEdge.element > 0.025 else {
            return nil
        }

        let horizonRow = strongestEdge.offset + 1
        let leftRow = strongestEdgeRow(in: sample, xRange: 0..<(sample.width / 2))
        let rightRow = strongestEdgeRow(in: sample, xRange: (sample.width / 2)..<sample.width)
        let rowDelta = Double(rightRow - leftRow)
        let rollDegrees = clamp(rowDelta / Double(sample.height) * 28, minimum: -12, maximum: 12)
        let confidence = clamp01(0.35 + strongestEdge.element * 4 + abs(rowDelta) / Double(sample.height) * 0.15)

        return HorizonDebugMetric(
            y: clamp01(Double(horizonRow) / Double(sample.height - 1)),
            rollDegrees: rollDegrees,
            confidence: confidence
        )
    }

    private func motionMetric(
        from sample: LuminanceSample?,
        personBounds: [NormalizedRect],
        timestamp: Date,
        latencyMs: Double
    ) -> MotionDebugMetric {
        let latencyRisk = clamp01((latencyMs - 80) / 240)
        let centers = personBounds.map { SubjectCenter(rect: $0) }

        guard let sample else {
            return MotionDebugMetric(
                cameraShake: 0.1 + latencyRisk * 0.2,
                subjectMotion: 0.08,
                blurRisk: 0.16 + latencyRisk * 0.24
            )
        }

        defer {
            previousMotionReference = MotionReference(
                timestamp: timestamp,
                luminanceValues: sample.values,
                subjectCenters: centers
            )
        }

        guard let previousMotionReference,
              previousMotionReference.luminanceValues.count == sample.values.count else {
            return MotionDebugMetric(
                cameraShake: 0.1 + latencyRisk * 0.12,
                subjectMotion: centers.isEmpty ? 0.04 : 0.08,
                blurRisk: 0.16 + latencyRisk * 0.2
            )
        }

        var totalFrameDelta = 0.0
        for (currentValue, previousValue) in zip(sample.values, previousMotionReference.luminanceValues) {
            totalFrameDelta += abs(currentValue - previousValue)
        }

        let frameDelta = totalFrameDelta / Double(sample.values.count)
        let cameraShake = clamp01(frameDelta * 3.2 + latencyRisk * 0.14)
        let subjectMotion = subjectMotionScore(
            current: centers,
            previous: previousMotionReference.subjectCenters,
            interval: max(0.05, timestamp.timeIntervalSince(previousMotionReference.timestamp))
        )
        let blurRisk = clamp01(0.12 + cameraShake * 0.55 + subjectMotion * 0.35 + latencyRisk * 0.1)

        return MotionDebugMetric(
            cameraShake: cameraShake,
            subjectMotion: subjectMotion,
            blurRisk: blurRisk
        )
    }

    nonisolated private func faceMetric(from observation: VNFaceObservation, exposureWarning: ExposureWarning) -> FaceDebugMetric {
        let bounds = normalizedRect(from: observation.boundingBox)
        let faceArea = bounds.width * bounds.height
        let yawDegrees = observation.yaw.map { Double(truncating: $0) * 180 / .pi }
        let eyeOpen = eyeOpenProbability(from: observation.landmarks)
        let landmarkBoost = observation.landmarks == nil ? 0 : 0.15

        return FaceDebugMetric(
            bounds: bounds,
            eyeOpenProbability: eyeOpen,
            expressionStability: expressionStability(from: observation.landmarks, yawDegrees: yawDegrees),
            sharpnessProbability: clamp01(0.48 + faceArea * 2.1 + landmarkBoost),
            skinExposureScore: skinExposureScore(for: exposureWarning),
            faceYawDegrees: yawDegrees
        )
    }

    nonisolated private func poseMetric(from observation: VNHumanBodyPoseObservation) -> PoseDebugMetric? {
        let points = [
            recognizedPoint(.leftShoulder, in: observation),
            recognizedPoint(.rightShoulder, in: observation),
            recognizedPoint(.leftWrist, in: observation),
            recognizedPoint(.rightWrist, in: observation),
            recognizedPoint(.leftEye, in: observation),
            recognizedPoint(.rightEye, in: observation)
        ].compactMap { $0 }

        guard !points.isEmpty else {
            return nil
        }

        let leftShoulder = recognizedPoint(.leftShoulder, in: observation)
        let rightShoulder = recognizedPoint(.rightShoulder, in: observation)
        let leftEye = recognizedPoint(.leftEye, in: observation)
        let rightEye = recognizedPoint(.rightEye, in: observation)
        let leftWrist = recognizedPoint(.leftWrist, in: observation)
        let rightWrist = recognizedPoint(.rightWrist, in: observation)

        return PoseDebugMetric(
            bounds: normalizedRect(containing: points),
            shouldersAngleDegrees: angleDegrees(from: leftShoulder, to: rightShoulder),
            eyeLineConfidence: averageConfidence([leftEye, rightEye]),
            handAwkwardnessRisk: handAwkwardnessRisk(
                wrists: [leftWrist, rightWrist],
                shoulders: [leftShoulder, rightShoulder],
                eyes: [leftEye, rightEye]
            )
        )
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

    private func rowAverage(in sample: LuminanceSample, row: Int, xRange: Range<Int>) -> Double {
        guard !xRange.isEmpty else {
            return 0
        }

        let base = row * sample.width
        let total = xRange.reduce(0) { total, x in
            total + sample.values[base + x]
        }
        return total / Double(xRange.count)
    }

    private func strongestEdgeRow(in sample: LuminanceSample, xRange: Range<Int>) -> Int {
        guard sample.height >= 2 else {
            return 0
        }

        return (1..<sample.height)
            .map { row in
                (
                    row: row,
                    edge: abs(
                        rowAverage(in: sample, row: row, xRange: xRange)
                            - rowAverage(in: sample, row: row - 1, xRange: xRange)
                    )
                )
            }
            .max { lhs, rhs in lhs.edge < rhs.edge }?
            .row ?? sample.height / 2
    }

    nonisolated private func normalizedRect(from rect: CGRect) -> NormalizedRect {
        let x = clamp01(Double(rect.origin.x))
        let y = clamp01(Double(rect.origin.y))
        let width = min(clamp01(Double(rect.width)), 1 - x)
        let height = min(clamp01(Double(rect.height)), 1 - y)
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    nonisolated private func normalizedRect(containing points: [VNRecognizedPoint]) -> NormalizedRect? {
        let visiblePoints = points.filter { $0.confidence >= 0.2 }
        guard !visiblePoints.isEmpty else {
            return nil
        }

        let xs = visiblePoints.map { Double($0.location.x) }
        let ys = visiblePoints.map { Double($0.location.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        let padding = 0.08
        return normalizedRect(
            from: CGRect(
                x: minX - padding,
                y: minY - padding,
                width: maxX - minX + padding * 2,
                height: maxY - minY + padding * 2
            )
        )
    }

    nonisolated private func recognizedPoint(
        _ name: VNHumanBodyPoseObservation.JointName,
        in observation: VNHumanBodyPoseObservation,
        minimumConfidence: VNConfidence = 0.2
    ) -> VNRecognizedPoint? {
        guard let point = try? observation.recognizedPoint(name), point.confidence >= minimumConfidence else {
            return nil
        }
        return point
    }

    nonisolated private func angleDegrees(from lhs: VNRecognizedPoint?, to rhs: VNRecognizedPoint?) -> Double? {
        guard let lhs, let rhs else {
            return nil
        }

        return atan2(
            Double(rhs.location.y - lhs.location.y),
            Double(rhs.location.x - lhs.location.x)
        ) * 180 / .pi
    }

    nonisolated private func averageConfidence(_ points: [VNRecognizedPoint?]) -> Double? {
        let confidences = points.compactMap { point -> Double? in
            guard let point else { return nil }
            return Double(point.confidence)
        }
        guard !confidences.isEmpty else {
            return nil
        }
        return clamp01(confidences.reduce(0, +) / Double(confidences.count))
    }

    nonisolated private func handAwkwardnessRisk(
        wrists: [VNRecognizedPoint?],
        shoulders: [VNRecognizedPoint?],
        eyes: [VNRecognizedPoint?]
    ) -> Double? {
        let visibleWrists = wrists.compactMap { $0 }
        guard !visibleWrists.isEmpty else {
            return nil
        }

        let shoulderY = averageLocationY(shoulders.compactMap { $0 })
        let eyeY = averageLocationY(eyes.compactMap { $0 })
        let referenceY = eyeY ?? shoulderY
        guard let referenceY else {
            return 0.22
        }

        let raisedHands = visibleWrists.filter { Double($0.location.y) > referenceY + 0.12 }.count
        return clamp01(0.18 + Double(raisedHands) * 0.32)
    }

    nonisolated private func averageLocationY(_ points: [VNRecognizedPoint]) -> Double? {
        guard !points.isEmpty else {
            return nil
        }
        return points.map { Double($0.location.y) }.reduce(0, +) / Double(points.count)
    }

    nonisolated private func eyeOpenProbability(from landmarks: VNFaceLandmarks2D?) -> Double? {
        let scores = [landmarks?.leftEye, landmarks?.rightEye]
            .compactMap { $0 }
            .compactMap(eyeAspectScore)

        guard !scores.isEmpty else {
            return nil
        }

        return clamp01(scores.reduce(0, +) / Double(scores.count))
    }

    nonisolated private func eyeAspectScore(_ eye: VNFaceLandmarkRegion2D) -> Double? {
        let points = eye.normalizedPoints
        guard points.count >= 4 else {
            return nil
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        let width = max(0.001, Double(maxX - minX))
        let height = Double(maxY - minY)
        return clamp01((height / width - 0.08) / 0.18)
    }

    nonisolated private func expressionStability(from landmarks: VNFaceLandmarks2D?, yawDegrees: Double?) -> Double? {
        let yawPenalty = min(abs(yawDegrees ?? 0) / 60, 0.32)
        guard let mouth = landmarks?.outerLips ?? landmarks?.innerLips else {
            return clamp01(0.72 - yawPenalty)
        }

        let mouthPoints = mouth.normalizedPoints
        let xs = mouthPoints.map(\.x)
        let ys = mouthPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return clamp01(0.72 - yawPenalty)
        }

        let width = max(0.001, Double(maxX - minX))
        let openness = Double(maxY - minY) / width
        return clamp01(0.82 - openness * 0.28 - yawPenalty)
    }

    nonisolated private func skinExposureScore(for warning: ExposureWarning) -> Double {
        switch warning {
        case .underexposed:
            return 0.34
        case .clippedHighlights:
            return 0.46
        case .balanced:
            return 0.72
        }
    }

    private func subjectMotionScore(
        current: [SubjectCenter],
        previous: [SubjectCenter],
        interval: TimeInterval
    ) -> Double {
        guard !current.isEmpty, !previous.isEmpty else {
            return current.isEmpty ? 0.03 : 0.08
        }

        let totalDistance = current
            .map { center in
                previous.map { center.distance(to: $0) }.min() ?? 0
            }
            .reduce(0, +)
        let averageDistance = totalDistance / Double(current.count)
        return clamp01((averageDistance / interval) * 0.55)
    }
}

private struct LuminanceSample {
    let width: Int
    let height: Int
    let values: [Double]
}

private struct MotionReference {
    let timestamp: Date
    let luminanceValues: [Double]
    let subjectCenters: [SubjectCenter]
}

private struct SubjectCenter {
    let x: Double
    let y: Double

    init(rect: NormalizedRect) {
        x = rect.x + rect.width / 2
        y = rect.y + rect.height / 2
    }

    func distance(to other: SubjectCenter) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
    min(maximum, max(minimum, value))
}

private func clamp01(_ value: Double) -> Double {
    clamp(value, minimum: 0, maximum: 1)
}
