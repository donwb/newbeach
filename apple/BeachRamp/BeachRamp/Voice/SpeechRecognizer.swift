import Foundation
import Observation
import Speech
import AVFoundation

/// Speech-to-text for the Ask bar: tap the mic, speak, the transcript lands
/// in the field live, and a pause ends the question. On-device recognition
/// when the device supports it. The app's audio session is `.ambient` so
/// the silent beach cam never interrupts other audio; recording needs
/// `.playAndRecord`, so the session flips for the duration and back after.
@MainActor
@Observable
final class SpeechRecognizer {
    enum State: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    /// Called once with the final transcript when the speaker pauses or
    /// stops the mic.
    var onFinal: ((String) -> Void)?

    /// How long a pause ends the question.
    var silence: TimeInterval = 1.4

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    var isListening: Bool { state == .listening }

    func toggle() {
        if isListening { stop(deliver: true) } else { start() }
    }

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            Task { @MainActor in
                guard let self else { return }
                guard auth == .authorized else { self.state = .denied; return }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else { self.state = .denied; return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        stop(deliver: false)
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            restoreSession()
            state = .unavailable
            return
        }

        state = .listening
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.armSilence()
                    if result.isFinal { self.stop(deliver: true) }
                }
                if error != nil { self.stop(deliver: !self.transcript.isEmpty) }
            }
        }
    }

    private func armSilence() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silence, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop(deliver: true) }
        }
    }

    func stop(deliver: Bool) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let wasListening = state == .listening
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        if wasListening { restoreSession() }
        state = .idle
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if deliver, wasListening, !text.isEmpty {
            onFinal?(text)
        }
    }

    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient)
    }
}
