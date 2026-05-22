import Foundation

/// Enforces safety policies before the agent executes any action.
///
/// Checks include:
/// - Emergency stop status
/// - Safety mode (full auto / approve-before-action / step-through)
/// - Per-app allowlist validation
/// - Budget limit enforcement
@MainActor
final class SafetyGate {
    /// Reference to the shared application state.
    private let appState: AppState

    /// Pending approval requests awaiting user confirmation.
    private var pendingApprovals: [ApprovalRequest] = []

    /// Continuation for awaiting user approval in approve-before-action mode.
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Checks whether an action is permitted given the current safety state.
    ///
    /// - Parameters:
    ///   - action: A description of the proposed action.
    ///   - targetAppBundleID: The bundle identifier of the target app, if applicable.
    /// - Returns: `true` if the action is allowed, `false` if blocked.
    func checkAction(action: String, targetAppBundleID: String?) async -> Bool {
        // 1. Emergency stop — block everything
        if appState.emergencyStop {
            return false
        }

        // 2. Budget check
        if appState.budgetLimit > 0 && appState.currentCost >= appState.budgetLimit {
            return false
        }

        // 3. App allowlist check
        if let bundleID = targetAppBundleID {
            if !appState.allowedApps.contains(bundleID) {
                return false
            }
        }

        // 4. Safety mode check
        switch appState.safetyMode {
        case .fullAuto:
            // All actions pass automatically
            return true

        case .approveBeforeAction:
            // Wait for user approval
            return await requestApproval(action: action)

        case .stepThrough:
            // Wait for user confirmation for each step
            return await requestApproval(action: action)
        }
    }

    /// Requests user approval for a pending action.
    ///
    /// In approve-before-action and step-through modes, this suspends the
    /// agent loop until the user confirms or denies the action.
    private func requestApproval(action: String) async -> Bool {
        let request = ApprovalRequest(
            action: action,
            timestamp: Date()
        )

        pendingApprovals.append(request)

        // Suspend until the user responds
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    /// Approves the oldest pending approval request.
    func approveOldestPending() {
        guard !pendingApprovals.isEmpty else { return }
        pendingApprovals.removeFirst()
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    /// Denies the oldest pending approval request.
    func denyOldestPending() {
        guard !pendingApprovals.isEmpty else { return }
        pendingApprovals.removeFirst()
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    /// Returns the list of currently pending approval requests.
    func pendingRequests() -> [ApprovalRequest] {
        pendingApprovals
    }

    /// Clears all pending approvals (e.g., on emergency stop).
    func clearAllPending() {
        pendingApprovals.removeAll()
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }
}

/// A single action awaiting user approval.
struct ApprovalRequest: Identifiable {
    let id: UUID = UUID()
    let action: String
    let timestamp: Date
}
