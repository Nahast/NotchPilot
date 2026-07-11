import AgentCore
@testable import ClaudeCodeProvider
import XCTest

final class DesktopSessionMetadataReaderTests: XCTestCase {
    private var directory: URL!
    private var reader: DesktopSessionMetadataReader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopMetadataTests-\(UUID().uuidString)", isDirectory: true)
        // Mirror the real nesting: <org-uuid>/<workspace-uuid>/local_*.json
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("org-1/ws-1", isDirectory: true),
            withIntermediateDirectories: true
        )
        reader = DesktopSessionMetadataReader(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func writeSessionFile(
        _ filename: String,
        payload: [String: Any]
    ) throws {
        var full = payload
        if full["sessionId"] == nil { full["sessionId"] = "local_\(UUID().uuidString)" }
        try JSONSerialization.data(withJSONObject: full)
            .write(to: directory.appendingPathComponent("org-1/ws-1/\(filename)"))
    }

    func testMapsCliSessionIdToTitle() throws {
        try writeSessionFile("local_a.json", payload: [
            "cliSessionId": "cli-1",
            "title": "Automated development workflows",
            "lastActivityAt": 1_000,
        ])
        XCTAssertEqual(
            reader.infoBySessionId()["cli-1"]?.title,
            "Automated development workflows"
        )
    }

    func testParsesScheduledTaskId() throws {
        try writeSessionFile("local_a.json", payload: [
            "cliSessionId": "cli-1",
            "title": "Backlog tick",
            "scheduledTaskId": "backlog-tick",
        ])
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.scheduledTaskId, "backlog-tick")
    }

    func testParsesPullRequestFromTopLevelFields() throws {
        try writeSessionFile("local_a.json", payload: [
            "cliSessionId": "cli-1",
            "title": "Fix onboarding",
            "prNumber": 552,
            "prState": "MERGED",
            "prUrl": "https://github.com/o/r/pull/552",
        ])
        let pr = reader.infoBySessionId()["cli-1"]?.pullRequest
        XCTAssertEqual(pr, PullRequestInfo(number: 552, state: .merged, url: "https://github.com/o/r/pull/552"))
    }

    func testParsesPullRequestFromPrsArrayFallback() throws {
        try writeSessionFile("local_a.json", payload: [
            "cliSessionId": "cli-1",
            "title": "Fix onboarding",
            "prs": [
                ["prNumber": 1, "state": "CLOSED", "url": "https://github.com/o/r/pull/1"],
                ["prNumber": 2, "state": "OPEN", "url": "https://github.com/o/r/pull/2"],
            ],
        ])
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.pullRequest?.number, 2)
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.pullRequest?.state, .open)
    }

    func testUnknownPrStateYieldsNoPullRequest() throws {
        try writeSessionFile("local_a.json", payload: [
            "cliSessionId": "cli-1",
            "title": "T",
            "prNumber": 5,
            "prState": "SOMETHING_NEW",
        ])
        XCTAssertNil(reader.infoBySessionId()["cli-1"]?.pullRequest)
    }

    func testMostRecentFileWinsOnDuplicateSession() throws {
        try writeSessionFile("local_old.json", payload: [
            "cliSessionId": "cli-1", "title": "Old title", "lastActivityAt": 1_000,
        ])
        try writeSessionFile("local_new.json", payload: [
            "cliSessionId": "cli-1", "title": "New title", "lastActivityAt": 2_000,
        ])
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.title, "New title")
    }

    func testOrphanAndBrokenFilesAreSkippedButUntitledKeepsDeepLinkId() throws {
        // No cliSessionId → cannot be joined to a local session → skipped.
        try writeSessionFile("local_orphan.json", payload: ["title": "Orphan"])
        try Data("not json".utf8).write(to: directory.appendingPathComponent("org-1/ws-1/broken.json"))
        // No title yet (brand-new session), but its own sessionId is still a
        // valid deep-link target.
        try writeSessionFile("local_untitled.json", payload: ["cliSessionId": "cli-1"])

        let infos = reader.infoBySessionId()
        XCTAssertEqual(infos.count, 1)
        XCTAssertNil(infos["cli-1"]?.title)
        XCTAssertNotNil(infos["cli-1"]?.localSessionId)
    }

    func testUpdateIsPickedUpAfterFileChanges() throws {
        let url = directory.appendingPathComponent("org-1/ws-1/local_a.json")
        try writeSessionFile("local_a.json", payload: ["cliSessionId": "cli-1", "title": "First"])
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.title, "First")

        try JSONSerialization.data(withJSONObject: [
            "cliSessionId": "cli-1", "title": "Renamed", "lastActivityAt": 3_000,
        ]).write(to: url)
        // Force a distinct mtime so the cache invalidates.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: url.path
        )
        XCTAssertEqual(reader.infoBySessionId()["cli-1"]?.title, "Renamed")
    }

    func testMissingDirectoryYieldsEmpty() {
        let missing = DesktopSessionMetadataReader(
            directory: directory.appendingPathComponent("nope")
        )
        XCTAssertTrue(missing.infoBySessionId().isEmpty)
    }
}
