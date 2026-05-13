import SwiftUI

struct ActionLog: View {
    @Binding var actions: [Action]

    var body: some View {
        List(actions) { action in
            HStack(spacing: 8) {
                Image(systemName: icon(for: action.type))
                    .foregroundColor(color(for: action.status))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.description)
                        .font(.caption)
                    Text(action.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    private func icon(for type: ActionType) -> String {
        switch type {
        case .click:  return "cursorarrow.click"
        case .type:   return "keyboard"
        case .launch: return "arrow.up.forward.app"
        case .focus:  return "target"
        case .quit:   return "xmark.square"
        }
    }

    private func color(for status: ActionStatus) -> Color {
        switch status {
        case .pending:   return .gray
        case .running:   return .blue
        case .completed: return .green
        case .failed:    return .red
        }
    }
}