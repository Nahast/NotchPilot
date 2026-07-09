import AgentCore
import Combine
import Foundation
import ProviderCore

/// `AgentProvider` for Cursor: consumes hook events spooled by the
/// notchpilot-hook helper (registered in `~/.cursor/hooks.json`).
/// Cursor keeps no locally-readable transcripts, so hooks are the signal:
/// prompt submitted → working, file edited → working + activity,
/// stop → idle.
public final class CursorProvider: AgentProvider {
    public struct Configuration {
        /// Spool directory for Cursor hook events.
        public var eventsDirectory: URL
        public var stalenessTimeout: () -> TimeInterval
        public var pollInterval: TimeInterval
        public var fsEventsLatency: TimeInterval

        public init(
            eventsDirectory: URL,
            stalenessTimeout: @escaping () -> TimeInterval = { 30 * 60 },
            pollInterval: TimeInterval = 2.0,
            fsEventsLatency: TimeInterval = 0.2
        ) {
            self.eventsDirectory = eventsDirectory
            self.stalenessTimeout = stalenessTimeout
            self.pollInterval = pollInterval
            self.fsEventsLatency = fsEventsLatency
        }
    }

    public let providerName = "Cursor"

    public var sessionsPublisher: AnyPublisher<[AgentSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    public var isLimitedModePublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    public var tokenTallyPublisher: AnyPublisher<TokenTally?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    static let activeGraceWindow: TimeInterval = 120

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.rjouffret.NotchPilot.CursorProvider")
    private let sessionsSubject = CurrentValueSubject<[AgentSession], Never>([])
    private var sessions: [String: AgentSession] = [:]
    private var watcher: FSEventsWatcher?
    private var pollTimer: DispatchSourceTimer?
    private var isRunning = false
    private var lastPublished: [AgentSession]?
    /// Injectable clock for tests.
    var now: () -> Date = { Date() }

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    deinit {
        stopOnQueue()
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true

            try? FileManager.default.createDirectory(
                at: self.configuration.eventsDirectory,
                withIntermediateDirectories: true
            )

            let watcher = FSEventsWatcher(
                paths: [self.configuration.eventsDirectory.path],
                latency: self.configuration.fsEventsLatency,
                queue: self.queue
            ) { [weak self] in
                self?.scan()
            }
            watcher.start()
            self.watcher = watcher

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

    // MARK: Scanning (queue-confined)

    private func scan() {
        processSpool()
        refreshLiveness()
        reapStale()
        publishIfChanged()
    }

    private func processSpool() {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(
            atPath: configuration.eventsDirectory.path
        ) else { return }

        var events: [(receivedAt: Date, payload: [String: Any])] = []
        for name in names where name.hasSuffix(".json") {
            let url = configuration.eventsDirectory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any] {
                let receivedAt = (dictionary["np_received_at"] as? Double)
                    .map(Date.init(timeIntervalSince1970:)) ?? Date()
                events.append((receivedAt, dictionary))
            }
            try? fileManager.removeItem(at: url)
        }

        for event in events.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            apply(event.payload, at: event.receivedAt)
        }
    }

    private func apply(_ payload: [String: Any], at timestamp: Date) {
        guard let eventName = payload["np_event_name"] as? String,
              eventName.hasPrefix("Cursor"),
              let sessionId = payload["conversation_id"] as? String, !sessionId.isEmpty
        else { return }

        let workspace = (payload["workspace_roots"] as? [String])?.first
            ?? payload["cwd"] as? String

        var session = sessions[sessionId] ?? AgentSession(
            id: sessionId,
            projectPath: workspace ?? "",
            status: .working,
            stateChangedAt: timestamp,
            lastActivityAt: timestamp,
            agentKind: .cursor
        )
        if let workspace, !workspace.isEmpty {
            session.projectPath = workspace
        }
        session.lastActivityAt = max(session.lastActivityAt, timestamp)

        func setStatus(_ status: AgentStatus) {
            if session.status != status {
                session.status = status
                session.stateChangedAt = timestamp
            }
        }

        switch eventName {
        case "CursorPromptSubmit":
            setStatus(.working)
            session.activity = "Working…"
        case "CursorFileEdit":
            setStatus(.working)
            if let filePath = payload["file_path"] as? String, !filePath.isEmpty {
                session.activity = "Editing \((filePath as NSString).lastPathComponent)…"
            } else {
                session.activity = "Editing files…"
            }
        case "CursorStop":
            setStatus(.idle)
            session.activity = "Done"
        default:
            break
        }

        sessions[sessionId] = session
    }

    private func refreshLiveness() {
        let cutoff = now().addingTimeInterval(-Self.activeGraceWindow)
        for (id, var session) in sessions {
            let active = session.lastActivityAt >= cutoff
            guard session.isActive != active else { continue }
            session.isActive = active
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
