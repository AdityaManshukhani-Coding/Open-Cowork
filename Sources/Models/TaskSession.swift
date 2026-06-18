import Foundation

public enum TaskStatus: Codable, Equatable {
    case idle
    case running
    case paused
    case waitingApproval
    case completed
    case failed(String)
    
    private enum CodingKeys: String, CodingKey {
        case type, reason
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "idle": self = .idle
        case "running": self = .running
        case "paused": self = .paused
        case "waitingApproval": self = .waitingApproval
        case "completed": self = .completed
        case "failed":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .failed(reason)
        default:
            self = .idle
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode("idle", forKey: .type)
        case .running:
            try container.encode("running", forKey: .type)
        case .paused:
            try container.encode("paused", forKey: .type)
        case .waitingApproval:
            try container.encode("waitingApproval", forKey: .type)
        case .completed:
            try container.encode("completed", forKey: .type)
        case .failed(let reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public enum StepStatus: String, Codable, Equatable {
    case pending
    case approved
    case executing
    case completed
    case failed
    case skipped
}

public struct FileBackup: Codable, Equatable {
    public let filePath: String
    public let backupPath: String
    public let isNewFile: Bool
    
    public init(filePath: String, backupPath: String, isNewFile: Bool) {
        self.filePath = filePath
        self.backupPath = backupPath
        self.isNewFile = isNewFile
    }
}

public struct TaskStep: Identifiable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var thought: String
    public var actionDescription: String
    public var screenshotPath: String?
    public var status: StepStatus
    public var errorMessage: String?
    public var cost: Double
    public var backups: [FileBackup]
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        thought: String = "",
        actionDescription: String = "",
        screenshotPath: String? = nil,
        status: StepStatus = .pending,
        errorMessage: String? = nil,
        cost: Double = 0.0,
        backups: [FileBackup] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.thought = thought
        self.actionDescription = actionDescription
        self.screenshotPath = screenshotPath
        self.status = status
        self.errorMessage = errorMessage
        self.cost = cost
        self.backups = backups
    }
}

public struct TaskSession: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var status: TaskStatus
    public var steps: [TaskStep]
    public var inputTokens: Int
    public var outputTokens: Int
    public var costEstimate: Double
    public var createdAt: Date
    public var isPinned: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .idle,
        steps: [TaskStep] = [],
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costEstimate: Double = 0.0,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.steps = steps
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costEstimate = costEstimate
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, title, status, steps, inputTokens, outputTokens, costEstimate, createdAt, isPinned
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(TaskStatus.self, forKey: .status)
        self.steps = try container.decode([TaskStep].self, forKey: .steps)
        self.inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        self.outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        self.costEstimate = try container.decode(Double.self, forKey: .costEstimate)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
    
    public var allBackups: [FileBackup] {
        return steps.flatMap { $0.backups }
    }
}
