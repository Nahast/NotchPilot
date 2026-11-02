@testable import ClaudeCodeProvider
import XCTest

final class TranscriptLineParserTests: XCTestCase {
    // Fixture lines recorded from a real Claude Code session shape (v2.x).
    private let assistantToolUseLine = """
    {"parentUuid":"p1","isSidechain":false,"userType":"external","cwd":"/Users/romain/Projects/demo","sessionId":"11111111-1111-1111-1111-111111111111","version":"2.1.0","gitBranch":"main","type":"assistant","uuid":"u1","timestamp":"2026-07-08T10:00:00.000Z","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Let me edit that."},{"type":"tool_use","id":"toolu_01","name":"Edit","input":{"file_path":"/Users/romain/Projects/demo/Sources/main.swift","old_string":"a","new_string":"b"}}],"stop_reason":"tool_use","usage":{"input_tokens":3,"cache_creation_input_tokens":2000,"cache_read_input_tokens":38000,"output_tokens":120}}}
    """

    private let userPromptLine = """
    {"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"/Users/romain/Projects/demo","sessionId":"11111111-1111-1111-1111-111111111111","type":"user","uuid":"u0","timestamp":"2026-07-08T09:59:00.000Z","message":{"role":"user","content":"please fix the bug"}}
    """

    private let toolResultLine = """
    {"parentUuid":"u1","isSidechain":false,"cwd":"/Users/romain/Projects/demo","sessionId":"11111111-1111-1111-1111-111111111111","type":"user","uuid":"u2","timestamp":"2026-07-08T10:00:05.000Z","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"ok"}]}}
    """

    func testAssistantToolUseLine() throws {
        let event = try XCTUnwrap(TranscriptLineParser.parse(assistantToolUseLine))
        XCTAssertEqual(event.sessionId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(event.cwd, "/Users/romain/Projects/demo")
        XCTAssertNotNil(event.timestamp, "line timestamp must be parsed")
        // 2026-07-08T10:00:00.000Z
        XCTAssertEqual(event.timestamp?.timeIntervalSince1970, 1_783_504_800)
        XCTAssertEqual(event.gitBranch, "main")
        guard case let .assistantActivity(activity) = event.kind else {
            return XCTFail("expected assistantActivity, got \(event.kind)")
        }
        XCTAssertEqual(activity.model, "claude-sonnet-4-5")
        XCTAssertEqual(activity.contextUsedTokens, 3 + 2000 + 38000 + 120)
        XCTAssertEqual(activity.activityDescription, "Editing main.swift…")
        XCTAssertTrue(activity.issuedToolUse)
    }

    func testUserPromptLine() throws {
        let event = try XCTUnwrap(TranscriptLineParser.parse(userPromptLine))
        XCTAssertEqual(event.kind, .userPrompt)
    }

    func testToolResultLine() throws {
        let event = try XCTUnwrap(TranscriptLineParser.parse(toolResultLine))
        XCTAssertEqual(event.kind, .toolResult)
    }

    func testAssistantTextOnlyLineHasNoToolUse() throws {
        let line = """
        {"type":"assistant","sessionId":"s","cwd":"/p","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":100,"output_tokens":5}}}
        """
        let event = try XCTUnwrap(TranscriptLineParser.parse(line))
        guard case let .assistantActivity(activity) = event.kind else {
            return XCTFail("expected assistantActivity")
        }
        XCTAssertNil(activity.activityDescription)
        XCTAssertFalse(activity.issuedToolUse)
        XCTAssertEqual(activity.contextUsedTokens, 115)
    }

    func testSummaryLineIsUninteresting() throws {
        let line = #"{"type":"summary","summary":"Fixing the bug","leafUuid":"x"}"#
        let event = try XCTUnwrap(TranscriptLineParser.parse(line))
        XCTAssertEqual(event.kind, .uninteresting)
    }

    func testSidechainLineIsUninteresting() throws {
        let line = """
        {"type":"assistant","isSidechain":true,"sessionId":"s","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
        """
        let event = try XCTUnwrap(TranscriptLineParser.parse(line))
        XCTAssertEqual(event.kind, .uninteresting)
    }

    func testMalformedLineReturnsNil() {
        XCTAssertNil(TranscriptLineParser.parse("not json at all {"))
        XCTAssertNil(TranscriptLineParser.parse(""))
        XCTAssertNil(TranscriptLineParser.parse("[1,2,3]")) // non-dictionary JSON
    }

    func testUnknownShapeDegradesGracefully() throws {
        // Format drift: assistant line with a completely different message shape.
        let line = #"{"type":"assistant","sessionId":"s","message":{"role":"assistant","content":"plain string content"}}"#
        let event = try XCTUnwrap(TranscriptLineParser.parse(line))
        guard case let .assistantActivity(activity) = event.kind else {
            return XCTFail("expected assistantActivity")
        }
        XCTAssertNil(activity.contextUsedTokens) // gauge hides, no crash
        XCTAssertNil(activity.activityDescription)
    }

    func testUsageMissingFieldsStillSums() throws {
        let line = #"{"type":"assistant","sessionId":"s","message":{"role":"assistant","content":[],"usage":{"input_tokens":42}}}"#
        let event = try XCTUnwrap(TranscriptLineParser.parse(line))
        guard case let .assistantActivity(activity) = event.kind else {
            return XCTFail("expected assistantActivity")
        }
        XCTAssertEqual(activity.contextUsedTokens, 42)
    }

    // MARK: Bookkeeping "user" lines (fixtures mirror real transcripts)

    func testInterruptMarkerEndsTheTurn() {
        let plain = #"{"type":"user","sessionId":"s","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let forTool = #"{"type":"user","sessionId":"s","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
        let asString = #"{"type":"user","sessionId":"s","message":{"role":"user","content":"[Request interrupted by user]"}}"#
        for line in [plain, forTool, asString] {
            XCTAssertEqual(TranscriptLineParser.parse(line)?.kind, .interrupted, line)
        }
    }

    func testBuiltInSlashCommandsAreNotPrompts() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>\n<command-message>model</command-message>"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>Caveat: The messages below were generated by the user while running local commands.</local-command-caveat>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to claude-opus</local-command-stdout>"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<bash-stdout></bash-stdout><bash-stderr></bash-stderr>"}}"#,
        ]
        for line in lines {
            XCTAssertEqual(TranscriptLineParser.parse(line)?.kind, .uninteresting, line)
        }
    }

    func testOrdinaryAndTaskNotificationPromptsStillStartATurn() {
        let typed = #"{"type":"user","message":{"role":"user","content":"fix the failing test"}}"#
        let blocks = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"deploy it"}]}}"#
        let background = #"{"type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>a1</task-id></task-notification>"}}"#
        for line in [typed, blocks, background] {
            XCTAssertEqual(TranscriptLineParser.parse(line)?.kind, .userPrompt, line)
        }
    }
}
