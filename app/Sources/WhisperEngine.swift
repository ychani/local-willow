import Foundation

/// Manages a localhost whisper-server child process (model stays warm in memory)
/// and transcribes WAV files against it.
final class WhisperEngine {
    private var process: Process?
    private let port = 8178
    private(set) var lastError: String?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Kills any whisper-server left on our port by a previous crashed/killed run.
    private func reapOrphans() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "whisper-server.*--port \(port)"]
        try? p.run()
        p.waitUntilExit()
    }

    func start() {
        guard !isRunning else { return }
        reapOrphans()
        let cfg = Config.shared
        guard FileManager.default.fileExists(atPath: cfg.whisperServerPath) else {
            lastError = "whisper-server not found at \(cfg.whisperServerPath) — brew install whisper-cpp"
            Log.write("engine: \(lastError!)")
            return
        }
        guard FileManager.default.fileExists(atPath: cfg.modelPath) else {
            lastError = "Model not found at \(cfg.modelPath)"
            Log.write("engine: \(lastError!)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cfg.whisperServerPath)
        var args = ["-m", cfg.modelPath, "-l", cfg.language,
                    "--host", "127.0.0.1", "--port", String(port)]
        let vocab = cfg.vocabulary
        if !vocab.isEmpty {
            args += ["--prompt", "Glossary: " + vocab.joined(separator: ", ") + ".",
                     "--carry-initial-prompt"]
        }
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            Log.write("engine: whisper-server pid \(proc.processIdentifier) exited "
                + "(code \(proc.terminationStatus), reason \(proc.terminationReason.rawValue))")
        }
        do {
            try p.run()
            process = p
            lastError = nil
            Log.write("engine: whisper-server started, pid \(p.processIdentifier)")
            // A bad argument (e.g. invalid language) makes it exit within ms — catch that
            // and say so instead of failing silently at the next dictation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !p.isRunning, self.process === p else { return }
                self.lastError = "Transcription engine exited right after launch — check language/model settings"
                Notify.post(self.lastError!)
            }
        } catch {
            lastError = "Failed to launch whisper-server: \(error.localizedDescription)"
            Log.write("engine: launch FAILED — \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        reapOrphans()
    }

    /// Restart to pick up changed model/language/vocabulary settings.
    func restart() {
        stop()
        // Give the old process a beat to release the port.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    func transcribe(wav: URL, timeout: TimeInterval = 120) async throws -> String {
        defer { try? FileManager.default.removeItem(at: wav) }
        if !isRunning { start() }

        let boundary = UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("response_format", "json")
        field("temperature", "0.0")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: wav))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = timeout

        // The server may still be loading the model right after launch — retry briefly.
        var attempt = 0
        while true {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(domain: "LocalWillow", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Bad response from whisper-server"])
                }
                if let err = json["error"] as? String {
                    throw NSError(domain: "LocalWillow", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: err])
                }
                return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let e as URLError where e.code == .cannotConnectToHost && attempt < 40 {
                attempt += 1
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
