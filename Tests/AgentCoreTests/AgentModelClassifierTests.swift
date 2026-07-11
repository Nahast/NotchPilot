import AgentCore
import XCTest

final class AgentModelClassifierTests: XCTestCase {
    func testSyntheticDetection() {
        XCTAssertTrue(AgentModelClassifier.isSynthetic("<synthetic>"))
        XCTAssertTrue(AgentModelClassifier.isSynthetic("  <SYNTHETIC>  "))
        XCTAssertTrue(AgentModelClassifier.isSynthetic("<something-else>"))
        XCTAssertFalse(AgentModelClassifier.isSynthetic("claude-opus-4-8"))
        XCTAssertFalse(AgentModelClassifier.isSynthetic(nil))
        XCTAssertFalse(AgentModelClassifier.isSynthetic(""))
    }

    func testListedDetection() {
        for id in ["claude-opus-4-8", "claude-sonnet-5", "claude-fable-5",
                   "claude-haiku-4-5-20251001", "sonnet", "opus", "haiku",
                   "claude-sonnet-4-5[1m]"] {
            XCTAssertTrue(AgentModelClassifier.isListed(id), "\(id) should be listed")
        }
        XCTAssertFalse(AgentModelClassifier.isListed("<synthetic>"))
        XCTAssertFalse(AgentModelClassifier.isListed("gpt-4o"))
        XCTAssertFalse(AgentModelClassifier.isListed(nil))
    }

    func testSyntheticOrUnlisted() {
        // Hidden: synthetic and unrecognized models.
        XCTAssertTrue(AgentModelClassifier.isSyntheticOrUnlisted("<synthetic>"))
        XCTAssertTrue(AgentModelClassifier.isSyntheticOrUnlisted("gpt-4o"))
        XCTAssertTrue(AgentModelClassifier.isSyntheticOrUnlisted("some-internal-model"))
        // Visible: known models and the not-yet-known (nil/empty) case.
        XCTAssertFalse(AgentModelClassifier.isSyntheticOrUnlisted("claude-opus-4-8"))
        XCTAssertFalse(AgentModelClassifier.isSyntheticOrUnlisted(nil))
        XCTAssertFalse(AgentModelClassifier.isSyntheticOrUnlisted(""))
    }

    func testIsHiddenByModelScopedToClaude() {
        func session(kind: AgentKind, model: String?) -> AgentSession {
            AgentSession(
                id: "s", projectPath: "/p", status: .working,
                stateChangedAt: Date(timeIntervalSince1970: 0),
                lastActivityAt: Date(timeIntervalSince1970: 0),
                model: model, agentKind: kind
            )
        }
        XCTAssertTrue(session(kind: .claude, model: "<synthetic>").isHiddenByModel)
        XCTAssertTrue(session(kind: .claude, model: "mystery-model").isHiddenByModel)
        XCTAssertFalse(session(kind: .claude, model: "claude-opus-4-8").isHiddenByModel)
        XCTAssertFalse(session(kind: .claude, model: nil).isHiddenByModel)
        // A Codex session with an unfamiliar model is never hidden by this rule.
        XCTAssertFalse(session(kind: .codex, model: "gpt-5-codex").isHiddenByModel)
    }
}
