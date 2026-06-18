import Foundation

public struct Teammate: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var systemPrompt: String
    public var provider: LLMProvider? // nil represents "Current"
    public var apiKey: String
    public var modelName: String
    
    public init(id: UUID = UUID(), name: String, systemPrompt: String, provider: LLMProvider?, modelName: String, apiKey: String = "") {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.provider = provider
        self.modelName = modelName
        self.apiKey = apiKey
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt, provider, apiKey, modelName
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        self.provider = try container.decodeIfPresent(LLMProvider.self, forKey: .provider)
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(provider, forKey: .provider)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelName, forKey: .modelName)
    }
}

public struct Team: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var teammates: [Teammate]
    
    public init(id: UUID = UUID(), name: String, teammates: [Teammate] = []) {
        self.id = id
        self.name = name
        self.teammates = teammates
    }
}
