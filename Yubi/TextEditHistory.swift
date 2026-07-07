import Foundation

private let yubiAppGroupIdentifier = "group.com.justin.yubi"

struct TextEditHistoryItem: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let sourceText: String
    let translatedText: String
    let targetLanguage: String
    let tone: String?

    init(
        id: UUID = UUID(),
        date: Date,
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        tone: String? = nil
    ) {
        self.id = id
        self.date = date
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.tone = tone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.sourceText = try container.decode(String.self, forKey: .sourceText)
        self.translatedText = try container.decode(String.self, forKey: .translatedText)
        self.targetLanguage = try container.decode(String.self, forKey: .targetLanguage)
        self.tone = try container.decodeIfPresent(String.self, forKey: .tone)
    }

    var preview: String {
        translatedText
            .split(whereSeparator: \.isNewline)
            .prefix(3)
            .joined(separator: "\n")
    }
}

enum TextEditHistoryStore {
    private static let key = "YubiTextEditHistory"
    private static let historyLimit = 50

    static func loadHistory() -> [TextEditHistoryItem] {
        guard let data = userDefaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TextEditHistoryItem].self, from: data)
        else {
            return []
        }

        return items
            .sorted { $0.date > $1.date }
            .prefix(historyLimit)
            .map { $0 }
    }

    static func save(_ item: TextEditHistoryItem) {
        var history = loadHistory()
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        history = Array(history.prefix(historyLimit))

        guard let data = try? JSONEncoder().encode(history) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: yubiAppGroupIdentifier) ?? .standard
    }
}
