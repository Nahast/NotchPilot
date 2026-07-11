import AgentCore
@testable import ClaudeCodeProvider
import XCTest

final class SessionRegistryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SessionRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func writeEntry(
        pid: Int,
        sessionId: String,
        kind: String = "interactive",
        name: String? = nil,
        cwd: String = "/Users/romain/Projects/demo"
    ) throws {
        var payload: [String: Any] = [
            "pid": pid,
            "sessionId": sessionId,
            "kind": kind,
            "entrypoint": "claude-desktop",
            "cwd": cwd,
        ]
        if let name { payload["name"] = name }
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: directory.appendingPathComponent("\(pid).json"))
    }

    func testReadsAliveEntriesOnly() throws {
        try writeEntry(pid: 100, sessionId: "alive-session", name: "droplet-a1")
        try writeEntry(pid: 200, sessionId: "dead-session", name: "droplet-b2")

        let reader = SessionRegistryReader(directory: directory) { pid in pid == 100 }
        let entries = reader.aliveEntries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries["alive-session"]?.name, "droplet-a1")
        XCTAssertNil(entries["dead-session"])
    }

    func testRoutineDetectionFromKind() throws {
        try writeEntry(pid: 100, sessionId: "s1", kind: "interactive")
        try writeEntry(pid: 200, sessionId: "s2", kind: "scheduled")

        let reader = SessionRegistryReader(directory: directory) { _ in true }
        let entries = reader.aliveEntries()

        XCTAssertEqual(entries["s1"]?.isRoutine, false)
        XCTAssertEqual(entries["s2"]?.isRoutine, true)
    }

    func testMalformedFilesAreSkipped() throws {
        try Data("not json".utf8).write(to: directory.appendingPathComponent("999.json"))
        try writeEntry(pid: 100, sessionId: "good")

        let reader = SessionRegistryReader(directory: directory) { _ in true }
        XCTAssertEqual(reader.aliveEntries().count, 1)
    }

    func testMissingDirectoryYieldsEmpty() {
        let reader = SessionRegistryReader(
            directory: directory.appendingPathComponent("does-not-exist")
        ) { _ in true }
        XCTAssertTrue(reader.aliveEntries().isEmpty)
    }

    func testDefaultLivenessCheckAgainstRealProcesses() {
        // Our own process is definitely alive; pid -1 is definitely not valid.
        XCTAssertTrue(SessionRegistryReader.defaultLivenessCheck(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(SessionRegistryReader.defaultLivenessCheck(-1))
    }
}
