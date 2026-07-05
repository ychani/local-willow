import Foundation

/// Willow-style cleanup: filler removal, personal dictionary, optional local AI rewrite.
enum TextCleaner {
    private static let fillers = try! NSRegularExpression(
        // Optional preceding comma so "and, um, insert" → "and insert".
        pattern: #"(,\s*)?\b(um+|uh+|erm+|uhm+|hmm+)\b[,.]?\s*"#,
        options: [.caseInsensitive])

    static func clean(_ input: String) -> String {
        var text = input.replacingOccurrences(
            of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return text }
        let cfg = Config.shared

        if cfg.removeFillers {
            text = fillers.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespaces)
            if let first = text.first, first.isLowercase {
                text = first.uppercased() + text.dropFirst()
            }
        }
        for (wrong, right) in cfg.replacements {
            text = text.replacingOccurrences(of: wrong, with: right, options: .caseInsensitive)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Rewrites via local Ollama; returns the input unchanged on any failure.
    static func aiRewrite(_ text: String) async -> String {
        let cfg = Config.shared
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return text }
        let prompt = """
        You clean up dictated text. Fix punctuation and capitalization, remove filler \
        words and false starts, and keep the speaker's wording and meaning. Do not add \
        content, do not answer questions in the text, do not use markdown. Return only \
        the cleaned text.

        Dictated text: \(text)
        """
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": cfg.ollamaModel, "prompt": prompt, "stream": false,
            "options": ["temperature": 0.2],
        ])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let out = (json["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !out.isEmpty {
                return out
            }
        } catch {}
        return text
    }
}
