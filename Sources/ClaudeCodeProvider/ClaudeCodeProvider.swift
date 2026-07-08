import AgentCore
import Combine
import Foundation

/// v1 `AgentProvider`: watches Claude Code hook-event spool files (reliable
/// status signal) and JSONL transcripts (activity + context gauge). All local,
/// no sockets, no network (design spec §4).
public final class ClaudeCodeProvider: AgentProvider {
    public struct Configuration {
        /// `~/.claude`
        public var claudeHome: URL
        /// Spool directory the notchpilot-hook helper writes into.
        public var eventsDirectory: URL
        /// Sessions with no signal for this long are reaped (crashed CLI).
        public var stalenessTimeout: () -> TimeInterval
        /// Fallback rescan cadence; FSEvents normally fires much sooner.
        public var pollInterval: TimeInterval
        public var fsEventsLatency: TimeInterval
        /// Whether our hooks are currently registered in settings.json —
        /// false means the provider labels itself "limited mode".
        public var hooksInstalled: () -> Bool

        public init(
            claudeHome: URL = ClaudeCodePaths.defaultClaudeHome,
            eventsDirectory: URL = ClaudeCodePaths.defaultEventsDirectory,
            stalenessTimeout: @escaping () -> TimeInterval = { 30 * 60 },
            pollInterval: TimeInterval = 2.0,
            fsEventsLatency: TimeInterval = 0.2,
            hooksInstalled: @escaping () -> Bool = { false }
        ) {
            self.claudeHome = claudeHome
            self.eventsDirectory = eventsDirectory
            self.stalenessTimeout = stalenessTimeout
            self.pollInterval = pollInterval
            self.fsEventsLatency = fsEventsLatency
            self.hooksInstalled = hooksInstalled
        }
    }

    public let providerName = "Claude Code"

    public var sessionsPublisher: AnyPublisher<[AgentSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    public var isLimitedModePublisher: AnyPublisher<Bool, Never> {
        limitedModeSubject.eraseToAnyPublisher()
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.rjouffret.NotchPilot.ClaudeCodeProvider")
    private let store = SessionStore()
    private let tailer = TranscriptTailer()
    private let sessionsSubject = CurrentValueSubject<[AgentSession], Never>([])
    private let limitedModeSubject = CurrentValueSubject<Bool, Never>(false)
    private var watchers: [FSEventsWatcher] = []
    private var pollTimer: DispatchSourceTimer?
    private var isRunning = false
    private var lastPublished: [AgentSession]?

    public init(configuration: Configuration = Configuration()) {
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

            var watchPaths: [String] = [self.configuration.eventsDirectory.path]
            let projectsDir = self.projectsDirectory
            if FileManager.default.fileExists(atPath: projectsDir.path) {
                watchPaths.append(projectsDir.path)
            } else if FileManager.default.fileExists(atPath: self.configuration.claudeHome.path) {
                // projects/ appears after the first session; watch the parent.
                watchPaths.append(self.configuration.claudeHome.path)
            }

            let watcher = FSEventsWatcher(
                paths: watchPaths,
                latency: self.configuration.fsEventsLatency,
                queue: self.queue
            ) { [weak self] in
                self?.scan()
            }
            watcher.start()
            self.watchers = [watcher]

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

    /// Forces a rescan (tests, manual refresh).
    public func rescanNow() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    private func stopOnQueue() {
        guard isRunning else { return }
        isRunning = false
        watchers.forEach { $0.stop() }
        watchers = []
        pollTimer?.cancel()
        pollTimer = nil
    }

    private var projectsDirectory: URL {
        configuration.claudeHome.appendingPathComponent("projects", isDirectory: true)
    }

    // MARK: Scanning (queue-confined)

    private func scan() {
        processHookEvents()
        scanTranscripts()
        store.reapStale(timeout: configuration.stalenessTimeout())
        store.recomputeLimitedStatuses()
        publishIfChanged()
    }

    private func processHookEvents() {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(
            atPath: configuration.eventsDirectory.path
        ) else { return }

        var events: [HookEvent] = []
        for name in names where name.hasSuffix(".json") {
            let url = configuration.eventsDirectory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let event = HookEvent.decode(from: data) {
                events.append(event)
            }
            // Consume the spool file either way — undecodable files must not
            // pile up or be retried forever.
            try? fileManager.removeItem(at: url)
        }

        // Apply in emission order: the helper stamps np_received_at with
        // sub-millisecond precision, which beats filename sorting when two
        // events land in the same millisecond.
        for event in events.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            store.apply(hook: event)
        }
    }

    private func scanTranscripts() {
        let fileManager = FileManager.default
        let projectsDir = projectsDirectory
        guard let enumerator = fileManager.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let staleCutoff = Date().addingTimeInterval(-configuration.stalenessTimeout())

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path

            // Don't parse historical transcripts that predate the staleness
            // window — but keep tailing files we already track.
            if !tailer.isKnown(path) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                guard modified >= staleCutoff else { continue }
            }

            let fallbackSessionId = url.deletingPathExtension().lastPathComponent
            let fallbackProjectPath = url.deletingLastPathComponent().lastPathComponent

            for lineData in tailer.readNewLines(at: path) {
                guard let event = TranscriptLineParser.parse(lineData) else { continue }
                store.apply(
                    transcript: event,
                    fallbackSessionId: fallbackSessionId,
                    fallbackProjectPath: fallbackProjectPath
                )
            }
        }
    }

    private func publishIfChanged() {
        let snapshot = store.snapshot()
        let limited = !configuration.hooksInstalled()

        if limited != limitedModeSubject.value {
            DispatchQueue.main.async { [limitedModeSubject] in
                limitedModeSubject.send(limited)
            }
        }
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        DispatchQueue.main.async { [sessionsSubject] in
            sessionsSubject.send(snapshot)
        }
    }
}

/// Well-known locations, overridable for tests and fixtures.
public enum ClaudeCodePaths {
    public static var defaultClaudeHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    public static var defaultApplicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NotchPilot", isDirectory: true)
    }

    public static var defaultEventsDirectory: URL {
        defaultApplicationSupport.appendingPathComponent("events", isDirectory: true)
    }

    public static var defaultHelperInstallURL: URL {
        defaultApplicationSupport
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("notchpilot-hook")
    }

    /// True when Claude Code appears to be installed for this user.
    public static func isClaudeCodeDetected(home: URL = defaultClaudeHome) -> Bool {
        FileManager.default.fileExists(atPath: home.path)
    }
}
