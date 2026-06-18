import Foundation

public struct CronMatcher {
    public static func isDue(expression: String, date: Date = Date()) -> Bool {
        let fields = expression.split(separator: " ").map { String($0) }
        guard fields.count == 5 else { return false }
        
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)
        let dayOfMonth = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        
        // Calendar component for weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        // Cron day of week: 0-6 (0 = Sunday, 1 = Monday, ..., 6 = Saturday) or 7 = Sunday
        let weekdayComponent = calendar.component(.weekday, from: date)
        let dayOfWeek = (weekdayComponent - 1)
        
        guard matchField(fields[0], value: minute, range: 0...59) else { return false }
        guard matchField(fields[1], value: hour, range: 0...23) else { return false }
        guard matchField(fields[2], value: dayOfMonth, range: 1...31) else { return false }
        guard matchField(fields[3], value: month, range: 1...12) else { return false }
        
        let dowField = fields[4]
        if dowField == "*" {
            return true
        }
        let matchedDow = matchField(dowField, value: dayOfWeek, range: 0...7)
        let matchedSundayFallback = (dayOfWeek == 0) && matchField(dowField, value: 7, range: 0...7)
        return matchedDow || matchedSundayFallback
    }
    
    public static func nextRunDate(for expression: String, startingFrom date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var current = date
        
        // Round to the current minute
        if let currentMinute = calendar.date(bySetting: .second, value: 0, of: current) {
            current = currentMinute
        }
        
        // Limit search to 1 week (10080 minutes) to avoid infinite loops
        for _ in 1...10080 {
            current = calendar.date(byAdding: .minute, value: 1, to: current) ?? current
            if isDue(expression: expression, date: current) {
                return current
            }
        }
        return nil
    }
    
    private static func matchField(_ field: String, value: Int, range: ClosedRange<Int>) -> Bool {
        if field == "*" { return true }
        
        // Handle lists (e.g. 1,3,5)
        if field.contains(",") {
            let parts = field.split(separator: ",")
            for part in parts {
                if matchField(String(part), value: value, range: range) {
                    return true
                }
            }
            return false
        }
        
        // Handle steps (e.g. */5)
        if field.hasPrefix("*/") {
            guard let step = Int(field.dropFirst(2)) else { return false }
            return value % step == 0
        }
        
        // Handle ranges (e.g. 1-5)
        if field.contains("-") {
            let parts = field.split(separator: "-")
            guard parts.count == 2,
                  let start = Int(parts[0]),
                  let end = Int(parts[1]) else { return false }
            return (start...end).contains(value)
        }
        
        // Handle exact match
        if let exact = Int(field) {
            return exact == value
        }
        
        return false
    }
}
