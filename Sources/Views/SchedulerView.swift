import SwiftUI

struct SchedulerView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var agentStore: AgentStore
    
    @State private var isShowingAddSheet = false
    @State private var newTitle = ""
    @State private var newPrompt = ""
    @State private var newCron = "*/5 * * * *" // default: every 5 mins
    @State private var cronErrorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Automation Schedules")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isShowingAddSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Tasks List
            if appStore.scheduledTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No schedules created yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Create First Schedule") {
                        isShowingAddSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appStore.scheduledTasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Text(task.cronExpression)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { task.isEnabled },
                                        set: { newValue in
                                            var updated = task
                                            updated.isEnabled = newValue
                                            if newValue {
                                                updated.nextRunAt = CronMatcher.nextRunDate(for: task.cronExpression)
                                            } else {
                                                updated.nextRunAt = nil
                                            }
                                            appStore.updateScheduledTask(updated)
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .scaleEffect(0.8)
                                }
                                
                                Text("\"\(task.prompt)\"")
                                    .font(.caption)
                                    .italic()
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                
                                Divider()
                                
                                HStack {
                                    if task.isEnabled, let nextRun = task.nextRunAt {
                                        Text("Next: \(nextRun, style: .time)")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Disabled")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        agentStore.startTask(task.prompt)
                                    }) {
                                        Text("Run Now")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        if let index = appStore.scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                                            appStore.deleteScheduledTask(at: index)
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
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
        .sheet(isPresented: $isShowingAddSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Automation Schedule")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Daily Backup, Morning check, etc.", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent Task Prompt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("What should the agent do? (e.g. Open Notes and write...)", text: $newPrompt)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cron Expression")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Link("Cron Help", destination: URL(string: "https://crontab.guru")!)
                            .font(.caption2)
                    }
                    TextField("*/5 * * * *", text: $newCron)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newCron) { val in
                            validateCron(val)
                        }
                    
                    if let err = cronErrorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else {
                        if let nextDate = CronMatcher.nextRunDate(for: newCron) {
                            Text("Next run: \(nextDate.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        isShowingAddSheet = false
                        resetForm()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Create") {
                        let task = ScheduledTask(
                            title: newTitle,
                            prompt: newPrompt,
                            cronExpression: newCron,
                            nextRunAt: CronMatcher.nextRunDate(for: newCron)
                        )
                        appStore.addScheduledTask(task)
                        isShowingAddSheet = false
                        resetForm()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              cronErrorMessage != nil)
                }
            }
            .padding()
            .frame(width: 320)
        }
    }
    
    private func validateCron(_ expr: String) {
        let fields = expr.split(separator: " ")
        if fields.count != 5 {
            cronErrorMessage = "Must have exactly 5 fields (min hour day month day-of-week)"
            return
        }
        cronErrorMessage = nil
    }
    
    private func resetForm() {
        newTitle = ""
        newPrompt = ""
        newCron = "*/5 * * * *"
        cronErrorMessage = nil
    }
}
