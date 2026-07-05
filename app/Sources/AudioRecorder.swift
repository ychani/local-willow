import AVFoundation
import Foundation

/// Captures the default microphone, downsamples to 16 kHz mono Int16,
/// and reports a smoothed input level for the waveform overlay.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples = Data()
    private let lock = NSLock()
    private(set) var isRecording = false

    var onLevel: ((Float) -> Void)?

    private let outFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    func start() throws {
        guard !isRecording else { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "LocalWillow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input (permission not granted?)"])
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        lock.lock(); samples = Data(); lock.unlock()

        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    private func process(buffer: AVAudioPCMBuffer) {
        // Level for the overlay (RMS of the raw float buffer).
        if let ch = buffer.floatChannelData?[0] {
            var sum: Float = 0
            let n = Int(buffer.frameLength)
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            let level = min(1.0, rms * 12)
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let data = out.int16ChannelData?[0], out.frameLength > 0 {
            let bytes = Data(bytes: data, count: Int(out.frameLength) * 2)
            lock.lock(); samples.append(bytes); lock.unlock()
        }
    }

    /// Stops capture and returns a WAV file, or nil if the take was too short.
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        converter = nil

        lock.lock(); let audio = samples; samples = Data(); lock.unlock()
        // Under ~0.3 s is an accidental tap, not dictation.
        guard audio.count > Int(16000 * 0.3) * 2 else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("willow-\(UUID().uuidString).wav")
        try? wavData(pcm: audio).write(to: url)
        return url
    }

    private func wavData(pcm: Data) -> Data {
        var d = Data()
        func put(_ s: String) { d.append(s.data(using: .ascii)!) }
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put("RIFF"); put32(UInt32(36 + pcm.count)); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)
        put32(16000); put32(16000 * 2); put16(2); put16(16)
        put("data"); put32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}
