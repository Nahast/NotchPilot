import AgentCore
import XCTest

final class SessionListLayoutTests: XCTestCase {
    private func session(
        _ id: String,
        isActive: Bool = true,
        isRoutine: Bool = false,
        lastActivityAt: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: id,
            projectPath: "/p/\(id)",
            status: .working,
            stateChangedAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: lastActivityAt),
            isActive: isActive,
            isRoutine: isRoutine
        )
    }

    func testActivesCappedAtLimit() {
        let sessions = (1...8).map { session("a\($0)") }
        let groups = SessionListLayout.groups(from: sessions, limit: 5)
        XCTAssertEqual(groups.active.count, 5)
        XCTAssertEqual(groups.active.map(\.id), ["a1", "a2", "a3", "a4", "a5"], "input order preserved")
        XCTAssertTrue(groups.inactive.isEmpty, "no fill when actives hit the cap")
    }

    func testMostRecentInactiveFillsUpToLimit() {
        let sessions = [
            session("a1"), session("a2"),
            session("old", isActive: false, lastActivityAt: 100),
            session("newest", isActive: false, lastActivityAt: 300),
            session("newer", isActive: false, lastActivityAt: 200),
            session("oldest", isActive: false, lastActivityAt: 50),
        ]
        let groups = SessionListLayout.groups(from: sessions, limit: 5)
        XCTAssertEqual(groups.active.map(\.id), ["a1", "a2"])
        XCTAssertEqual(groups.inactive.map(\.id), ["newest", "newer", "old"], "3 most recent fill to 5")
    }

    func testRoutinesAreSeparateAndExcludedFromMainList() {
        let sessions = [
            session("r1", isRoutine: true),
            session("a1"),
            session("r2", isActive: false, isRoutine: true, lastActivityAt: 10),
        ]
        let groups = SessionListLayout.groups(from: sessions, limit: 5)
        XCTAssertEqual(groups.active.map(\.id), ["a1"])
        XCTAssertEqual(groups.routines.map(\.id), ["r1", "r2"], "active routines first, then recent")
    }

    func testEmptyInput() {
        XCTAssertTrue(SessionListLayout.groups(from: []).isEmpty)
    }
}
