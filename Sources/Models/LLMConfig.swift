import Foundation

// MARK: - API Key Validation Result

public enum APIKeyStatus {
    case empty
    case valid
    case invalid(String) // reason why invalid
}

public enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case gemini = "Google Gemini"
    case deepseek = "DeepSeek"
    case mistral = "Mistral"
    case cohere = "Cohere"
    case xai = "xAI (Grok)"
    case perplexity = "Perplexity"
    case together = "Together AI"
    case groq = "Groq"
    case deepinfra = "Deep Infra"
    case fireworks = "Fireworks AI"
    case bedrock = "Amazon Bedrock"
    case azure = "Azure OpenAI"
    case huggingface = "Hugging Face"
    case nvidia = "Nvidia"
    case cerebras = "Cerebras"
    case novita = "NovitaAI"
    case openrouter = "OpenRouter"
    case ollama = "Ollama (Local)"
    case lmstudio = "LM Studio (Local)"
    case custom = "Custom (OpenAI-compatible)"
    
    public var id: String { self.rawValue }
    
    public var displayName: String { self.rawValue }
    
    // MARK: - API Key Validation
    
    /// Whether this provider requires an API key.
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmstudio: return false
        default: return true
        }
    }
    
    /// The expected prefix for this provider's API key, if one is known.
    public var apiKeyPrefix: String? {
        switch self {
        case .openai: return "sk-"
        case .anthropic: return "sk-ant-"
        case .gemini: return "AIza"
        case .deepseek: return "sk-"
        case .xai: return "xai-"
        case .perplexity: return "pplx-"
        case .groq: return "gsk_"
        case .fireworks: return nil  // Accepts both fw_ and sk- keys
        case .huggingface: return "hf_"
        case .nvidia: return "nvapi-"
        case .openrouter: return "sk-or-"
        case .mistral, .cohere, .together, .deepinfra, .cerebras, .novita, .bedrock, .azure, .ollama, .lmstudio, .custom:
            return nil
        }
    }
    
    /// A human-readable description of the expected key format.
    public var apiKeyHint: String {
        switch self {
        case .openai: return "Keys start with 'sk-' (e.g. sk-...). Project keys may use 'sk-proj-'."
        case .anthropic: return "Keys start with 'sk-ant-' (e.g. sk-ant-api03-...)"
        case .gemini: return "Keys start with 'AIza' or 'AQ' (Google AI Studio API key)"
        case .deepseek: return "Keys start with 'sk-' (OpenAI-compatible format)"
        case .xai: return "Keys start with 'xai-' (e.g. xai-...)"
        case .perplexity: return "Keys start with 'pplx-' (e.g. pplx-...)"
        case .groq: return "Keys start with 'gsk_' (e.g. gsk_...)"
        case .fireworks: return "Keys start with 'fw_' or 'sk-'"
        case .huggingface: return "Keys start with 'hf_' (e.g. hf_...)"
        case .nvidia: return "Keys start with 'nvapi-' (e.g. nvapi-...)"
        case .openrouter: return "Keys start with 'sk-or-' (e.g. sk-or-...)"
        case .bedrock: return "Uses AWS Access Key + Secret (set in ~/.aws/credentials)"
        case .azure: return "Azure resource key (from Azure AI portal)"
        case .mistral, .cohere, .together, .deepinfra, .cerebras, .novita:
            return "Enter your API key from the provider dashboard"
        case .ollama, .lmstudio: return "No API key required"
        case .custom: return "Enter your API key for the custom endpoint"
        }
    }
    
    /// Validates an API key against the expected format for this provider.
    /// - Returns: `.empty` if the key is blank, `.valid` if it matches the expected format,
    ///   `.invalid(reason)` if it appears to be in the wrong format.
    public func validateAPIKey(_ key: String) -> APIKeyStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        
        guard let prefix = apiKeyPrefix else {
            // No known prefix — accept any non-empty key, but check minimum length
            if trimmed.count < 8 {
                return .invalid("API key seems too short (minimum 8 characters expected)")
            }
            return .valid
        }
        
        if trimmed.hasPrefix(prefix) || (self == .gemini && trimmed.hasPrefix("AQ")) {
            let minLength: Int
            switch self {
            case .openai: minLength = 20  // sk- + at least 17 chars
            case .anthropic: minLength = 25 // sk-ant-api03- + chars
            case .gemini:
                if trimmed.hasPrefix("AIza") {
                    minLength = 39    // AIza + 35 chars
                } else {
                    minLength = 20    // AQ + at least 18 chars
                }
            case .deepseek: minLength = 20
            case .xai: minLength = 16
            case .perplexity: minLength = 18
            case .groq: minLength = 20
            case .fireworks: minLength = 16
            case .huggingface: minLength = 36  // hf_ + 34 chars
            case .nvidia: minLength = 25
            case .openrouter: minLength = 20
            default: minLength = 12
            }
            
            if trimmed.count < minLength {
                return .invalid("Key seems too short. Expected at least \(minLength) characters after '\(prefix)'.")
            }
            return .valid
        }
        
        // Check if it looks like a different provider's key
        let knownPrefixes: [(String, String)] = [
            ("sk-or-", "OpenRouter"),
            ("sk-ant-", "Anthropic"),
            ("sk-proj-", "OpenAI (project key)"),
            ("sk-", "OpenAI / OpenAI-compatible"),
            ("xai-", "xAI (Grok)"),
            ("pplx-", "Perplexity"),
            ("gsk_", "Groq"),
            ("fw_", "Fireworks AI"),
            ("hf_", "Hugging Face"),
            ("nvapi-", "Nvidia"),
            ("AIza", "Google Gemini"),
            ("AQ", "Google Gemini"),
        ]
        
        for (knownPrefix, providerName) in knownPrefixes {
            if knownPrefix == prefix { continue } // skip our own prefix
            if trimmed.hasPrefix(knownPrefix) {
                return .invalid("This looks like a \(providerName) key, not a \(rawValue) key. Keys for \(rawValue) should start with '\(prefix)'.")
            }
        }
        
        return .invalid("Key should start with '\(prefix)'. Yours starts with '\(String(trimmed.prefix(4)))...'")
    }
    
    // MARK: - Available Models Catalog
    
    /// Models that support image/vision input (omni / multimodal).
    /// Preferred for Open Cowork since the agent sends screenshots to the model.
    /// Updated June 2026 — all current frontier models from major providers are multimodal.
    public var visionModels: Set<String> {
        switch self {
        case .openai:
            return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano",
                    "gpt-4o", "gpt-4o-mini"]
        case .anthropic:
            return ["claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
                    "claude-sonnet-4-6", "claude-haiku-4-5-20251001",
                    "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
                    "claude-3-opus-20240229", "claude-3-sonnet-20240229",
                    "claude-3-haiku-20240307"]
        case .gemini:
            return ["gemini-3.5-flash", "gemini-3.1-pro", "gemini-3.1-flash-lite",
                    "gemini-3-flash", "gemini-2.5-pro", "gemini-2.5-flash",
                    "gemini-2.5-flash-lite"]
        case .deepseek:
            return ["deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat"]
        case .mistral:
            return ["mistral-medium-3.5", "mistral-small-4", "mistral-large-3",
                    "mistral-medium-3.1", "magistral-medium-1.2",
                    "ministral-3-14b", "ministral-3-8b", "ministral-3-3b",
                    "devstral-2"]
        case .cohere:
            return ["command-a-plus-05-2026", "command-a-vision-07-2025", "aya-vision"]
        case .xai:
            return ["grok-4.3", "grok-build-0.1", "grok-3", "grok-2", "grok-2-vision"]
        case .perplexity:
            return ["sonar-reasoning-pro", "sonar-pro", "sonar-deep-research"]
        case .together:
            return ["MiniMaxAI/MiniMax-M2.7", "Qwen/Qwen3.7-Max", "Qwen/Qwen3.6-Plus",
                    "moonshotai/Kimi-K2.6", "deepseek-ai/DeepSeek-V4-Pro",
                    "deepseek-ai/DeepSeek-V4-Flash", "nvidia/nemotron-3-ultra-550b-a55b",
                    "google/gemma-4-31B-it",
                    "MiniMaxAI/MiniMax-M3", "zai-org/GLM-5.1"]
        case .groq:
            return ["openai/gpt-oss-120b", "openai/gpt-oss-20b",
                    "meta-llama/llama-4-scout-17b-16e-instruct",
                    "llama-3.2-11b-vision-preview",
                    "llama-3.2-90b-vision-preview"]
        case .deepinfra:
            return ["nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",
                    "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning",
                    "deepseek-ai/DeepSeek-V4-Pro", "deepseek-ai/DeepSeek-V4-Flash",
                    "moonshotai/Kimi-K2.5",
                    "google/gemma-4-26B-A4B-it",
                    "Qwen/Qwen3.6-Plus", "Qwen/Qwen3.6-35B-A3B",
                    "Qwen/Qwen3.5-397B-A17B", "zai-org/GLM-5.1",
                    "MiniMaxAI/MiniMax-M2.5"]
        case .fireworks:
            return ["accounts/fireworks/models/llama-v3p2-11b-vision-instruct",
                    "accounts/fireworks/models/qwen2-vl-72b-instruct",
                    "accounts/fireworks/models/qwen3-vl-instruct",
                    "accounts/fireworks/models/llama-v4-scout-17b-instruct",
                    "accounts/fireworks/models/qwen3.7-plus-vl",
                    "accounts/fireworks/models/qwen3.6-plus",
                    "accounts/fireworks/models/gemma-4-31b-it",
                    "accounts/fireworks/models/kimi-k2.6",
                    "accounts/fireworks/models/step-3.7-flash"]
        case .bedrock:
            return ["anthropic.claude-opus-4-8-20260528-v1:0",
                    "anthropic.claude-3-5-sonnet-20241022-v2:0",
                    "anthropic.claude-3-haiku-20240307-v1:0",
                    "meta.llama4-17b-scout-instruct-v1:0",
                    "meta.llama3-2-11b-instruct-v1:0",
                    "meta.llama3-2-90b-instruct-v1:0",
                    "amazon.nova-premier-v1:0",
                    "amazon.nova-pro-v1:0",
                    "amazon.nova-lite-v1:0",
                    "amazon.nova-micro-v1:0",
                    "mistral.mistral-large-2407-v1:0",
                    "mistral.mistral-medium-3.5-v1:0",
                    "mistral.mistral-small-4-v1:0",
                    "deepseek.deepseek-v4-pro-v1:0",
                    "deepseek.deepseek-v4-flash-v1:0",
                    "cohere.command-a-plus-v1:0",
                    "google.gemma-3-4b-it-v1:0",
                    "google.gemma-3-12b-it-v1:0",
                    "google.gemma-3-27b-it-v1:0",
                    "nvidia.nemotron-3-super-120b-v1:0",
                    "nvidia.nemotron-3-nano-30b-v1:0",
                    "nvidia.nemotron-3-nano-12b-v1:0",
                    "nvidia.nemotron-3-nano-9b-v1:0",
                    "zai.glm-5-v1:0",
                    "zai.glm-4.7-v1:0",
                    "zai.glm-4.7-flash-v1:0"]
        case .azure:
            return ["gpt-5.5", "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.4-nano",
                    "gpt-5.3-chat", "gpt-5.2", "gpt-5.2-chat", "gpt-5.1", "gpt-5.1-chat",
                    "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4o", "gpt-4o-mini",
                    "gpt-4-turbo", "gpt-4-turbo-preview", "gpt-oss-120b", "gpt-oss-20b",
                    "computer-use-preview", "gpt-chat-latest"]
        case .huggingface:
            return ["nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",
                    "deepseek-ai/DeepSeek-V4-Pro", "deepseek-ai/DeepSeek-V4-Flash",
                    "openai/gpt-oss-120b", "meta-llama/Llama-3.1-8B-Instruct",
                    "nex-agi/Nex-N2-Pro"]
        case .nvidia:
            return ["nvidia/nemotron-3-ultra-550b-a55b",
                    "nvidia/nemotron-3-super-120b-a12b",
                    "nvidia/nemotron-3-nano-9b",
                    "moonshotai/kimi-k2.6",
                    "deepseek-ai/deepseek-v4-pro",
                    "zai-org/glm-5.1",
                    "google/gemma-2-27b",
                    "mistralai/mistral-large-3",
                    "deepseek-ai/DeepSeek-V4-Flash",
                    "qwen/qwen3.7-max",
                    "google/gemma-4-31b-it",
                    "openai/gpt-oss-120b",
                    "MiniMaxAI/MiniMax-M2.7",
                    "zai-org/GLM-5.1"]
        case .cerebras:
            return ["gpt-oss-120b", "zai-glm-4.7", "llama-3.1-8b", "llama-3.1-70b"]
        case .novita:
            return ["MiniMaxAI/MiniMax-M3", "deepseek-ai/DeepSeek-V4-Pro",
                    "deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V3.2",
                    "XiaomiMiMo/MiMo-V2.5-Pro", "Qwen/Qwen3.7-Max",
                    "moonshotai/Kimi-K2.6", "zai-org/GLM-5.1",
                    "google/gemma-4-31B-it", "Qwen/Qwen3.5-397B-A17B",
                    "zai-org/GLM-5", "Qwen/Qwen3-Max"]
        case .openrouter:
            return ["openai/gpt-5.5", "openai/gpt-5.4", "openai/gpt-5.4-mini",
                    "openai/gpt-4o", "openai/gpt-4o-mini",
                    "anthropic/claude-opus-4-8", "anthropic/claude-sonnet-4-6",
                    "anthropic/claude-3.5-sonnet",
                    "google/gemini-3.5-flash", "google/gemini-3.1-pro",
                    "google/gemini-2.5-flash", "google/gemini-2.5-pro",
                    "meta-llama/llama-3.2-11b-vision",
                    "meta-llama/llama-4-scout-17b-16e-instruct",
                    "deepseek/deepseek-v4-pro",
                    "mistralai/mistral-large-3", "mistralai/mistral-medium-3.5",
                    "mistralai/mistral-small-4",
                    "qwen/qwen3.7-plus", "qwen/qwen3.7-max",
                    "nvidia/nemotron-3-ultra-550b-a55b",
                    "x-ai/grok-4.3", "x-ai/grok-2",
                    "moonshotai/kimi-k2.6", "zai-org/glm-5.1",
                    "nex-agi/nex-n2-pro", "minimax/minimax-m3"]
        case .ollama:
            return ["llava:13b", "llava:7b", "minicpm-v:latest"]
        case .lmstudio:
            return []
        case .custom:
            return []
        }
    }
    
    /// The list of known available models for this provider.
    /// Omni/multimodal (vision-capable) models are listed first — preferred for screenshot-based desktop agents.
    /// The first model in the list is the default.
    public var availableModels: [String] {
        switch self {
        case .openai:
            return [
                "gpt-5.5",           // flagship — latest, most capable
                "gpt-5.4",           // high-performance coding & reasoning
                "gpt-5.4-mini",      // strong mini for coding & computer use
                "gpt-5.4-nano",      // smallest, fastest, cheapest
                "gpt-4o",            // omni — legacy but still capable
                "gpt-4o-mini",       // omni — cheaper legacy
                "gpt-4-turbo",       // legacy text model
                "o3",                // reasoning (text-only)
                "o4-mini",           // fast reasoning
            ]
        case .anthropic:
            return [
                "claude-opus-4-8",              // most capable, latest
                "claude-opus-4-7",              // high-performance reasoning
                "claude-opus-4-6",              // powerful reasoning
                "claude-sonnet-4-6",            // balanced speed & intelligence
                "claude-haiku-4-5-20251001",    // fastest, near-frontier
                "claude-3-5-sonnet-20241022",   // solid all-rounder
                "claude-3-5-haiku-20241022",    // fast, cheap
                "claude-3-opus-20240229",        // most powerful (legacy)
                "claude-3-sonnet-20240229",      // legacy mid-tier
                "claude-3-haiku-20240307",       // fastest Claude (legacy)
            ]
        case .gemini:
            return [
                "gemini-3.5-flash",        // latest fast multimodal
                "gemini-3.1-pro",        // advanced intelligence & coding
                "gemini-3.1-flash-lite", // lightweight
                "gemini-3-flash",        // frontier-class performance
                "gemini-2.5-pro",        // top Gemini
                "gemini-2.5-flash",      // fast multimodal
                "gemini-2.5-flash-lite", // fastest & cheapest 2.5
            ]
        case .deepseek:
            return [
                "deepseek-v4-pro",     // flagship — 1.6T params, 1M context
                "deepseek-v4-flash",   // fast — 284B params, 1M context
                "deepseek-chat",       // legacy alias (deprecated)
                "deepseek-reasoner",   // legacy alias (deprecated)
            ]
        case .mistral:
            return [
                "mistral-medium-3.5",    // frontier-class multimodal
                "mistral-small-4",       // hybrid instruct + reasoning + coding
                "mistral-large-3",       // open-weight general-purpose multimodal
                "mistral-medium-3.1",    // legacy frontier multimodal
                "magistral-medium-1.2",  // frontier reasoning model
                "ministral-3-14b",       // best-in-class text & vision
                "ministral-3-8b",        // efficient text & vision
                "ministral-3-3b",        // tiny but capable text & vision
                "devstral-2",            // frontier code agent
                "codestral",             // code completion
                "mistral-moderation-2",  // moderation
            ]
        case .cohere:
            return [
                "command-a-plus-05-2026", // first MoE: vision + reasoning + translation
                "command-a-03-2025",      // top performant model
                "command-a-reasoning-08-2025", // reasoning model
                "command-a-vision-07-2025",  // image input
                "command-a-translate-08-2025", // translation
                "command-r7b-12-2024",    // small, fast, RAG-optimized
                "command-r-plus-08-2024", // legacy RAG
                "command-r-08-2024",      // legacy instruction
                "command-r-03-2024",      // deprecated
                "command-r-plus-04-2024", // deprecated
                "command-light",          // deprecated
                "command",                // deprecated
                "aya-vision",             // multilingual vision
                "aya-expanse",            // multilingual text
            ]
        case .xai:
            return [
                "grok-4.3",        // latest flagship — agentic tool calling
                "grok-build-0.1",  // fast coding model for agentic workflows
                "grok-3",          // previous generation flagship
                "grok-2",          // legacy high-performance
                "grok-2-vision",   // legacy vision-enabled model
            ]
        case .perplexity:
            return [
                "sonar-deep-research",  // comprehensive multi-step research
                "sonar-reasoning-pro",  // vision + reasoning
                "sonar-pro",            // vision-capable
                "sonar",                // lightweight
            ]
        case .together:
            return [
                "MiniMaxAI/MiniMax-M2.7",                      // multimodal foundation
                "Qwen/Qwen3.7-Max",                            // vision + reasoning
                "Qwen/Qwen3.6-Plus",                           // multimodal
                "Qwen/Qwen3.5-397B-A17B",                      // flagship MoE
                "moonshotai/Kimi-K2.6",                        // agentic multimodal
                "zai-org/GLM-5.1",                             // agentic engineering
                "deepseek-ai/DeepSeek-V4-Pro",                 // flagship reasoning
                "deepseek-ai/DeepSeek-V4-Flash",               // fast reasoning
                "nvidia/nemotron-3-ultra-550b-a55b",           // frontier reasoning
                "openai/gpt-oss-120b",                         // open-weight reasoning
                "meta-llama/Llama-3.3-70B-Instruct-Turbo",     // vision
                "google/gemma-4-31B-it",                         // multimodal
                "LiquidAI/LFM2-24B-A2B",                        // efficient reasoning
                "MiniMaxAI/MiniMax-M3",                         // multimodal foundation
                "zai-org/GLM-5",                                // long-context reasoning
                "meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo",
                "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo",
                "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",
                "mistralai/Mixtral-8x22B-Instruct-v0.1",
            ]
        case .groq:
            return [
                "openai/gpt-oss-120b",                          // open-weight flagship
                "openai/gpt-oss-20b",                           // fast open-weight
                "meta-llama/llama-4-scout-17b-16e-instruct",    // latest Llama 4
                "llama-3.3-70b-versatile",
                "llama-3.3-8b-instant",
                "llama-3.1-70b-versatile",
                "llama-3.1-8b-instant",
                "qwen/qwen3-32b",
                "mixtral-8x7b-32768",
                "deepseek-r1-distill-llama-70b",
                "gemma2-9b-it",
                "qwen-2.5-72b-instruct",
                "groq/compound",                // agentic system
                "groq/compound-mini",           // agentic system
            ]
        case .deepinfra:
            return [
                "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",    // frontier reasoning
                "nvidia/Nemotron-3-Nano-Omni-30B-A3B-Reasoning", // multimodal omni
                "deepseek-ai/DeepSeek-V4-Pro",                 // flagship reasoning
                "deepseek-ai/DeepSeek-V4-Flash",               // fast reasoning
                "moonshotai/Kimi-K2.5",                        // agentic multimodal
                "zai-org/GLM-5.1",                             // agentic engineering
                "Qwen/Qwen3.6-35B-A3B",                        // efficient MoE
                "Qwen/Qwen3.5-397B-A17B",                      // flagship MoE
                "google/gemma-4-26B-A4B-it",                   // efficient multimodal
                "MiniMaxAI/MiniMax-M2.5",                      // coding & agentic
                "zai-org/GLM-5",                               // long-context reasoning
                "deepseek-ai/DeepSeek-V3.2",                   // sparse attention
                "Qwen/Qwen3.6-Plus",                           // multimodal
                "meta-llama/Llama-3.3-70B-Instruct",
                "meta-llama/Meta-Llama-3.1-70B-Instruct",
                "meta-llama/Meta-Llama-3.1-8B-Instruct",
                "mistralai/Mistral-Nemo-Instruct-2407",
                "deepseek-ai/deepseek-r1",
                "nvidia/nemotron-4-340b-instruct",
            ]
        case .fireworks:
            return [
                "accounts/fireworks/models/llama-v3p2-11b-vision-instruct",  // vision
                "accounts/fireworks/models/qwen2-vl-72b-instruct",           // vision
                "accounts/fireworks/models/qwen3-vl-instruct",               // vision
                "accounts/fireworks/models/llama-v4-scout-17b-instruct",     // Llama 4
                "accounts/fireworks/models/llama-v3p3-70b-instruct",
                "accounts/fireworks/models/llama-v3p1-70b-instruct",
                "accounts/fireworks/models/llama-v3p1-8b-instruct",
                "accounts/fireworks/models/mixtral-8x22b-instruct",
                "accounts/fireworks/models/deepseek-v4-pro",
                "accounts/fireworks/models/deepseek-v4-flash",
                "accounts/fireworks/models/deepseek-v3",
                "accounts/fireworks/models/deepseek-r1",
                "accounts/fireworks/models/gpt-oss-120b",
                "accounts/fireworks/models/kimi-k2.6",
                "accounts/fireworks/models/glm-5.1",
                "accounts/fireworks/models/gemma-4-31b-it",
                "accounts/fireworks/models/qwen3.7-plus-vl",                 // vision
                "accounts/fireworks/models/qwen3.6-plus",                    // vision
                "accounts/fireworks/models/minimax-m2.5",
                "accounts/fireworks/models/step-3.7-flash",                  // vision
            ]
        case .bedrock:
            return [
                "anthropic.claude-opus-4-8-20260528-v1:0",     // latest
                "anthropic.claude-3-5-sonnet-20241022-v2:0",   // vision
                "anthropic.claude-3-haiku-20240307-v1:0",      // vision
                "meta.llama4-17b-scout-instruct-v1:0",         // Llama 4
                "meta.llama3-3-70b-instruct-v1:0",
                "meta.llama3-1-70b-instruct-v1:0",
                "meta.llama3-1-8b-instruct-v1:0",
                "meta.llama3-1-405b-instruct-v1:0",
                "meta.llama3-2-11b-instruct-v1:0",             // vision
                "meta.llama3-2-90b-instruct-v1:0",             // vision
                "amazon.nova-premier-v1:0",
                "amazon.nova-pro-v1:0",
                "amazon.nova-lite-v1:0",
                "amazon.nova-micro-v1:0",
                "amazon.titan-text-express-v1",
                "mistral.mistral-large-2407-v1:0",
                "mistral.mistral-medium-3.5-v1:0",
                "mistral.mistral-small-4-v1:0",
                "deepseek.deepseek-v4-pro-v1:0",
                "deepseek.deepseek-v4-flash-v1:0",
                "deepseek.deepseek-v3.2-v1:0",
                "deepseek.deepseek-v3.1-v1:0",
                "deepseek.deepseek-r1-v1:0",
                "cohere.command-a-plus-v1:0",
                "cohere.command-a-v1:0",
                "cohere.command-r-plus-v1:0",
                "cohere.command-r-v1:0",
                "ai21.jamba-1-5-large-v1:0",
                "ai21.jamba-1-5-mini-v1:0",
                "google.gemma-3-4b-it-v1:0",
                "google.gemma-3-12b-it-v1:0",
                "google.gemma-3-27b-it-v1:0",
                "nvidia.nemotron-3-super-120b-v1:0",
                "nvidia.nemotron-3-nano-30b-v1:0",
                "nvidia.nemotron-3-nano-12b-v1:0",
                "nvidia.nemotron-3-nano-9b-v1:0",
                "zai.glm-5-v1:0",
                "zai.glm-4.7-v1:0",
                "zai.glm-4.7-flash-v1:0",
            ]
        case .azure:
            return [
                "gpt-chat-latest",       // preview
                "gpt-5.5",               // flagship
                "gpt-5.4",               // high-performance
                "gpt-5.4-pro",           // high-performance pro
                "gpt-5.4-mini",          // strong mini
                "gpt-5.4-nano",          // smallest
                "gpt-5.3-chat",          // chat
                "gpt-5.3-codex",         // coding
                "gpt-5.2",               // reasoning
                "gpt-5.2-chat",          // chat
                "gpt-5.2-codex",         // coding
                "gpt-5.1",               // reasoning
                "gpt-5.1-chat",          // chat
                "gpt-5.1-codex",         // coding
                "gpt-5",                 // core
                "gpt-5-mini",            // mini
                "gpt-5-nano",            // nano
                "gpt-4o",                // omni
                "gpt-4o-mini",           // omni
                "gpt-4-turbo",           // previous gen
                "gpt-4-turbo-preview",   // preview
                "o1",                    // reasoning
                "o1-mini",               // mini reasoning
                "o1-preview",            // preview
                "gpt-oss-120b",          // open-weight
                "gpt-oss-20b",           // open-weight
                "codex-mini",            // code
                "gpt-5-codex",           // code generation
                "computer-use-preview",  // agentic
            ]
        case .huggingface:
            return [
                "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B",    // frontier
                "deepseek-ai/DeepSeek-V4-Pro",                 // flagship
                "deepseek-ai/DeepSeek-V4-Flash",               // fast
                "openai/gpt-oss-120b",                         // open-weight
                "LiquidAI/LFM2.5-8B-A1B",                      // efficient
                "JetBrains/Mellum2-12B-A2.5B-Thinking",          // thinking
                "nex-agi/Nex-N2-Pro",                            // agentic MoE
                "meta-llama/Llama-3.1-8B-Instruct",              // popular
                "openbmb/MiniCPM5-1B",                           // tiny
                "sapientinc/HRM-Text-1B",                        // text
            ]
        case .nvidia:
            return [
                "nvidia/nemotron-3-ultra-550b-a55b",          // frontier reasoning
                "nvidia/nemotron-3-super-120b-a12b",          // multi-agent
                "nvidia/nemotron-3-nano-9b",                // fast edge
                "moonshotai/kimi-k2.6",                     // multimodal
                "deepseek-ai/deepseek-v4-pro",              // flagship
                "zai-org/glm-5.1",                            // agentic
                "meta/llama-3.3-70b-instruct",              // enterprise
                "google/gemma-2-27b",                       // high-performance
                "mistralai/mistral-large-3",                // reasoning
                "meta/llama-3.1-405b-instruct",
                "meta/llama-3.1-70b-instruct",
                "meta/llama-3.1-8b-instruct",
                "deepseek-ai/DeepSeek-V4-Flash",
                "qwen/qwen2.5-72b-instruct",
                "qwen/qwen3.7-max",
                "google/gemma-4-31b-it",
                "microsoft/phi-4",
                "microsoft/phi-4-mini",
                "openai/gpt-oss-120b",
                "MiniMaxAI/MiniMax-M2.7",
                "zai-org/GLM-5.1",
            ]
        case .cerebras:
            return [
                "gpt-oss-120b",        // production — OpenAI open-weight
                "zai-glm-4.7",         // preview — 355B MoE
                "llama-3.1-8b",        // 8B
                "llama-3.1-70b",       // 70B
            ]
        case .novita:
            return [
                "MiniMaxAI/MiniMax-M3",          // 1M context
                "deepseek-ai/DeepSeek-V4-Pro",   // 1M context
                "deepseek-ai/DeepSeek-V4-Flash", // 1M context
                "deepseek-ai/DeepSeek-V3.2",     // 163K context
                "XiaomiMiMo/MiMo-V2.5-Pro",      // 1M context
                "Qwen/Qwen3.7-Max",              // 1M context
                "moonshotai/Kimi-K2.6",          // 262K context
                "zai-org/GLM-5.1",               // 204K context
                "google/gemma-4-31B-it",           // 262K context
                "Qwen/Qwen3.5-397B-A17B",        // 262K context
                "zai-org/GLM-5",                 // 202K context
                "Qwen/Qwen3-Max",                // 262K context
            ]
        case .openrouter:
            return [
                "nex-agi/nex-n2-pro",                          // agentic MoE
                "qwen/qwen3.7-plus",                            // flagship
                "anthropic/claude-opus-4-8",                   // most capable
                "openai/gpt-5.5",                               // flagship
                "deepseek/deepseek-v4-pro",                    // flagship
                "meta-llama/llama-3.3-70b",                    // popular
                "google/gemma-4-31b",                          // multimodal
                "mistralai/mistral-large-3",                   // reasoning
                "x-ai/grok-2",                                  // xAI
                "perplexity/sonar",                             // research
                "qwen/qwen3.7-max",
                "moonshotai/kimi-k2.6",
                "zai-org/glm-5.1",
                "openai/gpt-5.4",
                "openai/gpt-5.4-mini",
                "openai/gpt-4o",
                "anthropic/claude-sonnet-4-6",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-3.5-flash",
                "google/gemini-3.1-pro",
                "google/gemini-2.5-flash",
                "google/gemini-2.5-pro",
                "meta-llama/llama-3.2-11b-vision",
                "meta-llama/llama-4-scout-17b-16e-instruct",
                "deepseek/deepseek-r1",
                "deepseek/deepseek-v3.1",
                "mistralai/mistral-medium-3.5",
                "mistralai/mistral-small-4",
                "mistralai/pixtral-large",
                "qwen/qwen2.5-72b-instruct",
                "nvidia/nemotron-3-ultra-550b-a55b",
                "x-ai/grok-4.3",
                "x-ai/grok-build-0.1",
                "minimax/minimax-m3",
            ]
        case .ollama:
            return [
                "llava:13b",       // vision model
                "llava:7b",        // smaller vision
                "minicpm-v:latest",  // vision
                "llama3.3",
                "llama3.2",
                "llama3.1:70b",
                "llama3.1:8b",
                "mistral",
                "gemma2:9b",
                "gemma2:27b",
                "qwen2.5:7b",
                "qwen2.5:72b",
                "deepseek-r1:14b",
                "deepseek-v3",
            ]
        case .lmstudio:
            return [
                "llava-v1.6-mistral-7b",
                "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF",
                "lmstudio-community/Meta-Llama-3.3-70B-Instruct-GGUF",
            ]
        case .custom:
            return []
        }
    }
    
    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .cohere: return "https://api.cohere.ai/v1"
        case .xai: return "https://api.x.ai/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .together: return "https://api.together.xyz/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepinfra: return "https://api.deepinfra.com/v1/openai"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .bedrock: return "https://bedrock-runtime.us-east-1.amazonaws.com"
        case .azure: return "https://YOUR-RESOURCE.openai.azure.com"
        case .huggingface: return "https://api-inference.huggingface.co/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .novita: return "https://api.novita.ai/v3/openai"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        case .custom: return ""
        }
    }
    
    /// The default model for this provider — always matches the first entry in `availableModels`.
    public var defaultModel: String {
        availableModels.first ?? ""
    }
}

public struct LLMConfig: Codable, Equatable {
    public var provider: LLMProvider
    public var apiKey: String
    public var baseURL: String
    public var modelName: String
    public var temperature: Double
    
    public init(
        provider: LLMProvider = .openai,
        apiKey: String = "",
        baseURL: String = LLMProvider.openai.defaultBaseURL,
        modelName: String = LLMProvider.openai.defaultModel,
        temperature: Double = 0.0
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelName = modelName
        self.temperature = temperature
    }
    
    public static var empty: LLMConfig {
        LLMConfig()
    }
}
