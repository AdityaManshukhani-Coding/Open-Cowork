import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var useCustomModel: Bool = false
    @State private var customModel: String = ""
    @State private var selectedCatalogModel: String = ""
    @State private var keyStatus: APIKeyStatus = .empty
    @State private var selectedProvider: LLMProvider = .openai
    @State private var hasInitializedProvider: Bool = false
    
    // MARK: - Vision Model Helpers
    
    private var effectiveModel: String {
        let provider = appStore.llmConfig.provider
        if provider == .ollama || provider == .lmstudio {
            return appStore.llmConfig.modelName.isEmpty ? provider.defaultModel : appStore.llmConfig.modelName
        } else if useCustomModel {
            return customModel.isEmpty ? provider.defaultModel : customModel
        } else if selectedCatalogModel.isEmpty || selectedCatalogModel == "__custom__" {
            return provider.defaultModel
        } else {
            return selectedCatalogModel
        }
    }
    
    private var showNonVisionWarning: Bool {
        let provider = appStore.llmConfig.provider
        return !provider.visionModels.isEmpty && !provider.visionModels.contains(effectiveModel)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: LLM Configuration
                settingsSection(title: "LLM Provider Settings") {
                    VStack(alignment: .leading, spacing: 14) {
                        // Provider Selector
                        HStack {
                            Text("Provider")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Menu {
                                ForEach(LLMProvider.allCases) { provider in
                                    Button(action: {
                                        selectedProvider = provider
                                        guard hasInitializedProvider else { return }
                                        let newConfig = LLMConfig(
                                            provider: provider,
                                            apiKey: "",
                                            baseURL: provider.defaultBaseURL,
                                            modelName: provider.defaultModel,
                                            temperature: appStore.llmConfig.temperature
                                        )
                                        appStore.llmConfig = newConfig
                                        appStore.saveConfig()
                                        selectedCatalogModel = ""
                                        useCustomModel = false
                                        customModel = ""
                                        validateKey()
                                    }) {
                                        HStack(spacing: 6) {
                                            ProviderIcon(imageName: providerImageName(for: provider), size: 14)
                                            Text(provider.rawValue)
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
                                    ProviderIcon(imageName: providerImageName(for: selectedProvider), size: 14)
                                    Text(selectedProvider.rawValue)
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 220)
                        }
                        
                        Divider().opacity(0.5)
                        
                        // API Key
                        if appStore.llmConfig.provider.requiresAPIKey {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Key")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    SecureField("Keys start with '\(appStore.llmConfig.provider.rawValue.lowercased())-'", text: $appStore.llmConfig.apiKey)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onChange(of: appStore.llmConfig.apiKey) { _ in
                                            appStore.saveConfig()
                                            validateKey()
                                        }
                                    
                                    keyStatusBadge
                                }
                                
                                Text(appStore.llmConfig.provider.apiKeyHint)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if case .invalid(let reason) = keyStatus {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("No API key required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Base URL
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Base URL")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if appStore.llmConfig.provider == .custom {
                                    Text("(Required)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                            TextField("Base URL", text: $appStore.llmConfig.baseURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: appStore.llmConfig.baseURL) { _ in appStore.saveConfig() }
                            
                            if appStore.llmConfig.provider == .custom {
                                Text("Enter the OpenAI-compatible endpoint URL (e.g. https://api.example.com/v1).")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        Divider().opacity(0.5)
                        
                        // Model Picker or Text Field
                        let provider = appStore.llmConfig.provider
                        let models = provider.availableModels
                        
                        if provider == .ollama || provider == .lmstudio {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model Name")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Model Name", text: $appStore.llmConfig.modelName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: appStore.llmConfig.modelName) { _ in appStore.saveConfig() }
                                
                                Text("Popular models: \(models.prefix(5).joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else if !models.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Model")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Our recommended models →") {
                                        // docs
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                }
                                
                                Menu {
                                    ForEach(models, id: \.self) { model in
                                        Button(action: {
                                            selectedCatalogModel = model
                                            useCustomModel = false
                                            appStore.llmConfig.modelName = model
                                            appStore.saveConfig()
                                        }) {
                                            HStack(spacing: 6) {
                                                ProviderIcon(imageName: modelImageName(for: model, provider: provider), size: 12)
                                                Text(model)
                                                Spacer()
                                                if provider.visionModels.contains(model) {
                                                    Text("👁")
                                                        .font(.system(size: 10))
                                                }
                                                if selectedCatalogModel == model && !useCustomModel {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button(action: {
                                        selectedCatalogModel = "__custom__"
                                        useCustomModel = true
                                        customModel = appStore.llmConfig.modelName
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "gearshape.fill")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 12, height: 12)
                                                .foregroundColor(.secondary)
                                            Text("Custom model...")
                                            Spacer()
                                            if useCustomModel {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        let displayModel = effectiveModel
                                        ProviderIcon(imageName: modelImageName(for: displayModel, provider: provider), size: 12)
                                        Text(useCustomModel ? (customModel.isEmpty ? "Custom model" : "Custom: \(customModel)") : displayModel)
                                            .font(.body)
                                            .lineLimit(1)
                                        if provider.visionModels.contains(displayModel) {
                                            Text("👁")
                                                .font(.system(size: 10))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .menuStyle(.borderlessButton)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if showNonVisionWarning {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 11))
                                        Text("This model may not support image input. Open Cowork sends screenshots — a vision-capable model (👁) is strongly recommended.")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(6)
                                    .background(Color.orange.opacity(0.08))
                                    .cornerRadius(4)
                                }
                                
                                if useCustomModel {
                                    TextField("Custom Model Name", text: $customModel)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onChange(of: customModel) { _ in
                                            appStore.llmConfig.modelName = customModel
                                            appStore.saveConfig()
                                        }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model Name")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Model Name", text: $appStore.llmConfig.modelName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: appStore.llmConfig.modelName) { _ in appStore.saveConfig() }
                            }
                        }
                        
                    }
                }
                
                // Section 2: Safety & Budget
                settingsSection(title: "Safety & Cost Controls") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Safety Mode")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $appStore.safetyMode) {
                                ForEach(SafetyMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                            .onChange(of: appStore.safetyMode) { _ in appStore.saveConfig() }
                        }
                        
                        Text(appStore.safetyMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Monthly Spending Limit Toggle
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Monthly Spending Limit")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Toggle("Monthly Spending Limit", isOn: $appStore.budgetEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .onChange(of: appStore.budgetEnabled) { _ in appStore.saveConfig() }
                            }
                            
                            HStack {
                                Text("Limit ($)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                TextField("", value: $appStore.budgetLimit, formatter: NumberFormatter.currencyFormatter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: appStore.budgetLimit) { _ in appStore.saveConfig() }
                            }
                            .opacity(appStore.budgetEnabled ? 1.0 : 0.4)
                            .disabled(!appStore.budgetEnabled)
                            
                            HStack {
                                Text("Estimated Spend This Month")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("$\(appStore.spentThisMonth, specifier: "%.4f")")
                                    .foregroundColor(.primary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .opacity(appStore.budgetEnabled ? 1.0 : 0.4)
                            .disabled(!appStore.budgetEnabled)
                            
                            HStack {
                                Spacer()
                                Button("Reset Monthly Cost") {
                                    appStore.spentThisMonth = 0.0
                                    appStore.saveConfig()
                                }
                                .buttonStyle(.bordered)
                            }
                            .opacity(appStore.budgetEnabled ? 1.0 : 0.4)
                            .disabled(!appStore.budgetEnabled)
                        }
                    }
                }
                
                // Section 3: Allowed Applications
                settingsSection(title: "Application Allowlist") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Enable Application Allowlist")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("Enable Application Allowlist", isOn: $appStore.allowlistEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: appStore.allowlistEnabled) { _ in appStore.saveConfig() }
                        }
                        
                        Text("The agent will only interact with applications listed here. Actions targeting other apps will be blocked.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .opacity(appStore.allowlistEnabled ? 1.0 : 0.4)
                        
                        if !appStore.allowedApps.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(appStore.allowedApps, id: \.self) { app in
                                    HStack {
                                        Text(app)
                                            .opacity(appStore.allowlistEnabled ? 1.0 : 0.4)
                                        Spacer()
                                        Button(action: {
                                            if let index = appStore.allowedApps.firstIndex(of: app) {
                                                appStore.allowedApps.remove(at: index)
                                                appStore.saveConfig()
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                    
                                    if app != appStore.allowedApps.last {
                                        Divider()
                                    }
                                }
                            }
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .frame(maxHeight: 180)
                            .opacity(appStore.allowlistEnabled ? 1.0 : 0.4)
                            .disabled(!appStore.allowlistEnabled)
                        }
                        
                        Button("Add from Applications…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            if panel.runModal() == .OK {
                                for url in panel.urls {
                                    guard url.pathExtension == "app" else { continue }
                                    let appName = url.deletingPathExtension().lastPathComponent
                                    if !appName.isEmpty && !appStore.allowedApps.contains(appName) {
                                        appStore.allowedApps.append(appName)
                                    }
                                }
                                appStore.saveConfig()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .opacity(appStore.allowlistEnabled ? 1.0 : 0.4)
                        .disabled(!appStore.allowlistEnabled)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            selectedProvider = appStore.llmConfig.provider
            restoreModelState()
            validateKey()
            hasInitializedProvider = true
        }
    }
    
    // MARK: - Helper Layouts
    
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(alignment: .leading) {
                content()
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.35))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Key Validation
    
    private func validateKey() {
        keyStatus = appStore.llmConfig.provider.validateAPIKey(appStore.llmConfig.apiKey)
    }
    
    @ViewBuilder
    private var keyStatusBadge: some View {
        switch keyStatus {
        case .empty:
            EmptyView()
        case .valid:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        case .invalid:
            HStack(spacing: 2) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Model State Restoration
    
    private func restoreModelState() {
        let provider = appStore.llmConfig.provider
        let models = provider.availableModels
        let currentModel = appStore.llmConfig.modelName
        
        if models.contains(currentModel) {
            selectedCatalogModel = currentModel
            useCustomModel = false
        } else if !currentModel.isEmpty && currentModel != provider.defaultModel {
            selectedCatalogModel = "__custom__"
            customModel = currentModel
            useCustomModel = true
        } else {
            selectedCatalogModel = ""
            useCustomModel = false
        }
    }
}

extension NumberFormatter {
    static var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
