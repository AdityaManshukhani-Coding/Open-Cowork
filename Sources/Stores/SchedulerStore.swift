import Foundation
import Combine

@MainActor
public class SchedulerStore: ObservableObject {
    private let appStore: AppStore
    private let agentStore: AgentStore
    private var timer: Timer?
    
    public init(appStore: AppStore, agentStore: AgentStore) {
        self.appStore = appStore
        self.agentStore = agentStore
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startTimer() {
        // Run a timer checking every minute. Align with the top of the next minute.
        let calendar = Calendar.current
        let now = Date()
        if let nextMinute = calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) {
            let delay = nextMinute.timeIntervalSince(now)
            
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkSchedules()
                    self?.timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.checkSchedules()
                        }
                    }
                }
            }
        } else {
            // Fallback immediately
            timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkSchedules()
                }
            }
        }
    }
    
    private func checkSchedules() {
        let now = Date()
        for i in 0..<appStore.scheduledTasks.count {
            var task = appStore.scheduledTasks[i]
            guard task.isEnabled else { continue }
            
            if CronMatcher.isDue(expression: task.cronExpression, date: now) {
                print("Scheduler: Running task '\(task.title)' due at \(now)")
                
                // Update run times
                task.lastRunAt = now
                task.nextRunAt = CronMatcher.nextRunDate(for: task.cronExpression, startingFrom: now)
                appStore.updateScheduledTask(task)
                
                // Trigger the agent loop
                agentStore.startTask(task.prompt)
            } else {
                // If nextRunAt is nil or in the past, recalculate it
                if task.nextRunAt == nil || task.nextRunAt! <= now {
                    task.nextRunAt = CronMatcher.nextRunDate(for: task.cronExpression, startingFrom: now)
                    appStore.updateScheduledTask(task)
                }
            }
        }
    }
}
