import Foundation

public enum SafetyMode: String, Codable, CaseIterable, Identifiable {
    case fullAuto = "Full Auto"
    case approveBeforeAction = "Approve Before Action"
    case stepThrough = "Step Through"

    public var id: String { self.rawValue }

    public var description: String {
        switch self {
        case .fullAuto:
            return "All actions execute automatically without asking for confirmation."
        case .approveBeforeAction:
            return "You must approve each action before the agent executes it."
        case .stepThrough:
            return "You must approve each action before execution, and confirm after each step completes."
        }
    }
    
    public var displayName: String {
        switch self {
        case .fullAuto: return "Full Auto"
        case .approveBeforeAction: return "Approve"
        case .stepThrough: return "Step Through"
        }
    }
}
