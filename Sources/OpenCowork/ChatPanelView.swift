import SwiftUI

/// The floating chat panel — the primary user interface for interacting with
/// the Open Cowork agent.  Uses UltraThinMaterial for a translucent glass-like
/// appearance on macOS 14+.  Liquid Glass APIs (macOS 26+) will be adopted
/// in a future update when the SDK is available.
struct ChatPanelView: View {
    /// Shared application state.
    @Bindable var appState: AppState

    /// The text currently being composed by the user.
    @State private var inputText: String = ""

    /// The scroll view proxy for auto-scrolling to the latest message.
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────
            headerView

            Divider()
                .opacity(0.3)

            // ── Message List ───────────────────────────────────────
            messageListView

            Divider()
                .opacity(0.3)

            // ── Input Bar ──────────────────────────────────────────
            inputBarView
        }
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        }
        .onAppear {
            NSApp.windows.first { $0.identifier?.rawValue == "chat-panel" }?
                .identifier = NSUserInterfaceItemIdentifier("chat-panel")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Open Cowork")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // Safety mode indicator
            safetyModeBadge

            // Emergency stop button
            Button {
                appState.triggerEmergencyStop()
            } label: {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Emergency Stop")
            .disabled(!appState.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Safety Mode Badge

    private var safetyModeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: safetyModeIcon)
                .font(.caption2)
            Text(appState.safetyMode.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var safetyModeIcon: String {
        switch appState.safetyMode {
        case .fullAuto: return "bolt.fill"
        case .approveBeforeAction: return "hand.raised.fill"
        case .stepThrough: return "forward.frame.fill"
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if appState.messages.isEmpty {
                        emptyStateView
                    }

                    ForEach(appState.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: appState.messages.count) { _, _ in
                if let last = appState.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Open Cowork")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Describe a task below and the agent will\ncontrol your Mac to complete it.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input Bar

    private var inputBarView: some View {
        HStack(spacing: 8) {
            TextField(
                appState.isRunning ? "Agent is working…" : "Describe a task…",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .onSubmit {
                submitTask()
            }
            .disabled(appState.isRunning)

            if appState.isRunning {
                // Stop button
                Button {
                    appState.stopAgent()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Stop Agent")
            } else {
                // Send button
                Button {
                    submitTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send Task")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func submitTask() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appState.currentTask = trimmed
        inputText = ""
        appState.startAgent()
    }
}

// MARK: - Message Bubble

/// A single chat message bubble with role-appropriate styling.
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Role icon
            Image(systemName: roleIcon)
                .font(.caption)
                .foregroundStyle(roleColor)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(roleColor)

                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 40)
        }
    }

    private var roleIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "info.circle.fill"
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Open Cowork"
        case .system: return "System"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return .green
        case .system: return .secondary
        }
    }
}

// MARK: - Settings View

/// The settings window for configuring providers, API keys, safety, and budget.
struct SettingsView: View {
    @Bindable var appState: AppState

    /// Local state for the "add app" text field in the safety tab.
    @State private var newBundleID: String = ""

    var body: some View {
        TabView {
            providerSettingsTab
                .tabItem {
                    Label("Provider", systemImage: "cpu")
                }

            safetySettingsTab
                .tabItem {
                    Label("Safety", systemImage: "shield")
                }

            budgetSettingsTab
                .tabItem {
                    Label("Budget", systemImage: "dollarsign.circle")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
    }

    // MARK: - Provider Tab

    private var providerSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $appState.selectedProvider) {
                    ForEach(ProviderKind.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                if appState.selectedProvider != .ollama && appState.selectedProvider != .lmStudio {
                    SecureField("API Key", text: $appState.apiKey)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model Name", text: $appState.modelName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL Override (optional)", text: $appState.baseURLOverride)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("AI Provider Configuration")
            }

            Section {
                Toggle("Use Local Model (Ollama / LM Studio)", isOn: $appState.useLocalModel)

                if appState.useLocalModel {
                    TextField("Local Endpoint URL", text: $appState.localModelURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("Local Model Name", text: $appState.localModelName)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Local Model")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Safety Tab

    private var safetySettingsTab: some View {
        Form {
            Section {
                Picker("Safety Mode", selection: $appState.safetyMode) {
                    ForEach(SafetyMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                VStack(alignment: .leading, spacing: 4) {
                    Text(safetyModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Control Mode")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed Applications")
                        .font(.subheadline)

                    ForEach(Array(appState.allowedApps).sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(appName(for: bundleID))
                                .font(.caption)
                            Spacer()
                            Button {
                                appState.allowedApps.remove(bundleID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("Bundle ID (e.g. com.apple.Safari)", text: $newBundleID)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Button("Add") {
                            addBundleID()
                        }
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } header: {
                Text("App Allowlist")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Budget Tab

    private var budgetSettingsTab: some View {
        Form {
            Section {
                HStack {
                    Text("Budget Limit")
                    TextField("0.00", value: $appState.budgetLimit, format: .currency(code: "USD"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("USD")
                        .foregroundStyle(.secondary)
                }

                Toggle("Pause agent when budget exceeded", isOn: $appState.pauseOnBudgetExceeded)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set to 0 for unlimited budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Spending Limits")
            }

            Section {
                HStack {
                    Text("Session Cost")
                    Spacer()
                    Text(appState.currentCost, format: .currency(code: "USD"))
                        .monospacedDigit()
                }

                HStack {
                    Text("Total Tokens")
                    Spacer()
                    Text("\(appState.totalTokens)")
                        .monospacedDigit()
                }
            } header: {
                Text("Current Session")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.quaternary)

            Text("Open Cowork")
                .font(.title)
                .fontWeight(.bold)

            Text("v0.1 — Foundation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A free, open-source, bring-your-own-key AI agent\nthat physically controls your Mac.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            Link("GitHub Repository", destination: URL(string: "https://github.com/opencowork/opencowork")!)
                .font(.caption)

            Text("Licensed under Apache 2.0")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(40)
    }

    // MARK: - Helpers

    private var safetyModeDescription: String {
        switch appState.safetyMode {
        case .fullAuto:
            return "The agent executes all actions automatically without asking for approval."
        case .approveBeforeAction:
            return "The agent pauses before each action and waits for your approval."
        case .stepThrough:
            return "The agent executes one action at a time and waits for you to confirm each step."
        }
    }

    private func appName(for bundleID: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// Adds the entered bundle ID to the allowlist and clears the input field.
    private func addBundleID() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.allowedApps.insert(trimmed)
        newBundleID = ""
    }
}

// MARK: - Visual Effect Fallback

/// NSViewRepresentable wrapper for NSVisualEffectView — provides the
/// translucent glass-like background for all panels.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
