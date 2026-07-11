@testable import ClaudeCodeProvider
import XCTest

final class ModelContextTableTests: XCTestCase {
    func testKnownModelsGet200k() {
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-sonnet-4-5"), 200_000)
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-opus-4-8"), 200_000)
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-3-5-haiku-20241022"), 200_000)
    }

    func testUnknownModelAssumes200k() {
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-hypothetical-9"), 200_000)
        XCTAssertEqual(ModelContextTable.contextWindow(for: nil), 200_000)
        XCTAssertEqual(ModelContextTable.contextWindow(for: ""), 200_000)
    }

    func testLongContextVariants() {
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-sonnet-4-5[1m]"), 1_000_000)
        XCTAssertEqual(ModelContextTable.contextWindow(for: "claude-sonnet-4-20250514-1m"), 1_000_000)
    }

    func testObservedUsageBeyondAssumedWindowProves1M() {
        // Real case: 1M-context sessions record plain ids ("claude-fable-5")
        // with usage far past 200k — the gauge must not clamp to red 100%.
        XCTAssertEqual(
            ModelContextTable.contextWindow(for: "claude-fable-5", observedUsedTokens: 411_083),
            1_000_000
        )
        // Usage within the assumed window changes nothing.
        XCTAssertEqual(
            ModelContextTable.contextWindow(for: "claude-fable-5", observedUsedTokens: 150_000),
            200_000
        )
        XCTAssertEqual(
            ModelContextTable.contextWindow(for: "claude-opus-4-8[1m]", observedUsedTokens: 50_000),
            1_000_000
        )
    }
}
