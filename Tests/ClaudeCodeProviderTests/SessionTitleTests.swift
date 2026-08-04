import AgentCore
@testable import ClaudeCodeProvider
import XCTest

/// The row title must match what the terminal tab shows. Claude Code writes
/// that string into the transcript as an `ai-title` line and separately
/// registers a *derived* placeholder name ("notchapp-2f") that the user never
/// sees anywhere — showing the placeholder is the bug these tests pin down.
final class SessionTitleTests: XCTestCase {
    private var store: SessionStore!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        store = SessionStore()
        clock = Date(timeIntervalSince1970: 1_000_000)
        store.now = { [weak self] in self?.clock ?? Date() }
    }

    // MARK: Parsing

    func testParsesAITitleLine() {
        let event = TranscriptLineParser.parse([
            "type": "ai-title",
            "aiTitle": "Fix Keychain authentication refreshing every 2 minutes",
            "sessionId": "s1",
        ])
        XCTAssertEqual(event?.kind, .title("Fix Keychain authentication refreshing every 2 minutes"))
    }

    func testBlankAITitleIsIgnored() {
        let event = TranscriptLineParser.parse(["type": "ai-title", "aiTitle": "", "sessionId": "s1"])
        XCTAssertEqual(event?.kind, .uninteresting, "an empty title must not blank out the row")
    }

    func testAITitleLineWithoutATitleIsIgnored() {
        let event = TranscriptLineParser.parse(["type": "ai-title", "sessionId": "s1"])
        XCTAssertEqual(event?.kind, .uninteresting)
    }

    // MARK: Precedence

    /// The reported bug: the panel showed "notchapp-2f" while iTerm showed
    /// "Fix Keychain authentication refreshing every 2 minutes".
    func testAITitleBeatsADerivedRegistryName() {
        seedSession()
        store.applyRegistry(["s1": registration(name: "notchapp-2f", nameSource: "derived")])
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        XCTAssertEqual(store.snapshot().first?.displayName,
                       "Fix Keychain authentication refreshing every 2 minutes")
    }

    /// Order must not matter — the registry is rescanned on every tick and
    /// would otherwise stomp the title back to the placeholder.
    func testRegistryRescanDoesNotClobberTheTitle() {
        seedSession()
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        store.applyRegistry(["s1": registration(name: "notchapp-2f", nameSource: "derived")])
        XCTAssertEqual(store.snapshot().first?.displayName,
                       "Fix Keychain authentication refreshing every 2 minutes")
    }

    /// A name the user chose themselves is what their terminal shows, so it
    /// outranks anything the model generated.
    func testExplicitlyNamedSessionKeepsItsName() {
        seedSession()
        store.applyRegistry(["s1": registration(name: "release-prep", nameSource: "user")])
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        XCTAssertEqual(store.snapshot().first?.displayName, "release-prep")
    }

    /// Older Claude Code builds omit nameSource; those names are the derived
    /// kind, so the title still wins.
    func testMissingNameSourceIsTreatedAsDerived() {
        seedSession()
        store.applyRegistry(["s1": registration(name: "notchapp-2f", nameSource: nil)])
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        XCTAssertEqual(store.snapshot().first?.displayName,
                       "Fix Keychain authentication refreshing every 2 minutes")
    }

    /// The desktop app's sidebar title is what the user sees for those
    /// sessions, and stays the top of the chain.
    func testDesktopTitleStillWins() {
        seedSession()
        store.applyRegistry(["s1": registration(name: "notchapp-2f", nameSource: "derived")])
        applyTitle("Generated title")
        store.applyDesktopMetadata(["s1": DesktopSessionInfo(title: "Sidebar title")])
        XCTAssertEqual(store.snapshot().first?.displayName, "Sidebar title")
    }

    /// Claude Code rewrites the title as the conversation moves on; the latest
    /// one is what the tab shows.
    func testLatestTitleWins() {
        seedSession()
        applyTitle("First understanding")
        applyTitle("What it actually turned into")
        XCTAssertEqual(store.snapshot().first?.displayName, "What it actually turned into")
    }

    /// With no title anywhere, the placeholder is still better than nothing.
    func testFallsBackToRegistryNameWithoutATitle() {
        seedSession()
        store.applyRegistry(["s1": registration(name: "notchapp-2f", nameSource: "derived")])
        XCTAssertEqual(store.snapshot().first?.displayName, "notchapp-2f")
    }

    /// A title line carries no timestamp and must not fabricate a session or
    /// move a status — it is metadata about a conversation, not activity.
    func testTitleAloneDoesNotCreateASession() {
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testTitleDoesNotChangeStatus() {
        seedSession()
        let before = store.snapshot().first?.status
        applyTitle("Fix Keychain authentication refreshing every 2 minutes")
        XCTAssertEqual(store.snapshot().first?.status, before)
    }

    // MARK: Helpers

    private func seedSession() {
        store.apply(hook: HookEvent(
            name: .sessionStart,
            sessionId: "s1",
            cwd: "/Users/rjouffret/Projects/NotchApp",
            message: nil,
            receivedAt: clock
        ))
    }

    private func applyTitle(_ title: String) {
        store.apply(
            transcript: TranscriptEvent(sessionId: "s1", cwd: nil, kind: .title(title)),
            fallbackSessionId: "s1",
            fallbackProjectPath: "/Users/rjouffret/Projects/NotchApp"
        )
    }

    private func registration(name: String?, nameSource: String?) -> SessionRegistryEntry {
        SessionRegistryEntry(
            sessionId: "s1",
            pid: 4242,
            kind: "interactive",
            entrypoint: "cli",
            name: name,
            nameSource: nameSource,
            cwd: "/Users/rjouffret/Projects/NotchApp"
        )
    }
}
