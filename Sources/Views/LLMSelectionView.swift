import SwiftUI

struct LLMSelectionView: View {
    @EnvironmentObject var appStore: AppStore
    var onComplete: () -> Void
    
    @State private var selectedProvider: LLMProvider? = nil
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""  // "" means use default
    @State private var customModel: String = ""
    @State private var baseURL: String = ""
    @State private var showKey: Bool = false
    @State private var keyStatus: APIKeyStatus = .empty
    @State private var useCustomModel: Bool = false
    @State private var modelSearchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool
    
    // MARK: - Vision Model Helpers
    
    /// Focus the search field automatically when the view appears.
    private func focusSearchField() {
        searchFieldFocused = true
    }
    
    /// The effective model name based on current selections.
    private var effectiveModel: String {
        guard let provider = selectedProvider else { return "" }
        if provider == .ollama || provider == .lmstudio {
            return customModel.isEmpty ? provider.defaultModel : customModel
        } else if useCustomModel || provider.availableModels.isEmpty {
            return customModel.isEmpty ? provider.defaultModel : customModel
        } else if selectedModel.isEmpty || selectedModel == "__custom__" {
            return provider.defaultModel
        } else {
            return selectedModel
        }
    }
    
    /// Whether the effective model supports vision/image input.
    private var isVisionCapable: Bool {
        guard let provider = selectedProvider else { return false }
        return provider.visionModels.contains(effectiveModel)
    }
    
    /// Whether to show a warning — only when the provider has vision models available
    /// but the user selected a non-vision one (or an unverified custom model).
    private var showNonVisionWarning: Bool {
        guard let provider = selectedProvider else { return false }
        return !provider.visionModels.isEmpty && !isVisionCapable
    }
    
