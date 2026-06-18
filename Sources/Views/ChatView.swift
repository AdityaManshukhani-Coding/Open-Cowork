import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var agentStore: AgentStore
    @State private var taskPrompt = ""
    @State private var attachedFiles: [URL] = []
    
    var selectedTeamName: String? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            // MAIN CHAT AREA
            VStack(spacing: 0) {
                if let teamName = selectedTeamName, let team = appStore.teams.first(where: { $0.name == teamName }) {
                    HStack {
                        Spacer()
                        Text("\(team.teammates.count) Teammates")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding()
                }
                
                if let session = appStore.activeSession {
                    activeSessionView(session)
                } else {
                    idleStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // RIGHT HAND SIDEBAR (File Changes)
            if let session = appStore.activeSession, !session.steps.isEmpty {
                Divider()
                rightSidebarView(session)
            }
        }
    }
    
    // MARK: - Idle State View
    private var idleStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("Hi, what's your plan for today?")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 24)
            
            // Chat Input Pill
            chatInputPill
            
            // File manager suggestion — functional folder picker
            Button(action: selectProject) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    if let project = appStore.activeProject {
                        Text(project.lastPathComponent)
                            .foregroundColor(.primary)
                    } else {
                        Text("Work in a project")
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 12))
                .padding(.top, 8)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Active Session View
    @ViewBuilder
    private func activeSessionView(_ session: TaskSession) -> some View {
        VStack(spacing: 0) {
            // Emergency stop banner
            if session.status == .running || session.status == .waitingApproval {
                Button(action: {
                    agentStore.triggerEmergencyStop()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                        Text("EMERGENCY STOP — Cmd+Shift+Esc")
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            // Header of active task
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                Spacer()
                statusIndicator(session.status)
            }
            .padding()
            
            Divider()
            
            // Task steps list (Chat history)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if !session.steps.isEmpty {
                            SelectableTextView(attributedString: chatHistoryAttributedString(session))
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }
                    .padding()
                }
                .onChange(of: session.steps.count) { _ in
                    withAnimation {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Bottom control panel & chat input
            VStack(spacing: 8) {
                if session.status == .waitingApproval {
                    approvalControls(session)
                } else if session.status == .running {
                    runningControls(session)
                } else {
                    completedControls(session)
                }
                
                // Keep input pill visible so they can add follow-up prompts
                chatInputPill
                    .padding(.vertical, 8)
            }
            .padding(.bottom, 16)
            .background(Color.white.opacity(0.8))
        }
    }
    
    // MARK: - Right Sidebar View
    @ViewBuilder
    private func rightSidebarView(_ session: TaskSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Context & Files")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if session.allBackups.isEmpty {
                        Text("No file changes yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(session.allBackups, id: \.filePath) { backup in
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.blue)
                                Text((backup.filePath as NSString).lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Token / Cost Counter at the bottom of the sidebar
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Text("Session Cost: $\(session.costEstimate, specifier: "%.4f")")
                Text("Tokens: \(session.inputTokens) in / \(session.outputTokens) out")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding()
        }
        .frame(width: 260)
        .background(Color.white.opacity(0.5))
    }
    
    // MARK: - Components
    
    private var chatInputPill: some View {
        VStack(spacing: 8) {
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(attachedFiles, id: \.self) { url in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text(url.lastPathComponent)
                                Button(action: {
                                    if let idx = attachedFiles.firstIndex(of: url) {
                                        attachedFiles.remove(at: idx)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            
            TextField("Open Cowork — Send a message, upload files, open a folder, or create a scheduled task...", text: $taskPrompt)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .frame(minHeight: 40)
                .onSubmit { submitTask() }
            
            HStack {
                Button(action: selectFiles) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Model selector — shows all models from the connected provider
                Menu {
                    ForEach(appStore.llmConfig.provider.availableModels, id: \.self) { model in
                        Button(action: {
                            appStore.llmConfig.modelName = model
                            appStore.saveConfig()
                        }) {
                            HStack(spacing: 6) {
                                ProviderIcon(imageName: modelImageName(for: model, provider: appStore.llmConfig.provider), size: 12)
                                Text(model)
                                if appStore.llmConfig.provider.visionModels.contains(model) {
                                    Text("👁")
                                        .font(.system(size: 10))
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        let labelModel = appStore.llmConfig.modelName.isEmpty ? appStore.llmConfig.provider.defaultModel : appStore.llmConfig.modelName
                        ProviderIcon(imageName: modelImageName(for: labelModel, provider: appStore.llmConfig.provider), size: 12)
                        Text(appStore.llmConfig.modelName.isEmpty
                             ? appStore.llmConfig.provider.displayName
                             : appStore.llmConfig.modelName)
                            .font(.system(size: 13))
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Permission selector — all safety modes
                Menu {
                    ForEach(SafetyMode.allCases) { mode in
                        Button(mode.displayName) {
                            appStore.safetyMode = mode
                            appStore.saveConfig()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(appStore.safetyMode.displayName)
                            .font(.system(size: 13))
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Button(action: { submitTask() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(taskPrompt.isEmpty ? Color.gray.opacity(0.3) : Color(NSColor.systemIndigo))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(taskPrompt.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 40)
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
    }
    
    private func suggestionButton(icon: String, text: String) -> some View {
        Button(action: {
            taskPrompt = text
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(text)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
    
    private func submitTask() {
        let promptText = taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptText.isEmpty {
            var fullPrompt = promptText
            if !attachedFiles.isEmpty {
                let fileList = attachedFiles.map { $0.path }.joined(separator: "\n")
                fullPrompt += "\n\nAttached Files:\n\(fileList)"
            }
            agentStore.startTask(fullPrompt)
            taskPrompt = ""
            attachedFiles.removeAll()
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !attachedFiles.contains(url) {
                    attachedFiles.append(url)
                }
            }
        }
    }
    
    private func selectProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Folder"
        if panel.runModal() == .OK, let url = panel.url {
            if !appStore.projects.contains(url) {
                appStore.projects.append(url)
            }
            appStore.activeProject = url
            appStore.saveConfig()
        }
    }
    
    // MARK: - Session Controls
    
    private func approvalControls(_ session: TaskSession) -> some View {
        let isPostStepConfirmation = appStore.safetyMode == .stepThrough && session.steps.last?.status == .completed
        return HStack(spacing: 16) {
            Text(isPostStepConfirmation ? "Step completed. Continue?" : "Review the action above.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { agentStore.rejectActiveStep() }) {
                Text(isPostStepConfirmation ? "Stop Here" : "Deny")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            
            Button(action: { agentStore.approveActiveStep() }) {
                Text(isPostStepConfirmation ? "Continue" : "Approve")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal)
    }
    
    private func runningControls(_ session: TaskSession) -> some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
                .padding(.trailing, 8)
            Text(session.steps.last?.actionDescription ?? "Agent is executing...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Stop") { agentStore.stopTask() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .padding(.horizontal)
    }
    
    private func completedControls(_ session: TaskSession) -> some View {
        HStack(spacing: 12) {
            Button("Reset Session") { appStore.activeSession = nil }
                .buttonStyle(.bordered)
            
            if !session.allBackups.isEmpty {
                Button(action: {
                    FileRollbackManager.shared.rollback(backups: session.allBackups)
                    var updated = session
                    for i in 0..<updated.steps.count { updated.steps[i].backups = [] }
                    appStore.updateActiveSession(updated)
                }) {
                    Text("Undo File Changes")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            
            if session.status == .paused {
                Button("Resume Task") { agentStore.startTask(session.title) }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Chat History Attributed String
    private func chatHistoryAttributedString(_ session: TaskSession) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        for (index, step) in session.steps.enumerated() {
            // Step header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let statusSymbol = stepStatusSymbol(step.status)
            let header = NSAttributedString(string: "\(statusSymbol) Step \(index + 1) · \(step.timestamp.formatted(date: .omitted, time: .shortened))\n", attributes: headerAttrs)
            result.append(header)
            
            // Thought
            if !step.thought.isEmpty {
                let thoughtAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: NSColor.textColor
                ]
                let thought = NSAttributedString(string: step.thought + "\n", attributes: thoughtAttrs)
                result.append(thought)
            }
            
            // Action
            if !step.actionDescription.isEmpty {
                let actionAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.systemBlue
                ]
                let action = NSAttributedString(string: "▶ " + step.actionDescription + "\n", attributes: actionAttrs)
                result.append(action)
            }
            
            // Error
            if let errMsg = step.errorMessage {
                let errorAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.systemRed
                ]
                let error = NSAttributedString(string: errMsg + "\n", attributes: errorAttrs)
                result.append(error)
            }
            
            // Screenshot
            if let screenshotPath = step.screenshotPath,
               let nsImage = NSImage(contentsOfFile: screenshotPath) {
                let attachment = NSTextAttachment()
                attachment.image = nsImage
                let maxWidth: CGFloat = 200
                let aspectRatio = nsImage.size.height / nsImage.size.width
                let height = min(maxWidth * aspectRatio, 140)
                attachment.bounds = NSRect(x: 0, y: 0, width: maxWidth, height: height)
                let attachmentString = NSAttributedString(attachment: attachment)
                result.append(attachmentString)
                result.append(NSAttributedString(string: "\n"))
            }
            
            // Separator between steps
            if index < session.steps.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        return result
    }
    
    private func stepStatusSymbol(_ status: StepStatus) -> String {
        switch status {
        case .pending: return "⏳"
        case .approved: return "✓"
        case .executing: return "⋯"
        case .completed: return "✓"
        case .failed: return "✗"
        case .skipped: return "⊘"
        }
    }
    
    private func statusIndicator(_ status: TaskStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .idle: text = "Idle"; color = .gray
        case .running: text = "Running"; color = .blue
        case .paused: text = "Paused"; color = .orange
        case .waitingApproval: text = "Awaiting Approval"; color = .green
        case .completed: text = "Completed"; color = .green
        case .failed(let reason): text = "Failed: \(reason)"; color = .red
        }
        return Text(text).font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(10)
    }
}
