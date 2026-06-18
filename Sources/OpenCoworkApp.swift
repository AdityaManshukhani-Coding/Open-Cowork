import SwiftUI
import AppKit

@main
struct OpenCoworkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appStore)
                .frame(width: 480, height: 420)
        }
        #endif
    }
}

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    public var statusItemController: StatusItemController?
    public let appStore = AppStore()
    public var agentStore: AgentStore?
    public var schedulerStore: SchedulerStore?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to regular activation policy so it shows in the Dock
        NSApp.setActivationPolicy(.regular)
        
        let agent = AgentStore(appStore: appStore)
        self.agentStore = agent
        
        let scheduler = SchedulerStore(appStore: appStore, agentStore: agent)
        self.schedulerStore = scheduler
        
        statusItemController = StatusItemController(appStore: appStore, agentStore: agent)
        
        // Ensure the app is active and frontmost at launch
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.showPanel()
        return true
    }
}
