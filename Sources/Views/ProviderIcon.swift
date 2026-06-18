import SwiftUI

// MARK: - Provider & Model Icon Helpers

/// Returns the asset catalog image name for each provider.
public func providerImageName(for provider: LLMProvider) -> String {
    switch provider {
    case .openai: return "openai"
    case .anthropic: return "anthropic"
    case .gemini: return "gemini"
    case .deepseek: return "deepseek"
    case .mistral: return "mistral"
    case .cohere: return "cohere"
    case .xai: return "xai"
    case .perplexity: return "perplexity"
    case .together: return "togetherai"
    case .groq: return "groq"
    case .deepinfra: return "deepinfra"
    case .fireworks: return "fireworks"
    case .bedrock: return "bedrock"
    case .azure: return "azure"
    case .huggingface: return "huggingface"
    case .nvidia: return "nvidia"
    case .cerebras: return "cerebras"
    case .novita: return "novita"
    case .openrouter: return "openrouter"
    case .ollama: return "ollama"
    case .lmstudio: return "lmstudio"
    case .custom: return "custom"
    }
}

/// Returns the asset catalog image name for a model based on its name.
/// Maps models to their **owner/creator** logo when available.
/// Falls back to the inference provider's logo (if known) before generic "custom".
public func modelImageName(for model: String, provider: LLMProvider? = nil) -> String {
    let lower = model.lowercased()

    // OpenAI models
    if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("o4") {
        return "openai"
    }

    // Anthropic / Claude models
    if lower.contains("claude") {
        return "claude"
    }

    // Google models
    if lower.contains("gemini") || lower.contains("gemma") {
        return "gemini"
    }

    // DeepSeek models
    if lower.contains("deepseek") {
        return "deepseek"
    }

    // Mistral models
    if lower.contains("mistral") || lower.contains("mixtral") || lower.contains("pixtral") || lower.contains("magistral") || lower.contains("ministral") || lower.contains("devstral") || lower.contains("codestral") {
        return "mistral"
    }

    // Cohere models
    if lower.contains("command") || lower.contains("aya") {
        return "cohere"
    }

    // xAI models
    if lower.contains("grok") {
        return "xai"
    }

    // Perplexity models
    if lower.contains("sonar") {
        return "perplexity"
    }

    // Meta/Llama models
    if lower.contains("llama") || lower.contains("llava") {
        return "meta"
    }

    // Qwen models (Alibaba)
    if lower.contains("qwen") {
        return "qwen"
    }

    // Nvidia models
    if lower.contains("phi") || lower.contains("nemotron") {
        return "nvidia"
    }

    // Cerebras models
    if lower.contains("cerebras") {
        return "cerebras"
    }

    // Hugging Face models
    if lower.contains("huggingface") || lower.contains("hf_") {
        return "huggingface"
    }

    // Kimi / Moonshot
    if lower.contains("kimi") || lower.contains("moonshot") {
        return "moonshot"
    }

    // MiniMax
    if lower.contains("minimax") {
        return "minimax"
    }

    // Z.ai / GLM
    if lower.contains("glm") || lower.contains("zai") {
        return "zai"
    }

    // Xiaomi / MiMo
    if lower.contains("mimo") || lower.contains("xiaomi") {
        return "xiaomi"
    }

    // Nex AGI
    if lower.contains("nex") {
        return "nex"
    }

    // Step models
    if lower.contains("step-") {
        return "step"
    }

    // JetBrains / Mellum
    if lower.contains("mellum") || lower.contains("jetbrains") {
        return "jetbrains"
    }

    // Liquid AI
    if lower.contains("lfm") || lower.contains("liquid") {
        return "liquidai"
    }

    // OpenBMB / MiniCPM
    if lower.contains("minicpm") || lower.contains("openbmb") {
        return "openbmb"
    }

    // Sapient
    if lower.contains("sapient") || lower.contains("hrm") {
        return "sapient"
    }

    // No owner match — fall back to the inference provider's logo if known
    if let provider {
        let providerImage = providerImageName(for: provider)
        // Only use provider logo for inference providers that host third-party models
        switch provider {
        case .together, .groq, .deepinfra, .fireworks, .novita, .openrouter, .nvidia, .huggingface, .cerebras, .bedrock, .azure:
            return providerImage
        default:
            break
        }
    }

    return "custom"
}

/// Reusable icon view for brand logos from the asset catalog.
/// Uses SwiftUI's native Image(asset-name) so .frame() sizing is respected.
/// All icons render in their original colors.
public struct ProviderIcon: View {
    public let imageName: String
    public var size: CGFloat = 12

    public init(imageName: String, size: CGFloat = 12) {
        self.imageName = imageName
        self.size = size
    }

    public var body: some View {
        if NSImage(named: imageName) != nil {
            Image(imageName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Fallback: settings gear for custom/unknown
            Image(systemName: "gearshape.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(.secondary)
        }
    }
}
