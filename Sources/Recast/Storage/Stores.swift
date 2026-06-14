import Foundation

@MainActor
final class CategoriesStore: ObservableObject {
    static let shared = CategoriesStore()
    private static let key = "rewriteCategories"

    @Published var categories: [RewriteCategory] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([RewriteCategory].self, from: data),
           !decoded.isEmpty {
            categories = decoded
        } else {
            categories = RewriteCategory.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func resetToDefaults() {
        categories = RewriteCategory.defaults
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private static let maxEntries = 500

    @Published private(set) var entries: [HistoryEntry] = []

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recast", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    private init() {
        load()
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func updatePick(id: UUID, category: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pickedCategory = category
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
