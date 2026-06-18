import Cocoa
import SwiftUI

@MainActor
public class StatusItemController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSWindow?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    private let appStore: AppStore
    private let agentStore: AgentStore

    public init(appStore: AppStore, agentStore: AgentStore) {
        self.appStore = appStore
        self.agentStore = agentStore
        super.init()
        setupStatusItem()
        setupPanel()
        setupEmergencyStopShortcut()
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupStatusItem() {
        // Create Status Item in System Menu Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use brain symbol image
            if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Open Cowork") {
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Setup Popover
        let popoverView = MenuBarPopoverView(onOpenMainApp: { [weak self] in
            self?.closePopover()
            self?.showPanel()
        })
        .environmentObject(appStore)
        .environmentObject(agentStore)
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 150)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: popoverView)
    }
    
    private func setupPanel() {
        // Create custom standard window
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580), // Start with onboarding size
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .normal
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 580)
        
        // Set SwiftUI View
        let contentView = NSHostingView(
            rootView: MainPanelView()
                .environmentObject(appStore)
                .environmentObject(agentStore)
        )
        panel.contentView = contentView
        panel.delegate = self
        
        self.panel = panel
        
        // Center the window on launch and show it
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of closing/destroying it
        sender.orderOut(nil)
        return false
    }
    
    @objc public func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func closePopover() {
        popover?.performClose(nil)
    }
    
    public func showPanel() {
        guard let panel = panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Emergency Stop Keyboard Shortcut

    private func setupEmergencyStopShortcut() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            guard let self = self else { return event }

            // Cmd+Shift+Esc triggers emergency stop
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command, .shift] && event.keyCode == 53 {
                // Only trigger if agent is actually running
                if !self.appStore.emergencyStop {
                    self.agentStore.triggerEmergencyStop()
                    print("Emergency stop triggered via Cmd+Shift+Esc")
                }
                return nil // Consume the event
            }

            return event
        }

        // Also attempt global monitor for when the app is in the background
        // Requires accessibility permissions which we already have
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
            guard let self = self else { return }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command, .shift] && event.keyCode == 53 {
                if !self.appStore.emergencyStop {
                    self.agentStore.triggerEmergencyStop()
                    print("Emergency stop triggered via global Cmd+Shift+Esc")
                }
            }
        }
    }
}
