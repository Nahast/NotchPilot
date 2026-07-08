import AgentCore
import Foundation

/// Central mutable session state. Not thread-safe by itself — the provider
/// confines all access to its serial queue.
final class SessionStore {
    struct Entry {
        var session: AgentSession
        /// At least one hook event seen for this session → status is hook-driven.
        var hookDriven: Bool
        /// Assistant issued a tool_use and no tool_result arrived yet.
        var pendingToolUse: Bool
    }

    private(set) var entries: [String: Entry] = [:]
    /// Injectable clock for tests.
    var now: () -> Date = { Date() }

    // MARK: Hook events

    func apply(hook event: HookEvent) {
        let timestamp = event.receivedAt
        let signal: SessionSignal
        switch event.name {
        case .sessionStart: signal = .hookSessionStart
        case .notification: signal = .hookNotification
        case .stop: signal = .hookStop
        case .sessionEnd: signal = .hookSessionEnd
        }

        var entry = entries[event.sessionId] ?? Entry(
            session: AgentSession(
                id: event.sessionId,
                projectPath: event.cwd ?? "",
                status: .working,
                stateChangedAt: timestamp,
                lastActivityAt: timestamp
            ),
            hookDriven: true,
            pendingToolUse: false
        )
        entry.hookDriven = true
        entry.session.isLimitedMode = false
        if let cwd = event.cwd, !cwd.isEmpty {
            entry.session.projectPath = cwd
        }
        entry.session.lastActivityAt = timestamp

        switch SessionStateMachine.transition(current: entries[event.sessionId]?.session.status, signal: signal) {
        case .remove:
            entries[event.sessionId] = nil
            return
        case let .set(status):
            if entries[event.sessionId]?.session.status != status {
                entry.session.stateChangedAt = timestamp
            }
            entry.session.status = status
        case .keep:
            break
        }

        if event.name == .notification {
            entry.session.activity = event.message ?? "Waiting for your approval"
        } else if event.name == .stop {
            entry.session.activity = "Done"
        }

        entries[event.sessionId] = entry
    }

    // MARK: Transcript events

    /// - Parameter fallbackSessionId: session id derived from the transcript
    ///   file name (`<uuid>.jsonl`), used when the line carries none.
    /// - Parameter fallbackProjectPath: display path derived from the
    ///   transcript's parent directory, used when no cwd is known.
    func apply(
        transcript event: TranscriptEvent,
        fallbackSessionId: String,
        fallbackProjectPath: String
    ) {
        let sessionId = event.sessionId ?? fallbackSessionId
        guard !sessionId.isEmpty else { return }
        if case .uninteresting = event.kind {
            // Still counts as file activity for staleness purposes.
            touch(sessionId: sessionId)
            return
        }

        let timestamp = now()
        var entry = entries[sessionId] ?? Entry(
            session: AgentSession(
                id: sessionId,
                projectPath: event.cwd ?? fallbackProjectPath,
                status: .working,
                stateChangedAt: timestamp,
                lastActivityAt: timestamp,
                isLimitedMode: true
            ),
            hookDriven: false,
            pendingToolUse: false
        )
        if let cwd = event.cwd, !cwd.isEmpty {
            entry.session.projectPath = cwd
        }
        entry.session.lastActivityAt = timestamp

        let signal: SessionSignal
        switch event.kind {
        case .assistantActivity: signal = .transcriptAssistantActivity
        case .toolResult: signal = .transcriptToolResult
        case .userPrompt: signal = .transcriptUserPrompt
        case .uninteresting: return // handled above
        }

        switch SessionStateMachine.transition(current: entries[sessionId]?.session.status, signal: signal) {
        case .remove:
            entries[sessionId] = nil
            return
        case let .set(status):
            if entries[sessionId]?.session.status != status {
                entry.session.stateChangedAt = timestamp
            }
            entry.session.status = status
        case .keep:
            break
        }

        switch event.kind {
        case let .assistantActivity(activity):
            if let description = activity.activityDescription {
                entry.session.activity = description
            }
            if let used = activity.contextUsedTokens {
                entry.session.contextUsedTokens = used
                entry.session.contextWindowTokens = ModelContextTable.contextWindow(for: activity.model)
            }
            entry.pendingToolUse = activity.issuedToolUse
        case .toolResult:
            entry.pendingToolUse = false
        case .userPrompt:
            entry.session.activity = "Working…"
            entry.pendingToolUse = false
        case .uninteresting:
            break
        }

        entries[sessionId] = entry
    }

    private func touch(sessionId: String) {
        guard var entry = entries[sessionId] else { return }
        entry.session.lastActivityAt = now()
        entries[sessionId] = entry
    }

    // MARK: Maintenance

    /// Removes sessions with no activity for `timeout` seconds
    /// (crashed CLI / missing SessionEnd). Returns true if anything changed.
    @discardableResult
    func reapStale(timeout: TimeInterval) -> Bool {
        let cutoff = now().addingTimeInterval(-timeout)
        let stale = entries.filter { $0.value.session.lastActivityAt < cutoff }.keys
        guard !stale.isEmpty else { return false }
        for key in stale { entries[key] = nil }
        return true
    }

    /// Re-derives statuses for transcript-only (limited mode) sessions:
    /// recent writes = working; mid-turn stall = probably waiting;
    /// long silence = idle. Returns true if anything changed.
    @discardableResult
    func recomputeLimitedStatuses(
        workingWindow: TimeInterval = 15,
        stallWindow: TimeInterval = 20,
        idleWindow: TimeInterval = 120
    ) -> Bool {
        var changed = false
        let currentTime = now()
        for (key, var entry) in entries where !entry.hookDriven {
            entry.session.isLimitedMode = true
            let age = currentTime.timeIntervalSince(entry.session.lastActivityAt)
            let derived: AgentStatus
            if age <= workingWindow {
                derived = .working
            } else if entry.pendingToolUse, age > stallWindow {
                derived = .needsAttention
            } else if age > idleWindow {
                derived = .idle
            } else {
                derived = entry.session.status
            }
            if derived != entry.session.status {
                entry.session.status = derived
                entry.session.stateChangedAt = currentTime
                if derived == .needsAttention {
                    entry.session.activity = "Probably waiting on you"
                }
                changed = true
            }
            if entry.session.isLimitedMode != entries[key]?.session.isLimitedMode {
                changed = true
            }
            entries[key] = entry
        }
        return changed
    }

    /// Sorted snapshot: needs-attention first (longest wait first), then
    /// working, then idle; stable by project name within a class.
    func snapshot() -> [AgentSession] {
        func rank(_ status: AgentStatus) -> Int {
            switch status {
            case .needsAttention: return 0
            case .working: return 1
            case .idle: return 2
            }
        }
        return entries.values.map(\.session).sorted { lhs, rhs in
            if rank(lhs.status) != rank(rhs.status) {
                return rank(lhs.status) < rank(rhs.status)
            }
            if lhs.stateChangedAt != rhs.stateChangedAt {
                return lhs.stateChangedAt < rhs.stateChangedAt
            }
            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
        }
    }
}
