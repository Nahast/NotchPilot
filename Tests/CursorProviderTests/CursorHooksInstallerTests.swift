@testable import CursorProvider
import XCTest

final class CursorHooksInstallerTests: XCTestCase {
    private var directory: URL!
    private var hooksURL: URL!
    private var installer: CursorHooksInstaller!
    private let helperPath = "/Users/test/Library/Application Support/NotchPilot/bin/notchpilot-hook"

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CursorHooksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hooksURL = directory.appendingPathComponent("hooks.json")
        installer = CursorHooksInstaller(hooksURL: hooksURL, helperPath: helperPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func parsed() throws -> NSDictionary {
        let data = try Data(contentsOf: hooksURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testFreshInstallCreatesAllManagedHooks() throws {
        try installer.install()
        let root = try parsed()
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        for (cursorEvent, spoolName) in CursorHooksInstaller.managedEvents {
            let entries = try XCTUnwrap(hooks[cursorEvent] as? [[String: Any]], "missing \(cursorEvent)")
            let command = try XCTUnwrap(entries[0]["command"] as? String)
            XCTAssertTrue(command.contains(helperPath))
            XCTAssertTrue(command.contains(spoolName))
            XCTAssertTrue(command.hasSuffix(" cursor-events"))
        }
        XCTAssertTrue(installer.isInstalled())
    }

    func testInstallIsIdempotent() throws {
        try installer.install()
        let first = try Data(contentsOf: hooksURL)
        XCTAssertNil(try installer.install(), "second install must be a no-op")
        XCTAssertEqual(try Data(contentsOf: hooksURL), first)
    }

    func testInstallPreservesForeignHooks() throws {
        try Data("""
        {"version": 1, "hooks": {"stop": [{"command": "my-own-stop-hook"}], "beforeReadFile": [{"command": "audit"}]}}
        """.utf8).write(to: hooksURL)
        try installer.install()
        let hooks = try XCTUnwrap(try parsed()["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2, "foreign stop hook kept, ours appended")
        XCTAssertEqual(stop[0]["command"] as? String, "my-own-stop-hook")
        XCTAssertNotNil(hooks["beforeReadFile"])
    }

    func testUninstallRestoresOriginalSemantics() throws {
        let original = """
        {"version": 1, "hooks": {"stop": [{"command": "my-own-stop-hook"}]}}
        """
        try Data(original.utf8).write(to: hooksURL)
        let originalParsed = try parsed()

        try installer.install()
        try installer.uninstall()
        XCTAssertEqual(try parsed(), originalParsed)
        XCTAssertFalse(installer.isInstalled())
    }

    func testMalformedFileRefused() throws {
        try Data("{ nope".utf8).write(to: hooksURL)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? CursorHooksInstaller.InstallerError, .malformedHooksFile)
        }
        XCTAssertEqual(try String(contentsOf: hooksURL, encoding: .utf8), "{ nope")
    }

    func testBackupCreatedBeforeModifyingWrite() throws {
        try Data(#"{"version": 1}"#.utf8).write(to: hooksURL)
        let backup = try XCTUnwrap(try installer.install())
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), #"{"version": 1}"#)
    }
}
