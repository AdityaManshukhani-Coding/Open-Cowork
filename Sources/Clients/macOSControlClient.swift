import Cocoa
import ApplicationServices
import ScreenCaptureKit

/// Media key actions sent via NSEvent systemDefined events (HID consumer usages).
public enum MediaAction: String {
    case play
    case pause
    case playPause = "play_pause"
    case next
    case previous
}

/// Direction for switching macOS Spaces (desktops).
public enum DesktopDirection: String {
    case left
    case right
}

/// Direction for swipe gestures. Note: real trackpad swipes are not
/// synthesizable from user space on macOS — see `swipe(_:)` for the
/// closest programmatic equivalents.
public enum SwipeDirection: String {
    case left
    case right
    case up
    case down
}

public struct macOSControlClient {
    public var captureScreenshot: () async -> Data?
    public var checkScreenRecordingPermission: () async -> Bool
    public var getAccessibilityTree: () -> String
    public var moveMouse: (_ point: CGPoint) -> Void
    public var clickMouse: (_ point: CGPoint, _ button: CGMouseButton, _ clickCount: Int) -> Void
    public var dragMouse: (_ start: CGPoint, _ end: CGPoint) -> Void
    public var scrollMouse: (_ horizontal: Int, _ vertical: Int) -> Void
    public var typeText: (_ text: String) -> Void
    public var keyStroke: (_ keyCode: CGKeyCode, _ flags: CGEventFlags) -> Void
    public var holdKey: (_ keyCode: CGKeyCode, _ flags: CGEventFlags, _ duration: TimeInterval) -> Void
    public var zoom: (_ zoomIn: Bool) -> Void
    public var launchApp: (_ appName: String) -> Bool
    public var spotlightQuery: (_ query: String) -> Void
    public var switchToApp: (_ appName: String) -> Bool
    public var media: (_ action: MediaAction) -> Void
    public var missionControl: () -> Void
    public var showDesktop: () -> Void
    public var appExpose: () -> Void
    public var switchDesktop: (_ direction: DesktopDirection) -> Void
    public var swipe: (_ direction: SwipeDirection) -> Void
}

