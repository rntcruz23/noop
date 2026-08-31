import XCTest
@testable import StrandAnalytics

final class TrendWindowTests: XCTestCase {
    func testFixedWindowIsInclusiveAndDoesNotWiden() {
        let rows: [(day: String, value: Double?)] = [
            ("2026-06-01", 1), ("2026-06-23", 2), ("2026-06-24", 3),
            ("2026-06-30", 4), ("2026-07-01", 5), ("bad", 6),
            ("2026-06-29", .nan),
        ]
        let result = TrendWindow.project(rows: rows, todayKey: "2026-06-30", dayCount: 7)
        XCTAssertEqual(result.startDay, "2026-06-24")
        XCTAssertEqual(result.endDay, "2026-06-30")
        XCTAssertEqual(result.points.map(\.day), ["2026-06-24", "2026-06-30"])
        XCTAssertEqual(result.observed, 2)
        XCTAssertEqual(result.expected, 7)
        XCTAssertTrue(result.hasOlderHistory)
    }

    func testDuplicateDaysResolveLastFiniteValue() {
        let result = TrendWindow.project(rows: [("2026-06-30", 1), ("2026-06-30", 2)],
                                         todayKey: "2026-06-30", dayCount: 7)
        XCTAssertEqual(result.points, [.init(day: "2026-06-30", value: 2)])
    }

    func testAllStartsAtEarliestValidObservation() {
        let result = TrendWindow.project(rows: [("bad", 1), ("2026-02-28", 2), ("2026-06-30", 3)],
                                         todayKey: "2026-06-30", dayCount: nil)
        XCTAssertEqual(result.startDay, "2026-02-28")
        XCTAssertEqual(result.expected, 123)
        XCTAssertEqual(result.observed, 2)
    }

    func testPreviousPointsUsesEqualPrecedingCalendarInterval() {
        let result = TrendWindow.previousPoints(rows: [
            ("2026-06-16", 1), ("2026-06-22", 2), ("2026-06-23", 3), ("2026-06-24", 4),
        ], todayKey: "2026-06-30", dayCount: 7)
        XCTAssertEqual(result.map(\.day), ["2026-06-22", "2026-06-23"])
    }

    func testOnePointWindow() {
        let result = TrendWindow.project(rows: [("2026-06-30", 7)],
                                         todayKey: "2026-06-30", dayCount: 1)
        XCTAssertEqual(result.points, [.init(day: "2026-06-30", value: 7)])
        XCTAssertEqual(result.startDay, "2026-06-30")
        XCTAssertEqual(result.expected, 1)
        XCTAssertFalse(result.hasOlderHistory)
    }

    func testFixedWindowWithNoDataStillReportsSelectedDates() {
        let result = TrendWindow.project(rows: [], todayKey: "2026-06-30", dayCount: 7)
        XCTAssertEqual(result.points, [])
        XCTAssertEqual(result.startDay, "2026-06-24")
        XCTAssertEqual(result.endDay, "2026-06-30")
        XCTAssertEqual(result.observed, 0)
        XCTAssertEqual(result.expected, 7)
    }

    func testNonfiniteValuesAreDropped() {
        let rows: [(day: String, value: Double?)] = [
            ("2026-06-28", .infinity), ("2026-06-29", -.infinity), ("2026-06-30", .nan),
        ]
        XCTAssertEqual(TrendWindow.project(rows: rows, todayKey: "2026-06-30", dayCount: 3).points, [])
    }

    func testInvalidTodayReturnsEmptyResult() {
        let result = TrendWindow.project(rows: [("2026-06-30", 1)], todayKey: "bad", dayCount: 7)
        XCTAssertNil(result.startDay)
        XCTAssertEqual(result.endDay, "bad")
        XCTAssertEqual(result.observed, 0)
        XCTAssertEqual(result.expected, 0)
    }

    func testDuplicateFiniteThenInvalidKeepsFiniteValue() {
        let rows: [(day: String, value: Double?)] = [("2026-06-30", 1), ("2026-06-30", .nan)]
        XCTAssertEqual(TrendWindow.project(rows: rows, todayKey: "2026-06-30", dayCount: 7).points,
                       [.init(day: "2026-06-30", value: 1)])
    }

    func testDuplicateInvalidThenFiniteUsesFiniteValue() {
        let rows: [(day: String, value: Double?)] = [("2026-06-30", .infinity), ("2026-06-30", 2)]
        XCTAssertEqual(TrendWindow.project(rows: rows, todayKey: "2026-06-30", dayCount: 7).points,
                       [.init(day: "2026-06-30", value: 2)])
    }

    func testAllWithNoDataIsEmpty() {
        let result = TrendWindow.project(rows: [], todayKey: "2026-06-30", dayCount: nil)
        XCTAssertNil(result.startDay)
        XCTAssertEqual(result.observed, 0)
        XCTAssertEqual(result.expected, 0)
        XCTAssertFalse(result.hasOlderHistory)
    }

    func testDayKeysMustBeCanonicalExactDates() {
        let rows: [(day: String, value: Double?)] = [
            ("2026-6-30", 1), ("2026-02-30", 2), ("2026-06-30T00:00:00Z", 3),
            ("2026-06-30", 4),
        ]
        let result = TrendWindow.project(rows: rows, todayKey: "2026-06-30", dayCount: 1)
        XCTAssertEqual(result.points, [.init(day: "2026-06-30", value: 4)])
        XCTAssertEqual(TrendWindow.project(rows: rows, todayKey: "2026-6-30", dayCount: 1).expected, 0)
    }
}
