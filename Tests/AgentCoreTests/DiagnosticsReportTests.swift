import AgentCore
import XCTest

final class DiagnosticsReportTests: XCTestCase {
    /// A baseline input with distinctive personal-looking values so leak
    /// tests can assert on their absence.
    private func makeInput(
        sessions: [AgentSession] = [],
        degradations: [String: String] = [:],
        usageEnabled: Bool = true,
        usageSignedOut: Bool = false
    ) -> DiagnosticsReport.Input {
        DiagnosticsReport.Input(
            appVersion: "1.2.3",
            appBuild: "45",
            macOSVersion: "Version 15.5 (Build 24F74)",
            hooksInstalled: true,
            helperPresent: true,
            // The absolute path production actually passes — a `~` fixture
            // would make the leak assertions below pass vacuously.
            helperInstallPath: "/Users/someone/Library/Application Support/NotchPilot/bin/notchpilot-hook",
            homeDirectory: "/Users/someone",
            agents: [
                .init(name: "Claude Code", enabled: true),
                .init(name: "Codex", enabled: true),
                .init(name: "Cursor", enabled: false),
            ],
            sessions: sessions,
            isLimitedMode: false,
            degradations: degradations,
            usageEnabled: usageEnabled,
            usageSignedOut: usageSignedOut
        )
    }

    private func makeSession(
        id: String = "s1",
        projectPath: String = "/Users/someone/very-private-project",
        status: AgentStatus = .working,
        name: String? = "secret-session-name",
        kind: AgentKind = .claude
    ) -> AgentSession {
        AgentSession(
            id: id,
            projectPath: projectPath,
            status: status,
            stateChangedAt: Date(),
            lastActivityAt: Date(),
            name: name,
            agentKind: kind
        )
    }

    func testHeaderStatesNoPersonalDataAndLocalOnly() {
        let report = DiagnosticsReport.render(makeInput())
        let firstLines = report.split(separator: "\n").prefix(4).joined(separator: "\n")
        XCTAssertTrue(firstLines.contains("no personal data"),
                      "the privacy statement must lead the report")
        XCTAssertTrue(report.contains("unless you paste it somewhere yourself"))
    }

    func testBasicFieldsAppear() {
        let report = DiagnosticsReport.render(makeInput())
        XCTAssertTrue(report.contains("NotchPilot 1.2.3 (build 45)"))
        XCTAssertTrue(report.contains("macOS: Version 15.5 (Build 24F74)"))
        XCTAssertTrue(report.contains("Hooks installed: yes"))
        XCTAssertTrue(report.contains(
            "Helper: present at ~/Library/Application Support/NotchPilot/bin/notchpilot-hook"))
        XCTAssertTrue(report.contains("Claude Code: connected"))
        XCTAssertTrue(report.contains("Cursor: disconnected"))
        XCTAssertTrue(report.contains("Limited mode: no"))
    }

    /// The header promises "no personal data", and a macOS short name is very
    /// often the user's real name — the only varying part of an otherwise
    /// fixed install path, so it has to be folded back to `~`.
    func testHelperPathHasTheHomeDirectoryRedacted() {
        let report = DiagnosticsReport.render(makeInput())
        XCTAssertTrue(report.contains(
            "Helper: present at ~/Library/Application Support/NotchPilot/bin/notchpilot-hook"))
        XCTAssertFalse(report.contains("/Users/"))
    }

    /// A helper somewhere other than the home directory carries no username to
    /// redact, and the location is the whole point of the line — leave it be.
    func testHelperPathOutsideHomeIsReportedVerbatim() {
        var input = makeInput()
        input.helperInstallPath = "/opt/notchpilot/bin/notchpilot-hook"
        let report = DiagnosticsReport.render(input)
        XCTAssertTrue(report.contains("Helper: present at /opt/notchpilot/bin/notchpilot-hook"))
    }

    func testMissingHelperAndAbsentHooksRender() {
        var input = makeInput()
        input.hooksInstalled = false
        input.helperPresent = false
        input.isLimitedMode = true
        let report = DiagnosticsReport.render(input)
        XCTAssertTrue(report.contains("Hooks installed: no"))
        XCTAssertTrue(report.contains("Helper: MISSING at "))
        XCTAssertTrue(report.contains("Limited mode: yes"))
    }

    func testSessionCountsByKindAndStatus() {
        let sessions = [
            makeSession(id: "a", status: .working, kind: .claude),
            makeSession(id: "b", status: .working, kind: .claude),
            makeSession(id: "c", status: .idle, kind: .claude),
            makeSession(id: "d", status: .needsAttention, kind: .codex),
        ]
        let report = DiagnosticsReport.render(makeInput(sessions: sessions))
        XCTAssertTrue(report.contains("Sessions: 4"))
        XCTAssertTrue(report.contains("claude: 3 (working 2, needs-attention 0, idle 1)"))
        XCTAssertTrue(report.contains("codex: 1 (working 0, needs-attention 1, idle 0)"))
        // Kinds without sessions stay out — a report full of zero rows buries
        // the signal.
        XCTAssertFalse(report.contains("cursor: 0"))
    }

    func testNoSessionsRendersNone() {
        let report = DiagnosticsReport.render(makeInput(sessions: []))
        XCTAssertTrue(report.contains("Sessions: none"))
    }

    /// The one guarantee the whole feature rests on: whatever sessions come
    /// in, nothing identifying leaves — only aggregate counts.
    func testSessionNamesAndPathsNeverLeak() {
        let sessions = [
            makeSession(projectPath: "/Users/someone/very-private-project",
                        name: "secret-session-name"),
        ]
        let report = DiagnosticsReport.render(makeInput(sessions: sessions))
        XCTAssertFalse(report.contains("very-private-project"))
        XCTAssertFalse(report.contains("secret-session-name"))
        XCTAssertFalse(report.contains("/Users/someone"))
    }

    func testDegradationsListedSortedByKey() {
        let report = DiagnosticsReport.render(makeInput(degradations: [
            "helper": "Hook helper couldn't be installed",
            "claude-hooks": "Claude hooks couldn't be installed",
        ]))
        let claudeRange = report.range(of: "claude-hooks: Claude hooks couldn't be installed")
        let helperRange = report.range(of: "helper: Hook helper couldn't be installed")
        XCTAssertNotNil(claudeRange)
        XCTAssertNotNil(helperRange)
        // Sorted keys make two reports diffable against each other.
        XCTAssertTrue(claudeRange!.lowerBound < helperRange!.lowerBound)
    }

    func testNoDegradationsRendersNone() {
        let report = DiagnosticsReport.render(makeInput(degradations: [:]))
        XCTAssertTrue(report.contains("Degradations: none"))
    }

    func testUsageGaugeStates() {
        XCTAssertTrue(DiagnosticsReport.render(makeInput(usageEnabled: false))
            .contains("Usage gauge: disabled"))
        XCTAssertTrue(DiagnosticsReport.render(makeInput(usageEnabled: true, usageSignedOut: false))
            .contains("Usage gauge: enabled, signed in"))
        XCTAssertTrue(DiagnosticsReport.render(makeInput(usageEnabled: true, usageSignedOut: true))
            .contains("Usage gauge: enabled, signed out"))
    }
}
