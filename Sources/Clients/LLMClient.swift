import Foundation

public struct LLMResponse {
    public let content: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let estimatedCost: Double
}

public struct LLMClient {
    public var query: (
        _ prompt: String,
        _ systemPrompt: String,
        _ screenshotData: Data?,
        _ config: LLMConfig
    ) async throws -> LLMResponse
}

extension LLMClient {
    public static func live() -> LLMClient {
        return LLMClient { prompt, systemPrompt, screenshotData, config in
            let session = URLSession.shared
            
            // 1. Determine if using Anthropic or OpenAI-compatible format
            let isAnthropic = config.provider == .anthropic
            
            var urlString = config.baseURL
            if !urlString.hasSuffix("/chat/completions") && !isAnthropic {
                if urlString.hasSuffix("/") {
                    urlString += "chat/completions"
                } else {
                    urlString += "/chat/completions"
                }
            } else if isAnthropic {
                if !urlString.hasSuffix("/messages") {
                    if urlString.hasSuffix("/") {
                        urlString += "messages"
                    } else {
                        urlString += "/messages"
                    }
                }
            }
            
            guard let url = URL(string: urlString) else {
                throw NSError(domain: "LLMClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL: \(urlString)"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add authorization headers
            if isAnthropic {
                request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            } else {
                // OpenAI-compatible
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            // Build the messages payload
            var requestBody: [String: Any] = [:]
            
            if isAnthropic {
                requestBody["model"] = config.modelName
                requestBody["system"] = systemPrompt
                requestBody["temperature"] = config.temperature
                
                var userContent: [[String: Any]] = []
                userContent.append([
                    "type": "text",
                    "text": prompt
                ])
                
                if let screenshotData = screenshotData {
                    let base64Image = screenshotData.base64EncodedString()
                    userContent.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64Image
                        ]
                    ])
                }
                
                requestBody["messages"] = [
                    [
                        "role": "user",
                        "content": userContent
                    ]
                ]
                requestBody["max_tokens"] = 4096
            } else {
                // OpenAI compatible format
                requestBody["model"] = config.modelName
                requestBody["temperature"] = config.temperature
                
                var messages: [[String: Any]] = []
                // Add system message
                messages.append([
                    "role": "system",
                    "content": systemPrompt
                ])
                
                var userContent: [Any] = []
                userContent.append([
                    "type": "text",
                    "text": prompt
                ])
                
                if let screenshotData = screenshotData {
                    let base64Image = screenshotData.base64EncodedString()
                    userContent.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)"
                        ]
                    ])
                }
                
                messages.append([
                    "role": "user",
                    "content": userContent
                ])
                
                requestBody["messages"] = messages
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "LLMClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error details available"
                throw NSError(domain: "LLMClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode): \(errorBody)"])
            }
            
            guard let responseJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw NSError(domain: "LLMClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response"])
            }
            
            // Extract content and tokens
            var content = ""
            var inputTokens = 0
            var outputTokens = 0
            
            if isAnthropic {
                if let contentArray = responseJSON["content"] as? [[String: Any]],
                   let firstContent = contentArray.first,
                   let text = firstContent["text"] as? String {
                    content = text
                }
                if let usage = responseJSON["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                    outputTokens = usage["output_tokens"] as? Int ?? 0
                }
            } else {
                // OpenAI standard
                if let choices = responseJSON["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let text = message["content"] as? String {
                    content = text
                }
                if let usage = responseJSON["usage"] as? [String: Any] {
                    inputTokens = usage["prompt_tokens"] as? Int ?? 0
                    outputTokens = usage["completion_tokens"] as? Int ?? 0
                }
            }
            
            // Compute estimated cost
            let estimatedCost = calculateCost(provider: config.provider, model: config.modelName, input: inputTokens, output: outputTokens)
            
            return LLMResponse(
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                estimatedCost: estimatedCost
            )
        }
    }
    
    private static func calculateCost(provider: LLMProvider, model: String, input: Int, output: Int) -> Double {
        // Approximate cost per million tokens (June 2026 rates)
        let rate: (input: Double, output: Double)
        
        switch provider {
        case .openai:
            if model.contains("gpt-5.5") {
                rate = (5.00, 30.00)
            } else if model.contains("gpt-5.4-mini") {
                rate = (0.75, 4.50)
            } else if model.contains("gpt-5.4-nano") {
                rate = (0.25, 1.50)
            } else if model.contains("gpt-5.4") {
                rate = (2.50, 15.00)
            } else if model.contains("gpt-4o-mini") || model.contains("o1-mini") || model.contains("o3-mini") || model.contains("o4-mini") {
                rate = (0.15, 0.60)
            } else if model.contains("gpt-4o") {
                rate = (2.50, 10.00)
            } else {
                rate = (5.00, 15.00)
            }
        case .anthropic:
            if model.contains("haiku") {
                rate = (0.25, 1.25)
            } else if model.contains("opus") {
                rate = (3.00, 15.00)
            } else {
                rate = (3.00, 15.00)
            }
        case .gemini:
            if model.contains("3.5") || model.contains("3.1") {
                rate = (0.075, 0.30)
            } else if model.contains("2.5") {
                rate = (0.05, 0.20)
            } else {
                rate = (0.075, 0.30)
            }
        case .deepseek:
            if model.contains("v4-pro") {
                rate = (1.30, 2.60)
            } else if model.contains("v4-flash") {
                rate = (0.10, 0.20)
            } else {
                rate = (0.27, 1.10)
            }
        case .mistral:
            if model.contains("medium-3.5") {
                rate = (2.00, 6.00)
            } else if model.contains("small-4") {
                rate = (0.20, 0.60)
            } else {
                rate = (2.00, 6.00)
            }
        case .cohere:
            if model.contains("command-a-plus") {
                rate = (0.50, 1.50)
            } else if model.contains("command-a") {
                rate = (0.50, 1.50)
            } else {
                rate = (0.50, 1.50)
            }
        case .xai:
            if model.contains("grok-4.3") {
                rate = (1.25, 2.50)
            } else if model.contains("grok-build") {
                rate = (1.00, 2.00)
            } else {
                rate = (3.00, 15.00)
            }
        case .perplexity:
            rate = (1.00, 1.00)
        case .together:
            rate = (0.90, 0.90)
        case .groq:
            rate = (0.60, 0.80)
        case .deepinfra:
            rate = (0.35, 0.40)
        case .fireworks:
            rate = (0.20, 0.30)
        case .bedrock:
            if model.contains("haiku") {
                rate = (0.25, 1.25)
            } else {
                rate = (3.00, 15.00)
            }
        case .azure:
            if model.contains("gpt-5.5") {
                rate = (5.00, 30.00)
            } else if model.contains("gpt-5.4-mini") {
                rate = (0.75, 4.50)
            } else if model.contains("gpt-5.4-nano") {
                rate = (0.25, 1.50)
            } else if model.contains("gpt-5.4") {
                rate = (2.50, 15.00)
            } else {
                rate = (5.00, 15.00)
            }
        case .huggingface:
            rate = (0.20, 0.50)
        case .nvidia:
            if model.contains("ultra") {
                rate = (0.50, 2.50)
            } else if model.contains("super") {
                rate = (0.10, 0.50)
            } else if model.contains("nano") {
                rate = (0.20, 0.80)
            } else {
                rate = (0.50, 0.60)
            }
        case .cerebras:
            rate = (0.60, 0.60)
        case .novita:
            rate = (0.35, 0.40)
        case .openrouter:
            if model.contains("haiku") {
                rate = (0.25, 1.25)
            } else if model.contains("sonnet") || model.contains("opus") {
                rate = (3.00, 15.00)
            } else if model.contains("gpt-5.5") {
                rate = (5.00, 30.00)
            } else if model.contains("gpt-5.4-mini") {
                rate = (0.75, 4.50)
            } else if model.contains("gpt-5.4-nano") {
                rate = (0.25, 1.50)
            } else if model.contains("gpt-5.4") {
                rate = (2.50, 15.00)
            } else if model.contains("grok-4.3") {
                rate = (1.25, 2.50)
            } else {
                rate = (2.50, 10.00)
            }
        case .ollama, .lmstudio:
            rate = (0.0, 0.0)
        case .custom:
            rate = (1.00, 3.00)
        }
        
        let inputCost = (Double(input) / 1_000_000.0) * rate.input
        let outputCost = (Double(output) / 1_000_000.0) * rate.output
        return inputCost + outputCost
    }
}
