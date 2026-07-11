import AgentCore
import XCTest

final class TokenTallyTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(TokenTally(tokens: 950).formatted, "950")
        XCTAssertEqual(TokenTally(tokens: 215_432).formatted, "215k")
        XCTAssertEqual(TokenTally(tokens: 1_234_000).formatted, "1.2M")
        XCTAssertEqual(TokenTally(tokens: 215_432, isApproximate: true).formatted, "≈215k")
    }
}
