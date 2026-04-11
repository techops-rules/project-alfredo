import Foundation

struct Habit: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isDoneToday: Bool

    init(id: UUID = UUID(), name: String, isDoneToday: Bool = false) {
        self.id = id
        self.name = name
        self.isDoneToday = isDoneToday
    }
}
