import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text via SFSpeechRecognizer with
/// requiresOnDeviceRecognition — audio and text never leave the phone.
@MainActor
final class SpeechEngine: ObservableObject {
    @Published var partial = ""
    @Published var isRecording = false
    @Published var level: Float = 0
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalText = ""

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func start(localeID: String) {
        guard !isRecording else { return }
        errorMessage = nil
        partial = ""
        finalText = ""

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            errorMessage = "No recognizer for \(localeID)"
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device recognition for \(localeID) isn't downloaded yet. iOS fetches it after you enable the keyboard language in Settings → General → Keyboard → Dictation."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.requiresOnDeviceRecognition = true  // hard privacy guarantee
            req.shouldReportPartialResults = true
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                if let ch = buffer.floatChannelData?[0] {
                    let n = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    let rms = sqrt(sum / Float(max(n, 1)))
                    Task { @MainActor [weak self] in self?.level = min(1.0, rms * 12) }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.partial = result.bestTranscription.formattedString
                        if result.isFinal { self.finalText = self.partial }
                    }
                    if let error, self.isRecording {
                        self.errorMessage = error.localizedDescription
                        self.teardown()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            teardown()
        }
    }

    /// Stops capture and returns the best transcription.
    func stop() async -> String {
        guard isRecording else { return "" }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        isRecording = false

        // Give the recognizer a moment to finalize after end-of-audio.
        for _ in 0..<20 {
            if !finalText.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let text = finalText.isEmpty ? partial : finalText
        teardown()
        return text
    }

    func cancel() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        teardown()
        partial = ""
    }

    private func teardown() {
        task?.cancel()
        task = nil
        request = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
