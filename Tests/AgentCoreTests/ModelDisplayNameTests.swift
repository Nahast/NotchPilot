import AgentCore
import XCTest

final class ModelDisplayNameTests: XCTestCase {
    func testModernIds() {
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-fable-5"), "Fable 5")
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-sonnet-5"), "Sonnet 5")
    }

    func testLongContextSuffix() {
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-sonnet-4-5[1m]"), "Sonnet 4.5 1M")
    }

    func testDateStampedIds() {
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-sonnet-4-20250514"), "Sonnet 4")
    }

    func testLegacyVersionFirstIds() {
        XCTAssertEqual(ModelDisplayName.displayName(for: "claude-3-5-haiku-20241022"), "Haiku 3.5")
    }

    func testNilAndEmpty() {
        XCTAssertNil(ModelDisplayName.displayName(for: nil))
        XCTAssertNil(ModelDisplayName.displayName(for: ""))
    }
}
