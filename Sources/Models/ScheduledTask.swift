import Foundation

public struct ScheduledTask: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var prompt: String
    public var cronExpression: String // e.g., "*/5 * * * *" or "0 9 * * *"
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var nextRunAt: Date?
    
    public init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        cronExpression: String,
        isEnabled: Bool = true,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.cronExpression = cronExpression
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }
}
