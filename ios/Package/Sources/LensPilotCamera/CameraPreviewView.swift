import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
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
#else
public struct CameraPreviewView: NSViewRepresentable {
    private let session: AVCaptureSession
    private let videoGravity: AVLayerVideoGravity

    public init(session: AVCaptureSession, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.session = session
        self.videoGravity = videoGravity
    }

    public func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = videoGravity
        return view
    }

    public func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.videoPreviewLayer.session = session
        nsView.videoPreviewLayer.videoGravity = videoGravity
    }
}

public final class PreviewView: NSView {
    public override var wantsUpdateLayer: Bool {
        true
    }

    public override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("PreviewView layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
#endif
