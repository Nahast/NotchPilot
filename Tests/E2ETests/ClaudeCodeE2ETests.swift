import AgentCore
@testable import ClaudeCodeProvider
import XCTest

/// Drives a real `ClaudeCodeProvider` the way Claude Code does: the real
/// `notchpilot-hook` binary for hook events, appended JSONL for the
/// transcript, real FSEvents in between. Transcript lines mirror the shapes in
/// real `~/.claude/projects` files.
final class ClaudeCodeE2ETests: XCTestCase {
    private var sandbox: Sandbox!
    private var provider: ClaudeCodeProvider!
    private var recorder: Recorder!
    private let sid = UUID().uuidString.lowercased()
    private let cwd = "/Users/romain/Projects/demo"

    private var transcript: URL {
        sandbox.claudeHome.appendingPathComponent("projects/-Users-romain-Projects-demo/\(sid).jsonl")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = try Sandbox()
    }

    override func tearDown() {
        provider?.stop()
        super.tearDown()
    }

    private func launch(hooksInstalled: Bool = true) {
        provider = ClaudeCodeProvider(configuration: .init(
            claudeHome: sandbox.claudeHome,
            eventsDirectory: sandbox.eventsDirectory,
            pollInterval: 0.2,
            fsEventsLatency: 0.05,
            hooksInstalled: { hooksInstalled },
            desktopSessionsDirectory: nil
        ))
        recorder = Recorder(provider.sessionsPublisher)
        provider.start()
    }

    private func hook(_ event: String, extra: [String: Any] = [:]) throws {
        var payload: [String: Any] = ["session_id": sid, "cwd": cwd, "transcript_path": transcript.path]
        payload.merge(extra) { _, new in new }
        XCTAssertEqual(try sandbox.fireHook(event, payload: payload), 0)
    }

    // MARK: Transcript lines

    private func line(_ type: String, _ message: String, extra: String = "") -> String {
        #"{"type":"\#(type)","sessionId":"\#(sid)","cwd":"\#(cwd)","gitBranch":"main","timestamp":"\#(Stamp.iso())"\#(extra),"message":\#(message)}"#
    }

