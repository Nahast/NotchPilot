import AgentCore
import XCTest

final class AgentSessionTests: XCTestCase {
    private func makeSession(
        path: String = "/Users/romain/Projects/demo",
        used: Int? = nil,
        window: Int? = nil
    ) -> AgentSession {
        AgentSession(
            id: "s1",
            projectPath: path,
            status: .working,
            contextUsedTokens: used,
            contextWindowTokens: window,
            stateChangedAt: Date(timeIntervalSince1970: 0),
            lastActivityAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testProjectNameIsLastPathComponent() {
        XCTAssertEqual(makeSession(path: "/Users/romain/Projects/demo").projectName, "demo")
    }

    func testProjectNameFallsBackToRawPathWhenEmptyComponent() {
        XCTAssertEqual(makeSession(path: "").projectName, "")
    }

    func testContextUsageFraction() {
        XCTAssertEqual(makeSession(used: 50_000, window: 200_000).contextUsageFraction, 0.25)
    }

    func testContextUsageFractionClampsToOne() {
        XCTAssertEqual(makeSession(used: 300_000, window: 200_000).contextUsageFraction, 1.0)
    }

    func testContextUsageFractionNilWithoutBothNumbers() {
        XCTAssertNil(makeSession(used: 50_000, window: nil).contextUsageFraction)
        XCTAssertNil(makeSession(used: nil, window: 200_000).contextUsageFraction)
        XCTAssertNil(makeSession(used: 1, window: 0).contextUsageFraction)
    }
}
