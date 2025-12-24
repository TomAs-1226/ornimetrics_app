import Foundation

struct EcoTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var description: String?
    var category: String
    var priority: Int
    var createdAt: Date
    var dueAt: Date?
    var done: Bool
    var source: String

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        category: String,
        priority: Int = 2,
        createdAt: Date = Date(),
        dueAt: Date? = nil,
        done: Bool = false,
        source: String = "ai"
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.done = done
        self.source = source
    }
}
