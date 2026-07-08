@testable import ClaudeCodeProvider
import XCTest

final class ActivityFormatterTests: XCTestCase {
    func testEditShowsBasename() {
        XCTAssertEqual(
            ActivityFormatter.describe(toolName: "Edit", input: ["file_path": "/a/b/main.swift"]),
            "Editing main.swift…"
        )
    }

    func testWriteShowsBasename() {
        XCTAssertEqual(
            ActivityFormatter.describe(toolName: "Write", input: ["file_path": "/a/README.md"]),
            "Writing README.md…"
        )
    }

    func testBashPrefersDescription() {
        XCTAssertEqual(
            ActivityFormatter.describe(
                toolName: "Bash",
                input: ["command": "swift test 2>&1", "description": "Run the test suite"]
            ),
            "Run the test suite"
        )
    }

    func testBashFallsBackToTruncatedCommand() {
        let long = String(repeating: "x", count: 100)
        let result = ActivityFormatter.describe(toolName: "Bash", input: ["command": long])
        XCTAssertTrue(result.hasPrefix("Running: xxxx"))
        XCTAssertTrue(result.hasSuffix("…"))
        XCTAssertLessThan(result.count, 60)
    }

    func testGrepShowsPattern() {
        XCTAssertEqual(
            ActivityFormatter.describe(toolName: "Grep", input: ["pattern": "AgentStatus"]),
            "Searching \"AgentStatus\"…"
        )
    }

    func testUnknownToolShowsName() {
        XCTAssertEqual(
            ActivityFormatter.describe(toolName: "SomeFutureTool", input: [:]),
            "SomeFutureTool…"
        )
    }

    func testMissingInputsDoNotCrash() {
        XCTAssertEqual(ActivityFormatter.describe(toolName: "Edit", input: [:]), "Editing files…")
        XCTAssertEqual(ActivityFormatter.describe(toolName: "Bash", input: [:]), "Running a command…")
        XCTAssertEqual(ActivityFormatter.describe(toolName: "Grep", input: [:]), "Searching…")
    }
}
