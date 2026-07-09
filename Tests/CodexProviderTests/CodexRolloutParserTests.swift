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
        XCTAssertEqual(event.kind, .sessionMeta(cwd: "/Users/romain/Projects/demo"))
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
}