    private func prompt(_ text: String) throws {
        try sandbox.append(line("user", #"{"role":"user","content":"\#(text)"}"#), to: transcript)
    }

    private func assistantToolUse(_ tool: String, input: String, used: Int) throws {
        let message = #"{"role":"assistant","id":"msg_\#(UUID().uuidString)","model":"claude-sonnet-4-5","content":[{"type":"tool_use","id":"toolu_1","name":"\#(tool)","input":\#(input)}],"usage":{"input_tokens":3,"cache_creation_input_tokens":\#(used),"cache_read_input_tokens":0,"output_tokens":40}}"#
        try sandbox.append(line("assistant", message), to: transcript)
    }

    private func toolResult() throws {
        try sandbox.append(
            line("user", #"{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}"#),
            to: transcript
        )
    }

    private func interruptMarker() throws {
        try sandbox.append(
            line("user", #"{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}"#),
            to: transcript
        )
    }

    // MARK: Scenarios

    /// One conversation from first hook to SessionEnd, every step asserted as
    /// the user would see it in the notch.
    func testFullConversationLifecycle() throws {
        launch()

        try hook("SessionStart")
        recorder.wait("row appears, working") { $0.first?.status == .working && $0.first?.projectName == "demo" }

        try prompt("run the tests")
        try assistantToolUse("Bash", input: #"{"command":"swift test","description":"Run the test suite"}"#, used: 12_000)
        recorder.wait("activity + gauge") {
            $0.first?.activity == "Run the test suite" && $0.first?.contextUsedTokens == 12_043
        }
        XCTAssertEqual(recorder.latest.first?.model, "claude-sonnet-4-5")
        XCTAssertEqual(recorder.latest.first?.contextWindowTokens, 200_000)
        XCTAssertEqual(recorder.latest.first?.gitBranch, "main")

        try hook("Notification", extra: [
            "notification_type": "permission_prompt", "message": "Claude needs your permission to use Bash",
        ])
        recorder.wait("needs attention") {
            $0.first?.status == .needsAttention && $0.first?.activity == "Claude needs your permission to use Bash"
        }

        try toolResult() // the user approved; the transcript advances
        recorder.wait("working again after approval") { $0.first?.status == .working }

        try hook("Stop")
        recorder.wait("done") { $0.first?.status == .idle && $0.first?.activity == "Done" }
        let idleSince = recorder.latest.first?.stateChangedAt

        // Claude Code nags ~60s after a finished turn. That must not re-alert.
        try hook("Notification", extra: [
            "notification_type": "idle_prompt", "message": "Claude is waiting for your input",
        ])
        recorder.settle()
        XCTAssertEqual(recorder.latest.first?.status, .idle)
        XCTAssertEqual(recorder.latest.first?.stateChangedAt, idleSince)
        XCTAssertEqual(recorder.latest.first?.activity, "Done")

        try hook("SessionEnd")
        recorder.wait("row removed") { $0.isEmpty }

        // The history must contain the approval alert, and no alert after Stop.
        XCTAssertTrue(recorder.snapshots.contains { $0.first?.status == .needsAttention })
        var sawStop = false
        for snapshot in recorder.snapshots {
            guard let status = snapshot.first?.status else { continue }
            if status == .idle { sawStop = true }
            if sawStop { XCTAssertNotEqual(status, .needsAttention, "idle reminder re-alerted a finished session") }
        }
    }

    /// Esc during a turn: Claude Code fires no Stop hook, only the transcript
    /// marker. The session must come back to idle, and the next prompt must
    /// work again.
    func testInterruptedTurnReturnsToIdleAndRecovers() throws {
        launch()
        try hook("SessionStart")
        try prompt("do a long thing")
        try assistantToolUse("Bash", input: #"{"command":"sleep 600"}"#, used: 5_000)
        recorder.wait("working") { $0.first?.activity == "Running: sleep 600" }

        try interruptMarker()
        recorder.wait("idle after interrupt") { $0.first?.status == .idle && $0.first?.activity == "Interrupted" }

        try prompt("never mind, run the linter")
        recorder.wait("working on the next prompt") { $0.first?.status == .working }
    }

    func testBuiltInSlashCommandsDoNotStartATurn() throws {
        launch()
        try hook("SessionStart")
        try hook("Stop")
        recorder.wait("idle") { $0.first?.status == .idle }

        // Exactly what `/model` writes: command, caveat, stdout.
        try sandbox.append(line("user", #"{"role":"user","content":"<command-name>/model</command-name>\n<command-message>model</command-message>"}"#), to: transcript)
        try sandbox.append(line("user", #"{"role":"user","content":"<local-command-stdout>Set model to claude-opus</local-command-stdout>"}"#, extra: #","isMeta":false"#), to: transcript)
        recorder.settle()
        XCTAssertEqual(recorder.latest.first?.status, .idle)
    }

    /// Hooks declined: statuses are inferred from the transcript alone. An
    /// interrupt must read as idle immediately, not "working" for 15s.
    func testLimitedModeInterruptDoesNotFlashWorking() throws {
        launch(hooksInstalled: false)
        try prompt("go")
        try assistantToolUse("Bash", input: #"{"command":"sleep 600"}"#, used: 1_000)
        recorder.wait("limited-mode row, working") { $0.first?.status == .working && $0.first?.isLimitedMode == true }

        try interruptMarker()
        recorder.wait("idle") { $0.first?.status == .idle }
        recorder.settle(1.5)
        XCTAssertEqual(recorder.latest.first?.status, .idle)
    }

    /// The helper must be fast and always exit 0, even on garbage.
    func testHookHelperToleratesGarbageInput() throws {
        launch()
        let process = Process()
        process.executableURL = Sandbox.helperURL
        process.arguments = ["Stop"]
        process.environment = ["NOTCHPILOT_EVENTS_DIR": sandbox.eventsDirectory.path]
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data("{{ not json".utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        recorder.settle(0.5)
        XCTAssertTrue(recorder.latest.isEmpty)
    }
}
