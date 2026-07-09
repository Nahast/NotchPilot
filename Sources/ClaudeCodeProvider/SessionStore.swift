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
        /// This session was seen in the live session registry at some point.
        var hadRegistryEntry = false
        /// Short derived name from the session registry ("droplet-a1").
        var registryName: String?
        /// Sidebar title from the Claude desktop app — what the user actually
        /// sees, so it wins over the registry name.
        var desktopTitle: String?
        /// The registry marked this session as a non-interactive run.
        var registryIsRoutine = false
        /// The desktop app recorded this session as a scheduled-task run.
        var scheduledTaskId: String?

        /// Applies the display-name precedence to the session value.
        mutating func refreshName() {
            session.name = desktopTitle ?? registryName
        }

        /// Routine = launched by a scheduled task (desktop metadata is ground
        /// truth) or registered as a non-interactive run.
        var isRoutine: Bool {
            scheduledTaskId != nil || registryIsRoutine
        }
    }

    /// Sessions with no registry entry stay "active" for this long after
    /// their last signal (covers headless runs that never register).
    static let activeGraceWindow: TimeInterval = 120

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
        // Prefer the line's own timestamp: parsing a pre-existing transcript
        // at launch must not look like fresh activity.
        let timestamp = event.timestamp ?? now()
        if case .uninteresting = event.kind {
            // Still counts as file activity for staleness purposes.
            touch(sessionId: sessionId, at: timestamp)
            return
        }
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
        if let branch = event.gitBranch, !branch.isEmpty {
            entry.session.gitBranch = branch
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
            if let model = activity.model, !model.isEmpty {
                entry.session.model = model
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

    private func touch(sessionId: String, at timestamp: Date) {
        guard var entry = entries[sessionId] else { return }
        entry.session.lastActivityAt = max(entry.session.lastActivityAt, timestamp)
        entries[sessionId] = entry
    }

    // MARK: Session registry (live processes)

    /// Merges Claude Code's live session registry: alive sessions get their
    /// name/kind and are marked active; sessions that used to be registered
    /// but no longer are (process exited) flip to inactive + idle. Sessions
    /// never registered fall back to a recent-activity grace window.
    func applyRegistry(_ alive: [String: SessionRegistryEntry]) {
        let timestamp = now()

        // Ensure every alive registered session exists and is up to date.
        for (sessionId, registration) in alive {
            var entry = entries[sessionId] ?? Entry(
                session: AgentSession(
                    id: sessionId,
                    projectPath: registration.cwd ?? "",
                    status: .idle,
                    stateChangedAt: timestamp,
                    lastActivityAt: timestamp,
                    isLimitedMode: true
                ),
                hookDriven: false,
                pendingToolUse: false
            )
            entry.hadRegistryEntry = true
            entry.session.isActive = true
            entry.registryName = registration.name ?? entry.registryName
            entry.registryIsRoutine = registration.isRoutine
            entry.refreshName()
            entry.session.isRoutine = entry.isRoutine
            if entry.session.projectPath.isEmpty, let cwd = registration.cwd {
                entry.session.projectPath = cwd
            }
            entries[sessionId] = entry
        }

        // Everything else: previously-registered sessions whose process died
        // are inactive (and can't still be working); unregistered sessions
        // stay active only within the grace window.
        for (sessionId, var entry) in entries where alive[sessionId] == nil {
            let wasActive = entry.session.isActive
            if entry.hadRegistryEntry {
                entry.session.isActive = false
            } else {
                let age = timestamp.timeIntervalSince(entry.session.lastActivityAt)
                entry.session.isActive = age <= Self.activeGraceWindow
            }
            if wasActive, !entry.session.isActive, entry.session.status != .idle {
                entry.session.status = .idle
                entry.session.stateChangedAt = timestamp
            }
            entries[sessionId] = entry
        }
    }

    // MARK: Desktop app metadata

    /// Applies per-session metadata from the Claude desktop app: sidebar
    /// titles (beat registry names), scheduled-task markers (routines), and
    /// attached pull requests. All survive process exit.
    func applyDesktopMetadata(_ metadata: [String: DesktopSessionInfo]) {
        for (sessionId, info) in metadata {
            guard var entry = entries[sessionId] else { continue }
            entry.desktopTitle = info.title ?? entry.desktopTitle
            entry.scheduledTaskId = info.scheduledTaskId ?? entry.scheduledTaskId
            entry.session.pullRequest = info.pullRequest ?? entry.session.pullRequest
            if entry.session.gitBranch == nil {
                entry.session.gitBranch = info.branch
            }
            entry.refreshName()
            entry.session.isRoutine = entry.isRoutine
            entries[sessionId] = entry
        }
    }

    // MARK: Maintenance

    /// Removes sessions with no activity for `timeout` seconds
    /// (crashed CLI / missing SessionEnd). Sessions whose process is alive
    /// (active) are never reaped — an open-but-quiet session is still open.
    @discardableResult
    func reapStale(timeout: TimeInterval) -> Bool {
        let cutoff = now().addingTimeInterval(-timeout)
        let stale = entries.filter {
            !$0.value.session.isActive && $0.value.session.lastActivityAt < cutoff
        }.keys
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
        // Heuristics apply to transcript-only sessions that are still running;
        // a dead process must stay idle no matter how fresh its last write is.
        for (key, var entry) in entries where !entry.hookDriven && entry.session.isActive {
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

    /// Sorted snapshot: regular sessions before routines (routines render as
    /// their own trailing section); active before inactive; then
    /// needs-attention first (longest wait first), working, idle; stable by
    /// display name within a class.
    func snapshot() -> [AgentSession] {
        func rank(_ status: AgentStatus) -> Int {
            switch status {
            case .needsAttention: return 0
            case .working: return 1
            case .idle: return 2
            }
        }
        return entries.values.map(\.session).sorted { lhs, rhs in
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
