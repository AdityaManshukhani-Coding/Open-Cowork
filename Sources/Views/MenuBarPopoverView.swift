import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var agentStore: AgentStore
    
    @State private var promptText: String = ""
    
    let onOpenMainApp: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Open Cowork")
                    .font(.headline)
                Spacer()
                Button(action: onOpenMainApp) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .help("Open Main App")
            }
            
            // Status/Controls
            HStack {
                if appStore.activeSession?.status == .running {
                    Button(action: {
                        agentStore.triggerEmergencyStop()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("Stop Agent")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            // Quick Prompt
            TextField("Quick task...", text: $promptText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    if !promptText.isEmpty {
                        // TODO: Implement quick task submission logic here if needed
                        // For now, just open the main app to the chat view
                        onOpenMainApp()
                        promptText = ""
                    }
                }
        }
        .padding()
        .frame(width: 300)
    }
}
