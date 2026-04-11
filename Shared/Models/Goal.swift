import Foundation

enum GoalCategory: String, Codable, CaseIterable {
    case financial, reading, sideProject
}

struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var targetDate: String
    var progressPercent: Int
    var category: GoalCategory

    init(
        id: UUID = UUID(),
        name: String,
        targetDate: String = "",
        progressPercent: Int = 0,
        category: GoalCategory = .sideProject
    ) {
        self.id = id
        self.name = name
        self.targetDate = targetDate
        self.progressPercent = progressPercent
        self.category = category
    }
}
