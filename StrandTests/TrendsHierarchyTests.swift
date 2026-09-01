import XCTest
@testable import Strand

final class TrendsHierarchyTests: XCTestCase {
    func testChargeIsTheDefaultHero() {
        XCTAssertEqual(TrendsMetric.defaultHero, .charge)
    }

    func testSecondaryRowsContainEveryMetricExceptHeroInStableOrder() {
        XCTAssertEqual(TrendsMetric.secondary(to: .charge), [.hrv, .rhr, .rest, .effort])
        for selected in TrendsMetric.allCases {
            let secondary = TrendsMetric.secondary(to: selected)
            XCTAssertEqual(secondary.count, 4)
            XCTAssertFalse(secondary.contains(selected))
            XCTAssertEqual(secondary, TrendsMetric.allCases.filter { $0 != selected })
            XCTAssertEqual(Set(secondary + [selected]), Set(TrendsMetric.allCases))
        }
    }

    func testEveryMetricMapsToExistingDetailRoute() {
        XCTAssertEqual(TrendsMetric.charge.detailKey, "recovery")
        XCTAssertEqual(TrendsMetric.hrv.detailKey, "hrv")
        XCTAssertEqual(TrendsMetric.rhr.detailKey, "rhr")
        XCTAssertEqual(TrendsMetric.rest.detailKey, "sleep_performance")
        XCTAssertEqual(TrendsMetric.effort.detailKey, "strain")
    }

    func testSelectedPointFallsBackToLatestAndRejectsStaleIndex() {
        XCTAssertEqual(TrendsMetric.selectedOrLatestIndex(selected: nil, count: 3), 2)
        XCTAssertEqual(TrendsMetric.selectedOrLatestIndex(selected: 1, count: 3), 1)
        XCTAssertEqual(TrendsMetric.selectedOrLatestIndex(selected: 8, count: 3), 2)
        XCTAssertNil(TrendsMetric.selectedOrLatestIndex(selected: nil, count: 0))
    }

    func testEmptyStateAccountsForEveryHeroMetricSource() {
        XCTAssertFalse(TrendsMetric.hasAnyData(recovery: 0, hrv: 0, rhr: 0, rest: 0, effort: 0))
        XCTAssertTrue(TrendsMetric.hasAnyData(recovery: 0, hrv: 0, rhr: 0, rest: 1, effort: 0))
    }
}