extension macOSControlClient {
    public static func live() -> macOSControlClient {
        return macOSControlClient(
            captureScreenshot: {
                // ═══════════════════════════════════════════════════════════════
                // PRIMARY: ScreenCaptureKit — the ONLY fully supported screen
                // capture API on macOS 15. CGDisplayCreateImage is obsoleted.
                // CGWindowListCreateImage is deprecated and returns blank images
                // without permission. screencapture CLI inherits the parent
                // process's TCC permissions and also fails without them.
                //
                // CORRECT FILTER: SCContentFilter(display:excludingApplications:[],
                // exceptingWindows:[]) captures the ENTIRE display including all
                // windows from all apps. The `including:` variant only captures
                // specific apps — that was the previous bug.
                //
                // REQUIRES: App must be in System Settings → Privacy & Security →
                // Screen & System Audio Recording. On ad-hoc signed builds,
                // re-grant permission after each rebuild.
                // ═══════════════════════════════════════════════════════════════
                if #available(macOS 14.0, *) {
                    do {
                        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                        print("[captureScreenshot] SCShareableContent: displays=\(shareableContent.displays.count), apps=\(shareableContent.applications.count), windows=\(shareableContent.windows.count)")
                        
                        guard let display = shareableContent.displays.first else {
                            print("[captureScreenshot] ERROR: No displays found")
                            return nil
                        }
                        print("[captureScreenshot] Using display: \(display.width)x\(display.height)")
                        
                        let filter = SCContentFilter(
                            display: display,
                            excludingApplications: [],
                            exceptingWindows: []
                        )
                        let config = SCStreamConfiguration()
                        config.width = display.width
                        config.height = display.height
                        config.showsCursor = true
                        
                        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        print("[captureScreenshot] ScreenCaptureKit succeeded: \(cgImage.width)x\(cgImage.height)")
                        return processImage(cgImage)
                    } catch {
                        print("[captureScreenshot] ScreenCaptureKit failed: \(error.localizedDescription)")
                    }
                }

                // ═══════════════════════════════════════════════════════════════
                // FALLBACK: screencapture CLI
                // Only works if the Terminal app (or whichever process launched
                // us) has Screen Recording permission. Without it, screencapture
                // produces an image with only this app's windows.
                // ═══════════════════════════════════════════════════════════════
                print("[captureScreenshot] Trying screencapture CLI fallback...")
                if let data = Self.captureWithScreenCaptureCLI() {
                    print("[captureScreenshot] screencapture CLI succeeded: \(data.count) bytes")
                    return data
                }

                print("[captureScreenshot] ERROR: All capture methods failed — check Screen & System Audio Recording permission")
                return nil
            },
            checkScreenRecordingPermission: {
                await Self.hasScreenRecordingPermission()
            },
            getAccessibilityTree: {
                guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return "No active application" }
                let pid = frontmostApp.processIdentifier
                let appElement = AXUIElementCreateApplication(pid)
                
                var output = "Active Application: \(frontmostApp.localizedName ?? "Unknown") (PID: \(pid))\n\n"
                
                // Read top level windows first
                var windows: AnyObject?
                let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
                if result == .success, let windowsArray = windows as? [AXUIElement] {
                    for (index, window) in windowsArray.enumerated() {
                        output += "Window \(index):\n"
                        traverseElement(window, indent: "  ", output: &output, depth: 0)
                    }
                } else {
                    // Fallback to app directly
                    traverseElement(appElement, indent: "  ", output: &output, depth: 0)
                }
                
                return output
            },
            moveMouse: { point in
                // CGEvent uses the same logical-point space as the AX tree —
                // no Retina scaling needed.
                let source = CGEventSource(stateID: .combinedSessionState)
                let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
                moveEvent?.post(tap: .cghidEventTap)
            },
            clickMouse: { point, button, clickCount in
                // CGEvent uses the same logical-point space as the AX tree —
                // no Retina scaling needed.
                let source = CGEventSource(stateID: .combinedSessionState)
                
                let mouseDownType: CGEventType
                let mouseUpType: CGEventType
                
                if button == .right {
                    mouseDownType = .rightMouseDown
                    mouseUpType = .rightMouseUp
                } else {
                    mouseDownType = .leftMouseDown
                    mouseUpType = .leftMouseUp
                }
                
                // Move cursor to the target position first
                let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)
                moveEvent?.post(tap: .cghidEventTap)
                usleep(20000) // 20ms delay
                
