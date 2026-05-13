import AppKit
import SwiftUI

final class ChatPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostView = NSHostingView(rootView: ChatPanelView())
        hostView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostView
    }
}

struct ChatPanelView: View {
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var actions: [Action] = []
    @State private var showActionLog: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if showActionLog {
                ActionLog(actions: $actions)
                    .frame(maxHeight: 150)
                    .transition(.move(edge: .bottom))
            }

            Divider()

            HStack {
                Button {
                    withAnimation { showActionLog.toggle() }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundColor(showActionLog ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle action log")

                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendMessage)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)

            CostDisplay()
        }
        .frame(minWidth: 320, minHeight: 400)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let message = Message(role: .user, content: text)
        messages.append(message)
        inputText = ""
    }
}