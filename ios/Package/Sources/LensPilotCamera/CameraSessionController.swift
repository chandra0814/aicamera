import AVFoundation
import Foundation

public enum CameraAuthorizationState: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

public protocol CameraSessionControlling: AnyObject {
    var session: AVCaptureSession { get }
    var photoOutput: AVCapturePhotoOutput { get }
    var videoDataOutput: AVCaptureVideoDataOutput { get }
    func authorizationState() -> CameraAuthorizationState
    func requestAccess() async -> Bool
    func configure(position: AVCaptureDevice.Position) async throws
    func start() async
    func stop() async
}

public final class CameraSessionController: NSObject, CameraSessionControlling {
    public let session = AVCaptureSession()
    public let photoOutput = AVCapturePhotoOutput()
    public let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "ai.lenspilot.camera.session")
    private var currentInput: AVCaptureDeviceInput?

    public override init() {
        super.init()
    }

    public func authorizationState() -> CameraAuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    public func configure(position: AVCaptureDevice.Position = .back) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSession(position: position)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func start() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume()
            }
        }
    }

    public func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraSessionError.noCameraForPosition
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }

        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        if !session.outputs.contains(videoDataOutput), session.canAddOutput(videoDataOutput) {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            session.addOutput(videoDataOutput)
        }
    }
}

public enum CameraSessionError: Error, Equatable {
    case noCameraForPosition
    case cannotAddInput
}
