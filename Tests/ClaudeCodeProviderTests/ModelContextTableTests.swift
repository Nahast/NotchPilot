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
}