                for count in 1...clickCount {
                    let downEvent = CGEvent(mouseEventSource: source, mouseType: mouseDownType, mouseCursorPosition: point, mouseButton: button)
                    downEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
                    downEvent?.post(tap: .cghidEventTap)
                    
                    usleep(30000) // 30ms press delay
                    
                    let upEvent = CGEvent(mouseEventSource: source, mouseType: mouseUpType, mouseCursorPosition: point, mouseButton: button)
                    upEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
                    upEvent?.post(tap: .cghidEventTap)
                    
                    if count < clickCount {
                        usleep(150000) // 150ms delay between double clicks
                    }
                }
            },
            dragMouse: { start, end in
                // CGEvent uses the same logical-point space as the AX tree —
                // no Retina scaling needed.
                let source = CGEventSource(stateID: .combinedSessionState)
                
                // Move to start
                let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)
                moveEvent?.post(tap: .cghidEventTap)
                usleep(50000) // 50ms
                
                // Mouse down
                let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
                downEvent?.post(tap: .cghidEventTap)
                usleep(50000)
                
                // Mouse drag
                let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left)
                dragEvent?.post(tap: .cghidEventTap)
                usleep(100000)
                
                // Mouse up
                let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
                upEvent?.post(tap: .cghidEventTap)
            },
            scrollMouse: { horizontal, vertical in
                let source = CGEventSource(stateID: .combinedSessionState)
                let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0)
                scrollEvent?.post(tap: .cghidEventTap)
            },
            typeText: { text in
                let source = CGEventSource(stateID: .combinedSessionState)
                
                for char in text.utf16 {
                    let keyEventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                    let keyEventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                    
                    var code = char
                    keyEventDown?.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: nil, unicodeString: &code)
                    keyEventUp?.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: nil, unicodeString: &code)
                    
                    keyEventDown?.post(tap: .cghidEventTap)
                    usleep(5000) // 5ms delay between down and up
                    keyEventUp?.post(tap: .cghidEventTap)
                    usleep(10000) // 10ms delay between characters
                }
            },
            keyStroke: { keyCode, flags in
                // For modifier-key combos (Cmd+, Shift+, etc.), use AppleScript
                // System Events which has a higher-priority injection pipeline than
                // CGEvent.  macOS blocks CGEvent keystrokes from reaching system
                // overlays like Spotlight, and sometimes swallows them when the
                // frontmost app is a menubar popover.
                if !flags.isEmpty {
                    let script = Self.buildAppleScriptKeystroke(keyCode: keyCode, flags: flags)
                    Self.executeAppleScript(script)
                } else {
                    // Plain key (no modifiers) — CGEvent works fine for these
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let downEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                    let upEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
                    downEvent?.post(tap: .cghidEventTap)
                    usleep(20000)
                    upEvent?.post(tap: .cghidEventTap)
                }
            },
            holdKey: { keyCode, flags, duration in
                // AppleScript `key down`/`key up` for reliable modifier-hold across
                // apps.  CGEvent hold events are sometimes dropped by the frontmost
                // app when the process that posted them is not itself frontmost.
                let script = Self.buildAppleScriptKeyHold(keyCode: keyCode, flags: flags, duration: duration)
                Self.executeAppleScript(script)
            },
            zoom: { zoomIn in
                // Cmd+Plus / Cmd+Minus — uses AppleScript for the same reason
                // as keyStroke with modifiers.
                let char = zoomIn ? "=" : "-"
                let script = "tell application \"System Events\" to keystroke \"\(char)\" using command down"
                Self.executeAppleScript(script)
            },
            launchApp: { appName in
                // Standard app launching via Workspace API
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                
                // Try launching by name
                if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName) ??
                                NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple." + appName.lowercased()) {
                    NSWorkspace.shared.openApplication(at: appUrl, configuration: config, completionHandler: nil)
                    return true
                }
                
                // Alternative: Search applications folder
                let fileManager = FileManager.default
                let appsDirs = [
                    URL(fileURLWithPath: "/Applications"),
                    URL(fileURLWithPath: "/System/Applications")
                ]
                
                for dir in appsDirs {
                    if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) {
                        if let matchedApp = contents.first(where: { $0.lastPathComponent.lowercased().contains(appName.lowercased()) }) {
                            NSWorkspace.shared.openApplication(at: matchedApp, configuration: config, completionHandler: nil)
                            return true
                        }
                    }
                }
                
                return false
            },
            spotlightQuery: { query in
                // Open Spotlight via AppleScript Cmd+Space, wait for the overlay,
                // then type the query.  CGEvent cannot reach the Spotlight overlay
                // because macOS WindowServer blocks synthetic keystrokes to system
                // processes.  AppleScript System Events uses a higher-priority
                // injection path that Spotlight accepts.
                
                // Step 1: Open Spotlight
                let openScript = "tell application \"System Events\" to keystroke space using command down"
                Self.executeAppleScript(openScript)
                usleep(800_000) // 800ms — Spotlight needs time to animate in
                
                // Step 2: Type the query
                // Escape the query for AppleScript string literals
                let escaped = query
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let typeScript = "tell application \"System Events\" to keystroke \"\(escaped)\""
                Self.executeAppleScript(typeScript)
            },
            switchToApp: { appName in
                let runningApps = NSWorkspace.shared.runningApplications
                let lowercased = appName.lowercased()
                
                // Find by localized name (best match)
                if let target = runningApps.first(where: {
                    $0.localizedName?.lowercased() == lowercased
                }) {
                    target.activate(options: .activateIgnoringOtherApps)
                    return true
                }
                
                // Fuzzy match: app name contains search term
                if let target = runningApps.first(where: {
                    $0.localizedName?.lowercased().contains(lowercased) ?? false
                }) {
                    target.activate(options: .activateIgnoringOtherApps)
                    return true
                }
                
                // Try by bundle identifier
                if let target = runningApps.first(where: {
                    $0.bundleIdentifier?.lowercased().contains(lowercased) ?? false
                }) {
                    target.activate(options: .activateIgnoringOtherApps)
                    return true
                }
                
                return false
            },
            media: { action in
                // Send media key events via NSEvent systemDefined events.
                // These are HID consumer usages (0x80 page) that macOS routes
                // to the media handler regardless of frontmost app.
                Self.postMediaKey(action)
            },
            missionControl: {
                // Ctrl+Up = Mission Control (equivalent to F3 on most Macs)
                let script = "tell application \"System Events\" to key code 126 using {control down}"
                Self.executeAppleScript(script)
            },
            showDesktop: {
                // F11 = Show Desktop on Apple Magic Keyboard
                let script = "tell application \"System Events\" to key code 103"
                Self.executeAppleScript(script)
            },
            appExpose: {
                // Ctrl+Down = App Exposé (windows of current app)
                let script = "tell application \"System Events\" to key code 125 using {control down}"
                Self.executeAppleScript(script)
            },
            switchDesktop: { direction in
                // Ctrl+Left / Ctrl+Right = switch macOS Spaces (desktops)
                let keyCode: Int = (direction == .left) ? 123 : 124
                let script = "tell application \"System Events\" to key code \(keyCode) using {control down}"
                Self.executeAppleScript(script)
            },
            swipe: { direction in
                // NOTE: macOS does NOT expose a public API for sending trackpad
                // swipe gestures. The private MultitouchSupport.framework can
                // only RECEIVE touches, not synthesize them. The most common
                // programmatic equivalent is the keyboard shortcut that has
                // the same observable effect:
                //   - swipe left  → Ctrl+Left  (next desktop, also "back" in browsers)
                //   - swipe right → Ctrl+Right (previous desktop, also "forward" in browsers)
                //   - swipe up    → Ctrl+Up    (Mission Control, equivalent to 3-finger swipe up)
                //   - swipe down  → Ctrl+Down  (App Exposé, equivalent to 3-finger swipe down)
                let keyCode: Int
                switch direction {
                case .left:  keyCode = 123
                case .right: keyCode = 124
                case .up:    keyCode = 126
                case .down:  keyCode = 125
                }
                let script = "tell application \"System Events\" to key code \(keyCode) using {control down}"
                Self.executeAppleScript(script)
            }
        )
    }
    
    // Helper to extract an attribute from AXUIElement
    private static func getAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success {
            return value
        }
        return nil
    }
    
    // Recursive traversal of accessibility elements
    private static func traverseElement(_ element: AXUIElement, indent: String, output: inout String, depth: Int) {
        if depth > 4 { return } // Safeguard traversal depth
        
        guard let role = getAttribute(element, attribute: kAXRoleAttribute) as? String else { return }
        
        let title = getAttribute(element, attribute: kAXTitleAttribute) as? String ?? ""
        let description = getAttribute(element, attribute: kAXDescriptionAttribute) as? String ?? ""
        let value = getAttribute(element, attribute: kAXValueAttribute)
        
        var rect = CGRect.zero
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        
        if posResult == .success, let posVal = positionValue {
            var point = CGPoint.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
            rect.origin = point
        }
        
        if sizeResult == .success, let sizeVal = sizeValue {
            var size = CGSize.zero
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            rect.size = size
        }
        
        let displayValue = (value != nil) ? "\(value!)" : ""
        
        // Print only interactive and text-containing roles
        let interactiveRoles = [
            "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
            "AXPopUpButton", "AXMenuButton", "AXLink", "AXMenuItem", "AXSlider",
            "AXComboBox", "AXStaticText", "AXSearchField", "AXRow", "AXTab"
        ]
        
        let isInteractive = interactiveRoles.contains(role)
        let hasContent = !title.isEmpty || !description.isEmpty || !displayValue.isEmpty
        
        if isInteractive || hasContent || role == "AXWindow" {
            let frameStr = "x: \(Int(rect.origin.x)), y: \(Int(rect.origin.y)), w: \(Int(rect.width)), h: \(Int(rect.height))"
            output += "\(indent)- [\(role)] Title: \"\(title)\" Desc: \"\(description)\" Val: \"\(displayValue)\" Frame: {\(frameStr)}\n"
        }
        
        // Traverse child elements
        var children: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                traverseElement(child, indent: indent + "  ", output: &output, depth: depth + 1)
            }
        }
    }
    
    // MARK: - AppleScript Keystroke Injection
    
    /// Executes an AppleScript string and returns success/failure.
    /// Uses NSAppleScript which has a higher-priority event injection path
    /// than CGEvent — macOS treats it as "user-initiated" and routes it
    /// to system overlays (Spotlight, Mission Control) that CGEvent cannot reach.
    @discardableResult
    private static func executeAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error = error {
            print("[executeAppleScript] Error: \(error)")
            return false
        }
        return true
    }
    
    /// Builds an AppleScript `keystroke` / `key code` command with modifier keys.
    /// Special keys (Return, Tab, Delete, Escape, arrows) use `key code N` because
    /// AppleScript's `keystroke` command does not support control characters or
    /// Unicode arrows as string arguments.
    ///
    /// Examples:
    ///   `tell application "System Events" to keystroke "n" using {command down}`
    ///   `tell application "System Events" to key code 36 using {command down}`  (Return)
    private static func buildAppleScriptKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
        var modifiers: [String] = []
        if flags.contains(.maskCommand)   { modifiers.append("command down") }
        if flags.contains(.maskShift)     { modifiers.append("shift down") }
        if flags.contains(.maskAlternate) { modifiers.append("option down") }
        if flags.contains(.maskControl)   { modifiers.append("control down") }
        
        let usingClause: String
        if modifiers.isEmpty {
            usingClause = ""
        } else {
            usingClause = " using {\(modifiers.joined(separator: ", "))}"
        }
        
        // Special keys must use `key code N` — `keystroke` can't represent them
        if let specialCode = appleScriptSpecialKeyCode(for: keyCode) {
            return "tell application \"System Events\" to key code \(specialCode)\(usingClause)"
        }
        
        // Printable character — use `keystroke "char"`
        let char = characterForKeyCode(keyCode)
        let escapedChar = char
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"System Events\" to keystroke \"\(escapedChar)\"\(usingClause)"
    }
    
    /// Returns the numeric key code for keys that need `key code N` instead of `keystroke`.
    /// Returns nil for printable keys that can use `keystroke "char"`.
    private static func appleScriptSpecialKeyCode(for keyCode: CGKeyCode) -> Int? {
        switch keyCode {
        case 36:  return 36   // Return
        case 48:  return 48   // Tab
        case 49:  return 49   // Space
        case 51:  return 51   // Delete/Backspace
        case 53:  return 53   // Escape
        case 126: return 126  // Up arrow
        case 125: return 125  // Down arrow
        case 123: return 123  // Left arrow
        case 124: return 124  // Right arrow
        default:  return nil  // Printable — use keystroke
        }
    }
    
    /// Builds an AppleScript `key down` / `key up` pair with a hold duration.
    /// Example: hold Cmd+Tab for 2 seconds.
    private static func buildAppleScriptKeyHold(keyCode: CGKeyCode, flags: CGEventFlags, duration: TimeInterval) -> String {
        let keyName = appleScriptKeyName(for: keyCode)
        var modifiers: [String] = []
        if flags.contains(.maskCommand)   { modifiers.append("command down") }
        if flags.contains(.maskShift)     { modifiers.append("shift down") }
        if flags.contains(.maskAlternate) { modifiers.append("option down") }
        if flags.contains(.maskControl)   { modifiers.append("control down") }
        
        let usingClause: String
        if modifiers.isEmpty {
            usingClause = ""
        } else {
            usingClause = " using {\(modifiers.joined(separator: ", "))}"
        }
        
        let durationStr = String(format: "%.2f", max(duration, 0.05))
        return """
        tell application "System Events"
            key down \(keyName)\(usingClause)
            delay \(durationStr)
            key up \(keyName)\(usingClause)
        end tell
        """
    }
    
    /// Maps a CGKeyCode to the printable character string AppleScript expects
    /// for `keystroke "char"`.  Only called for non-special keys (i.e. after
    /// `appleScriptSpecialKeyCode` returns nil).
    private static func characterForKeyCode(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 0:  return "a"
        case 1:  return "s"
        case 2:  return "d"
        case 3:  return "f"
        case 4:  return "h"
        case 5:  return "g"
        case 6:  return "z"
        case 7:  return "x"
        case 8:  return "c"
        case 9:  return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 22: return "1"
        case 23: return "2"
        case 24: return "="  // Note: also Cmd+= (zoom in) when combined with Cmd
        case 25: return "0"
        case 26: return "3"
        case 27: return "-"  // Note: also Cmd+- (zoom out) when combined with Cmd
        case 28: return "8"
        case 29: return "6"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."
        case 50: return "`"
        default: return "?"
        }
    }
    
    /// Maps a CGKeyCode to the named key string AppleScript expects for `key down`/`key up`.
    private static func appleScriptKeyName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 36: return "return"
        case 48: return "tab"
        case 49: return "space"
        case 51: return "delete"
        case 53: return "escape"
        case 126: return "up arrow"
        case 125: return "down arrow"
        case 123: return "left arrow"
        case 124: return "right arrow"
        default:
            // For letter/symbol keys, use the character wrapped in quotes
            return characterForKeyCode(keyCode)
        }
    }
    
    // MARK: - Media Key Injection (NSEvent systemDefined)
    
    /// Sends a media key event (play/pause/next/previous) via NSEvent
    /// `systemDefined` with subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS) and
    /// the HID consumer usage code encoded in `data1`.
    ///
    /// This is the only public way to send media keys on macOS — CGEvent
    /// cannot represent HID consumer usages (which live on USB HID
    /// consumer page 0x0C, not the keyboard usage page 0x07).
    ///
    /// The HID consumer codes used:
    ///   • 0xCD = Play/Pause
    ///   • 0xB5 = Next track
    ///   • 0xB6 = Previous track
    private static func postMediaKey(_ action: MediaAction) {
        let consumerCode: Int
        switch action {
        case .play, .pause, .playPause:
            consumerCode = 0xCD  // Play/Pause (toggle)
        case .next:
            consumerCode = 0xB5
        case .previous:
            consumerCode = 0xB6
        }
        
        // Each media key tap is sent as a key-down followed by a key-up event
        // separated by ~20ms. The system treats this as a single press.
        let timestamp = ProcessInfo.processInfo.systemUptime
        
        // Key down: data1 = (code << 16) | 0xa00
        if let downEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0),
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: (consumerCode << 16) | 0xa00,
            data2: -1
        ) {
            downEvent.cgEvent?.post(tap: .cghidEventTap)
        }
        
        usleep(20_000)  // 20ms between down and up
        
        // Key up: data1 = (code << 16) | 0xb00
        if let upEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0),
            timestamp: timestamp + 0.02,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (consumerCode << 16) | 0xb00,
            data2: -1
        ) {
            upEvent.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Permission Checks
    
    /// Checks whether the app has screen-recording permission by probing
    /// `SCShareableContent`.  This is the ONLY reliable check for ad-hoc
    /// signed debug builds:
    ///
    ///   - `CGPreflightScreenCaptureAccess()` returns true in pre-flight
    ///     state AND with stale TCC entries — completely unreliable.
    ///   - `SCScreenshotManager.captureImage()` silently returns a black
    ///     image instead of throwing when permission is denied.
    ///   - `SCShareableContent` genuinely throws a TCC error when the app
    ///     lacks Screen Recording permission.
    public static func hasScreenRecordingPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                return !content.displays.isEmpty
            } catch {
                print("[hasScreenRecordingPermission] SCShareableContent failed: \(error.localizedDescription)")
                return false
            }
        }
        // macOS < 14: CGPreflight is the best we have
        return CGPreflightScreenCaptureAccess()
    }
    

    
    /// Bulletproof screen capture using the `screencapture` CLI tool.
    /// This is the SAME tool macOS uses for Cmd+Shift+3/4/5 screenshots.
    /// It captures the ENTIRE display with all windows from all apps.
    ///
    /// This bypasses ScreenCaptureKit's `SCContentFilter` bugs entirely
    /// and is the fallback used by production apps like CleanShot and Shottr
    /// when the API path fails.
    private static func captureWithScreenCaptureCLI() -> Data? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("oc_screencapture_\(UUID().uuidString).png")
        let tempPath = tempFile.path
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x  = no sound effect
        // -C  = include cursor
        // -t png = lossless PNG (we'll resize & compress to JPEG ourselves)
        process.arguments = ["-x", "-C", "-t", "png", tempPath]
        
        // Capture stderr so we can log permission errors
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            
            guard process.terminationStatus == 0 else {
                print("[captureWithScreenCaptureCLI] screencapture failed (status \(process.terminationStatus)): \(errorString)")
                try? FileManager.default.removeItem(at: tempFile)
                return nil
            }
            
            guard let imageData = try? Data(contentsOf: tempFile),
                  !imageData.isEmpty else {
                print("[captureWithScreenCaptureCLI] No data written to temp file")
                try? FileManager.default.removeItem(at: tempFile)
                return nil
            }
            
            // Clean up temp file immediately
            try? FileManager.default.removeItem(at: tempFile)
            
            // Decode PNG → resize → re-encode as JPEG at consistent quality.
            // We always go through processImage so quality is uniform regardless
            // of source dimensions.
            guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("[captureWithScreenCaptureCLI] Failed to decode screencapture output")
                return nil
            }
            
            return processImage(imageRef)
        } catch {
            print("[captureWithScreenCaptureCLI] Failed to run screencapture: \(error)")
            try? FileManager.default.removeItem(at: tempFile)
            return nil
        }
    }
    
    private static func processImage(_ imageRef: CGImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let width = CGFloat(imageRef.width)
        let height = CGFloat(imageRef.height)
        
        var newWidth = width
        var newHeight = height
        if width > maxDimension || height > maxDimension {
            if width > height {
                newWidth = maxDimension
                newHeight = (height / width) * maxDimension
            } else {
                newWidth = (width / height) * maxDimension
                newHeight = maxDimension
            }
        }
        
        // Use the source image's color space so drawing doesn't fail or produce
        // wrong colors when the display uses a wide-gamut profile (e.g. Display P3).
        let colorSpace = imageRef.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // Preserve the original bitmap info (alpha channel, byte order) so the
        // context format matches the source image exactly.
        let bitmapInfo = imageRef.bitmapInfo.rawValue
        // CGContext only supports 8, 16, or 32 bits per component. If the source
        // image has an unusual bit depth (e.g., 10-bit HDR), fall back to 8-bit
        // to avoid context creation failure.
        let bitsPerComponent = [8, 16, 32].contains(imageRef.bitsPerComponent)
            ? imageRef.bitsPerComponent
            : 8
        
        guard let context = CGContext(
            data: nil,
            width: Int(newWidth),
            height: Int(newHeight),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        // SCScreenshotManager.captureImage() returns a CGImage that is
        // already correctly oriented — no flip needed.  Adding a
        // translate+scale transform here would invert the image.
        context.draw(imageRef, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let scaledCGImage = context.makeImage() else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: scaledCGImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
