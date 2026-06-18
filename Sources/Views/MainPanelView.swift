import SwiftUI
import AppKit

public enum OnboardingStep {
    case welcome
    case permissions
    case llmSetup
    case main
}

public struct MainPanelView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var agentStore: AgentStore
    
    enum Tab: Hashable {
        case chat
        case search
        case schedules
        case settings
        case team(String)
        case project(String)
        case conversation(UUID)
    }
    
    @State private var selectedTab: Tab = .chat
    @State private var onboardingStep: OnboardingStep = .welcome
    
    // selectedTeamName tracks which team tab is active (if any)
    private var selectedTeamName: String? {
        if case .team(let name) = selectedTab { return name }
        return nil
    }
    
    private let onboardingSize = NSSize(width: 420, height: 580)
    private let mainSize = NSSize(width: 1100, height: 700)
    
    private var currentSize: NSSize {
        onboardingStep == .main ? mainSize : onboardingSize
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if onboardingStep != .main {
                Color.clear.frame(height: 28)
            }
            
            switch onboardingStep {
            case .welcome:
                WelcomeView { transitionTo(.permissions) }
            case .permissions:
                OnboardingView(onContinue: { transitionTo(.llmSetup) })
            case .llmSetup:
                LLMSelectionView { transitionTo(.main) }
            case .main:
                mainAppView
            }
        }
        .preferredColorScheme(.light)
        .frame(
            minWidth: currentSize.width,
            maxWidth: currentSize.width,
            minHeight: currentSize.height,
            maxHeight: currentSize.height
        )
        .background(
            onboardingStep == .main ? Color(NSColor.windowBackgroundColor) : Color.white
        )
    }
    
    private func transitionTo(_ step: OnboardingStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            onboardingStep = step
        }
        let newSize = (step == .main) ? mainSize : onboardingSize
        resizeWindow(to: newSize)
    }
    
    private func resizeWindow(to newSize: NSSize) {
        guard let window = NSApp.windows.first(where: { $0.delegate is StatusItemController }) else { return }
        let currentFrame = window.frame
        let deltaY = currentFrame.size.height - newSize.height
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + deltaY,
            width: newSize.width,
            height: newSize.height
        )
        window.minSize = newSize
        window.setFrame(newFrame, display: true, animate: false)
    }
    
    private func selectTab(_ tab: Tab) {
        selectedTab = tab
        
        // Handle side effects of tab selection
        switch tab {
        case .chat:
            appStore.activeSession = nil
        case .conversation(let id):
            if let session = appStore.sessions.first(where: { $0.id == id }) {
                appStore.activeSession = session
            }
        default:
            break
        }
    }
    
    // MARK: - Main App View
    
    private var mainAppView: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 0) {
                // Header (Logo area)
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                    
                    Text("OpenCowork")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.top, 32)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Top Navigation
                        sidebarButton(title: "New Chat", tab: .chat, icon: "plus")
                        sidebarButton(title: "Search", tab: .search, icon: "magnifyingglass")
                        sidebarButton(title: "Scheduled Tasks", tab: .schedules, icon: "alarm")
                        
                        // Teams Section
                        sidebarSection(title: "Teams", onAdd: { appStore.showingCreateTeam = true }) {
                            if appStore.teams.isEmpty {
                                emptyStateText("No teams yet")
                            } else {
                                ForEach(appStore.teams) { team in
                                    sidebarItem(title: team.name, tab: .team(team.name), icon: "person.2")
                                }
                            }
                        }
                        
                        // Projects Section
                        sidebarSection(title: "Projects", onAdd: { selectProjectFolder() }) {
                            if appStore.projects.isEmpty {
                                emptyStateText("No projects yet")
                            } else {
                                ForEach(appStore.projects, id: \.self) { project in
                                    sidebarItem(title: project.lastPathComponent, tab: .project(project.path), icon: "folder")
                                }
                            }
                        }
                        
                        // Conversations Section
                        sidebarSection(title: "Conversations", hideIcon: true, onAdd: { selectTab(.chat) }) {
                            if appStore.sessions.isEmpty {
                                emptyStateText("No conversations yet")
                            } else {
                                ForEach(appStore.sessions, id: \.id) { session in
                                    conversationRow(session: session)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                Spacer()
                
                // Bottom Settings
                VStack(spacing: 0) {
                    sidebarItem(title: "Settings", tab: .settings, icon: "gearshape")
                        .padding(.horizontal, 8)
                        .padding(.bottom, 16)
                }
            }
            .frame(width: 260)
            .background(Color.white)
            
            Divider()
                .background(Color.gray.opacity(0.1))
            
            // Content Pane
            Group {
                switch selectedTab {
                case .chat, .conversation, .project:
                    ChatView()
                case .team(let name):
                    ChatView(selectedTeamName: name)
                case .search:
                    SearchChatsView(selectedTab: $selectedTab)
                case .schedules:
                    SchedulerView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.98))
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $appStore.showingCreateTeam) {
            CreateTeamView()
        }
    }
    
    // MARK: - Handlers
    
    private func selectProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !appStore.projects.contains(url) {
                appStore.projects.append(url)
            }
            appStore.activeProject = url
            appStore.saveConfig()
        }
    }
    
    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func sidebarButton(title: String, tab: Tab, icon: String) -> some View {
        Button(action: {
            selectTab(tab)
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedTab == tab ? Color.gray.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, hideIcon: Bool = false, onAdd: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 6)
            
            content()
        }
    }
    
    @ViewBuilder
    private func sidebarItem(title: String, tab: Tab, icon: String, iconSize: CGFloat = 14) -> some View {
        Button(action: {
            selectTab(tab)
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .frame(width: 16)
                    .foregroundColor(hideIconForConversations(icon: icon) ? .secondary.opacity(0.5) : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedTab == tab ? Color.gray.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func conversationRow(session: TaskSession) -> some View {
        ConversationRowView(
            session: session,
            isSelected: selectedTab == Tab.conversation(session.id),
            onSelect: { selectTab(Tab.conversation(session.id)) },
            onDelete: {
                appStore.deleteSession(id: session.id)
                if selectedTab == Tab.conversation(session.id) {
                    selectTab(.chat)
                }
            },
            onTogglePin: {
                appStore.togglePinSession(id: session.id)
            }
        )
    }
    
    private func hideIconForConversations(icon: String) -> Bool {
        return icon == "circle.fill"
    }
}

// MARK: - Conversation Row (sub-view so @State works correctly)

struct ConversationRowView: View {
    @EnvironmentObject var appStore: AppStore
    
    let session: TaskSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: session.isPinned ? "pin.fill" : "circle.fill")
                        .font(.system(size: session.isPinned ? 10 : 4, weight: .regular))
                        .frame(width: 16)
                        .foregroundColor(session.isPinned ? .orange : .secondary.opacity(0.5))
                    Text(session.title)
                        .font(.system(size: 13, weight: session.isPinned ? .semibold : .regular))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Pin / Delete actions
            HStack(spacing: 4) {
                Button(action: onTogglePin) {
                    Image(systemName: session.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } message: {
                    Text("Are you sure you want to delete \"\(session.title)\"? This cannot be undone.")
                }
            }
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.gray.opacity(0.1) : Color.clear)
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
