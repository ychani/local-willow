import Foundation

/// Converts an arbitrary audio file (m4a, mp3, wav, aiff, caf…) into the
/// 16 kHz mono 16-bit WAV that whisper-server expects, using the built-in
/// `afconvert` (no external dependencies). The original file is never touched;
/// output goes to a temp file the caller is responsible for removing.
enum AudioConverter {
    /// Audio extensions the app will attempt to transcribe.
    static let supportedExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "aifc",
                                      "caf", "aac", "mp4", "m4b", "flac"]

    struct ConversionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Returns a temp WAV URL; delete it when done.
    static func toWhisperWAV(_ source: URL) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("localwillow-\(UUID().uuidString).wav")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        // WAVE container, little-endian 16-bit PCM at 16 kHz, downmixed to mono.
        p.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                       source.path, out.path]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice

        do {
            try p.run()
        } catch {
            throw ConversionError(message: "Couldn't start audio converter: \(error.localizedDescription)")
        }
        p.waitUntilExit()

        guard p.terminationStatus == 0,
              FileManager.default.fileExists(atPath: out.path) else {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: out)
            throw ConversionError(message: "Couldn't read this audio file"
                + (detail.map { " — \($0)" } ?? "."))
        }
        return out
    }
}
