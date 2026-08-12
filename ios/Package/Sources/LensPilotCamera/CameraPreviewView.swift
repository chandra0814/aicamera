import AVFoundation
import SwiftUI
import UIKit

public struct CameraPreviewView: UIViewRepresentable {
    private let session: AVCaptureSession
    private let videoGravity: AVLayerVideoGravity

    public init(session: AVCaptureSession, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.session = session
        self.videoGravity = videoGravity
    }

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = videoGravity
        return view
    }

    public func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.videoPreviewLayer.videoGravity = videoGravity
    }
}

public final class PreviewView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("PreviewView layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
