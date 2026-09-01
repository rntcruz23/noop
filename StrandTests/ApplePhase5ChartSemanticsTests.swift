import XCTest
import StrandDesign
import WhoopStore
@testable import Strand

final class ApplePhase5ChartSemanticsTests: XCTestCase {
    func testSleepDurationUsesNormativeNeedRatherThanObservedAverage() {
        let data = AsleepDurationData.build(days: [
            day("2026-08-01", sleep: 360),
            day("2026-08-02", sleep: 390),
            day("2026-08-03", sleep: 420),
        ])

        XCTAssertEqual(data.typicalTotalMin ?? -1, 390, accuracy: 0.001)
        XCTAssertGreaterThan(data.sleepNeedMin, data.typicalTotalMin ?? .infinity)
        XCTAssertEqual(data.sleepNeedMin, SleepModel.debtNeedMin(days: [
            day("2026-08-01", sleep: 360),
            day("2026-08-02", sleep: 390),
            day("2026-08-03", sleep: 420),
        ]), accuracy: 0.001)
    }

    func testMetricChartSemanticsAreFixedForStressAndCenteredForDeviation() {
        XCTAssertEqual(MetricChartSemantics.markStyle(key: "stress"), .stressZones)
        XCTAssertEqual(MetricChartSemantics.markStyle(key: "steps"), .bars)
        XCTAssertEqual(MetricChartSemantics.domain(key: "stress", values: [1.2, 2.1]), 0...3)
        XCTAssertEqual(MetricChartSemantics.domain(key: "skin_temp", values: [-0.2, 0.7]), -0.7...0.7)
    }

    func testStepsReferenceIsPersonalAverageAndSkinBandStraddlesZero() {
        XCTAssertEqual(MetricChartSemantics.referenceValue(key: "steps", values: [4_000, 8_000, 12_000]), 8_000)
        XCTAssertNil(MetricChartSemantics.referenceValue(key: "steps", values: []))

        let band = MetricChartSemantics.skinDeviationBand(values: [-0.4, -0.2, 0.1, 0.3, 0.8])
        XCTAssertNotNil(band)
        XCTAssertLessThanOrEqual(band!.lowerBound, 0)
        XCTAssertGreaterThanOrEqual(band!.upperBound, 0)
    }

    private func day(_ key: String, sleep: Double) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }
}
