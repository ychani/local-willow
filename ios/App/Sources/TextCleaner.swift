import Foundation

/// Same cleanup pipeline as the macOS app: filler removal + tidy punctuation.
enum TextCleaner {
    private static let fillers = try! NSRegularExpression(
        pattern: #"(,\s*)?\b(um+|uh+|erm+|uhm+|hmm+)\b[,.]?\s*"#,
        options: [.caseInsensitive])

    static func clean(_ input: String) -> String {
        var text = input.replacingOccurrences(
            of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return text }

        text = fillers.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespaces)
        if let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }
}
