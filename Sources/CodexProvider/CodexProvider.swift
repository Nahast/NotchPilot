import AgentCore
import Combine
import Foundation
import ProviderCore

/// `AgentProvider` for OpenAI Codex: tails rollout transcripts under
/// `~/.codex/sessions/` (task lifecycle events are written in real time) and
/// takes session names from `~/.codex/session_index.jsonl`. All local.
public final class CodexProvider: AgentProvider {
    public struct Configuration {
        public var codexHome: URL
        public var stalenessTimeout: () -> TimeInterval
        public var pollInterval: TimeInterval
        public var fsEventsLatency: TimeInterval

        public init(
            codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true),
            stalenessTimeout: @escaping () -> TimeInterval = { 30 * 60 },
            pollInterval: TimeInterval = 2.0,
            fsEventsLatency: TimeInterval = 0.2
        ) {
            self.codexHome = codexHome
            self.stalenessTimeout = stalenessTimeout
            self.pollInterval = pollInterval
            self.fsEventsLatency = fsEventsLatency
        }
    }

    public let providerName = "Codex"

    public var sessionsPublisher: AnyPublisher<[AgentSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    /// Codex statuses come from explicit transcript events — never "limited".
    public var isLimitedModePublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var tokenTallyPublisher: AnyPublisher<TokenTally?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    /// Sessions with no writes for this long count as inactive.
    static let activeGraceWindow: TimeInterval = 120

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.rjouffret.NotchPilot.CodexProvider")
    private let tailer = TranscriptTailer()
    private let index: CodexSessionIndex
    private let sessionsSubject = CurrentValueSubject<[AgentSession], Never>([])
    private var sessions: [String: AgentSession] = [:]
    private var watcher: FSEventsWatcher?
    private var pollTimer: DispatchSourceTimer?
    private var isRunning = false
    private var lastPublished: [AgentSession]?
    /// Injectable clock for tests.
    var now: () -> Date = { Date() }

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.index = CodexSessionIndex(
            url: configuration.codexHome.appendingPathComponent("session_index.jsonl")
        )
    }

    deinit {
        stopOnQueue()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true

            let sessionsDir = self.sessionsDirectory
            if FileManager.default.fileExists(atPath: sessionsDir.path) {
                let watcher = FSEventsWatcher(
                    paths: [sessionsDir.path],
                    latency: self.configuration.fsEventsLatency,
                    queue: self.queue
                ) { [weak self] in
                    self?.scan()
                }
                watcher.start()
                self.watcher = watcher
            }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + self.configuration.pollInterval,
                repeating: self.configuration.pollInterval
            )
            timer.setEventHandler { [weak self] in
                self?.scan()
            }
            timer.resume()
            self.pollTimer = timer

            self.scan()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    public func rescanNow() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    private func stopOnQueue() {
        guard isRunning else { return }
        isRunning = false
        watcher?.stop()
        watcher = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    private var sessionsDirectory: URL {
        configuration.codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    // MARK: Scanning (queue-confined)

    private func scan() {
        scanRollouts()
        applyNames()
        refreshLiveness()
        reapStale()
        publishIfChanged()
    }

    private func scanRollouts() {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let staleCutoff = now().addingTimeInterval(-configuration.stalenessTimeout())

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let sessionId = CodexRolloutParser.sessionId(fromFilename: url.lastPathComponent)
            else { continue }
            let path = url.path

            if !tailer.isKnown(path) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard modified >= staleCutoff else { continue }
            }

            for lineData in tailer.readNewLines(at: path).lines {
                guard let event = CodexRolloutParser.parse(lineData) else { continue }
                apply(event, sessionId: sessionId)
            }
        }
    }

    private func apply(_ event: CodexEvent, sessionId: String) {
        let timestamp = event.timestamp ?? now()
        var session = sessions[sessionId] ?? AgentSession(
            id: sessionId,
            projectPath: "",
            status: .working,
            stateChangedAt: timestamp,
            lastActivityAt: timestamp,
            agentKind: .codex
        )
        session.lastActivityAt = max(session.lastActivityAt, timestamp)

        func setStatus(_ status: AgentStatus) {
            if session.status != status {
                session.status = status
                session.stateChangedAt = timestamp
            }
        }

        switch event.kind {
        case let .sessionMeta(cwd):
            if let cwd, !cwd.isEmpty {
                session.projectPath = cwd
            }
        case .taskStarted, .userMessage:
            setStatus(.working)
        case .taskComplete:
            setStatus(.idle)
            session.activity = "Done"
        case let .agentActivity(description):
            setStatus(.working)
            session.activity = description
        case .approvalRequest:
            setStatus(.needsAttention)
            session.activity = "Waiting for your approval"
        case let .tokenCount(usedTokens, contextWindow):
            session.contextUsedTokens = usedTokens ?? session.contextUsedTokens
            session.contextWindowTokens = contextWindow ?? session.contextWindowTokens
        case .uninteresting:
            break
        }

        sessions[sessionId] = session
    }

    private func applyNames() {
        let names = index.threadNames()
        for (id, var session) in sessions {
            if let name = names[id], session.name != name {
                session.name = name
                sessions[id] = session
            }
        }
    }

    private func refreshLiveness() {
        let cutoff = now().addingTimeInterval(-Self.activeGraceWindow)
        for (id, var session) in sessions {
            let active = session.lastActivityAt >= cutoff
            guard session.isActive != active else { continue }
            session.isActive = active
            // A silent Codex process can't still be working.
            if !active, session.status != .idle {
                session.status = .idle
                session.stateChangedAt = now()
            }
            sessions[id] = session
        }
    }

    private func reapStale() {
        let cutoff = now().addingTimeInterval(-configuration.stalenessTimeout())
        for (id, session) in sessions
        where !session.isActive && session.lastActivityAt < cutoff {
            sessions[id] = nil
        }
    }

    private func publishIfChanged() {
        let snapshot = AgentSessionOrdering.standardSort(Array(sessions.values))
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        DispatchQueue.main.async { [sessionsSubject] in
            sessionsSubject.send(snapshot)
        }
    }
}
