@testable import JumpService
import XCTest

final class JumpServiceTests: XCTestCase {
    /// The path is interpolated into AppleScript source; backslashes and
    /// quotes must arrive escaped or the script breaks (or worse, runs with a
    /// different meaning).
    func testEscapesBackslashesAndQuotes() {
        XCTAssertEqual(
            JumpService.appleScriptStringLiteral(#"/Users/x/we"ird\path"#),
            #"/Users/x/we\"ird\\path"#
        )
    }

    func testPlainPathPassesThrough() {
        XCTAssertEqual(
            JumpService.appleScriptStringLiteral("/Users/rjouffret/Projects/NotchApp"),
            "/Users/rjouffret/Projects/NotchApp"
        )
    }

    /// Control characters (a newline is legal in a macOS filename) cannot be
    /// escaped into a single-line AppleScript literal — the script must not
    /// be built at all, so the caller falls back to app activation.
    func testControlCharactersRefuseToBuildAScript() {
        XCTAssertNil(JumpService.appleScriptStringLiteral("/Users/x/line\nbreak"))
        XCTAssertNil(JumpService.appleScriptStringLiteral("/Users/x/tab\there"))
        XCTAssertNil(JumpService.appleScriptStringLiteral("/Users/x/cr\rhere"))
        XCTAssertNil(JumpService.appleScriptStringLiteral("/Users/x/del\u{7F}here"))
    }
}
