import Combine
import Foundation

/// A source of live agent sessions. v1 ships `ClaudeCodeProvider`;
/// Cursor/Codex support later means new conformers — nothing else changes.
public protocol AgentProvider: AnyObject {
    /// Human-readable provider name ("Claude Code").
    var providerName: String { get }
    /// Emits the full session list on every change. Must emit on the main queue.
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { get }
    /// True when the provider is running without its reliable signal source
    /// (for Claude Code: hooks declined/unavailable → transcript heuristics only).
    var isLimitedModePublisher: AnyPublisher<Bool, Never> { get }
    /// Start watching. Idempotent.
    func start()
    /// Stop watching and release file-system resources. Idempotent.
    func stop()
}
