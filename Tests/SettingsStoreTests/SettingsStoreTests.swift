import SettingsStore
import XCTest

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAgentConnectionsDefaultToEnabled() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.claudeEnabled)
        XCTAssertTrue(store.codexEnabled)
        XCTAssertTrue(store.cursorEnabled)
    }

    func testDisconnectPersistsAcrossLaunches() {
        let store = SettingsStore(defaults: defaults)
        store.codexEnabled = false
        store.cursorEnabled = false

        // A fresh store over the same defaults = app relaunch.
        let relaunched = SettingsStore(defaults: defaults)
        XCTAssertTrue(relaunched.claudeEnabled)
        XCTAssertFalse(relaunched.codexEnabled)
        XCTAssertFalse(relaunched.cursorEnabled)
    }

    func testReconnectPersists() {
        let store = SettingsStore(defaults: defaults)
        store.claudeEnabled = false
        store.claudeEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).claudeEnabled)
    }

    // MARK: Schema versioning

    /// A fresh install must stamp the current schema version so a future
    /// migration can tell "new install" from "pre-versioning install".
    func testFreshInstallStampsCurrentSchemaVersion() {
        _ = SettingsStore(defaults: defaults)
        XCTAssertEqual(
            defaults.integer(forKey: "settingsSchemaVersion"),
            SettingsStore.currentSchemaVersion
        )
    }

    /// An install that predates versioning (has settings but no version key)
    /// must be recognized as version 0 and migrated forward, not treated as
    /// fresh — its existing choices survive.
    func testPreVersioningInstallMigratesWithoutLosingSettings() {
        defaults.set(false, forKey: "agentCodexEnabled") // user's prior choice
        defaults.set(true, forKey: "didCompleteOnboarding")

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.codexEnabled, "migration must not clobber existing settings")
        XCTAssertTrue(store.didCompleteOnboarding)
        XCTAssertEqual(defaults.integer(forKey: "settingsSchemaVersion"),
                       SettingsStore.currentSchemaVersion)
    }

    /// A downgrade (defaults written by a NEWER app version) must leave the
    /// stored version untouched rather than silently rewriting it backwards.
    func testNewerSchemaVersionIsLeftAlone() {
        defaults.set(SettingsStore.currentSchemaVersion + 5, forKey: "settingsSchemaVersion")
        _ = SettingsStore(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsSchemaVersion"),
                       SettingsStore.currentSchemaVersion + 5)
    }
}
