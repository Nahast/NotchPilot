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
        // The provider pipeline always resolves liveness before reaping.
        store.applyRegistry([:])
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

    // MARK: Session registry

    private func registryEntry(
        session: String,
        pid: Int32 = 1234,
        kind: String = "interactive",
        name: String? = nil,
        cwd: String = "/Users/romain/Projects/demo"
    ) -> SessionRegistryEntry {
        SessionRegistryEntry(
            sessionId: session,
            pid: pid,
            kind: kind,
            entrypoint: "claude-desktop",
            name: name,
            cwd: cwd
        )
    }

    func testRegistryCreatesActiveNamedSession() {
        store.applyRegistry(["r1": registryEntry(session: "r1", name: "droplet-a1")])
        let session = store.snapshot()[0]
        XCTAssertEqual(session.name, "droplet-a1")
        XCTAssertEqual(session.displayName, "droplet-a1")
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.isRoutine)
        XCTAssertEqual(session.status, .idle)
    }

    func testRegistryMarksRoutineFromNonInteractiveKind() {
        store.applyRegistry(["r1": registryEntry(session: "r1", kind: "scheduled", name: "backlog-tick")])
        XCTAssertTrue(store.snapshot()[0].isRoutine)
    }

    func testSessionGoesInactiveAndIdleWhenProcessDies() {
        store.applyRegistry(["r1": registryEntry(session: "r1", name: "droplet-a1")])
        store.apply(hook: hookEvent(.sessionStart, session: "r1"))
        XCTAssertEqual(store.snapshot()[0].status, .working)

        advance(10)
        store.applyRegistry([:]) // process exited
        let session = store.snapshot()[0]
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.status, .idle, "a dead process can't still be working")
        XCTAssertEqual(session.name, "droplet-a1", "name survives process exit")
    }

    func testAliveRegistrySessionIsNeverReaped() {
        store.applyRegistry(["r1": registryEntry(session: "r1")])
        advance(10 * 60 * 60) // 10 hours idle
        store.applyRegistry(["r1": registryEntry(session: "r1")])
        store.reapStale(timeout: 30 * 60)
        XCTAssertEqual(store.snapshot().count, 1, "open-but-quiet sessions stay listed")
    }

    func testUnregisteredSessionUsesActivityGraceWindow() {
        transcriptOnlySession()
        store.applyRegistry([:])
        XCTAssertTrue(store.snapshot()[0].isActive, "fresh activity keeps it active")

        advance(SessionStore.activeGraceWindow + 60)
        store.applyRegistry([:])
        XCTAssertFalse(store.snapshot()[0].isActive, "grace window expired")
    }

    func testDesktopTitleBeatsRegistryName() {
        store.applyRegistry(["r1": registryEntry(session: "r1", name: "droplet-a1")])
        store.applyDesktopMetadata(["r1": DesktopSessionInfo(title: "Automated development workflows")])
        XCTAssertEqual(store.snapshot()[0].displayName, "Automated development workflows")

        // Registry refresh must not clobber the desktop title.
        store.applyRegistry(["r1": registryEntry(session: "r1", name: "droplet-a1")])
        XCTAssertEqual(store.snapshot()[0].displayName, "Automated development workflows")
    }

    func testMetadataForUnknownSessionIsIgnored() {
        store.applyDesktopMetadata(["ghost": DesktopSessionInfo(title: "Some title")])
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testScheduledTaskIdMarksRoutine() {
        store.applyRegistry(["r1": registryEntry(session: "r1", name: "droplet-35")])
        XCTAssertFalse(store.snapshot()[0].isRoutine)

        store.applyDesktopMetadata(["r1": DesktopSessionInfo(
            title: "Backlog tick",
            scheduledTaskId: "backlog-tick"
        )])
        let session = store.snapshot()[0]
        XCTAssertTrue(session.isRoutine)
        XCTAssertEqual(session.displayName, "Backlog tick")
    }

    func testPullRequestAttachedToSession() {
        store.applyRegistry(["r1": registryEntry(session: "r1")])
        store.applyDesktopMetadata(["r1": DesktopSessionInfo(
            pullRequest: PullRequestInfo(number: 552, state: .open)
        )])
        XCTAssertEqual(store.snapshot()[0].pullRequest?.number, 552)
        XCTAssertEqual(store.snapshot()[0].pullRequest?.state, .open)
    }

    func testDesktopSessionIdPropagatesForDeepLinking() {
        store.applyRegistry(["r1": registryEntry(session: "r1")])
        store.applyDesktopMetadata(["r1": DesktopSessionInfo(
            localSessionId: "local_abc-123"
        )])
        XCTAssertEqual(store.snapshot()[0].desktopSessionId, "local_abc-123")
    }

    // MARK: Token tally

    private func applyAssistantTokens(
        session: String = "s1",
        messageId: String,
        newTokens: Int,
        at timestamp: Date? = nil
    ) {
        let activity = AssistantActivity(messageId: messageId, newTokens: newTokens)
        store.apply(
            transcript: TranscriptEvent(
                sessionId: session,
                cwd: nil,
                kind: .assistantActivity(activity),
                timestamp: timestamp ?? clock
            ),
            fallbackSessionId: session,
            fallbackProjectPath: "demo"
        )
    }

    func testTallyAccumulatesTodaysTokens() {
        applyAssistantTokens(messageId: "m1", newTokens: 1_000)
        applyAssistantTokens(messageId: "m2", newTokens: 500)
        XCTAssertEqual(store.tokenTally.tokens, 1_500)
        XCTAssertFalse(store.tokenTally.isApproximate)
    }

    func testTallyDedupesByMessageId() {
        applyAssistantTokens(messageId: "m1", newTokens: 1_000)
        applyAssistantTokens(messageId: "m1", newTokens: 1_000) // replayed line
        XCTAssertEqual(store.tokenTally.tokens, 1_000)
    }

    func testTallyIgnoresOtherDays() {
        applyAssistantTokens(messageId: "old", newTokens: 9_999, at: clock.addingTimeInterval(-86_400 * 2))
        applyAssistantTokens(messageId: "new", newTokens: 100)
        XCTAssertEqual(store.tokenTally.tokens, 100)
    }

    func testTallyResetsOnDayRollover() {
        applyAssistantTokens(messageId: "m1", newTokens: 1_000)
        XCTAssertEqual(store.tokenTally.tokens, 1_000)
        advance(86_400 + 3600) // next day
        store.rolloverTallyIfNeeded()
        XCTAssertEqual(store.tokenTally.tokens, 0)
        applyAssistantTokens(messageId: "m2", newTokens: 250)
        XCTAssertEqual(store.tokenTally.tokens, 250)
    }

    func testSnapshotOrdersRoutinesLast() {
        // Inactive session with attention-worthy history.
        store.apply(hook: hookEvent(.notification, session: "inactive-a", cwd: "/p/one"))
        let alive = [
            "work": registryEntry(session: "work", name: "droplet-a1"),
            "routine": registryEntry(session: "routine", kind: "scheduled", name: "backlog-tick"),
        ]
        store.applyRegistry(alive)
        // "inactive-a" has no registry entry; age it past the grace window.
        advance(SessionStore.activeGraceWindow + 60)
        store.applyRegistry(alive)

        XCTAssertEqual(
            store.snapshot().map(\.id),
            ["work", "inactive-a", "routine"],
            "regular sessions (active then inactive) before routines"
        )
    }
}
