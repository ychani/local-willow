import Foundation

enum Hotkey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, rightControl, f13
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .f13: return "F13"
        }
    }

    // (keyCode, is-modifier). Modifiers arrive via flagsChanged, F13 via keyDown/keyUp.
    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .f13: return 105
        }
    }

    var isModifier: Bool { self != .f13 }
}

final class Config {
    static let shared = Config()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "hotkey": Hotkey.rightOption.rawValue,
            "toggleDictation": false,
            "language": "en",
            "removeFillers": true,
            "sounds": true,
            "aiMode": false,
            "ollamaModel": "llama3.2:3b",
            "modelPath": Config.defaultModelPath,
            "whisperServerPath": "/opt/homebrew/bin/whisper-server",
            "vocabulary": "",
            "replacements": "",
        ])
    }

    static var defaultModelPath: String {
        let ws = NSHomeDirectory() + "/workspace/local-willow/models/ggml-large-v3-turbo-q5_0.bin"
        return ws
    }

    var hotkey: Hotkey {
        get { Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }

    /// When true, the hotkey toggles a take: one press starts, the next press stops.
    /// When false (default), dictation records only while the hotkey is held.
    var toggleDictation: Bool {
        get { d.bool(forKey: "toggleDictation") }
        set { d.set(newValue, forKey: "toggleDictation") }
    }

    /// Human phrase for how to trigger dictation, matching the current mode.
    /// e.g. "Hold Right ⌥ Option" or "Press Right ⌥ Option".
    var actionHint: String {
        (toggleDictation ? "Press " : "Hold ") + hotkey.label
    }

    var language: String {
        get {
            let v = (d.string(forKey: "language") ?? "en")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // An empty/garbage value makes whisper-server exit at launch — never pass one.
            return v.count == 2 || v == "auto" ? v : "en"
        }
        set { d.set(newValue, forKey: "language") }
    }

    var removeFillers: Bool {
        get { d.bool(forKey: "removeFillers") }
        set { d.set(newValue, forKey: "removeFillers") }
    }

    var sounds: Bool {
        get { d.bool(forKey: "sounds") }
        set { d.set(newValue, forKey: "sounds") }
    }

    var aiMode: Bool {
        get { d.bool(forKey: "aiMode") }
        set { d.set(newValue, forKey: "aiMode") }
    }

    var ollamaModel: String {
        get { d.string(forKey: "ollamaModel") ?? "llama3.2:3b" }
        set { d.set(newValue, forKey: "ollamaModel") }
    }

    var modelPath: String {
        get { d.string(forKey: "modelPath") ?? Config.defaultModelPath }
        set { d.set(newValue, forKey: "modelPath") }
    }

    var whisperServerPath: String {
        get { d.string(forKey: "whisperServerPath") ?? "/opt/homebrew/bin/whisper-server" }
        set { d.set(newValue, forKey: "whisperServerPath") }
    }

    /// One term per line. Biases Whisper toward personal names/jargon.
    var vocabulary: [String] {
        get {
            (d.string(forKey: "vocabulary") ?? "")
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    var vocabularyRaw: String {
        get { d.string(forKey: "vocabulary") ?? "" }
        set { d.set(newValue, forKey: "vocabulary") }
    }

    /// Lines of "wrong -> right".
    var replacements: [(String, String)] {
        (d.string(forKey: "replacements") ?? "").split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "->")
            guard parts.count == 2 else { return nil }
            let a = parts[0].trimmingCharacters(in: .whitespaces)
            let b = parts[1].trimmingCharacters(in: .whitespaces)
            return a.isEmpty ? nil : (a, b)
        }
    }

    var replacementsRaw: String {
        get { d.string(forKey: "replacements") ?? "" }
        set { d.set(newValue, forKey: "replacements") }
    }
}