    /// Returns the list of models filtered by the current search query.
    private func filteredModels(for provider: LLMProvider) -> [String] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return provider.availableModels }
        return provider.availableModels.filter { model in
            model.lowercased().contains(query)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your AI Provider")
                        .font(.title2.bold())
                    
                    Text("Connect directly to your AI provider. No markup, no subscription.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Divider()
                
                // Provider picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Provider")
                        .font(.body.bold())
                        .foregroundColor(.primary)
                    
                    // Custom dropdown using Button+Menu to render images (macOS Picker can't)
                    Menu {
                        ForEach(LLMProvider.allCases) { provider in
                            Button(action: {
                                selectedProvider = provider
                                if !provider.availableModels.isEmpty {
                                    selectedModel = provider.availableModels.first ?? ""
                                } else {
                                    selectedModel = ""
                                }
                                useCustomModel = false
                                customModel = ""
                                modelSearchQuery = ""
                                apiKey = ""
                                validateKey()
                            }) {
                                HStack(spacing: 6) {
                                    ProviderIcon(imageName: providerImageName(for: provider), size: 8)
                                    Text(provider.rawValue)
                                        .font(.body)
                                    Spacer()
                                    if selectedProvider == provider {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let provider = selectedProvider {
                                ProviderIcon(imageName: providerImageName(for: provider), size: 8)
                                Text(provider.rawValue)
                                    .font(.body)
                            } else {
                                Text("Select a provider...")
                                    .font(.body)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                
                // Only show config options if a provider is selected
                if let provider = selectedProvider {
                    // API Key field (not shown for local providers)
                    if provider.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("API Key")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Spacer()
                                keyStatusBadge
                            }
                            
                            HStack(spacing: 6) {
                                Group {
                                    if showKey {
                                        TextField("Enter your API key", text: $apiKey)
                                    } else {
                                        SecureField("Enter your API key", text: $apiKey)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                                .onChange(of: apiKey) { _ in validateKey() }
                                
                                Button(action: { showKey.toggle() }) {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Key format hint
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(provider.apiKeyHint)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            // Validation message
                            if case .invalid(let reason) = keyStatus {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Text(reason)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            
                            Text("Stored locally, never leaves your machine.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        
                        // Base URL for custom provider
                        if provider == .custom {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Base URL")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                
                                TextField("https://api.example.com/v1", text: $baseURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                
                                Text("The OpenAI-compatible endpoint URL for your custom provider.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Text("Base URL is required for custom providers.")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("No API key required — running locally.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Model selection
                    if provider == .ollama || provider == .lmstudio {
                        // Local providers: always use text field (users pull arbitrary models)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            TextField("Model name", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption2)
                            
                            // Show common model suggestions
                            HStack(spacing: 6) {
                                Text("Popular:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(provider.availableModels.prefix(5), id: \.self) { model in
                                    Button(action: { customModel = model }) {
                                        HStack(spacing: 4) {
                                            ProviderIcon(imageName: modelImageName(for: model, provider: provider), size: 8)
                                            Text(model)
                                                .font(.caption)
                                            if provider.visionModels.contains(model) {
                                                Text("👁")
                                                    .font(.system(size: 10))
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            if showNonVisionWarning {
                                visionWarningView
                            }
                        }
                        .padding(.horizontal, 12)
                    } else if !provider.availableModels.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Model")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: { /* TODO: link to docs */ }) {
                                    Text("Recommended →")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Inline model picker — search + list always visible
                            let models = filteredModels(for: provider)
                            VStack(alignment: .leading, spacing: 0) {
                                // ── Embedded search field ─────────────────────────
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    TextField("Search models...", text: $modelSearchQuery)
                                        .textFieldStyle(.plain)
                                        .font(.body)
                                        .focused($searchFieldFocused)
                                    if !modelSearchQuery.isEmpty {
                                        Button(action: { modelSearchQuery = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                                )
                                .padding(.horizontal, 6)
                                .padding(.top, 6)
                                .padding(.bottom, 4)

                                Divider()
                                    .padding(.horizontal, 6)

                                // ── Filtered model list ───────────────────────────
                                if !modelSearchQuery.isEmpty && models.isEmpty {
                                    Text("No models match \"\(modelSearchQuery)\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                }

                                ScrollView {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(models, id: \.self) { model in
                                            Button(action: {
                                                selectedModel = model
                                                useCustomModel = false
                                                modelSearchQuery = ""
                                            }) {
                                                HStack(spacing: 6) {
                                                    ProviderIcon(imageName: modelImageName(for: model, provider: provider), size: 8)
                                                    Text(model)
                                                        .font(.body)
                                                    if provider.visionModels.contains(model) {
                                                        Text("👁")
                                                            .font(.system(size: 10))
                                                    }
                                                    Spacer()
                                                    if selectedModel == model && !useCustomModel {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.accentColor)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .contentShape(Rectangle())
                                                .background(
                                                    selectedModel == model && !useCustomModel
                                                    ? Color.accentColor.opacity(0.12)
                                                    : Color.clear
                                                )
                                            }
                                            .buttonStyle(.plain)

                                            if model != models.last {
                                                Divider()
                                                    .padding(.horizontal, 4)
                                            }
                                        }

                                        if !models.isEmpty {
                                            Divider()
                                        }

                                        Button(action: {
                                            useCustomModel = true
                                            selectedModel = "__custom__"
                                            customModel = ""
                                            modelSearchQuery = ""
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "gearshape.fill")
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 8, height: 8)
                                                Text("Custom model...")
                                                    .font(.body)
                                                Spacer()
                                                if useCustomModel {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .contentShape(Rectangle())
                                            .background(useCustomModel ? Color.accentColor.opacity(0.12) : Color.clear)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxHeight: 220)
                            }
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .id(provider)
                            .onAppear {
                                focusSearchField()
                            }
                            
                            // Non-vision model warning
                            if showNonVisionWarning {
                                visionWarningView
                            }
                        }
                        .padding(.horizontal, 12)
                        
                        // Custom model text field
                        if useCustomModel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom Model Name")
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                TextField("Enter model identifier", text: $customModel)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)
                                Text("Exact model ID as specified by the provider.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                    } else {
                        // For providers without a catalog (e.g., custom endpoint), show a text field
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Model")
                                .font(.body.bold())
                                .foregroundColor(.primary)
                            
                            TextField("Model name (e.g. gpt-4o)", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                            
                            Text("Enter the model name for your custom endpoint.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                
                Divider()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: saveAndContinue) {
                        HStack(spacing: 6) {
                            Text("Complete Setup")
                            Image(systemName: "checkmark")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .background(canProceed ? Color.black : Color.gray.opacity(0.4))
                    .cornerRadius(8)
                    .disabled(!canProceed)
                    
                    Button(action: onComplete) {
                        Text("Skip for now")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .onAppear {
            restoreSavedConfig()
        }
    }
    
    // MARK: - Shared Views
    
    @ViewBuilder
    private var visionWarningView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            Text("This model may not support image input. A vision-capable model (👁) is recommended.")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Key Validation
    
    private func validateKey() {
        guard let provider = selectedProvider else {
            keyStatus = .empty
            return
        }
        keyStatus = provider.validateAPIKey(apiKey)
    }
    
    private var canProceed: Bool {
        guard let provider = selectedProvider else {
            return false
        }

        // If using a custom model, the user must have typed a model name
        if useCustomModel && customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        // Custom provider requires a base URL
        if provider == .custom && baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if !provider.requiresAPIKey {
            return true
        }
        // Must have a key and it must be valid (or at least not empty for providers with no prefix)
        switch keyStatus {
        case .valid: return true
        case .empty, .invalid: return false
        }
    }
    
    @ViewBuilder
    private var keyStatusBadge: some View {
        switch keyStatus {
        case .empty:
            EmptyView()
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.primary)
                Text("Valid")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        case .invalid:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Invalid")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Save
    
    private func saveAndContinue() {
        guard let provider = selectedProvider else { return }
        
        // Determine the effective model name
        let effectiveModel: String
        if provider == .ollama || provider == .lmstudio {
            effectiveModel = customModel.isEmpty ? provider.defaultModel : customModel
        } else if useCustomModel || provider.availableModels.isEmpty {
            effectiveModel = customModel.isEmpty ? provider.defaultModel : customModel
        } else if selectedModel.isEmpty || selectedModel == "__custom__" {
            effectiveModel = provider.defaultModel
        } else {
            effectiveModel = selectedModel
        }
        
        // Use custom base URL for custom provider, otherwise use provider default
        let effectiveBaseURL = provider == .custom
            ? baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : provider.defaultBaseURL
        
        // Single assignment to avoid multiple @Published triggers
        let config = LLMConfig(
            provider: provider,
            apiKey: apiKey,
            baseURL: effectiveBaseURL,
            modelName: effectiveModel,
            temperature: appStore.llmConfig.temperature
        )
        appStore.llmConfig = config
        appStore.saveConfig()
        onComplete()
    }
    
    private func restoreSavedConfig() {
        let saved = appStore.llmConfig
        if !saved.apiKey.isEmpty || saved.provider != .openai {
            selectedProvider = saved.provider
            apiKey = saved.apiKey
            baseURL = saved.baseURL
            
            // Check if saved model is in the catalog
            let models = saved.provider.availableModels
            if models.contains(saved.modelName) {
                selectedModel = saved.modelName
                useCustomModel = false
            } else if !saved.modelName.isEmpty && saved.modelName != saved.provider.defaultModel {
                selectedModel = "__custom__"
                customModel = saved.modelName
                useCustomModel = true
            } else {
                // Use first recommended model as default
                selectedModel = models.first ?? ""
                useCustomModel = false
            }
        } else {
            selectedProvider = nil // Start with no selection
            selectedModel = ""
            apiKey = ""
            baseURL = ""
        }
        validateKey()
    }
}
