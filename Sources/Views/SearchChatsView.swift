import SwiftUI

public struct SearchChatsView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var searchText: String = ""
    @Binding var selectedTab: MainPanelView.Tab
    
    var filteredSessions: [TaskSession] {
        if searchText.isEmpty {
            return appStore.sessions
        } else {
            return appStore.sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search all chats...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 16))
            }
            .padding()
            .background(Color.white)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.1)),
                alignment: .bottom
            )
            
            // Results List
            if filteredSessions.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.3))
                        .padding(.bottom, 8)
                    Text("No chats found")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSessions) { session in
                            Button(action: {
                                selectedTab = .conversation(session.id)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                        Text(session.createdAt, style: .date)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider().padding(.leading)
                        }
                    }
                }
            }
        }
    }
}
