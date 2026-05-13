import Foundation

struct Settings: Codable, Sendable {
    var provider: Provider
    var apiKey: String
    var model: String
    var approvalMode: ApprovalMode

    static let `default` = Settings(
        provider: .anthropic,
        apiKey: "",
        model: "claude-sonnet-4-20250514",
        approvalMode: .auto
    )
}

enum Provider: String, Codable, Sendable {
    case anthropic
    case openai
    case ollama
}

enum ApprovalMode: String, Codable, Sendable {
    case auto
    case approve
    case step
}