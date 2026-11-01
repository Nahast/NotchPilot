import AgentCore
@testable import CodexProvider
import XCTest

/// Drives a real `CodexProvider` against rollouts shaped like the ones
/// current Codex writes (`custom_tool_call`, guardian / subagent threads,
/// a multi-KB `session_meta`, `last_token_usage`).
final class CodexE2ETests: XCTestCase {
    private var sandbox: Sandbox!
    private var provider: CodexProvider!
    private var recorder: Recorder!
    private var clock = Date()
    private let cwd = "/Users/romain/Projects/api"

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = try Sandbox()
    }

    override func tearDown() {
        provider?.stop()
        super.tearDown()
    }

    private func launch() {
        clock = Date()
        provider = CodexProvider(configuration: .init(
            codexHome: sandbox.codexHome,
            pollInterval: 0.2,
            fsEventsLatency: 0.05
        ))
        provider.now = { [unowned self] in clock }
        recorder = Recorder(provider.sessionsPublisher)
        provider.start()
    }

    private func rollout(_ id: String) -> URL {
        sandbox.codexHome.appendingPathComponent("sessions/2026/10/30/rollout-2026-10-30T10-00-00-\(id).jsonl")
    }

    private func newId() -> String { UUID().uuidString.lowercased() }

    private func write(_ id: String, _ type: String, _ payload: String) throws {
        try sandbox.append(#"{"timestamp":"\#(Stamp.iso())","type":"\#(type)","payload":\#(payload)}"#, to: rollout(id))
    }

    private func meta(_ id: String, parent: String? = nil, source: String = "user", promptBytes: Int = 0) throws {
        let parentField = parent.map { #""parent_thread_id":"\#($0)","# } ?? ""
        let prompt = String(repeating: "p", count: promptBytes)
        try write(id, "session_meta", #"{"id":"\#(id)",\#(parentField)"cwd":"\#(cwd)","originator":"codex-tui","thread_source":"\#(source)","base_instructions":"\#(prompt)"}"#)
    }

    private func toolCall(_ id: String, call: String) throws {
        try write(id, "response_item", #"{"type":"custom_tool_call","status":"completed","call_id":"\#(call)","name":"exec","input":"text(1)"}"#)
    }

    private func toolOutput(_ id: String, call: String) throws {
        try write(id, "response_item", #"{"type":"custom_tool_call_output","call_id":"\#(call)","output":"ok"}"#)
    }

    // MARK: Scenarios

    func testModernRolloutLifecycle() throws {
        let id = newId()
        try sandbox.append(
            #"{"id":"\#(id)","thread_name":"Add pagination","updated_at":"\#(Stamp.iso())"}"#,
            to: sandbox.codexHome.appendingPathComponent("session_index.jsonl")
        )
        launch()

        try meta(id)
        try write(id, "event_msg", #"{"type":"task_started","turn_id":"t1"}"#)
        recorder.wait("working + name") {
            $0.first?.status == .working && $0.first?.displayName == "Add pagination" && $0.first?.projectName == "api"
        }

        try toolCall(id, call: "c1")
        recorder.wait("tool activity") { $0.first?.activity == "Running a command…" }

        try write(id, "event_msg", #"{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"total_tokens":41000},"model_context_window":475000}}"#)
        recorder.wait("gauge follows the last request, not the session total") {
            $0.first?.contextUsedTokens == 41_000 && $0.first?.contextWindowTokens == 475_000
        }

        try toolOutput(id, call: "c1")
        try write(id, "event_msg", #"{"type":"task_complete","turn_id":"t1"}"#)
        recorder.wait("done") { $0.first?.status == .idle && $0.first?.activity == "Done" }
    }

    /// Pre-existing long rollout at launch: `session_meta` is buried under the
    /// tailer's tail window, so the project must come from the head read.
    func testColdStartOnLongRolloutStillKnowsItsProject() throws {
        let id = newId()
        try meta(id, promptBytes: 300_000)
        try write(id, "event_msg", #"{"type":"task_started"}"#)
        for n in 0..<50 {
            try write(id, "event_msg", #"{"type":"item_completed","n":\#(n),"pad":"\#(String(repeating: "z", count: 6_000))"}"#)
        }
        launch()
        recorder.wait("project resolved from the head of the file") {
            $0.first?.projectName == "api" && $0.first?.status == .working
        }
    }

    /// Guardian approval reviews and subagents are separate rollouts. They
    /// must never become rows, and they must keep the owner alive.
    func testGuardianAndSubagentThreadsAreNotRows() throws {
        let main = newId(), guardian = newId(), subagent = newId()
        launch()

        try meta(main)
        try write(main, "event_msg", #"{"type":"task_started"}"#)
        recorder.wait("main row") { $0.count == 1 }

        try meta(guardian, parent: main, source: "guardian_review")
        try write(guardian, "event_msg", #"{"type":"task_started"}"#)
        try meta(subagent, parent: main, source: "subagent")
        try write(subagent, "event_msg", #"{"type":"task_started"}"#)
        try toolCall(subagent, call: "s1")
        recorder.settle(1.5)

        for snapshot in recorder.snapshots {
            XCTAssertLessThanOrEqual(snapshot.count, 1, "a sub-thread surfaced as a row")
            XCTAssertTrue(snapshot.allSatisfy { $0.id == main })
        }
        XCTAssertEqual(recorder.latest.first?.status, .working)
    }

    /// A build that writes nothing for minutes is still a working session.
    func testLongRunningToolCallKeepsTheSessionWorking() throws {
        let id = newId()
        launch()
        try meta(id)
        try write(id, "event_msg", #"{"type":"task_started"}"#)
        try toolCall(id, call: "build")
        recorder.wait("working") { $0.first?.activity == "Running a command…" }

        clock = clock.addingTimeInterval(10 * 60) // ten silent minutes
        provider.rescanNow()
        recorder.settle(0.6)
        XCTAssertEqual(recorder.latest.first?.status, .working)
        XCTAssertEqual(recorder.latest.first?.isActive, true)

        try toolOutput(id, call: "build")
        try write(id, "event_msg", #"{"type":"task_complete"}"#)
        recorder.wait("idle once finished") { $0.first?.status == .idle }
    }

    func testSilentSessionWithNoOpenToolCallGoesIdle() throws {
        let id = newId()
        launch()
        try meta(id)
        try write(id, "event_msg", #"{"type":"task_started"}"#)
        recorder.wait("working") { $0.first?.status == .working }

        clock = clock.addingTimeInterval(10 * 60)
        provider.rescanNow()
        recorder.wait("idle + inactive") { $0.first?.status == .idle && $0.first?.isActive == false }
    }

    func testInterruptedTurnReturnsToIdle() throws {
        let id = newId()
        launch()
        try meta(id)
        try write(id, "event_msg", #"{"type":"task_started"}"#)
        try toolCall(id, call: "c1")
        recorder.wait("working") { $0.first?.status == .working }

        try write(id, "event_msg", #"{"type":"turn_aborted","reason":"interrupted"}"#)
        recorder.wait("idle, interrupted") { $0.first?.status == .idle && $0.first?.activity == "Interrupted" }
    }
}
