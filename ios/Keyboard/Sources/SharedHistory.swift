import Foundation

// The keyboard target compiles independently of the app target, so it needs
// its own copies of the shared history types (kept intentionally tiny).

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
}

enum HistoryStore {
    static let suite = "group.dev.yun.localwillow"
    static let key = "history"

    static func load(from defaults: UserDefaults) -> [HistoryItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return [] }
        return decoded
    }
}
