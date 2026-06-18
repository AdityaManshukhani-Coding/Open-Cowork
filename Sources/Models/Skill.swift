import Foundation

public struct Skill: Identifiable, Codable, Equatable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var systemPromptInstructions: String
    public var isEnabled: Bool
    
    public init(
        name: String,
        description: String,
        systemPromptInstructions: String,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.description = description
        self.systemPromptInstructions = systemPromptInstructions
        self.isEnabled = isEnabled
    }
}
