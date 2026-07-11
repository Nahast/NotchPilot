import Foundation

/// The canonical session ordering used everywhere sessions are listed:
/// regular sessions before routines, active before inactive, then
/// needs-attention (longest wait first), working, idle; stable by display
/// name within a class.
public enum AgentSessionOrdering {
    public static func standardSort(_ sessions: [AgentSession]) -> [AgentSession] {
        func rank(_ status: AgentStatus) -> Int {
            switch status {
            case .needsAttention: return 0
            case .working: return 1
            case .idle: return 2
            }
        }
        return sessions.sorted { lhs, rhs in
            if lhs.isRoutine != rhs.isRoutine {
                return !lhs.isRoutine
            }
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            if rank(lhs.status) != rank(rhs.status) {
                return rank(lhs.status) < rank(rhs.status)
            }
            if lhs.stateChangedAt != rhs.stateChangedAt {
                return lhs.stateChangedAt < rhs.stateChangedAt
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
