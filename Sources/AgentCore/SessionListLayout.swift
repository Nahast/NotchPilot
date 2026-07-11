import Foundation

/// Presentation grouping for the expanded panel:
/// - main list capped at `limit` rows — all active sessions first (up to the
///   cap), topped up with the most recently active inactive sessions
/// - routines in their own section at the end, same capping rule
public enum SessionListLayout {
    public struct Groups: Equatable {
        public var active: [AgentSession]
        public var inactive: [AgentSession]
        public var routines: [AgentSession]

        public var isEmpty: Bool {
            active.isEmpty && inactive.isEmpty && routines.isEmpty
        }
    }

    public static func groups(from sessions: [AgentSession], limit: Int = 5) -> Groups {
        let main = sessions.filter { !$0.isRoutine }
        let active = Array(main.filter(\.isActive).prefix(limit))
        let fill = limit - active.count
        let inactive: [AgentSession]
        if fill > 0 {
            inactive = Array(
                main.filter { !$0.isActive }
                    .sorted { $0.lastActivityAt > $1.lastActivityAt }
                    .prefix(fill)
            )
        } else {
            inactive = []
        }

        let allRoutines = sessions.filter(\.isRoutine)
        let activeRoutines = Array(allRoutines.filter(\.isActive).prefix(limit))
        let routineFill = limit - activeRoutines.count
        var routines = activeRoutines
        if routineFill > 0 {
            routines += allRoutines.filter { !$0.isActive }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .prefix(routineFill)
        }

        return Groups(active: active, inactive: inactive, routines: routines)
    }
}
