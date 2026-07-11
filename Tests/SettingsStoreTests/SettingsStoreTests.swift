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
}
