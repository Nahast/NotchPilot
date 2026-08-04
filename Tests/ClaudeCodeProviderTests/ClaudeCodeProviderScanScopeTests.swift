import AgentCore
import Combine
@testable import ClaudeCodeProvider
import XCTest

/// Cost of a scan, not its output: an append to one transcript must not cost a
/// walk of every transcript the user has ever produced. The provider is driven
/// directly (no `start()`) so no FSEvents stream or poll timer can inflate the
/// counters mid-assertion.
final class ClaudeCodeProviderScanScopeTests: XCTestCase {
    private var fixtureRoot: URL!
    private var claudeHome: URL!
    private var eventsDir: URL!
    private var projectDir: URL!
    private var provider: ClaudeCodeProvider!
    private var cancellables: Set<AnyCancellable> = []

    private let sessionId = "33333333-3333-3333-3333-333333333333"
    private let historyCount = 40

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotchPilotScopeTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        claudeHome = fixtureRoot.appendingPathComponent(".claude", isDirectory: true)
        eventsDir = fixtureRoot.appendingPathComponent("events", isDirectory: true)
        projectDir = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-Users-romain-Projects-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        makeProvider(fullWalkInterval: 60)
    }

    /// The one test that runs the real stream: nothing else can produce the
    /// update, so it fails if FSEvents paths stop reaching the provider.
    func testRealFSEventsPathDrivesTheUpdateWithoutAWalk() throws {
        makeProvider(pollInterval: 3600, fullWalkInterval: 3600)
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/first.swift", tokens: 10_000),
            to: transcriptURL
        )

        let discovered = expectSessions("launch walk finds the transcript") { sessions in
            sessions.contains { $0.id == self.sessionId }
        }
        provider.start()
        wait(for: [discovered], timeout: 5)

        let updated = expectSessions("append arrives via FSEvents") { sessions in
            sessions.first(where: { $0.id == self.sessionId })?.contextUsedTokens == 60_000
        }
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/second.swift", tokens: 60_000),
            to: transcriptURL
        )
        wait(for: [updated], timeout: 10)

        XCTAssertEqual(
            provider.scanMetricsSnapshot().fullWalks, 1,
            "the launch walk must be the only one — the append came from a reported path"
        )
    }

    override func tearDownWithError() throws {
        provider.stop()
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: fixtureRoot)
        try super.tearDownWithError()
    }

    private func makeProvider(pollInterval: TimeInterval = 3600, fullWalkInterval: TimeInterval) {
        provider = ClaudeCodeProvider(configuration: .init(
            claudeHome: claudeHome,
            eventsDirectory: eventsDir,
            stalenessTimeout: { 30 * 60 },
            pollInterval: pollInterval,
            fsEventsLatency: 0.05,
            fullWalkInterval: fullWalkInterval,
            hooksInstalled: { true },
            isProcessAlive: { _ in false },
            desktopSessionsDirectory: nil
        ))
    }

    private var transcriptURL: URL {
        projectDir.appendingPathComponent("\(sessionId).jsonl")
    }

    private func assistantLine(sessionId: String, activityFile: String, tokens: Int) -> String {
        """
        {"isSidechain":false,"cwd":"/Users/romain/Projects/demo","sessionId":"\(sessionId)","type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"\(activityFile)"}}],"usage":{"input_tokens":\(tokens),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """
    }

    private func appendTranscriptLine(_ line: String, to url: URL) throws {
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    /// Stands in for the pile of past transcripts a real `~/.claude/projects`
    /// accumulates.
    private func writeHistory() throws {
        for index in 0..<historyCount {
            let id = "history-\(index)"
            try appendTranscriptLine(
                assistantLine(sessionId: id, activityFile: "/a/old\(index).swift", tokens: 10),
                to: projectDir.appendingPathComponent("\(id).jsonl")
            )
        }
    }

    /// Fulfils once the published list satisfies the predicate. Deliberately
    /// does not force a rescan — the scan under test is the only trigger.
    private func expectSessions(
        _ description: String,
        where predicate: @escaping ([AgentSession]) -> Bool
    ) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.assertForOverFulfill = false
        provider.sessionsPublisher
            .filter(predicate)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        return expectation
    }

    func testTargetedChangeDoesNotRewalkTheTree() throws {
        try writeHistory()
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/first.swift", tokens: 10_000),
            to: transcriptURL
        )

        provider.rescanNow() // the launch walk
        let afterLaunch = provider.scanMetricsSnapshot()
        XCTAssertEqual(afterLaunch.fullWalks, 1)
        XCTAssertEqual(afterLaunch.transcriptFilesVisited, historyCount + 1)

        let updated = expectSessions("gauge follows the append") { sessions in
            sessions.first(where: { $0.id == self.sessionId })?.contextUsedTokens == 60_000
        }
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/second.swift", tokens: 60_000),
            to: transcriptURL
        )
        provider.fileSystemDidChange(paths: [transcriptURL.path])
        let afterAppend = provider.scanMetricsSnapshot()

        XCTAssertEqual(
            afterAppend.fullWalks, afterLaunch.fullWalks,
            "an append to one known transcript must not walk the whole tree"
        )
        XCTAssertEqual(
            afterAppend.transcriptFilesVisited - afterLaunch.transcriptFilesVisited, 1,
            "only the transcript FSEvents reported should be read"
        )
        wait(for: [updated], timeout: 5)
    }

    func testNewTranscriptReportedByPathIsPickedUpWithoutAWalk() throws {
        try writeHistory()
        provider.rescanNow()
        let afterLaunch = provider.scanMetricsSnapshot()

        let appeared = expectSessions("new session appears") { sessions in
            sessions.contains { $0.id == self.sessionId }
        }
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/new.swift", tokens: 5),
            to: transcriptURL
        )
        provider.fileSystemDidChange(paths: [transcriptURL.path])
        wait(for: [appeared], timeout: 5)

        XCTAssertEqual(provider.scanMetricsSnapshot().fullWalks, afterLaunch.fullWalks)
    }

    /// FSEvents reports the containing folder alongside (or instead of) the
    /// file. That folder is read on its own — not taken as licence to walk
    /// every other project.
    func testDirectoryLevelEventReadsOnlyThatFolder() throws {
        try writeHistory()
        provider.rescanNow()
        let afterLaunch = provider.scanMetricsSnapshot()

        let otherProject = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-Users-romain-Projects-other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherProject, withIntermediateDirectories: true)
        let appeared = expectSessions("session in the reported folder appears") { sessions in
            sessions.contains { $0.id == "other-session" }
        }
        try appendTranscriptLine(
            assistantLine(sessionId: "other-session", activityFile: "/a/other.swift", tokens: 7),
            to: otherProject.appendingPathComponent("other-session.jsonl")
        )

        provider.fileSystemDidChange(paths: [otherProject.path])
        wait(for: [appeared], timeout: 5)

        let after = provider.scanMetricsSnapshot()
        XCTAssertEqual(after.fullWalks, afterLaunch.fullWalks)
        XCTAssertEqual(after.transcriptFilesVisited - afterLaunch.transcriptFilesVisited, 1)
    }

    /// The safety net: a transcript nobody told us about must not stay
    /// invisible, so the walk still runs on its own cadence.
    func testThrottledWalkRecoversATranscriptNoEventMentioned() throws {
        makeProvider(fullWalkInterval: 0)
        provider.rescanNow()

        let appeared = expectSessions("session recovered by the walk") { sessions in
            sessions.contains { $0.id == self.sessionId }
        }
        try appendTranscriptLine(
            assistantLine(sessionId: sessionId, activityFile: "/a/missed.swift", tokens: 5),
            to: transcriptURL
        )
        provider.fileSystemDidChange(paths: []) // the event never arrived
        wait(for: [appeared], timeout: 5)
    }

    /// Paths that no longer exist (deleted between the event and the scan) and
    /// paths outside the transcript tree must be shrugged off.
    func testUnusableChangedPathsAreIgnored() throws {
        try writeHistory()
        provider.rescanNow()
        let afterLaunch = provider.scanMetricsSnapshot()

        provider.fileSystemDidChange(paths: [
            projectDir.appendingPathComponent("deleted.jsonl").path,
            eventsDir.appendingPathComponent("hook.json").path,
        ])
        let after = provider.scanMetricsSnapshot()
        XCTAssertEqual(after.fullWalks, afterLaunch.fullWalks)
        XCTAssertEqual(after.transcriptFilesVisited, afterLaunch.transcriptFilesVisited + 1)
    }
}
