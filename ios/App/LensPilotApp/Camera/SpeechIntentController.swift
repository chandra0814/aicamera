import AVFoundation
import Combine
import Foundation
import Speech

enum SpeechIntentState: Equatable {
    case idle
    case requestingPermission
    case listening
    case finalizing
    case unavailable(String)
    case failed(String)
}

@MainActor
final class SpeechIntentController: ObservableObject {
    @Published private(set) var state: SpeechIntentState = .idle
    @Published private(set) var transcript = ""

    var onFinalTranscript: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isInputTapInstalled = false

    init(locale: Locale = .autoupdatingCurrent) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isListening: Bool {
        audioEngine.isRunning
    }

    func startListening() async {
        guard !audioEngine.isRunning else { return }
        state = .requestingPermission
        transcript = ""

        guard let speechRecognizer else {
            failBeforeStart("Voice input is unavailable on this device.")
            return
        }

        guard speechRecognizer.isAvailable else {
            failBeforeStart("Voice input is temporarily unavailable.")
            return
        }

        guard speechRecognizer.supportsOnDeviceRecognition else {
            failBeforeStart("On-device voice input is unavailable. Type your request instead.")
            return
        }

        let speechAllowed = await requestSpeechAuthorization()
        guard speechAllowed else {
            failBeforeStart("Speech recognition permission is required for voice input.")
            return
        }

        let microphoneAllowed = await requestMicrophoneAuthorization()
        guard microphoneAllowed else {
            failBeforeStart("Microphone permission is required for voice input.")
            return
        }

        do {
            try startAudioRecognition(using: speechRecognizer)
        } catch {
            stopAudio(cancelTask: true)
            failBeforeStart("Voice input could not start.")
        }
    }

    func stopListening(commitTranscript: Bool = false) {
        let finalTranscript = transcript
        stopAudio(cancelTask: true)
        state = .idle

        if commitTranscript, !finalTranscript.isEmpty {
            onFinalTranscript?(finalTranscript)
        }
    }

    private func startAudioRecognition(using speechRecognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        if isInputTapInstalled {
            inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        isInputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let spokenText = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.transcript = spokenText

                    if result.isFinal {
                        self.completeRecognition()
                    }
                }

                if error != nil, self.audioEngine.isRunning {
                    self.failDuringRecognition("Voice input stopped. Type your request instead.")
                }
            }
        }
    }

    private func completeRecognition() {
        state = .finalizing
        let finalTranscript = transcript
        stopAudio(cancelTask: false)
        state = .idle

        if !finalTranscript.isEmpty {
            onFinalTranscript?(finalTranscript)
        }
    }

    private func failBeforeStart(_ message: String) {
        state = .unavailable(message)
        onFailure?(message)
    }

    private func failDuringRecognition(_ message: String) {
        stopAudio(cancelTask: true)
        state = .failed(message)
        onFailure?(message)
    }

    private func stopAudio(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        recognitionRequest?.endAudio()

        if cancelTask {
            recognitionTask?.cancel()
        }

        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
