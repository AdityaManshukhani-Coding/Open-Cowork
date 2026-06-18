import Foundation
import Combine

@MainActor
public class AppStore: ObservableObject {
    @Published public var llmConfig: LLMConfig = .empty
    @Published public var safetyMode: SafetyMode = .approveBeforeAction
    @Published public var emergencyStop: Bool = false
    @Published public var allowedApps: [String] = ["Finder", "Safari", "TextEdit", "Terminal", "System Settings", "Notes", "Xcode", "Figma", "OpenCowork"]
    @Published public var budgetEnabled: Bool = false
    @Published public var budgetLimit: Double = 5.0
    @Published public var spentThisMonth: Double = 0.0
    @Published public var allowlistEnabled: Bool = false
    @Published public var activeSession: TaskSession?
    @Published public var sessions: [TaskSession] = []
    @Published public var scheduledTasks: [ScheduledTask] = []
    @Published public var skills: [Skill] = []
    
    // New Features state
    @Published public var teams: [Team] = []
    @Published public var activeProject: URL? = nil
    @Published public var showingCreateTeam: Bool = false
    @Published public var projects: [URL] = []
    
    private let configKey = "com.opencode.opencowork.config"
    private let safetyModeKey = "com.opencode.opencowork.safetyMode"
    private let appsKey = "com.opencode.opencowork.apps"
    private let budgetEnabledKey = "com.opencode.opencowork.budgetEnabled"
    private let budgetKey = "com.opencode.opencowork.budget"
    private let spentKey = "com.opencode.opencowork.spent"
    private let allowlistEnabledKey = "com.opencode.opencowork.allowlistEnabled"
    private let sessionsKey = "com.opencode.opencowork.sessions"
    private let tasksKey = "com.opencode.opencowork.tasks"
    private let skillsKey = "com.opencode.opencowork.skills"
    private let teamsKey = "com.opencode.opencowork.teams"
    private let projectsKey = "com.opencode.opencowork.projects"
    private let activeProjectKey = "com.opencode.opencowork.activeProject"
    
    public init() {
        loadSettings()
    }
    
    public func loadSettings() {
        let defaults = UserDefaults.standard
        
        // Load LLM Config
        if let data = defaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            self.llmConfig = config
        } else {
            // Default config is empty
            self.llmConfig = LLMConfig()
        }
        
        // Load Safety Mode
        // Migrate from old approve-before-action boolean key if present
        if let modeData = defaults.data(forKey: safetyModeKey),
           let mode = try? JSONDecoder().decode(SafetyMode.self, from: modeData) {
            self.safetyMode = mode
        } else {
            // Fallback: check old boolean key for migration
            let oldApproveKey = "com.opencode.opencowork.approve"
            if defaults.object(forKey: oldApproveKey) != nil {
                self.safetyMode = defaults.bool(forKey: oldApproveKey) ? .approveBeforeAction : .fullAuto
            } else {
                self.safetyMode = .approveBeforeAction
            }
        }
        
        // Load Allowed Apps
        if let apps = defaults.stringArray(forKey: appsKey) {
            self.allowedApps = apps
        }
        
        // Load Budget Toggle
        if defaults.object(forKey: budgetEnabledKey) != nil {
            self.budgetEnabled = defaults.bool(forKey: budgetEnabledKey)
        }
        
        // Load Budget
        if defaults.object(forKey: budgetKey) != nil {
            self.budgetLimit = defaults.double(forKey: budgetKey)
        }
        
        // Load Spent
        self.spentThisMonth = defaults.double(forKey: spentKey)
        
        // Load Allowlist Toggle
        if defaults.object(forKey: allowlistEnabledKey) != nil {
            self.allowlistEnabled = defaults.bool(forKey: allowlistEnabledKey)
        }
        
        // Load Sessions
        if let data = defaults.data(forKey: sessionsKey),
           let list = try? JSONDecoder().decode([TaskSession].self, from: data) {
            self.sessions = list
        }
        
        // Load Scheduled Tasks
        if let data = defaults.data(forKey: tasksKey),
           let list = try? JSONDecoder().decode([ScheduledTask].self, from: data) {
            self.scheduledTasks = list
        }
        
