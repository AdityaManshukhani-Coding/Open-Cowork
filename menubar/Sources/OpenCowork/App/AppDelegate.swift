import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarController: MenubarController?
    private var chatPanel: ChatPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubarController = MenubarController()
        chatPanel = ChatPanel()
    }

    func togglePanel() {
        guard let panel = chatPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}