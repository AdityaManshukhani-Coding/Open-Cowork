import SwiftUI
import Combine

/// Central observable application state shared across all views.
///
/// Owns the agent loop, action log, cost tracker, safety gate, and all
/// user-configurable settings.  Injected via the SwiftUI environment so
/// every view can read and mutate state without prop-drilling.
///
/// Marked `@MainActor` because all state mutations happen on the main thread
/// (UI updates, Observable tracking) and this satisfies Swift 6 concurrency.
@MainActor
@Observable
final class AppState {
    // ── Agent Status ───────────────────────────────────────────────────
    /// Whether the agent loop is currently executing a task.
    var isRunning: Bool = false

    /// The current task description, if any.
    var currentTask: String = ""

    /// The list of chat messages exchanged with the agent.
    var messages: [ChatMessage] = []

    /// The live action log entries.
    var actionLog: [ActionLogEntry] = []

    /// The current cost estimate for the active session.
    var currentCost: Double = 0.0

    /// Total tokens used in the current session.
    var totalTokens: Int = 0

    // ── Safety Settings ────────────────────────────────────────────────
    /// The current safety mode.
    var safetyMode: SafetyMode = .approveBeforeAction

    /// Apps the agent is permitted to interact with.
    var allowedApps: Set<String> = [
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.apple.finder",
        "com.apple.calendar",
        "com.apple.reminders",
    ]

    /// Whether the emergency stop has been triggered.
    var emergencyStop: Bool = false

    // ── Provider Settings ──────────────────────────────────────────────
    /// The currently selected AI provider.
    var selectedProvider: ProviderKind = .openAI

    /// The API key for the selected provider.
    var apiKey: String = ""

    /// The base URL override (for OpenAI-compatible providers).
    var baseURLOverride: String = ""

    /// The model name to use.
    var modelName: String = "gpt-4o"

    /// Whether to use a local model (Ollama / LM Studio).
    var useLocalModel: Bool = false

    /// The local model endpoint URL.
    var localModelURL: String = "http://localhost:11434"

    /// The local model name.
    var localModelName: String = "llama3.2"

    // ── Budget Settings ────────────────────────────────────────────────
    /// The per-session budget limit in USD.  0 means no limit.
    var budgetLimit: Double = 0.0

    /// Whether to pause the agent when the budget is exceeded.
    var pauseOnBudgetExceeded: Bool = true

    // ── Internal State ─────────────────────────────────────────────────
    /// The agent loop instance (created lazily when the agent starts).
    private var agentLoop: AgentLoop?

    /// Cancellation token for the running agent task.
    private var agentTask: Task<Void, Never>?

    // ── Methods ────────────────────────────────────────────────────────

    /// Starts the agent loop with the current task description.
    func startAgent() {
        guard !isRunning else { return }
        guard !currentTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addSystemMessage("Please describe a task before starting the agent.")
            return
        }

        isRunning = true
        emergencyStop = false
        actionLog.removeAll()
        currentCost = 0.0
        totalTokens = 0

        let task = currentTask
        addUserMessage(task)

        let loop = AgentLoop(appState: self)
        self.agentLoop = loop

        agentTask = Task { @MainActor in
            addSystemMessage("Agent started. Task: \"\(task)\"")

            // Run the agent loop
            await loop.run(task: task)

            if emergencyStop {
                addSystemMessage("Emergency stop triggered. Agent halted.")
            } else {
                addSystemMessage("Agent stopped.")
            }
            isRunning = false
        }
    }

    /// Stops the agent loop gracefully.
    func stopAgent() {
        agentLoop?.stop()
        agentTask?.cancel()
        agentTask = nil
        isRunning = false
        addSystemMessage("Agent stopped by user.")
    }

    /// Triggers an emergency stop — halts all actions immediately.
    func triggerEmergencyStop() {
        emergencyStop = true
        agentLoop?.stop()
        agentTask?.cancel()
        agentTask = nil
        isRunning = false
        addSystemMessage("⚠️ EMERGENCY STOP triggered. All actions halted.")
    }

    /// Adds a user message to the chat.
    func addUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, content: text))
    }

    /// Adds a system/agent message to the chat.
    func addSystemMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, content: text))
    }

    /// Adds an entry to the action log.
    func logAction(_ entry: ActionLogEntry) {
        actionLog.append(entry)
    }

    /// Updates the cost tracking with new token usage.
    func updateCost(tokens: Int, cost: Double) {
        totalTokens += tokens
        currentCost += cost
    }
}

// MARK: - Supporting Types

/// A single chat message in the conversation.
struct ChatMessage: Identifiable, Equatable {
    let id: UUID = UUID()
    let timestamp: Date = Date()
    let role: MessageRole
    let content: String
}

/// The role of a chat message.
enum MessageRole: String, CaseIterable, Equatable {
    case user = "User"
    case assistant = "Assistant"
    case system = "System"
}

/// An entry in the live action log.
struct ActionLogEntry: Identifiable, Equatable {
    let id: UUID = UUID()
    let timestamp: Date = Date()
    let action: String
    let detail: String
    let status: ActionStatus
}

/// The status of an action log entry.
enum ActionStatus: String, CaseIterable, Equatable {
    case success = "✓"
    case failure = "✗"
    case pending = "…"
    case warning = "⚠"
}

/// The safety mode for the agent.
enum SafetyMode: String, CaseIterable, Equatable {
    case fullAuto = "Full Auto"
    case approveBeforeAction = "Approve Before Action"
    case stepThrough = "Step Through"
}

/// The kind of AI provider.
enum ProviderKind: String, CaseIterable, Equatable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google (Gemini)"
    case deepSeek = "DeepSeek"
    case mistral = "Mistral"
    case cohere = "Cohere"
    case xAI = "xAI (Grok)"
    case perplexity = "Perplexity"
    case togetherAI = "Together AI"
    case groq = "Groq"
    case deepInfra = "Deep Infra"
    case fireworksAI = "Fireworks AI"
    case openRouter = "OpenRouter"
    case ollama = "Ollama (Local)"
    case lmStudio = "LM Studio (Local)"
    case custom = "Custom OpenAI-Compatible"
}
