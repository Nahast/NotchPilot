import AgentCore
import Combine
@testable import CodexProvider
import XCTest

final class CodexProviderIntegrationTests: XCTestCase {
    private var codexHome: URL!
    private var provider: CodexProvider!
    private var cancellables: Set<AnyCancellable> = []
    private let sessionId = "019d097d-d8fb-7742-b09c-bcb6a814449d"

    override func setUpWithError() throws {
        try super.setUpWithError()
        codexHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CodexTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: codexHome.appendingPathComponent("sessions/2026/07/08", isDirectory: true),
            withIntermediateDirectories: true
        )
        provider = CodexProvider(configuration: .init(
            codexHome: codexHome,
            stalenessTimeout: { 30 * 60 },
            pollInterval: 0.15,
            fsEventsLatency: 0.05
        ))
    }

    override func tearDownWithError() throws {
        provider.stop()
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: codexHome)
        try super.tearDownWithError()
    }

    private var rolloutURL: URL {
        codexHome.appendingPathComponent(
            "sessions/2026/07/08/rollout-2026-07-08T10-00-00-\(sessionId).jsonl"
        )
    }

    private func appendLine(_ line: String) throws {
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: rolloutURL.path) {
            let handle = try FileHandle(forWritingTo: rolloutURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: rolloutURL)
        }
    }

    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

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

    func testRolloutLifecycleWithNameAndGauge() throws {
        try Data("""
        {"id":"\(sessionId)","thread_name":"Fix the tests","updated_at":"\(isoNow())"}\n
        """.utf8).write(to: codexHome.appendingPathComponent("session_index.jsonl"))

        try appendLine(#"{"timestamp":"\#(isoNow())","type":"session_meta","payload":{"id":"\#(sessionId)","cwd":"/Users/romain/Projects/api"}}"#)
        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"task_started"}}"#)
        provider.start()

        waitForSessions(description: "working codex session with name") { sessions in
            sessions.count == 1
                && sessions[0].agentKind == .codex
                && sessions[0].status == .working
                && sessions[0].displayName == "Fix the tests"
                && sessions[0].projectName == "api"
                && sessions[0].isActive
        }

        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":50000},"model_context_window":258400}}}"#)
        waitForSessions(description: "gauge") { sessions in
            sessions.first?.contextUsedTokens == 50_000
                && sessions.first?.contextWindowTokens == 258_400
        }

        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"task_complete"}}"#)
        waitForSessions(description: "idle after task_complete") { sessions in
            sessions.first?.status == .idle
        }
    }

    /// Polling and the safety-net walk are pushed out of reach, so the only
    /// thing that can carry the append through is the path FSEvents reported.
    func testAppendArrivesViaTheReportedPathAlone() throws {
        provider = CodexProvider(configuration: .init(
            codexHome: codexHome,
            stalenessTimeout: { 30 * 60 },
            pollInterval: 3600,
            fsEventsLatency: 0.05,
            fullWalkInterval: 3600
        ))
        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"task_started"}}"#)

        let started = expectation(description: "rollout picked up at launch")
        started.assertForOverFulfill = false
        provider.sessionsPublisher
            .filter { $0.first?.status == .working }
            .sink { _ in started.fulfill() }
            .store(in: &cancellables)
        provider.start()
        wait(for: [started], timeout: 5)

        let done = expectation(description: "append arrives via FSEvents")
        done.assertForOverFulfill = false
        provider.sessionsPublisher
            .filter { $0.first?.status == .idle }
            .sink { _ in done.fulfill() }
            .store(in: &cancellables)
        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"task_complete"}}"#)
        wait(for: [done], timeout: 10)
    }

    func testApprovalRequestFlipsToNeedsAttention() throws {
        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"task_started"}}"#)
        try appendLine(#"{"timestamp":"\#(isoNow())","type":"event_msg","payload":{"type":"exec_approval_request"}}"#)
        provider.start()

        waitForSessions(description: "needs attention") { sessions in
            sessions.first?.status == .needsAttention
                && sessions.first?.activity == "Waiting for your approval"
        }
    }
}
