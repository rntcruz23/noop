import XCTest
@testable import StrandAnalytics

/// Pins `VitalBands` — the Health Monitor's personal-baseline banding. Mirrors the Android
/// `VitalBandsTest` case-for-case with identical numbers, so the two platforms can never
/// band the same vital differently.
final class VitalBandsTests: XCTestCase {

    private let hrvCfg = Baselines.hrvCfg
    private let hrvPop: ClosedRange<Double> = 40...120

    func testNullValueIsNoData() {
        let r = VitalBands.band(value: nil, history: [50.0], populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.band, .noData)
    }

    // THE MOTIVATING CASE: a personal-normal HRV of 35 ms with the population band at 40-120.
    // Below the trust gate it is still judged against the population, hence out-of-range.
    func testLowHrvBelow14NightsPopulationOutOfRange() {
        let r = VitalBands.band(value: 35, history: Array(repeating: 35.0, count: 10),
                                populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .population)
        XCTAssertEqual(r.nights, 10)
    }

    // The fix: at 14 trusted nights the same 35 ms is in-range against the user's OWN baseline.
    func testLowHrvAt14NightsPersonalInRange() {
        let r = VitalBands.band(value: 35, history: Array(repeating: 35.0, count: 14),
                                populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.band, .inRange)
        XCTAssertEqual(r.basis, .personal)
        XCTAssertEqual(r.nights, 14)
    }

    func testPersonalBigDeviationOutOfRange() {
        // Constant 35 ms history → spread floors out; 70 ms is far beyond 2σ of that baseline.
        let r = VitalBands.band(value: 70, history: Array(repeating: 35.0, count: 30),
                                populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .personal)
    }

    func testPersonalJustInside2SigmaInRange() {
        let hist: [Double?] = Array(repeating: 35.0, count: 30)
        let state = Baselines.foldHistory(hist, cfg: hrvCfg)
        // 1.99σ in σ-space (spread is abs-dev, 1.253×spread ≈ σ): strictly inside the 2σ gate.
        let edge = state.baseline + 1.99 * 1.253 * state.spread
        XCTAssertEqual(VitalBands.band(value: edge, history: hist,
                                       populationRange: hrvPop, cfg: hrvCfg).band, .inRange)
    }

    func testImplausibleValueAlwaysOutOfRangeEvenWithTrustedBaseline() {
        // hrv cfg bounds are 5-250: 300 ms is implausible regardless of personal spread,
        // so the absolute outer guard fires and basis stays population.
        let r = VitalBands.band(value: 300, history: Array(repeating: 35.0, count: 30),
                                populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .population)
    }

    func testNilCfgSpo2StaysPopulationOnly() {
        // A nil cfg (SpO₂) disables the personal path: an absolute <95% floor always applies.
        let r = VitalBands.band(value: 93, history: [], populationRange: 95...100, cfg: nil)
        XCTAssertEqual(r.band, .outOfRange)
        XCTAssertEqual(r.basis, .population)
    }

    func testNilNightsDoNotCountTowardTrust() {
        // 13 valid nights then 10 trailing skips: only 13 valid → provisional, still population.
        let hist: [Double?] = Array(repeating: 35.0, count: 13) + Array(repeating: nil, count: 10)
        let r = VitalBands.band(value: 35, history: hist, populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.basis, .population)
    }

