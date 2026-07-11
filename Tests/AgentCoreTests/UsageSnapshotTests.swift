import AgentCore
import XCTest

final class UsageSnapshotTests: XCTestCase {
    func testParsesKnownAndPerModelWindows() throws {
        let json = """
        {
            "five_hour": {"utilization": 16, "resets_at": "2026-07-08T23:20:00.000Z"},
            "seven_day": {"utilization": 19, "resets_at": "2026-07-12T09:00:00.000Z"},
            "seven_day_opus": {"utilization": 42.5, "resets_at": "2026-07-12T09:00:00.000Z"},
            "seven_day_fable": {"utilization": 7, "resets_at": "2026-07-12T09:00:00.000Z"},
            "extra_metadata": "ignored"
        }
        """
        let snapshot = try XCTUnwrap(UsageSnapshot.parse(from: Data(json.utf8)))
        XCTAssertEqual(snapshot.windows.map(\.key), [
            "five_hour", "seven_day", "seven_day_fable", "seven_day_opus",
        ], "5h first, 7d second, then per-model windows")

        let fiveHour = snapshot.windows[0]
        XCTAssertEqual(fiveHour.label, "5h")
        XCTAssertEqual(fiveHour.usedFraction, 0.16, accuracy: 0.001)
        XCTAssertEqual(fiveHour.remainingFraction, 0.84, accuracy: 0.001)
        XCTAssertNotNil(fiveHour.resetsAt)

        XCTAssertEqual(snapshot.windows[2].label, "7d Fable")
        XCTAssertEqual(snapshot.windows[3].label, "7d Opus")
    }

    func testUnknownWindowKeysGetReadableLabels() {
        XCTAssertEqual(UsageSnapshot.label(forKey: "five_hour"), "5h")
        XCTAssertEqual(UsageSnapshot.label(forKey: "seven_day"), "7d")
        XCTAssertEqual(UsageSnapshot.label(forKey: "seven_day_fable"), "7d Fable")
        XCTAssertEqual(UsageSnapshot.label(forKey: "thirty_day"), "Thirty Day")
    }

    func testUtilizationClamped() throws {
        let json = #"{"five_hour": {"utilization": 250}}"#
        let snapshot = try XCTUnwrap(UsageSnapshot.parse(from: Data(json.utf8)))
        XCTAssertEqual(snapshot.windows[0].usedFraction, 1.0)
        XCTAssertEqual(snapshot.windows[0].remainingFraction, 0.0)
    }

    func testGarbageYieldsNil() {
        XCTAssertNil(UsageSnapshot.parse(from: Data("not json".utf8)))
        XCTAssertNil(UsageSnapshot.parse(from: Data("{}".utf8)))
        XCTAssertNil(UsageSnapshot.parse(from: Data(#"{"error": "unauthorized"}"#.utf8)))
    }
}
