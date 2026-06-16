import Foundation
import Speech
import AVFoundation

/// Live on-device dictation for Quick Add (FR-QADD-080). Wraps `SFSpeechRecognizer` + `AVAudioEngine`
/// and publishes the running transcript. Device/permission-bound at runtime (needs the mic + speech
/// usage descriptions in Info.plist); a no-op without authorization or a recognizer. The view binds
/// `transcript` into the NL field while `isRecording`.
@MainActor
@Observable
final class SpeechDictation {
    private(set) var isRecording = false
    private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Whether dictation is usable on this device/locale (the mic button hides otherwise).
    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { return }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else { return }
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            cleanup(); return
        }

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { cleanup(); return }
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { cleanup(); return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        cleanup()
    }

    private func cleanup() {
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
