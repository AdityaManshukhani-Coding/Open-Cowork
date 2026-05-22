import SwiftUI
import AppKit

/// The main entry point for the Open Cowork macOS menubar application.
///
/// This app runs as a menubar-only (LSUIElement) application — it has no Dock
/// icon and no standard window.  Interaction happens through the menubar icon
/// and a floating chat panel that can be toggled from the menu.
@main
struct OpenCoworkApp: App {
    /// Shared application state, injected into the view hierarchy.
    @State private var appState = AppState()

    /// Tracks whether the floating chat panel is currently visible.
    @State private var chatPanelVisible = false

    init() {
        // Make this a menubar-only app — no Dock icon, no standard menu bar
        // menus beyond what we explicitly provide.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // ── Menubar Extra ──────────────────────────────────────────────
        MenuBarExtra("Open Cowork", systemImage: "sparkles") {
            // Status indicator
            if appState.isRunning {
                Label("Agent running…", systemImage: "circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Agent idle", systemImage: "circle")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Toggle chat panel
            Button {
                chatPanelVisible.toggle()
                if chatPanelVisible {
                    bringChatPanelToFront()
                }
            } label: {
                Label(
                    chatPanelVisible ? "Hide Chat Panel" : "Show Chat Panel",
                    systemImage: chatPanelVisible ? "eye.slash" : "bubble.left.and.bubble.right"
                )
            }

            Divider()

            // Quick actions
            Button {
                appState.startAgent()
            } label: {
                Label("Start Agent", systemImage: "play.fill")
            }
            .disabled(appState.isRunning)

            Button {
                appState.stopAgent()
            } label: {
                Label("Stop Agent", systemImage: "stop.fill")
            }
            .disabled(!appState.isRunning)

            Divider()

            // Settings
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Open Cowork", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        // ── Floating Chat Panel (Window) ───────────────────────────────
        WindowGroup("Open Cowork", id: "chat-panel") {
            ChatPanelView(appState: appState)
                .frame(minWidth: 420, idealWidth: 480, minHeight: 560, idealHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 640)
        .commands {
            // Remove default "New Window" menu item since we only want one panel
            CommandGroup(replacing: .newItem) {}
        }

        // ── Settings Window ────────────────────────────────────────────
        Settings {
            SettingsView(appState: appState)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 480)
        }
        .windowResizability(.contentSize)
    }

    /// Brings the floating chat panel window to the front and gives it focus.
    private func bringChatPanelToFront() {
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "chat-panel" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
