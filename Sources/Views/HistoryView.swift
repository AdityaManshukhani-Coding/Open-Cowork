import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var agentStore: AgentStore
    @State private var expandedSessionId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Task History")
                    .font(.headline)
                Spacer()

                if !appStore.sessions.isEmpty {
                    Button(action: {
                        appStore.clearSessions()
                        expandedSessionId = nil
                    }) {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            if appStore.sessions.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)

                    Text("No task history yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Completed and stopped tasks will appear here for review.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(appStore.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: TaskSession) -> some View {
        let isExpanded = expandedSessionId == session.id

        VStack(alignment: .leading, spacing: 0) {
            // Session summary header (always visible)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSessionId = isExpanded ? nil : session.id
                }
            }) {
                HStack(spacing: 10) {
                    // Status icon
                    Image(systemName: statusIcon(for: session.status))
                        .foregroundColor(statusColor(for: session.status))
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(session.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(session.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("\(session.steps.count) step\(session.steps.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("$\(session.costEstimate, specifier: "%.4f")")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("\(session.inputTokens + session.outputTokens) tokens")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail section
            if isExpanded {
                Divider()
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    // Stats row
                    HStack(spacing: 16) {
                        statLabel("Status", value: statusText(for: session.status))
                        statLabel("Input", value: "\(session.inputTokens) tok")
                        statLabel("Output", value: "\(session.outputTokens) tok")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Steps detail
                    if !session.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Steps")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 6)

                            SelectableTextView(attributedString: historyStepsAttributedString(session))
                        }
                        .padding(.bottom, 8)
                    }

                    // Error messages
                    if let errorStep = session.steps.first(where: { $0.errorMessage != nil }),
                       let errorMsg = errorStep.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMsg)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        // Re-run button
                        Button(action: {
                            agentStore.startTask(session.title)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Re-run")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        // Undo file changes if any
                        if !session.allBackups.isEmpty {
                            Button(action: {
                                FileRollbackManager.shared.rollback(backups: session.allBackups)
                                // Clear backups after rollback
                                var updated = session
                                for i in 0..<updated.steps.count {
                                    updated.steps[i].backups = []
                                }
                                appStore.updateActiveSession(updated)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Undo Files")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }

                        // Delete session
                        Button(action: {
                            if let index = appStore.sessions.firstIndex(where: { $0.id == session.id }) {
                                appStore.sessions.remove(at: index)
                                appStore.saveConfig()
                                if expandedSessionId == session.id {
                                    expandedSessionId = nil
                                }
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func statusIcon(for status: TaskStatus) -> String {
        switch status {
        case .idle: return "circle"
        case .running: return "arrow.triangle.turn.up.right.circle.fill"
        case .paused: return "pause.circle.fill"
        case .waitingApproval: return "hand.raised.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(for status: TaskStatus) -> Color {
        switch status {
        case .idle: return .gray
        case .running: return .blue
        case .paused: return .orange
        case .waitingApproval: return .yellow
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func statusText(for status: TaskStatus) -> String {
        switch status {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused: return "Paused"
        case .waitingApproval: return "Awaiting"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }

    @ViewBuilder
    private func statLabel(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func historyStepsAttributedString(_ session: TaskSession) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        for (index, step) in session.steps.enumerated() {
            // Step header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let statusSymbol = historyStepStatusSymbol(step.status)
            let header = NSAttributedString(string: "\(statusSymbol) Step \(index + 1)\n", attributes: headerAttrs)
            result.append(header)
            
            // Action
            if !step.actionDescription.isEmpty {
                let actionAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.textColor
                ]
                let action = NSAttributedString(string: step.actionDescription + "\n", attributes: actionAttrs)
                result.append(action)
            }
            
            // Thought
            if !step.thought.isEmpty {
                let thoughtAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
                let thought = NSAttributedString(string: step.thought + "\n", attributes: thoughtAttrs)
                result.append(thought)
            }
            
            // Error
            if let errMsg = step.errorMessage {
                let errorAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.systemRed
                ]
                let error = NSAttributedString(string: errMsg + "\n", attributes: errorAttrs)
                result.append(error)
            }
            
            // Separator between steps
            if index < session.steps.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        return result
    }
    
    private func historyStepStatusSymbol(_ status: StepStatus) -> String {
        switch status {
        case .pending: return "⏳"
        case .approved: return "✓"
        case .executing: return "⋯"
        case .completed: return "✓"
        case .failed: return "✗"
        case .skipped: return "⊘"
        }
    }

}
