import AgentCore
@testable import CodexProvider
import XCTest

final class CodexRolloutParserTests: XCTestCase {
    // Fixtures mirror real ~/.codex rollout lines (codex 0.115).
    func testSessionMeta() throws {
        let line = """
        {"timestamp":"2026-03-20T04:26:08.120Z","type":"session_meta","payload":{"id":"019d097d-d8fb-7742-b09c-bcb6a814449d","cwd":"/Users/romain/Projects/demo","originator":"codex_vscode","cli_version":"0.115.0"}}
        """
        let event = try XCTUnwrap(CodexRolloutParser.parse(Data(line.utf8)))
        XCTAssertEqual(event.kind, .sessionMeta(cwd: "/Users/romain/Projects/demo", parentThreadId: nil))
        XCTAssertNotNil(event.timestamp)
    }

    func testTaskLifecycle() throws {
        let started = #"{"timestamp":"2026-03-20T04:26:09.000Z","type":"event_msg","payload":{"type":"task_started"}}"#
        let complete = #"{"timestamp":"2026-03-20T04:27:09.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(started.utf8))?.kind, .taskStarted)
        XCTAssertEqual(CodexRolloutParser.parse(Data(complete.utf8))?.kind, .taskComplete)
    }

    func testFunctionCallShellDescription() throws {
        let line = """
        {"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"swift test\\"]}"}}
        """
        let event = try XCTUnwrap(CodexRolloutParser.parse(Data(line.utf8)))
        XCTAssertEqual(event.kind, .agentActivity(description: "Running: swift test"))
    }

    func testTokenCount() throws {
        let line = """
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":11386,"cached_input_tokens":2432,"output_tokens":282,"total_tokens":11668},"model_context_window":258400},"rate_limits":null}}
        """
        let event = try XCTUnwrap(CodexRolloutParser.parse(Data(line.utf8)))
        XCTAssertEqual(event.kind, .tokenCount(usedTokens: 11_668, contextWindow: 258_400))
    }

    func testApprovalRequestDetectedBySubstring() throws {
        let line = #"{"type":"event_msg","payload":{"type":"exec_approval_request","command":["rm","-rf"]}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(line.utf8))?.kind, .approvalRequest)
    }

    func testUserMessage() throws {
        let line = #"{"type":"event_msg","payload":{"type":"user_message","message":"fix it"}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(line.utf8))?.kind, .userMessage)
    }

    func testUnknownShapesDegrade() {
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(#"{"type":"event_msg","payload":{"type":"something_new"}}"#.utf8))?.kind,
            .uninteresting
        )
        XCTAssertNil(CodexRolloutParser.parse(Data("not json".utf8)))
    }

    func testSessionIdFromFilename() {
        XCTAssertEqual(
            CodexRolloutParser.sessionId(
                fromFilename: "rollout-2026-03-19T21-25-35-019d097d-d8fb-7742-b09c-bcb6a814449d.jsonl"
            ),
            "019d097d-d8fb-7742-b09c-bcb6a814449d"
        )
        XCTAssertNil(CodexRolloutParser.sessionId(fromFilename: "not-a-rollout.jsonl"))
        XCTAssertNil(CodexRolloutParser.sessionId(fromFilename: "rollout-short.jsonl"))
    }

    // MARK: Modern rollout shapes (fixtures mirror codex rollouts from Oct 2026)

    func testCustomToolCallIsActivityWithItsCallId() throws {
        let exec = #"{"type":"response_item","payload":{"type":"custom_tool_call","status":"completed","call_id":"call_1","name":"exec","input":"text(1+1)"}}"#
        let patch = #"{"type":"response_item","payload":{"type":"custom_tool_call","call_id":"call_2","name":"apply_patch","input":"*** Begin Patch"}}"#
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(exec.utf8))?.kind,
            .agentActivity(description: "Running a command…", callId: "call_1")
        )
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(patch.utf8))?.kind,
            .agentActivity(description: "Editing files…", callId: "call_2")
        )
    }

    func testToolOutputsCloseTheirCall() {
        let custom = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call_1","output":"ok"}}"#
        let function = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call_9","output":"ok"}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(custom.utf8))?.kind, .toolOutput(callId: "call_1"))
        XCTAssertEqual(CodexRolloutParser.parse(Data(function.utf8))?.kind, .toolOutput(callId: "call_9"))
    }

    func testExecCommandUsesCmdKey() {
        let line = #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"c","arguments":"{\"cmd\":\"swift test\"}"}}"#
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(line.utf8))?.kind,
            .agentActivity(description: "Running: swift test", callId: "c")
        )
    }

    func testTurnAborted() {
        let line = #"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(line.utf8))?.kind, .turnAborted)
    }

    func testSubThreadMetaCarriesItsParent() {
        let line = #"{"type":"session_meta","payload":{"id":"c","parent_thread_id":"p","cwd":"/x","thread_source":"guardian_review"}}"#
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(line.utf8))?.kind,
            .sessionMeta(cwd: "/x", parentThreadId: "p")
        )
    }

    func testTurnContextCarriesCwd() {
        let line = #"{"type":"turn_context","payload":{"turn_id":"t","cwd":"/Users/romain/Projects/api"}}"#
        XCTAssertEqual(CodexRolloutParser.parse(Data(line.utf8))?.kind, .turnContext(cwd: "/Users/romain/Projects/api"))
    }

    /// The session total only grows; the gauge must follow what the last
    /// request actually put in the window.
    func testTokenCountPrefersLastRequestUsage() {
        let line = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"total_tokens":41000},"model_context_window":475000}}}"#
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(line.utf8))?.kind,
            .tokenCount(usedTokens: 41_000, contextWindow: 475_000)
        )
    }

    func testTokenCountWithoutInfoIsHarmless() {
        let line = #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{}}}"#
        XCTAssertEqual(
            CodexRolloutParser.parse(Data(line.utf8))?.kind,
            .tokenCount(usedTokens: nil, contextWindow: nil)
        )
    }

    func testReadHeadFindsMetaBehindALargePrompt() throws {
        let path = NSTemporaryDirectory() + "head-\(UUID().uuidString).jsonl"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let prompt = String(repeating: "x", count: 300_000) // > the tailer's 256 KB window
        let meta = #"{"type":"session_meta","payload":{"cwd":"/Users/romain/Projects/api","base_instructions":""# + prompt + #""}}"# + "\n{\"type\":\"turn_context\"}\n"
        try Data(meta.utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(
            CodexRolloutParser.readHead(atPath: path)?.kind,
            .sessionMeta(cwd: "/Users/romain/Projects/api", parentThreadId: nil)
        )
        XCTAssertNil(CodexRolloutParser.readHead(atPath: "/nonexistent/rollout.jsonl"))
    }
}
