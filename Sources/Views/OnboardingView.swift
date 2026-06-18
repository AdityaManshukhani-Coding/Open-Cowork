import SwiftUI
import ApplicationServices
import ScreenCaptureKit
import AppKit

struct OnboardingView: View {
    var onContinue: (() -> Void)? = nil

    @State private var hasAccessibility = false
    @State private var hasScreenRecording = false
    @State private var hasCheckedScreenCaptureKit = false
    @State private var isCheckingScreenCapture = false
    @State private var permissionTimer: Timer?

    // MARK: - Permission Check

    private func checkPermissions(canPrompt: Bool = false) {
        // Check accessibility using both TCC and direct API test
        hasAccessibility = AXIsProcessTrusted() || silentAccessibilityCheck()

        checkScreenRecording(canPrompt: canPrompt)
    }

    /// Silently checks accessibility permission by trying to actually USE
    /// the Accessibility API. AXIsProcessTrusted() checks the TCC database
    /// by binary hash, which breaks on every ad-hoc rebuild. This method
    /// directly tests if the current process can read AX attributes from
    /// other apps — the definitive proof of accessibility permission.
    private func silentAccessibilityCheck() -> Bool {
        // Once verified in this session, keep it
        if hasAccessibility { return true }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        return result == .success
    }

    /// Checks screen recording permission by attempting a real
    /// `SCShareableContent` probe.  This is the ONLY reliable check for
    /// ad-hoc signed debug builds:
    ///
    ///   - `CGPreflightScreenCaptureAccess()` is broken: returns true in
    ///     "pre-flight" state AND with stale TCC entries from old builds.
    ///   - `CGRequestScreenCaptureAccess()` may not persist the grant for
    ///     ad-hoc binaries whose hash changes on rebuild.
    ///   - `tccutil reset` wipes valid permissions, creating loops.
    ///
    /// `SCShareableContent.excludingDesktopWindows()` genuinely throws a
    /// TCC error when the app lacks Screen Recording permission, and
    /// succeeds (with real display data) when permission is granted.
    private func checkScreenRecording(canPrompt: Bool) {
        // Once verified in this session, keep it — macOS force-quits apps
        // when revoking screen recording, so it can't flip mid-session.
        if hasScreenRecording { return }

        // Don't re-probe on timer ticks unless the user clicked Refresh
        guard !hasCheckedScreenCaptureKit || canPrompt else { return }
        guard !isCheckingScreenCapture else { return }

        if #available(macOS 14.0, *) {
            isCheckingScreenCapture = true
            hasCheckedScreenCaptureKit = true

            Task { @MainActor in
                let granted = await Self.probeScreenRecordingPermission()
                isCheckingScreenCapture = false
                hasScreenRecording = granted
                print("[OnboardingView] Screen Recording \(granted ? "granted ✓" : "not granted ✗") (canPrompt=\(canPrompt))")

                if !granted && canPrompt {
                    // User clicked Refresh but permission isn't detected.
                    // Open System Settings so they can toggle it on, then
                    // they can click Refresh again.
                    CGRequestScreenCaptureAccess()
                    openSystemPreferences(pane: "Privacy_ScreenCapture")
                }
            }
        } else {
            // macOS < 14: CGPreflight is the best available check
            hasScreenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    /// Definitive runtime check — attempts `SCShareableContent` to see if
    /// the app can actually enumerate displays.  Throws = no permission.
    @available(macOS 14.0, *)
    private static func probeScreenRecordingPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )
            return !content.displays.isEmpty
        } catch {
            print("[OnboardingView] SCShareableContent probe failed: \(error.localizedDescription)")
            return false
        }
    }



    // MARK: - Restart

    /// Restarts the app WITHOUT rebuilding — preserves the binary hash so
    /// permissions are NOT invalidated.
    ///
    /// Uses `open -n <bundlePath>` (NO `-a` flag!) to force a fresh instance.
    /// The `-a` flag expects an application name, not a full path, so using it
    /// with Bundle.main.bundlePath silently fails.
    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        print("[OnboardingView] Restarting app at path: \(bundlePath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundlePath]

        do {
            try process.run()
            print("[OnboardingView] Successfully spawned new instance via open -n")
        } catch {
            print("[OnboardingView] ERROR: Failed to launch new instance: \(error)")
            // Fallback: use NSWorkspace as a last resort
            let url = URL(fileURLWithPath: bundlePath)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    print("[OnboardingView] ERROR: NSWorkspace fallback also failed: \(error)")
                }
            }
        }

        // Give the new instance time to launch before terminating this one
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("[OnboardingView] Terminating old instance")
            NSApp.terminate(nil)
        }
    }

    // MARK: - System Prefs

    private func openSystemPreferences(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }



    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Header ───────────────────────────────────────────
                VStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 42))
                        .foregroundColor(.primary)
                        .padding(.top, 12)

                    Text("System Permissions")
                        .font(.title2.bold())

                    Text("Open Cowork needs these permissions to control your desktop.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Divider()

                // ── Permission Status Cards ──────────────────────────
                VStack(spacing: 12) {
                    // Accessibility card
                    permissionCard(
                        title: "Accessibility",
                        subtitle: "Simulate mouse clicks & keyboard typing",
                        granted: hasAccessibility,
                        pane: "Privacy_Accessibility",
                        action: {
                                    // Re-prompt for permission
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            AXIsProcessTrustedWithOptions(options as CFDictionary)
                            openSystemPreferences(pane: "Privacy_Accessibility")
                        }
                    )

                    // Screen Recording card
                    permissionCard(
                        title: "Screen Recording",
                        subtitle: "Capture screenshots for AI visual reasoning",
                        granted: hasScreenRecording,
                        pane: "Privacy_ScreenCapture",
                        action: {
                            CGRequestScreenCaptureAccess()
                            openSystemPreferences(pane: "Privacy_ScreenCapture")
                        }
                    )
                }

                // ── All permissions granted ──────────────────────────
                if hasAccessibility && hasScreenRecording {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.primary)
                        Text("All permissions granted!")
                            .font(.body.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 8)
                }

                Divider()

                // ── Action Buttons ───────────────────────────────────
                HStack(spacing: 12) {
                    Button(action: { checkPermissions(canPrompt: true) }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.black)

                    if hasAccessibility && hasScreenRecording, let onContinue = onContinue {
                        Button(action: onContinue) {
                            Label("Continue", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                    } else {
                        Button(action: restartApp) {
                            Label("Restart App", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                    }
                }



                Spacer(minLength: 8)
            }
        }
        .padding(20)
        .onAppear {
            checkPermissions(canPrompt: false)

            // ── TCC Notification Observer ────────────────────────────
            // Listen for macOS TCC changes so the UI updates instantly
            // when the user toggles permissions in System Settings.
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                // Permissions take a moment to propagate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkPermissions(canPrompt: false)
                }
            }

            // ── Polling fallback ─────────────────────────────────────
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                checkPermissions(canPrompt: false)
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: - Permission Card Builder

    @ViewBuilder
    private func permissionCard(
        title: String,
        subtitle: String,
        granted: Bool,
        pane: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(granted ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.body.bold())
                    Text(granted ? "✓" : "✗")
                        .font(.caption.monospaced())
                        .foregroundColor(granted ? .primary : .secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !granted {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }


}
