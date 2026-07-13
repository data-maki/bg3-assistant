import AVFoundation
import Foundation
import Speech

/// Dictation for the overlay chat. Streams microphone audio through Apple's
/// speech recognizer (on-device when the model is available) and publishes the
/// live transcript, which the chat tab mirrors into the draft field.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition not authorized — enable it in System Settings › Privacy."
                    return
                }
                self.requestMicrophone()
            }
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else {
                    self.errorMessage = "Microphone access denied — enable it in System Settings › Privacy."
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is unavailable on this system."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            errorMessage = "No microphone input is available."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Could not start the microphone: \(error.localizedDescription)"
            return
        }

        self.request = request
        transcript = ""
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.finishRecording() }
                }
                if error != nil, self.isRecording { self.finishRecording() }
            }
        }
    }

    func stop() {
        request?.endAudio()
        finishRecording()
    }

    private func finishRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        task?.finish()
        task = nil
        request = nil
        isRecording = false
    }
}
