import SwiftUI

struct ChatBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .padding(10)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(12)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            if message.role == .agent {
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}