import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var expandedSkillName: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agent Skills & Capabilities")
                    .font(.headline)
                Spacer()
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.primary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            ScrollView {
                VStack(spacing: 12) {
                    Text("Skills inject specialized context and instructions into the AI agent loop. Toggle capabilities on or off as needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    ForEach(appStore.skills) { skill in
                        VStack(alignment: .leading, spacing: 0) {
                            // Skill row header
                            HStack {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedSkillName == skill.name {
                                            expandedSkillName = nil
                                        } else {
                                            expandedSkillName = skill.name
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: expandedSkillName == skill.name ? "chevron.down" : "chevron.right")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(skill.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { skill.isEnabled },
                                    set: { _ in
                                        appStore.toggleSkill(name: skill.name)
                                    }
                                ))
                                .toggleStyle(.switch)
                                .scaleEffect(0.8)
                             }
                            .padding()
                            
                            // Expanded detail section
                            if expandedSkillName == skill.name {
                                VStack(alignment: .leading, spacing: 8) {
                                    Divider()
                                    
                                    Text("PROMPT INSTRUCTIONS INJECTED:")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    
                                    Text(skill.systemPromptInstructions)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                        )
                                }
                                .padding([.horizontal, .bottom])
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
        }
    }
}
