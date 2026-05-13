import Foundation

struct Action: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ActionType
    let description: String
    let timestamp: Date
    var status: ActionStatus

    init(
        id: UUID = UUID(),
        type: ActionType,
        description: String,
        timestamp: Date = Date(),
        status: ActionStatus = .pending
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.status = status
    }
}

enum ActionType: String, Codable, Sendable {
    case click
    case type
    case launch
    case focus
    case quit
}

enum ActionStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
}