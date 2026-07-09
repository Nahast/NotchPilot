@testable import ClaudeCodeProvider
import XCTest

final class DesktopSessionTitleReaderTests: XCTestCase {
    private var directory: URL!
    private var reader: DesktopSessionTitleReader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopTitlesTests-\(UUID().uuidString)", isDirectory: true)
        // Mirror the real nesting: <org-uuid>/<workspace-uuid>/local_*.json
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("org-1/ws-1", isDirectory: true),
            withIntermediateDirectories: true
        )
        reader = DesktopSessionTitleReader(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func writeSessionFile(
        _ filename: String,
        cliSessionId: String?,
        title: String?,
        lastActivityAt: Double = 1_000
    ) throws {
        var payload: [String: Any] = ["sessionId": "local_\(UUID().uuidString)", "lastActivityAt": lastActivityAt]
        if let cliSessionId { payload["cliSessionId"] = cliSessionId }
        if let title { payload["title"] = title }
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: directory.appendingPathComponent("org-1/ws-1/\(filename)"))
    }

    func testMapsCliSessionIdToTitle() throws {
        try writeSessionFile("local_a.json", cliSessionId: "cli-1", title: "Automated development workflows")
        XCTAssertEqual(
            reader.titlesBySessionId(),
            ["cli-1": "Automated development workflows"]
        )
    }

    func testMostRecentFileWinsOnDuplicateSession() throws {
        try writeSessionFile("local_old.json", cliSessionId: "cli-1", title: "Old title", lastActivityAt: 1_000)
        try writeSessionFile("local_new.json", cliSessionId: "cli-1", title: "New title", lastActivityAt: 2_000)
        XCTAssertEqual(reader.titlesBySessionId()["cli-1"], "New title")
    }

    func testFilesWithoutTitleOrSessionAreSkipped() throws {
        try writeSessionFile("local_untitled.json", cliSessionId: "cli-1", title: nil)
        try writeSessionFile("local_orphan.json", cliSessionId: nil, title: "Orphan")
        try Data("not json".utf8).write(to: directory.appendingPathComponent("org-1/ws-1/broken.json"))
        XCTAssertTrue(reader.titlesBySessionId().isEmpty)
    }

    func testTitleUpdateIsPickedUpAfterFileChanges() throws {
        let url = directory.appendingPathComponent("org-1/ws-1/local_a.json")
        try writeSessionFile("local_a.json", cliSessionId: "cli-1", title: "First")
        XCTAssertEqual(reader.titlesBySessionId()["cli-1"], "First")

        try JSONSerialization.data(withJSONObject: [
            "cliSessionId": "cli-1", "title": "Renamed", "lastActivityAt": 3_000,
        ]).write(to: url)
        // Force a distinct mtime so the cache invalidates.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: url.path
        )
        XCTAssertEqual(reader.titlesBySessionId()["cli-1"], "Renamed")
    }

    func testMissingDirectoryYieldsEmpty() {
        let missing = DesktopSessionTitleReader(
            directory: directory.appendingPathComponent("nope")
        )
        XCTAssertTrue(missing.titlesBySessionId().isEmpty)
    }
}
