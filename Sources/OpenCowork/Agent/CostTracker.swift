import Foundation

/// Tracks token usage and estimated cost for every AI model call.
///
/// Maintains per-session totals and provides real-time cost estimates
/// based on provider-specific pricing.  All costs are displayed to the
/// user with full transparency — no markup, no hidden fees.
@MainActor
final class CostTracker {
    /// Reference to the shared application state.
    private let appState: AppState

    /// Pricing data for common models (USD per 1M tokens).
    /// Input and output tokens are priced separately by most providers.
    private let modelPricing: [String: (inputPerMillion: Double, outputPerMillion: Double)] = [
        // OpenAI
        "gpt-4o": (inputPerMillion: 2.50, outputPerMillion: 10.00),
        "gpt-4o-mini": (inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gpt-4-turbo": (inputPerMillion: 10.00, outputPerMillion: 30.00),
        "o1": (inputPerMillion: 15.00, outputPerMillion: 60.00),
        "o1-mini": (inputPerMillion: 3.00, outputPerMillion: 12.00),
        "o3-mini": (inputPerMillion: 1.10, outputPerMillion: 4.40),

        // Anthropic
        "claude-sonnet-4-20250514": (inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-sonnet-20241022": (inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-haiku-20241022": (inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-3-opus-20240229": (inputPerMillion: 15.00, outputPerMillion: 75.00),

        // Google
        "gemini-2.5-pro": (inputPerMillion: 1.25, outputPerMillion: 10.00),
        "gemini-2.5-flash": (inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gemini-2.0-flash": (inputPerMillion: 0.10, outputPerMillion: 0.40),

        // DeepSeek
        "deepseek-chat": (inputPerMillion: 0.27, outputPerMillion: 1.10),
        "deepseek-reasoner": (inputPerMillion: 0.55, outputPerMillion: 2.19),

        // Mistral
        "mistral-large": (inputPerMillion: 2.00, outputPerMillion: 6.00),
        "mistral-small": (inputPerMillion: 0.20, outputPerMillion: 0.60),

        // xAI
        "grok-3": (inputPerMillion: 3.00, outputPerMillion: 15.00),
        "grok-3-mini": (inputPerMillion: 0.30, outputPerMillion: 0.50),

        // Local models are free
        "llama3.2": (inputPerMillion: 0.0, outputPerMillion: 0.0),
        "llama3.1": (inputPerMillion: 0.0, outputPerMillion: 0.0),
        "mistral-nemo": (inputPerMillion: 0.0, outputPerMillion: 0.0),
    ]

    init(appState: AppState) {
        self.appState = appState
    }

    /// Records token usage from an AI model call and updates the running totals.
    ///
    /// - Parameters:
    ///   - inputTokens: Number of prompt/input tokens consumed.
    ///   - outputTokens: Number of completion/output tokens generated.
    ///   - model: The model name used for pricing lookup.
    func recordUsage(inputTokens: Int, outputTokens: Int, model: String) {
        let pricing = modelPricing[model] ?? (inputPerMillion: 1.0, outputPerMillion: 5.0)
        let inputCost = (Double(inputTokens) / 1_000_000.0) * pricing.inputPerMillion
        let outputCost = (Double(outputTokens) / 1_000_000.0) * pricing.outputPerMillion
        let totalCost = inputCost + outputCost
        let totalTokens = inputTokens + outputTokens

        appState.updateCost(tokens: totalTokens, cost: totalCost)
    }

    /// Estimates the cost for a given number of tokens with a specific model.
    ///
    /// - Parameters:
    ///   - inputTokens: Estimated input tokens.
    ///   - outputTokens: Estimated output tokens.
    ///   - model: The model name.
    /// - Returns: The estimated cost in USD.
    func estimateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        let pricing = modelPricing[model] ?? (inputPerMillion: 1.0, outputPerMillion: 5.0)
        let inputCost = (Double(inputTokens) / 1_000_000.0) * pricing.inputPerMillion
        let outputCost = (Double(outputTokens) / 1_000_000.0) * pricing.outputPerMillion
        return inputCost + outputCost
    }

    /// Returns a human-readable summary of the current session's usage.
    func sessionSummary() -> String {
        let cost = appState.currentCost
        let tokens = appState.totalTokens
        return "\(tokens) tokens · $\(String(format: "%.4f", cost))"
    }

    /// Resets the session counters to zero.
    func resetSession() {
        appState.updateCost(tokens: -appState.totalTokens, cost: -appState.currentCost)
    }
}
