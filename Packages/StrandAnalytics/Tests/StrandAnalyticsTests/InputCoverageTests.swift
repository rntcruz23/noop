import XCTest
@testable import StrandAnalytics

/// Coverage classification + summary tests. `testSummaryParityFixture` is the CROSS-PLATFORM
/// CONTRACT: the Android twin (InputCoverageTest.kt) classifies the same counts and asserts the
/// same summary bytes. Change one, change both.
final class InputCoverageTests: XCTestCase {

    func testThresholdBoundaries() {
        let rows = InputCoverage.classify(counts: [
            "hr": 3600,        // exactly the regular threshold
            "rr": 119,         // one under → sparse
            "motion": 1,       // any trickle → sparse
            "skin_temp": 0,    // explicit zero → missing
            // resp/spo2/steps omitted → missing
        ])
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.status) })
        XCTAssertEqual(byId["hr"], .regular)
        XCTAssertEqual(byId["rr"], .sparse)
        XCTAssertEqual(byId["motion"], .sparse)
        XCTAssertEqual(byId["skin_temp"], .missing)
        XCTAssertEqual(byId["resp"], .missing)
        XCTAssertEqual(byId["spo2"], .missing)
        XCTAssertEqual(byId["steps"], .missing)
    }

    func testRowsKeepFixedDisplayOrder() {
        let rows = InputCoverage.classify(counts: [:])
        XCTAssertEqual(rows.map { $0.id },
                       ["hr", "rr", "motion", "skin_temp", "resp", "spo2", "steps"])
    }

    func testFetchLimitMatchesRegularThreshold() {
        XCTAssertEqual(InputCoverage.fetchLimit("hr"), 3600)
        XCTAssertEqual(InputCoverage.fetchLimit("skin_temp"), 24)
        XCTAssertEqual(InputCoverage.fetchLimit("nonsense"), 1)   // unknown id stays harmless
    }

    func testAllMissingCollapsesToNoDataSentence() {
        let rows = InputCoverage.classify(counts: [:])
        XCTAssertEqual(InputCoverage.summary(rows: rows),
                       "No sensor data from this strap in the last 24 hours.")
    }

    func testEmptyGroupsAreOmitted() {
        // Everything regular → only the first sentence.
        let allRegular = InputCoverage.classify(counts: [
            "hr": 4000, "rr": 200, "motion": 4000, "skin_temp": 30,
            "resp": 30, "spo2": 30, "steps": 30,
        ])
        XCTAssertEqual(InputCoverage.summary(rows: allRegular),
                       "Feeding your scores: Heart rate, R-R intervals, Motion, Skin temp, Respiratory, Blood oxygen, Steps.")
    }

    /// THE cross-platform fixture — same counts, same bytes as the Kotlin twin. A realistic 5/MG
    /// day: HR + motion banking regularly, R-R trickling, skin temp trickling, no SpO2/resp/steps.
    func testSummaryParityFixture() {
        let rows = InputCoverage.classify(counts: [
            "hr": 3600, "rr": 42, "motion": 3600, "skin_temp": 3,
        ])
        XCTAssertEqual(InputCoverage.summary(rows: rows),
                       "Feeding your scores: Heart rate, Motion. "
                       + "Sparse: R-R intervals, Skin temp. "
                       + "Missing: Respiratory, Blood oxygen, Steps.")
    }
}