    func testStaleBaselineFallsBackToPopulation() {
        // 20 valid nights then 20 missing (> staleDays = 14): status stale → population fallback.
        let hist: [Double?] = Array(repeating: 35.0, count: 20) + Array(repeating: nil, count: 20)
        let r = VitalBands.band(value: 35, history: hist, populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(r.basis, .population)
    }

    func testSkinTempHistoryPartitionsMixedSemantics() {
        // 34.1/33.8 are absolute °C; 0.2/-0.1 are deviations. Each displayed kind keeps only its own.
        let mixed: [Double?] = [34.1, 0.2, nil, 33.8, -0.1]
        XCTAssertEqual(VitalBands.skinTempHistory(matching: 0.3, in: mixed), [nil, 0.2, nil, nil, -0.1])
        XCTAssertEqual(VitalBands.skinTempHistory(matching: 34.0, in: mixed), [34.1, nil, nil, 33.8, nil])
    }

    func testCalendarSeriesPadsMissingDays() {
        let rows: [(day: String, value: Double?)] = [("2026-06-01", 50.0), ("2026-06-04", 52.0)]
        XCTAssertEqual(VitalBands.calendarSeries(rows), [50.0, nil, nil, 52.0])
    }

    func testCalendarSeriesDropsMalformedKeysEmptyIsEmpty() {
        XCTAssertEqual(VitalBands.calendarSeries([]), [])
        let rows: [(day: String, value: Double?)] = [
            ("not-a-date", 1.0), ("2026-6-01", 2.0), ("2026-02-30", 3.0),
            ("2026-06-01T00:00:00Z", 4.0), ("2026-06-01", 50.0),
        ]
        XCTAssertEqual(VitalBands.calendarSeries(rows), [50.0])
    }

    func testCalendarSeriesDuplicateDaysUseLastWriteIncludingNil() {
        let rows: [(day: String, value: Double?)] = [
            ("2026-06-01", 40), ("2026-06-01", 41), ("2026-06-02", 42),
            ("2026-06-02", nil),
        ]
        XCTAssertEqual(VitalBands.calendarSeries(rows), [41, nil])
    }

    func testNonfiniteCurrentIsOutOfRangeButNeverPresentedWithin() {
        for value in [Double.nan, .infinity, -.infinity] {
            let result = VitalBands.presentation(value: value, history: Array(repeating: 50, count: 14),
                                                 populationRange: hrvPop, cfg: hrvCfg)
            XCTAssertEqual(result.band, .outOfRange)
            XCTAssertEqual(result.position, .noData)
            XCTAssertEqual(VitalBands.presentation(value: value, history: [],
                                                   populationRange: 95...100, cfg: nil).position, .noData)
        }
    }

    func testNonfiniteHistoryDoesNotCountTowardBaseline() {
        let history: [Double?] = Array(repeating: 50, count: 13) + [.nan, .infinity, -.infinity]
        let result = VitalBands.presentation(value: 50, history: history,
                                             populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(result.nights, 13)
        XCTAssertEqual(result.basis, .population)
    }

    func testRestingHeartRateLowAndHighDirections() {
        let history: [Double?] = Array(repeating: 50, count: 14)
        XCTAssertEqual(VitalBands.presentation(value: 40, history: history,
                                               populationRange: 40...60,
                                               cfg: Baselines.restingHRCfg).position, .below)
        XCTAssertEqual(VitalBands.presentation(value: 60, history: history,
                                               populationRange: 40...60,
                                               cfg: Baselines.restingHRCfg).position, .above)
    }

    func testRestingHeartRatePhysiologicalBoundariesAreInclusive() {
        for value in [30.0, 120.0] {
            XCTAssertEqual(VitalBands.band(value: value, history: [], populationRange: 30...120,
                                           cfg: Baselines.restingHRCfg).band, .inRange)
        }
        for value in [29.0, 121.0] {
            XCTAssertEqual(VitalBands.band(value: value, history: [], populationRange: 30...120,
                                           cfg: Baselines.restingHRCfg).band, .outOfRange)
        }
    }

    func testPresentationExposesTrustedPersonalBoundsAndDirection() {
        let history: [Double?] = Array(repeating: 50.0, count: 14)
        let result = VitalBands.presentation(value: 55, history: history,
                                             populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(result.basis, .personal)
        XCTAssertEqual(result.status, .trusted)
        XCTAssertEqual(result.center!, 50, accuracy: 0.000_001)
        XCTAssertEqual(result.lowerBound, 37.47, accuracy: 0.000_001)
        XCTAssertEqual(result.upperBound, 62.53, accuracy: 0.000_001)
        XCTAssertEqual(result.position, .within)
        XCTAssertEqual(result.nights, 14)
    }

    func testPresentationUsesNamedPopulationFallbackWhileProvisional() {
        let result = VitalBands.presentation(value: 35, history: Array(repeating: 35.0, count: 10),
                                             populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(result.basis, .population)
        XCTAssertEqual(result.status, .provisional)
        XCTAssertNil(result.center)
        XCTAssertEqual(result.lowerBound, 40)
        XCTAssertEqual(result.upperBound, 120)
        XCTAssertEqual(result.position, .below)
    }

    func testPresentationPadsTrailingGapThroughDisplayedDay() {
        let rows = (1...20).map { day in
            (day: String(format: "2026-06-%02d", day), value: Optional(50.0))
        }
        let result = VitalBands.presentation(value: 50, historyRows: rows,
                                             displayedDay: "2026-07-06",
                                             populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(result.status, .stale)
        XCTAssertEqual(result.basis, .population)
    }

    func testPresentationMatchesSharedExpectedFixture() {
        let cases: [(String, VitalBands.Presentation)] = [
            ("cold", VitalBands.presentation(value: 35, history: Array(repeating: 35, count: 3),
                                              populationRange: hrvPop, cfg: hrvCfg)),
            ("provisional", VitalBands.presentation(value: 35, history: Array(repeating: 35, count: 10),
                                                    populationRange: hrvPop, cfg: hrvCfg)),
            ("trusted", VitalBands.presentation(value: 55, history: Array(repeating: 50, count: 14),
                                                populationRange: hrvPop, cfg: hrvCfg)),
            ("stale", VitalBands.presentation(value: 50,
                                              history: Array(repeating: 50, count: 20) + Array(repeating: nil, count: 15),
                                              populationRange: hrvPop, cfg: hrvCfg)),
        ]
        let actual = cases.map { name, value in
            [name, value.band.rawValue, value.basis.rawValue, value.status?.rawValue ?? "null",
             value.center.map { String(format: "%.3f", $0) } ?? "null",
             String(format: "%.3f", value.lowerBound), String(format: "%.3f", value.upperBound),
             value.position.rawValue, String(value.nights)].joined(separator: "|")
        }.joined(separator: "\n")
        let expected = """
        cold|outOfRange|population|calibrating|null|40.000|120.000|below|3
        provisional|outOfRange|population|provisional|null|40.000|120.000|below|10
        trusted|inRange|personal|trusted|50.000|37.470|62.530|within|14
        stale|inRange|population|stale|null|40.000|120.000|within|20
        """
        XCTAssertEqual(actual, expected)
    }

    func testPresentationDoesNotOverwritePreviousNightWhenPadding() {
        let rows = (1...14).map { day in
            (day: String(format: "2026-06-%02d", day), value: Optional(50.0))
        }
        let result = VitalBands.presentation(value: 50, historyRows: rows,
                                             displayedDay: "2026-06-15",
                                             populationRange: hrvPop, cfg: hrvCfg)
        XCTAssertEqual(result.status, .trusted)
        XCTAssertEqual(result.nights, 14)
        XCTAssertEqual(result.basis, .personal)
    }

    func testPresentationHonorsManualRecalibrationEpoch() {
        let rows = (1...14).map { day in
            (day: String(format: "2026-06-%02d", day), value: Optional(50.0))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
            .timeIntervalSince1970
        let result = VitalBands.presentation(value: 50, historyRows: rows,
                                             displayedDay: "2026-06-15",
                                             populationRange: hrvPop, cfg: hrvCfg,
                                             baselineEpoch: epoch)
        XCTAssertEqual(result.status, .calibrating)
        XCTAssertEqual(result.nights, 5)
        XCTAssertEqual(result.basis, .population)
    }
}
