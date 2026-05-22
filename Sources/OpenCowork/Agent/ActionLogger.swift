import Foundation

/// Records every action the agent takes with timestamps, descriptions,
/// and status indicators.  Entries are appended to the shared AppState
/// so the UI can display them in real time.
@MainActor
final class ActionLogger {
    /// Reference to the shared application state.
    private let appState: AppState

    /// The date formatter for timestamp display.
    private let dateFormatter: DateFormatter

    init(appState: AppState) {
        self.appState = appState
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    /// Logs an action with the given parameters.
    ///
    /// - Parameters:
    ///   - action: A short label for the action (e.g., "Click", "Type", "Screenshot").
    ///   - detail: A longer description of what happened.
    ///   - status: The outcome status of the action.
    func log(action: String, detail: String, status: ActionStatus) {
        let entry = ActionLogEntry(
            action: action,
            detail: detail,
            status: status
        )
        appState.logAction(entry)
    }

    /// Returns a formatted timestamp string for the current time.
    func formattedTimestamp() -> String {
        dateFormatter.string(from: Date())
    }
}
