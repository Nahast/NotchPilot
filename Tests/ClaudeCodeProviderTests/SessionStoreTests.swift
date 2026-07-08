import AgentCore
@testable import ClaudeCodeProvider
import XCTest

final class SessionStoreTests: XCTestCase {
    private var store: SessionStore!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        store = SessionStore()
        clock = Date(timeIntervalSince1970: 1_000_000)
        store.now = { [weak self] in self?.clock ?? Date() }
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    private func hookEvent(
        _ name: HookEvent.Name,
        session: String = "s1",
        cwd: String? = "/Users/romain/Projects/demo",
        message: String? = nil
    ) -> HookEvent {
        HookEvent(
            name: name,
            sessionId: session,
            cwd: cwd,
            message: message,
            receivedAt: clock
        )
    }

    func testSessionStartCreatesWorkingSession() {
        store.apply(hook: hookEvent(.sessionStart))
        let sessions = store.snapshot()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "s1")
        XCTAssertEqual(sessions[0].status, .working)
        XCTAssertEqual(sessions[0].projectName, "demo")
        XCTAssertFalse(sessions[0].isLimitedMode)
    }

    func testNotificationSetsAttentionAndWaitingActivity() {
        store.apply(hook: hookEvent(.sessionStart))
        advance(10)
        store.apply(hook: hookEvent(.notification, message: "Claude needs your permission to use Bash"))
        let session = store.snapshot()[0]
        XCTAssertEqual(session.status, .needsAttention)
        XCTAssertEqual(session.activity, "Claude needs your permission to use Bash")
        XCTAssertEqual(session.stateChangedAt, clock)
    }

    func testNotificationWithoutMessageUsesDefaultCopy() {
        store.apply(hook: hookEvent(.notification))
        XCTAssertEqual(store.snapshot()[0].activity, "Waiting for your approval")
    }

    func testStateChangedAtOnlyMovesOnStatusChange() {
        store.apply(hook: hookEvent(.sessionStart))
        let started = clock!
        advance(5)
        // Another working-ish signal must not reset the state clock.
        store.apply(
            transcript: TranscriptEvent(sessionId: "s1", cwd: nil, kind: .assistantActivity(AssistantActivity())),
            fallbackSessionId: "s1",
            fallbackProjectPath: "demo"
        )
        XCTAssertEqual(store.snapshot()[0].stateChangedAt, started)
    }

    func testSessionEndRemovesSession() {
        store.apply(hook: hookEvent(.sessionStart))
        store.apply(hook: hookEvent(.sessionEnd))
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testTranscriptActivityUpdatesGaugeAndActivity() {
        store.apply(hook: hookEvent(.sessionStart))
        let activity = AssistantActivity(
            model: "claude-sonnet-4-5",
            contextUsedTokens: 40_123,
            activityDescription: "Editing main.swift…",
            issuedToolUse: true
        )
        store.apply(
            transcript: TranscriptEvent(sessionId: "s1", cwd: nil, kind: .assistantActivity(activity)),
            fallbackSessionId: "s1",
            fallbackProjectPath: "demo"
        )
        let session = store.snapshot()[0]
        XCTAssertEqual(session.activity, "Editing main.swift…")
        XCTAssertEqual(session.contextUsedTokens, 40_123)
        XCTAssertEqual(session.contextWindowTokens, 200_000)
    }

    func testStaleSessionIsReaped() {
        store.apply(hook: hookEvent(.sessionStart))
        advance(31 * 60)
        store.reapStale(timeout: 30 * 60)
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testFreshSessionSurvivesReaping() {
        store.apply(hook: hookEvent(.sessionStart))
        advance(10 * 60)
        store.reapStale(timeout: 30 * 60)
        XCTAssertEqual(store.snapshot().count, 1)
    }

    // MARK: Limited mode (transcript-only sessions)

    private func transcriptOnlySession(pendingToolUse: Bool = false) {
        let activity = AssistantActivity(
            model: "claude-sonnet-4-5",
            contextUsedTokens: 1000,
            activityDescription: "Running tests…",
            issuedToolUse: pendingToolUse
        )
        store.apply(
            transcript: TranscriptEvent(
                sessionId: "t1",
                cwd: "/Users/romain/Projects/demo",
                kind: .assistantActivity(activity)
            ),
            fallbackSessionId: "t1",
            fallbackProjectPath: "demo"
        )
    }

    func testLimitedModeRecentWritesMeanWorking() {
        transcriptOnlySession()
        store.recomputeLimitedStatuses()
        let session = store.snapshot()[0]
        XCTAssertEqual(session.status, .working)
        XCTAssertTrue(session.isLimitedMode)
    }

    func testLimitedModeMidTurnStallMeansProbablyWaiting() {
        transcriptOnlySession(pendingToolUse: true)
        advance(30)
        store.recomputeLimitedStatuses()
        let session = store.snapshot()[0]
        XCTAssertEqual(session.status, .needsAttention)
        XCTAssertEqual(session.activity, "Probably waiting on you")
    }

    func testLimitedModeLongSilenceMeansIdle() {
        transcriptOnlySession(pendingToolUse: false)
        advance(180)
        store.recomputeLimitedStatuses()
        XCTAssertEqual(store.snapshot()[0].status, .idle)
    }

    func testHookDrivenSessionIgnoresLimitedHeuristics() {
        store.apply(hook: hookEvent(.stop))
        advance(180)
        store.recomputeLimitedStatuses()
        // Stays idle-from-hook; heuristics must not touch hook-driven sessions.
        let session = store.snapshot()[0]
        XCTAssertEqual(session.status, .idle)
        XCTAssertFalse(session.isLimitedMode)
    }

    // MARK: Sorting

    func testSnapshotOrdersAttentionFirstThenWorkingThenIdle() {
        store.apply(hook: hookEvent(.sessionStart, session: "w", cwd: "/p/working"))
        store.apply(hook: hookEvent(.stop, session: "i", cwd: "/p/idle"))
        store.apply(hook: hookEvent(.notification, session: "a", cwd: "/p/attention"))
        XCTAssertEqual(store.snapshot().map(\.id), ["a", "w", "i"])
    }
}
