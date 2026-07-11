@testable import HookInstaller
import XCTest

final class HookInstallerTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL!
    private var installer: HookInstaller!
    private let helperPath = "/Users/test/Library/Application Support/NotchPilot/bin/notchpilot-hook"

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HookInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        installer = HookInstaller(settingsURL: settingsURL, helperPath: helperPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func writeSettings(_ json: String) throws {
        try Data(json.utf8).write(to: settingsURL)
    }

    private func parsedSettings() throws -> NSDictionary {
        let data = try Data(contentsOf: settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func backupFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".notchpilot-") && $0.hasSuffix(".bak") }
    }

    // MARK: Fresh install

    func testInstallIntoMissingFileCreatesAllFourHooks() throws {
        try installer.install()
        let settings = try parsedSettings()
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        for event in HookInstaller.managedEvents {
            let entries = try XCTUnwrap(hooks[event] as? [[String: Any]], "missing \(event)")
            XCTAssertEqual(entries.count, 1)
            let inner = try XCTUnwrap(entries[0]["hooks"] as? [[String: Any]])
            let command = try XCTUnwrap(inner[0]["command"] as? String)
            XCTAssertTrue(command.contains(helperPath))
            XCTAssertTrue(command.hasSuffix(" \(event)"))
            XCTAssertEqual(inner[0]["type"] as? String, "command")
        }
        XCTAssertTrue(installer.isInstalled())
    }

    func testHelperPathWithSpacesIsQuoted() throws {
        try installer.install()
        let settings = try parsedSettings()
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let entries = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let inner = try XCTUnwrap(entries[0]["hooks"] as? [[String: Any]])
        let command = try XCTUnwrap(inner[0]["command"] as? String)
        XCTAssertEqual(command, "\"\(helperPath)\" SessionStart")
    }

    // MARK: Idempotency (spec §7: apply twice → identical file)

    func testInstallTwiceIsIdempotent() throws {
        try installer.install()
        let firstContents = try Data(contentsOf: settingsURL)
        let backupsAfterFirst = try backupFiles().count

        let backup = try installer.install()
        XCTAssertNil(backup, "second install must be a no-op")
        XCTAssertEqual(try Data(contentsOf: settingsURL), firstContents)
        XCTAssertEqual(try backupFiles().count, backupsAfterFirst, "no extra backup on no-op")
    }

    // MARK: Merging with existing content

    func testInstallPreservesExistingHooksAndSettings() throws {
        try writeSettings("""
        {
            "model": "opus",
            "permissions": {"allow": ["Bash(ls:*)"]},
            "hooks": {
                "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "my-formatter"}]}],
                "SessionStart": [{"hooks": [{"type": "command", "command": "echo hi"}]}]
            }
        }
        """)
        try installer.install()
        let settings = try parsedSettings()

        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertNotNil(settings["permissions"])

        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let postToolUse = try XCTUnwrap(hooks["PostToolUse"] as? [[String: Any]])
        XCTAssertEqual(postToolUse.count, 1, "foreign hook untouched")

        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        XCTAssertEqual(sessionStart.count, 2, "user's SessionStart entry kept, ours appended")
        let firstInner = try XCTUnwrap(sessionStart[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(firstInner[0]["command"] as? String, "echo hi")
        XCTAssertTrue(installer.isInstalled())
    }

    // MARK: Uninstall (spec §7: uninstall → original restored)

    func testUninstallRestoresOriginalSemantics() throws {
        let original = """
        {
            "model": "opus",
            "hooks": {
                "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "my-formatter"}]}],
                "SessionStart": [{"hooks": [{"type": "command", "command": "echo hi"}]}]
            }
        }
        """
        try writeSettings(original)
        let originalParsed = try parsedSettings()

        try installer.install()
        XCTAssertTrue(installer.isInstalled())
        try installer.uninstall()

        XCTAssertEqual(try parsedSettings(), originalParsed)
        XCTAssertFalse(installer.isInstalled())
    }

    func testUninstallOnFreshInstallLeavesNoHooksKey() throws {
        try installer.install()
        try installer.uninstall()
        let settings = try parsedSettings()
        XCTAssertNil(settings["hooks"], "empty hooks dictionary should be removed entirely")
    }

    func testUninstallWhenNotInstalledIsNoOp() throws {
        try writeSettings(#"{"model": "opus"}"#)
        let backup = try installer.uninstall()
        XCTAssertNil(backup)
        XCTAssertEqual(try parsedSettings(), ["model": "opus"] as NSDictionary)
    }

    // MARK: Malformed settings (spec §5: refuse to write)

    func testMalformedSettingsRefusedOnInstall() throws {
        try writeSettings("{ this is not json")
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? HookInstaller.InstallerError, .malformedSettings)
        }
        // File must be untouched.
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "{ this is not json")
        XCTAssertEqual(try backupFiles().count, 0)
        XCTAssertFalse(installer.isInstalled())
    }

    func testWrongShapeHooksKeyRefused() throws {
        try writeSettings(#"{"hooks": "surprise, a string"}"#)
        XCTAssertThrowsError(try installer.install())
    }

    // MARK: Backups

    func testTimestampedBackupCreatedBeforeModifyingWrite() throws {
        try writeSettings(#"{"model": "opus"}"#)
        let backup = try XCTUnwrap(try installer.install())
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let backupContents = try String(contentsOf: backup, encoding: .utf8)
        XCTAssertEqual(backupContents, #"{"model": "opus"}"#)
    }

    func testNoBackupWhenCreatingFreshFile() throws {
        let backup = try installer.install()
        XCTAssertNil(backup, "no backup needed when settings.json did not exist")
        XCTAssertEqual(try backupFiles().count, 0)
    }
}