        // Load Skills
        if let data = defaults.data(forKey: skillsKey),
           let list = try? JSONDecoder().decode([Skill].self, from: data) {
            self.skills = list
        } else {
            // Seed default skills
            self.skills = [
                Skill(
                    name: "Web Search",
                    description: "Enables the agent to open Safari and use search engines to retrieve information.",
                    systemPromptInstructions: "You can open Safari to perform search queries when the user asks for external information. Use search bars to type search queries."
                ),
                Skill(
                    name: "File Manager",
                    description: "Allows the agent to write files directly and run shell commands.",
                    systemPromptInstructions: "You have direct access to write files using the 'write_file' action, and execute terminal commands using the 'shell' action. Prefer these direct actions over manual terminal GUI inputs."
                ),
                Skill(
                    name: "Browser Control",
                    description: "Instructs the agent on keyboard shortcuts and navigation actions inside browsers.",
                    systemPromptInstructions: "Use 'command+l' to focus the Safari address bar, type the URL, and press 'return' to navigate. Scroll up/down to see content."
                )
            ]
            saveConfig()
        }
        
        // Load Teams
        if let data = defaults.data(forKey: teamsKey),
           let list = try? JSONDecoder().decode([Team].self, from: data) {
            self.teams = list
        }
        
        // Load Projects
        if let data = defaults.data(forKey: projectsKey),
           let list = try? JSONDecoder().decode([URL].self, from: data) {
            self.projects = list
        }
        
        if let data = defaults.data(forKey: activeProjectKey),
           let url = try? JSONDecoder().decode(URL.self, from: data) {
            self.activeProject = url
        }
    }
    
    public func saveConfig() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(llmConfig) {
            defaults.set(data, forKey: configKey)
        }
        if let modeData = try? JSONEncoder().encode(safetyMode) {
            defaults.set(modeData, forKey: safetyModeKey)
        }
        defaults.set(allowedApps, forKey: appsKey)
        defaults.set(budgetEnabled, forKey: budgetEnabledKey)
        defaults.set(budgetLimit, forKey: budgetKey)
        defaults.set(spentThisMonth, forKey: spentKey)
        defaults.set(allowlistEnabled, forKey: allowlistEnabledKey)
        
        // Save sessions
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: sessionsKey)
        }
        
        // Save tasks
        if let data = try? JSONEncoder().encode(scheduledTasks) {
            defaults.set(data, forKey: tasksKey)
        }
        
        // Save skills
        if let data = try? JSONEncoder().encode(skills) {
            defaults.set(data, forKey: skillsKey)
        }
        
        // Save teams
        if let data = try? JSONEncoder().encode(teams) {
            defaults.set(data, forKey: teamsKey)
        }
        
        // Save projects
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: projectsKey)
        }
        
        if let active = activeProject, let data = try? JSONEncoder().encode(active) {
            defaults.set(data, forKey: activeProjectKey)
        } else {
            defaults.removeObject(forKey: activeProjectKey)
        }
    }
    
    public func createSession(prompt: String) -> TaskSession {
        let session = TaskSession(title: prompt, status: .idle)
        self.activeSession = session
        self.sessions.insert(session, at: 0)
        saveConfig()
        return session
    }
    
    public func updateActiveSession(_ session: TaskSession) {
        self.activeSession = session
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        saveConfig()
    }
    
    public func deleteSession(id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if activeSession?.id == id {
            activeSession = nil
        }
        saveConfig()
    }
    
    public func togglePinSession(id: UUID) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].isPinned.toggle()
            // Sort pinned sessions first
            sessions.sort { lhs, rhs in
                if lhs.isPinned && !rhs.isPinned { return true }
                if !lhs.isPinned && rhs.isPinned { return false }
                return lhs.createdAt > rhs.createdAt
            }
            saveConfig()
        }
    }
    
    public func addSpentCost(_ cost: Double) {
        self.spentThisMonth += cost
        saveConfig()
    }
    
    public func clearSessions() {
        self.sessions = []
        self.activeSession = nil
        saveConfig()
    }
    
    // Scheduled Tasks CRUD
    public func addScheduledTask(_ task: ScheduledTask) {
        self.scheduledTasks.append(task)
        saveConfig()
    }
    
    public func deleteScheduledTask(at index: Int) {
        guard index >= 0 && index < scheduledTasks.count else { return }
        self.scheduledTasks.remove(at: index)
        saveConfig()
    }
    
    public func updateScheduledTask(_ task: ScheduledTask) {
        if let index = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
            scheduledTasks[index] = task
            saveConfig()
        }
    }
    
    // Skills Management
    public func toggleSkill(name: String) {
        if let index = skills.firstIndex(where: { $0.name == name }) {
            skills[index].isEnabled.toggle()
            saveConfig()
        }
    }
}
