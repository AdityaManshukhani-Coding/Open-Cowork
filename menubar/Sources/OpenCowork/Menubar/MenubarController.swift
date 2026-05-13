import AppKit

@MainActor
class MenubarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "OpenCowork")
        button.action = #selector(handleLeftClick)
        button.target = self

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Toggle Chat Panel", action: #selector(togglePanel), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func handleLeftClick() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.togglePanel()
        }
    }

    @objc private func togglePanel() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.togglePanel()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}