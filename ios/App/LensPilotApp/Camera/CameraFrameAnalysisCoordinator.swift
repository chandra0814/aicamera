@preconcurrency import AVFoundation
import Foundation
import LensPilotVision

final class CameraFrameAnalysisCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let sampleBufferQueue = DispatchQueue(label: "ai.lenspilot.camera.frame-analysis")

    var onSceneDebugState: (@MainActor (SceneDebugState) -> Void)?

    private let analyzer: any FrameAnalyzing
    private let minimumAnalysisInterval: TimeInterval
    private var isAnalyzing = false
    private var lastAnalysisStartedAt = Date.distantPast

    init(analyzer: any FrameAnalyzing, minimumAnalysisInterval: TimeInterval = 0.5) {
        self.analyzer = analyzer
        self.minimumAnalysisInterval = minimumAnalysisInterval
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard !isAnalyzing, now.timeIntervalSince(lastAnalysisStartedAt) >= minimumAnalysisInterval else {
            return
        }

        isAnalyzing = true
        lastAnalysisStartedAt = now

        Task { [analyzer, weak self] in
            let debugState = await analyzer.analyze(sampleBuffer: sampleBuffer)

            self?.sampleBufferQueue.async { [weak self] in
                self?.isAnalyzing = false
            }

            guard let debugState else { return }

            await MainActor.run { [weak self] in
                self?.onSceneDebugState?(debugState)
            }
        }
    }
}
