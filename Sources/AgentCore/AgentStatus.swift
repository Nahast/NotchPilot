import Foundation

/// The three status classes NotchPilot distinguishes for a session.
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    /// The agent is actively working on a turn.
    case working
    /// The agent is blocked waiting on the user (permission prompt, question, ...).
    case needsAttention
    /// The turn finished; the session is idle until the user prompts again.
    case idle
}
