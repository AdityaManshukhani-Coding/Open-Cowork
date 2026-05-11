# Open Cowork v0.1 — Implementation Tasks

## CRITICAL RULES
- Commit + push to `origin/main` after every working module.
- Conventional commits: feat:, fix:, chore:.
- No comments in code unless necessary. Follow Swift 6 and Python best practices.

## Project Structure
```
Open-Cowork/
├── menubar/                          # Swift 6 Xcode project
│   ├── Sources/
│   │   ├── App/          (AppDelegate.swift, main.swift)
│   │   ├── Menubar/      (MenubarController.swift)
│   │   ├── UI/           (ChatPanel.swift, ChatBubble.swift, ActionLog.swift, CostDisplay.swift)
│   │   ├── Control/      (AccessibilityController.swift, MouseController.swift, KeyboardController.swift, AppController.swift)
│   │   └── Models/       (Message.swift, Action.swift, Settings.swift)
│   ├── Resources/        (Info.plist, OpenCowork.entitlements)
│   └── OpenCowork.xcodeproj/
├── orchestrator/                     # Python
│   ├── requirements.txt, main.py, agent_loop.py, safety.py, cost_tracker.py, storage.py
│   └── providers/        (anthropic.py, openai.py, ollama.py)
├── CONTRIBUTING.md
└── LICENSE (MIT)
```

## MODULE 1: Menubar Shell + Floating Chat Panel (Swift 6)

### AppDelegate.swift
- NSApplicationDelegate. Create NSStatusBar item. Toggle ChatPanel on click.
- Menu items: Preferences, Quit.

### MenubarController.swift
- Manage NSStatusItem lifecycle. Use SF Symbol "brain.head.profile".
- Show/hide ChatPanel. Right-click menu.

### ChatPanel.swift
- Floating NSPanel (non-activating, utility style). Contains SwiftUI via NSHostingView.
- Text field at bottom + send button. Scrollable message list. Collapsible action log.
- Cost display footer. Rounded corners, native look.

### ChatBubble.swift
- SwiftUI: user right/bold, agent left/gray. Timestamps.

### ActionLog.swift
- SwiftUI list: click/type/open app actions with timestamps and icons.

### CostDisplay.swift
- Real-time "1,234 tokens · ~$0.02" footer. Updates via Combine publisher.

### Models
- Message: id, role (user/agent), content, timestamp.
- Action: id, type (.click, .type, .launch, .focus, .quit), description, timestamp, status.
- Settings: provider, apiKey, model, approvalMode (auto/approve/step).

## MODULE 2: Layer 1 — AXUIElement Control (Swift 6)

### AccessibilityController.swift
Wrapper around macOS Accessibility API:
- getFocusedApp() -> AXUIElement?
- getElementAtPosition(x: CGFloat, y: CGFloat) -> AXUIElement?
- getAttribute(_ element: AXUIElement, attribute: String) -> AnyObject?
- setAttribute(_ element: AXUIElement, attribute: String, value: AnyObject)
- performAction(_ element: AXUIElement, action: String) -> AXError
- pressButton(_ element: AXUIElement)
- click(_ element: AXUIElement)
- typeText(_ element: AXUIElement, text: String)
- getAllElements(in element: AXUIElement) -> [AXUIElement]
- findElement(role: String, label: String?, in element: AXUIElement) -> AXUIElement?
- getPosition(_ element: AXUIElement) -> CGPoint?
- getSize(_ element: AXUIElement) -> CGSize?
- getWindowList(for app: AXUIElement) -> [AXUIElement]
- observeFocus(callback: @escaping (AXUIElement) -> Void) — uses AXObserverCreate

### MouseController.swift
CGEvent mouse control:
- move(to point: CGPoint)
- click(at point: CGPoint, button: CGMouseButton = .left)
- rightClick(at point: CGPoint)
- doubleClick(at point: CGPoint)
- drag(from: CGPoint, to: CGPoint)
- scroll(deltaX: Int, deltaY: Int)
- getCurrentPosition() -> CGPoint

### KeyboardController.swift
CGEvent keyboard control:
- type(_ text: String) — convert each char to CGEvent
- pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = [])
- pressShortcut(_ keyCode: CGKeyCode, modifiers: CGEventFlags) — cmd+c, cmd+v etc.

### AppController.swift
NSWorkspace control:
- launchApp(bundleIdentifier: String) -> Bool
- bringToFront(bundleIdentifier: String)
- runningApps() -> [NSRunningApplication]
- quitApp(bundleIdentifier: String)

## MODULE 3: Python Orchestrator

### main.py
FastAPI server on localhost:8484:
- POST /task — receive task description, start agent loop
- GET /status — health check + current task status
- GET /actions — stream action log
- WebSocket /ws — real-time updates to Swift UI

### agent_loop.py
Core loop: get task → request screen state from Swift → send to AI → parse actions → send to Swift for execution → observe → repeat until done.

### safety.py
- Action allowlist per bundle ID
- Approval modes: auto, approve-before-action, step-through
- Emergency stop signal

### cost_tracker.py
Parse token usage from provider responses. Multiply by per-model pricing. Expose via endpoint.

### providers/
- anthropic.py: messages API, tool-use support
- openai.py: chat completions, tool-use support  
- ollama.py: local generate endpoint

### storage.py
SQLite: tasks, actions, messages, costs tables.

## Entitlements Info.plist
Key: `com.apple.security.automation.apple-events` = YES
Also need Accessibility permission — user prompted on first AXUIElement call.

## ORDER
1. Swift project structure + menubar + chat panel (Module 1)
2. AXUIElement + CGEvent control layer (Module 2)
3. Python orchestrator (Module 3)
4. Push after each module. If you finish v0.1, do v0.2: ScreenCaptureKit screenshots, vision fallback, per-app allowlist UI.