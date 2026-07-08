import AgentCore
@testable import ClaudeCodeProvider
import XCTest

final class SessionStateMachineTests: XCTestCase {
    // The spec §4 table, verbatim.

    func testSessionStartHookSetsWorking() {
        XCTAssertEqual(SessionStateMachine.transition(current: nil, signal: .hookSessionStart), .set(.working))
        XCTAssertEqual(SessionStateMachine.transition(current: .idle, signal: .hookSessionStart), .set(.working))
    }

    func testNotificationHookSetsNeedsAttention() {
        XCTAssertEqual(SessionStateMachine.transition(current: .working, signal: .hookNotification), .set(.needsAttention))
    }

    func testTranscriptAdvanceClearsNeedsAttention() {
        XCTAssertEqual(
            SessionStateMachine.transition(current: .needsAttention, signal: .transcriptAssistantActivity),
            .set(.working)
        )
        XCTAssertEqual(
            SessionStateMachine.transition(current: .needsAttention, signal: .transcriptToolResult),
            .set(.working)
        )
    }

    func testStopHookSetsIdle() {
        XCTAssertEqual(SessionStateMachine.transition(current: .working, signal: .hookStop), .set(.idle))
    }

    func testSessionEndRemoves() {
        XCTAssertEqual(SessionStateMachine.transition(current: .working, signal: .hookSessionEnd), .remove)
        XCTAssertEqual(SessionStateMachine.transition(current: nil, signal: .hookSessionEnd), .remove)
    }

    // Edge cases beyond the table.

    func testTrailingTranscriptWritesDoNotResurrectIdleSession() {
        XCTAssertEqual(
            SessionStateMachine.transition(current: .idle, signal: .transcriptAssistantActivity),
            .keep
        )
        XCTAssertEqual(
            SessionStateMachine.transition(current: .idle, signal: .transcriptToolResult),
            .keep
        )
    }

    func testNewUserPromptRestartsIdleSession() {
        XCTAssertEqual(
            SessionStateMachine.transition(current: .idle, signal: .transcriptUserPrompt),
            .set(.working)
        )
    }

    func testUnknownSessionDiscoveredMidTurnIsWorking() {
        XCTAssertEqual(
            SessionStateMachine.transition(current: nil, signal: .transcriptAssistantActivity),
            .set(.working)
        )
    }

    func testWorkingStaysWorkingOnTranscriptActivity() {
        XCTAssertEqual(
            SessionStateMachine.transition(current: .working, signal: .transcriptAssistantActivity),
            .keep
        )
    }

    // Scripted end-to-end sequence: the canonical session lifecycle.
    func testFullLifecycleSequence() {
        var status: AgentStatus?
        func apply(_ signal: SessionSignal) -> Bool {
            switch SessionStateMachine.transition(current: status, signal: signal) {
            case let .set(next): status = next; return true
            case .keep: return true
            case .remove: status = nil; return false
            }
        }

        XCTAssertTrue(apply(.hookSessionStart))
        XCTAssertEqual(status, .working)
        XCTAssertTrue(apply(.transcriptAssistantActivity))
        XCTAssertEqual(status, .working)
        XCTAssertTrue(apply(.hookNotification))
        XCTAssertEqual(status, .needsAttention)
        XCTAssertTrue(apply(.transcriptToolResult))
        XCTAssertEqual(status, .working)
        XCTAssertTrue(apply(.hookStop))
        XCTAssertEqual(status, .idle)
        XCTAssertTrue(apply(.transcriptUserPrompt))
        XCTAssertEqual(status, .working)
        XCTAssertTrue(apply(.hookStop))
        XCTAssertEqual(status, .idle)
        XCTAssertFalse(apply(.hookSessionEnd))
        XCTAssertNil(status)
    }
}
