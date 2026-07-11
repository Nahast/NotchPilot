import AgentCore
import Foundation

/// A status-relevant signal for one session, from either local source.
public enum SessionSignal: Equatable {
    case hookSessionStart
    case hookNotification
    case hookStop
    case hookSessionEnd
    case transcriptAssistantActivity
    case transcriptToolResult
    case transcriptUserPrompt
}

public enum StatusTransition: Equatable {
    case set(AgentStatus)
    case remove
    case keep
}

/// Pure status state machine — the table from design spec §4:
///
/// | Event                       | New status      |
/// |-----------------------------|-----------------|
/// | SessionStart hook           | working         |
/// | Notification hook           | needs attention |
/// | transcript advances again   | working         |
/// | Stop hook                   | idle (done)     |
/// | SessionEnd hook             | session removed |
public enum SessionStateMachine {
    public static func transition(current: AgentStatus?, signal: SessionSignal) -> StatusTransition {
        switch signal {
        case .hookSessionStart:
            return .set(.working)
        case .hookNotification:
            return .set(.needsAttention)
        case .hookStop:
            return .set(.idle)
        case .hookSessionEnd:
            return .remove
        case .transcriptUserPrompt:
            // A fresh human prompt starts a new turn from any state.
            return .set(.working)
        case .transcriptAssistantActivity, .transcriptToolResult:
            switch current {
            case .none:
                // Session discovered mid-turn (app launched while agent runs).
                return .set(.working)
            case .needsAttention:
                // "transcript advances again" — the user unblocked the agent.
                return .set(.working)
            case .working:
                return .keep
            case .idle:
                // Trailing writes right after Stop (summaries, hooks output)
                // must not resurrect a finished turn.
                return .keep
            }
        }
    }
}
