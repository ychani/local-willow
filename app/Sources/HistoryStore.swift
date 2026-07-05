import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
}

/// Last 20 dictations, persisted locally in UserDefaults. Nothing leaves the machine.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var items: [HistoryItem] = []
    private let key = "history"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ text: String) {
        items.insert(HistoryItem(id: UUID(), text: text, date: Date()), at: 0)
        if items.count > 20 { items.removeLast(items.count - 20) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
