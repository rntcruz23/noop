import XCTest
import SwiftUI
@testable import StrandDesign

final class TrendChartTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testDownsamplePreservesSegmentBoundariesAndSingletons() {
        let first = (0..<40).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0) * day), value: Double($0), segment: "a")
        }
        let singleton = TrendPoint(date: Date(timeIntervalSince1970: 40 * day), value: 500, segment: "b")
        let last = (41..<81).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0) * day), value: Double($0), segment: "a")
        }

        let result = ChartDownsample.minMaxBucketed(
            first + [singleton] + last,
            threshold: 8,
            targetCount: 8
        )

        XCTAssertEqual(result.filter { $0.segment == "b" }.map(\.date), [singleton.date])
        XCTAssertTrue(result.contains { $0.date == first.first?.date })
        XCTAssertTrue(result.contains { $0.date == first.last?.date })
        XCTAssertTrue(result.contains { $0.date == last.first?.date })
        XCTAssertTrue(result.contains { $0.date == last.last?.date })
        let ranges = ChartGeometry.segmentRanges(points: result)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[1], 8...8)
        XCTAssertEqual(result[ranges[0]].first?.date, first.first?.date)
        XCTAssertEqual(result[ranges[0]].last?.date, first.last?.date)
        XCTAssertEqual(result[ranges[2]].first?.date, last.first?.date)
        XCTAssertEqual(result[ranges[2]].last?.date, last.last?.date)
    }

    func testDailySegmentIdsUseCalendarDaysAcrossDSTAndGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dates = ["2024-03-09", "2024-03-10", "2024-03-11", "2024-03-13"].map {
            ISO8601DateFormatter.dayDate($0, calendar: calendar)
        }

        XCTAssertEqual(ChartGeometry.dailySegmentIds(dates: dates, calendar: calendar), ["0", "0", "0", "1"])
    }

    func testNormalizedCalendarPositionsUseFullWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = ISO8601DateFormatter.dayDate("2026-01-01", calendar: calendar)
        let end = ISO8601DateFormatter.dayDate("2026-01-11", calendar: calendar)
        let dates = ["2026-01-01", "2026-01-02", "2026-01-11"].map {
            ISO8601DateFormatter.dayDate($0, calendar: calendar)
        }

        let result = ChartGeometry.normalizedCalendarPositions(
            dates: dates,
            domain: start...end,
            calendar: calendar
        )

        let positions = try! XCTUnwrap(result)
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(positions[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(positions[1], 0.1, accuracy: 0.000_001)
        XCTAssertEqual(positions[2], 1, accuracy: 0.000_001)
    }

    func testSummaryAxisDatesUseAtMostThreeCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = ISO8601DateFormatter.dayDate("2026-01-01", calendar: calendar)
        let end = ISO8601DateFormatter.dayDate("2026-01-10", calendar: calendar)

        let dates = ChartGeometry.summaryAxisDates(domain: start...end, calendar: calendar)

        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dates.first, start)
        XCTAssertEqual(dates.last, end)
        XCTAssertEqual(dates[1], ISO8601DateFormatter.dayDate("2026-01-05", calendar: calendar))
    }

    func testContextRangeClipsToPlotDomain() {
        XCTAssertEqual(ChartGeometry.clippedRange(40...80, to: 50...100), 50...80)
        XCTAssertNil(ChartGeometry.clippedRange(10...20, to: 50...100))
    }

    func testSummaryChromeSuppressesDetailOnlyMarks() {
        let points = [
            TrendPoint(date: Date(timeIntervalSince1970: 0), value: 10),
            TrendPoint(date: Date(timeIntervalSince1970: day), value: 20),
        ]
        let detail = TrendChart(points: points)
        let summary = TrendChart(points: points, chrome: .summary)

        XCTAssertTrue(detail.rendersArea)
        XCTAssertTrue(detail.rendersPersistentYAxis)
        XCTAssertTrue(detail.rendersAllPointMarkers)
        XCTAssertTrue(detail.rendersTooltip)
        XCTAssertFalse(summary.rendersArea)
        XCTAssertFalse(summary.rendersPersistentYAxis)
        XCTAssertFalse(summary.rendersAllPointMarkers)
        XCTAssertFalse(summary.rendersTooltip)
    }

    func testSelectionFallsBackToLatestFullResolutionPoint() {
        let points = (0..<200).map {
            TrendPoint(date: Date(timeIntervalSince1970: Double($0) * day), value: Double($0))
        }
        XCTAssertEqual(ChartGeometry.selectedOrLatestPoint(selectedDate: nil, points: points)?.date, points.last?.date)
        let selected = points[73]
        XCTAssertEqual(
            ChartGeometry.selectedOrLatestPoint(selectedDate: selected.date.addingTimeInterval(day / 4), points: points)?.date,
            selected.date
        )
    }
}

private extension ISO8601DateFormatter {
    static func dayDate(_ value: String, calendar: Calendar) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }
}
