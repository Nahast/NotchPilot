import AgentCore
import Combine
@testable import ClaudeCodeProvider
import XCTest

/// Integration: provider pointed at a fake `~/.claude` fixture tree; inject
/// spool events; assert the published session list (design spec §7).
final class ClaudeCodeProviderIntegrationTests: XCTestCase {
    private var fixtureRoot: URL!
    private var claudeHome: URL!
    private var eventsDir: URL!
    private var projectDir: URL!
    private var provider: ClaudeCodeProvider!
    private var cancellables: Set<AnyCancellable> = []

    private let sessionId = "22222222-2222-2222-2222-222222222222"

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotchPilotTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        claudeHome = fixtureRoot.appendingPathComponent(".claude", isDirectory: true)
        eventsDir = fixtureRoot.appendingPathComponent("events", isDirectory: true)
        projectDir = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-Users-romain-Projects-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        provider = ClaudeCodeProvider(configuration: .init(
            claudeHome: claudeHome,
            eventsDirectory: eventsDir,
            stalenessTimeout: { 30 * 60 },
            pollInterval: 0.15,
            fsEventsLatency: 0.05,
            hooksInstalled: { true }
        ))
    }

    override func tearDownWithError() throws {
        provider.stop()
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: fixtureRoot)
        try super.tearDownWithError()
    }

    private var transcriptURL: URL {
        projectDir.appendingPathComponent("\(sessionId).jsonl")
    }

    private func appendTranscriptLine(_ line: String) throws {
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: transcriptURL.path) {
            let handle = try FileHandle(forWritingTo: transcriptURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: transcriptURL)
        }
    }

    private func spoolHookEvent(_ name: String, extra: [String: Any] = [:]) throws {
        var payload: [String: Any] = [
            "hook_event_name": name,
            "session_id": sessionId,
            "cwd": "/Users/romain/Projects/demo",
            "np_received_at": Date().timeIntervalSince1970,
        ]
        payload.merge(extra) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let filename = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
        try data.write(to: eventsDir.appendingPathComponent(filename))
    }

    /// Waits until the published session list satisfies the predicate.
    private func waitForSessions(
        timeout: TimeInterval = 5,
        description: String,
        where predicate: @escaping ([AgentSession]) -> Bool
    ) {
        let expectation = expectation(description: description)
        expectation.assertForOverFulfill = false
        provider.sessionsPublisher
            .filter(predicate)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        provider.rescanNow()
        wait(for: [expectation], timeout: timeout)
    }

    private func assistantLine(activityFile: String, tokens: Int) -> String {
        """
        {"isSidechain":false,"cwd":"/Users/romain/Projects/demo","sessionId":"\(sessionId)","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"\(activityFile)"}}],"usage":{"input_tokens":\(tokens),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """
    }

    func testHookEventCreatesSessionAndTranscriptFillsActivity() throws {
        provider.start()

        try spoolHookEvent("SessionStart")
        waitForSessions(description: "session appears working") { sessions in
            sessions.count == 1 && sessions[0].status == .working && sessions[0].projectName == "demo"
        }

        try appendTranscriptLine(assistantLine(activityFile: "/Users/romain/Projects/demo/main.swift", tokens: 50_000))
        waitForSessions(description: "activity + gauge from transcript") { sessions in
            sessions.first?.activity == "Editing main.swift…"
                && sessions.first?.contextUsedTokens == 50_000
                && sessions.first?.contextWindowTokens == 200_000
        }
    }

    func testNotificationThenTranscriptAdvanceFlipsStatus() throws {
        provider.start()
        try spoolHookEvent("SessionStart")
        try spoolHookEvent("Notification", extra: ["message": "Claude needs your permission to use Bash"])
        waitForSessions(description: "needs attention") { sessions in
            sessions.first?.status == .needsAttention
                && sessions.first?.activity == "Claude needs your permission to use Bash"
        }

        try appendTranscriptLine(assistantLine(activityFile: "/x/y.swift", tokens: 100))
        waitForSessions(description: "back to working") { sessions in
            sessions.first?.status == .working
        }
    }

    func testStopThenSessionEndLifecycle() throws {
        provider.start()
        try spoolHookEvent("SessionStart")
        try spoolHookEvent("Stop")
        waitForSessions(description: "idle after Stop") { sessions in
            sessions.first?.status == .idle
        }

        try spoolHookEvent("SessionEnd")
        waitForSessions(description: "removed after SessionEnd") { sessions in
            sessions.isEmpty
        }
    }

    func testSpoolFilesAreConsumed() throws {
        provider.start()
        try spoolHookEvent("SessionStart")
        waitForSessions(description: "session exists") { !$0.isEmpty }

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: eventsDir.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertTrue(leftovers.isEmpty, "spool files must be deleted after processing")
    }

    func testTranscriptOnlySessionDiscoveredInLimitedShape() throws {
        provider.start()
        // No hook events at all — session discovered from transcript alone.
        try appendTranscriptLine(assistantLine(activityFile: "/a/b.swift", tokens: 10))
        waitForSessions(description: "transcript-only session") { sessions in
            sessions.count == 1 && sessions[0].isLimitedMode && sessions[0].status == .working
        }
    }

    func testPreexistingTranscriptIsPickedUpOnStart() throws {
        try appendTranscriptLine(assistantLine(activityFile: "/a/pre.swift", tokens: 42))
        provider.start()
        waitForSessions(description: "existing transcript discovered") { sessions in
            sessions.first?.activity == "Editing pre.swift…"
        }
    }
}
