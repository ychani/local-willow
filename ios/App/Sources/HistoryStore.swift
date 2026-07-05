import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
}

/// Last 20 dictations in the shared App Group, so the keyboard extension
/// can offer them for insertion in any app. Local to the device.
final class HistoryStore: ObservableObject {
    static let suite = "group.dev.yun.localwillow"
    static let key = "history"

    @Published private(set) var items: [HistoryItem] = []
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suite) ?? .standard
        items = Self.load(from: defaults)
    }

    static func load(from defaults: UserDefaults) -> [HistoryItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return [] }
        return decoded
    }

    func add(_ text: String) {
        items.insert(HistoryItem(id: UUID(), text: text, date: Date()), at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
