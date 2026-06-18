import SwiftUI

public struct CreateTeamView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var teamName: String = ""
    @State private var teammates: [Teammate] = []
    
    // Auto-detect local models
    @State private var localModelsCache: [LLMProvider: [String]] = [:]
    @State private var isDetectingLocalModels: [LLMProvider: Bool] = [:]
    @State private var detectionFailed: [LLMProvider: Bool] = [:]
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Team")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.white)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.1)),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // Team Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Team Name")
                            .font(.system(size: 13, weight: .medium))
                        
                        TextField("e.g. Frontend Development Team", text: $teamName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    // Teammates List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Teammates")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button(action: addTeammate) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12))
                                    Text("Add Teammate")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if teammates.isEmpty {
                            Text("No teammates added yet.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach($teammates) { $teammate in
                                teammateRow(teammate: $teammate)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(white: 0.98))
            
            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                
                Button(action: saveTeam) {
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)
                        .background(teamName.isEmpty || teammates.isEmpty ? Color.blue.opacity(0.5) : Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(teamName.isEmpty || teammates.isEmpty)
            }
            .padding()
            .background(Color.white)
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.1)),
                alignment: .top
            )
        }
        .frame(width: 500, height: 600)
        .onAppear {
            detectLocalModels(for: .ollama)
            detectLocalModels(for: .lmstudio)
        }
    }
    
    private func addTeammate() {
        teammates.append(Teammate(
            name: "Agent \(teammates.count + 1)",
            systemPrompt: "You are an AI assistant...",
            provider: nil, // Default to "Current"
            modelName: appStore.llmConfig.modelName,
            apiKey: ""
        ))
    }
    
    private func saveTeam() {
        let team = Team(name: teamName, teammates: teammates)
        appStore.teams.append(team)
        appStore.saveConfig()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func detectLocalModels(for provider: LLMProvider) {
        guard provider == .ollama || provider == .lmstudio else { return }
        
        guard isDetectingLocalModels[provider] != true else { return }
        
        isDetectingLocalModels[provider] = true
        detectionFailed[provider] = false
        
        let urlString: String
        if provider == .ollama {
            urlString = "http://localhost:11434/api/tags"
        } else {
            urlString = "http://localhost:1234/v1/models"
        }
        
        guard let url = URL(string: urlString) else {
            isDetectingLocalModels[provider] = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0 // Short timeout so UI doesn't hang long if offline
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isDetectingLocalModels[provider] = false
                
                guard let data = data, error == nil else {
                    self.detectionFailed[provider] = true
                    return
                }
                
                do {
                    var modelNames: [String] = []
                    if provider == .ollama {
                        struct OllamaResponse: Decodable {
                            struct OllamaModel: Decodable {
                                let name: String
                            }
                            let models: [OllamaModel]?
                        }
                        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
                        modelNames = decoded.models?.map { $0.name } ?? []
                    } else {
                        struct LMStudioResponse: Decodable {
                            struct LMStudioModel: Decodable {
                                let id: String
                            }
                            let data: [LMStudioModel]?
                        }
                        let decoded = try JSONDecoder().decode(LMStudioResponse.self, from: data)
                        modelNames = decoded.data?.map { $0.id } ?? []
                    }
                    
                    if modelNames.isEmpty {
                        self.detectionFailed[provider] = true
                    } else {
                        self.localModelsCache[provider] = modelNames
                        self.detectionFailed[provider] = false
                    }
                } catch {
                    print("Failed to decode local models for \(provider.rawValue): \(error)")
                    self.detectionFailed[provider] = true
                }
            }
        }.resume()
    }
    
    private func teammateRow(teammate: Binding<Teammate>) -> some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Name", text: teammate.name)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Button(action: {
                    if let idx = teammates.firstIndex(where: { $0.id == teammate.id }) {
                        teammates.remove(at: idx)
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Text("Provider:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("", selection: teammate.provider) {
                    Text("Current (Use OpenCowork config)").tag(nil as LLMProvider?)
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider as LLMProvider?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)
                .onChange(of: teammate.wrappedValue.provider) { newProvider in
                    let resolved = newProvider ?? appStore.llmConfig.provider
                    teammate.wrappedValue.modelName = resolved.defaultModel
                    if resolved == .ollama || resolved == .lmstudio {
                        detectLocalModels(for: resolved)
                    }
                }
                
                Spacer()
            }
            
            // API Key (Only for cloud providers, not shown for local or "Current")
            if let selectedProvider = teammate.wrappedValue.provider, selectedProvider.requiresAPIKey {
                HStack(spacing: 8) {
                    Text("API Key:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    
                    SecureField("Enter API key", text: teammate.apiKey)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                }
            }
            
            // Model Selector / Detection
            let effectiveProvider = teammate.wrappedValue.provider ?? appStore.llmConfig.provider
            
            if effectiveProvider == .ollama || effectiveProvider == .lmstudio {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Model:")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        if isDetectingLocalModels[effectiveProvider] == true {
                            ProgressView()
                                .controlSize(.small)
                            Text("Detecting local models...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            if let models = localModelsCache[effectiveProvider], !models.isEmpty {
                                Picker("", selection: teammate.modelName) {
                                    // Make sure current value is represented if it's custom / custom typed
                                    if !models.contains(teammate.wrappedValue.modelName) && !teammate.wrappedValue.modelName.isEmpty {
                                        Text(teammate.wrappedValue.modelName).tag(teammate.wrappedValue.modelName)
                                    }
                                    
                                    ForEach(models, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                    
                                    Text("Custom model ID...").tag("")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                                
                                Button(action: { detectLocalModels(for: effectiveProvider) }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { detectLocalModels(for: effectiveProvider) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Retry Detection")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    let modelsList = localModelsCache[effectiveProvider] ?? []
                    let showManualField = modelsList.isEmpty || 
                                           teammate.wrappedValue.modelName.isEmpty || 
                                           !modelsList.contains(teammate.wrappedValue.modelName)
                    
                    if showManualField {
                        HStack {
                            TextField("Enter local model ID (e.g. llama3.2)", text: teammate.modelName)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .background(Color.white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                        .padding(.leading, 50)
                        
                        Text(effectiveProvider == .ollama ? "Ollama running at http://localhost:11434" : "LM Studio running at http://localhost:1234")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 50)
                    }
                }
            } else {
                HStack {
                    Text("Model:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: teammate.modelName) {
                        ForEach(effectiveProvider.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)
                    
                    Spacer()
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("System Prompt")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextEditor(text: teammate.systemPrompt)
                    .font(.system(size: 13))
                    .frame(height: 80)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}
