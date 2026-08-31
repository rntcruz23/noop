import Foundation

/// Personal-baseline banding for the Health Monitor's vital tiles.
///
/// In-range is judged against the user's OWN trailing baseline (the Winsorized EWMA
/// the rest of `Baselines` builds) once that baseline is trusted — `Baselines.minNightsTrust`
/// (14) valid nights and not stale. Until then, and again whenever a wear gap makes the
/// baseline stale, the fixed population range is the fallback.
///
/// `MetricCfg`'s physiological bounds stay an absolute outer guard either way. They are
/// deliberately NOT used as the in-range band: doing so would resurrect the exact false
/// positive this fixes — a perfectly normal personal HRV of 35 ms reading permanently
/// out-of-range against the 40–120 population band. The bounds only catch values that are
/// implausible for any human (e.g. an HRV of 300 ms), which no personal spread should excuse.
///
/// APPROXIMATE — informational, not a diagnosis.
public enum VitalBands {

    public enum Band: String, Equatable, Sendable { case inRange, outOfRange, noData }

    /// How the band was judged — drives the tile's caption wording.
    public enum Basis: String, Equatable, Sendable { case personal, population }

    public struct Result: Equatable, Sendable {
        public let band: Band
        public let basis: Basis
        /// Valid nights backing the personal baseline (0 when none).
        public let nights: Int
        public init(band: Band, basis: Basis, nights: Int) {
            self.band = band
            self.basis = basis
            self.nights = nights
        }
    }

    public enum Position: String, Equatable, Sendable { case below, within, above, noData }

    /// Read-only context for presenting a vital without changing its scoring classification.
    public struct Presentation: Equatable, Sendable {
        public let band: Band
        public let basis: Basis
        public let status: BaselineStatus?
        public let center: Double?
        public let lowerBound: Double
        public let upperBound: Double
        public let position: Position
        public let nights: Int
    }

    /// |z| at or below this is in-range vs the personal baseline — about 95% of the user's
    /// own normal nights. `Baselines.deviation`'s own `inNormalRange` (|z| <= 1) would flag
    /// roughly a third of normal nights, which is far too noisy for a passive at-a-glance tile.
    public static let sigmaK: Double = 2.0

    /// Band a single vital `value`.
    ///
    /// - Parameters:
    ///   - value: today's value, or nil for no data.
    ///   - history: nightly values oldest→newest EXCLUDING the displayed day. A nil entry is
    ///     a missing night; use `calendarSeries` first to pad real wear gaps so staleness sees them.
    ///   - populationRange: the fixed typical-adult range used as the cold-start / stale fallback.
    ///   - cfg: nil disables the personal path entirely (SpO2 stays population-only — there is
    ///     no SpO2 `MetricCfg` and an absolute floor is meaningful regardless of personal history).
    public static func band(value: Double?,
                            history: [Double?],
                            populationRange: ClosedRange<Double>,
                            cfg: MetricCfg?) -> Result {
        let context = presentation(value: value, history: history,
                                   populationRange: populationRange, cfg: cfg)
        return Result(band: context.band, basis: context.basis, nights: context.nights)
    }

    /// Exposes the exact bounds and baseline state used by `band` for presentation-only context.
    public static func presentation(value: Double?,
                                    history: [Double?],
                                    populationRange: ClosedRange<Double>,
                                    cfg: MetricCfg?) -> Presentation {
        guard let value else {
            return Presentation(band: .noData, basis: .population, status: nil, center: nil,
                                lowerBound: populationRange.lowerBound,
                                upperBound: populationRange.upperBound,
                                position: .noData, nights: 0)
        }
        guard let cfg else {
            let position = position(of: value, in: populationRange)
            return Presentation(band: position == .within ? .inRange : .outOfRange,
                                basis: .population, status: nil, center: nil,
                                lowerBound: populationRange.lowerBound,
                                upperBound: populationRange.upperBound,
                                position: position, nights: 0)
        }
        let state = Baselines.foldHistory(history, cfg: cfg)
        let physiologicallyValid = cfg.minVal <= value && value <= cfg.maxVal
        if state.trusted && physiologicallyValid {
            let radius = sigmaK * 1.253 * state.spread
            let range = max(cfg.minVal, state.baseline - radius)...min(cfg.maxVal, state.baseline + radius)
            let position = position(of: value, in: range)
            return Presentation(band: position == .within ? .inRange : .outOfRange,
                                basis: .personal, status: state.status, center: state.baseline,
                                lowerBound: range.lowerBound, upperBound: range.upperBound,
                                position: position, nights: state.nValid)
        }
        let position = position(of: value, in: populationRange)
        return Presentation(band: physiologicallyValid && position == .within ? .inRange : .outOfRange,
                            basis: .population, status: state.status, center: nil,
                            lowerBound: populationRange.lowerBound,
                            upperBound: populationRange.upperBound,
                            position: position, nights: state.nValid)
    }

    /// Calendar-pads resolved history strictly before `displayedDay`, including a trailing wear gap.
    public static func presentation(value: Double?,
                                    historyRows: [(day: String, value: Double?)],
                                    displayedDay: String,
                                    populationRange: ClosedRange<Double>,
                                    cfg: MetricCfg?,
                                    baselineEpoch: Double = 0) -> Presentation {
        guard let displayed = parseDay(displayedDay),
              let prior = utcCalendar.date(byAdding: .day, value: -1, to: displayed) else {
            return presentation(value: value, history: [], populationRange: populationRange, cfg: cfg)
        }
        let validRows = historyRows.filter { row in
            guard let date = parseDay(row.day) else { return false }
            return date < displayed
        }
        var paddedRows = validRows
        let priorKey = dayFormatter.string(from: prior)
        if !validRows.contains(where: { $0.day == priorKey }) {
            paddedRows.append((day: priorKey, value: nil))
        }
        let rows = calendarRows(paddedRows)
        guard let cfg, baselineEpoch > 0 else {
            return presentation(value: value, history: rows.map { $0.value },
                                populationRange: populationRange, cfg: cfg)
        }
        let state = Baselines.foldHistory(rows.map { $0.value }, dayKeys: rows.map { $0.day },
                                          cfg: cfg, baselineEpoch: baselineEpoch)
        return presentation(value: value, state: state,
                            populationRange: populationRange, cfg: cfg)
    }

    private static func presentation(value: Double?, state: BaselineState,
                                     populationRange: ClosedRange<Double>,
                                     cfg: MetricCfg) -> Presentation {
        guard let value else {
            return Presentation(band: .noData, basis: .population, status: nil, center: nil,
                                lowerBound: populationRange.lowerBound,
                                upperBound: populationRange.upperBound,
                                position: .noData, nights: 0)
        }
        let physiologicallyValid = cfg.minVal <= value && value <= cfg.maxVal
        if state.trusted && physiologicallyValid {
            let radius = sigmaK * 1.253 * state.spread
            let range = max(cfg.minVal, state.baseline - radius)...min(cfg.maxVal, state.baseline + radius)
            let pointPosition = position(of: value, in: range)
            return Presentation(band: pointPosition == .within ? .inRange : .outOfRange,
                                basis: .personal, status: state.status, center: state.baseline,
                                lowerBound: range.lowerBound, upperBound: range.upperBound,
                                position: pointPosition, nights: state.nValid)
        }
        let pointPosition = position(of: value, in: populationRange)
        return Presentation(band: physiologicallyValid && pointPosition == .within ? .inRange : .outOfRange,
                            basis: .population, status: state.status, center: nil,
                            lowerBound: populationRange.lowerBound,
                            upperBound: populationRange.upperBound,
                            position: pointPosition, nights: state.nValid)
    }

    private static func position(of value: Double,
                                 in range: ClosedRange<Double>) -> Position {
        guard value.isFinite else { return .noData }
        if value < range.lowerBound { return .below }
        if value > range.upperBound { return .above }
        return .within
    }

    // MARK: - Skin temp (mixed semantics: absolute °C from CSV import vs ±°C on-device deviation)

    /// A skin-temp value >= 20 °C is read as an ABSOLUTE skin temperature; smaller magnitudes
    /// are read as a ±°C deviation. The WHOOP CSV export stores absolute °C in its skin-temp
    /// column while NOOP's on-device pipeline stores a deviation from the personal baseline, so
    /// a merged series is bimodal. The displayed value picks which kind its history keeps.
    /// Heuristic but physically safe: no real wrist skin temp is below 20 °C, and no real
    /// nightly deviation reaches ±20 °C.
    public static func isAbsoluteSkinTemp(_ v: Double) -> Bool { v >= 20.0 }

    /// Keep only history entries of the SAME kind (absolute vs deviation) as the displayed
    /// `value`; entries of the other kind become nil (missing nights) so the baseline that
    /// `band` folds isn't computed across two incompatible scales.
    public static func skinTempHistory(matching value: Double, in history: [Double?]) -> [Double?] {
        let absolute = isAbsoluteSkinTemp(value)
        return history.map { v in
            guard let v else { return nil }
            return isAbsoluteSkinTemp(v) == absolute ? v : nil
        }
    }

    /// Deviation-semantics config for on-device skin-temp rows: ±°C around the personal mean,
    /// guarded to a physically sane ±8 °C. (The standard `skin_temp` config in `Baselines`
    /// is the ABSOLUTE-°C one, used for CSV-imported rows.)
    public static let skinTempDeviationCfg = MetricCfg(
        minVal: -8.0, maxVal: 8.0, floorSpread: 0.3, halfLifeB: 14.0, halfLifeS: 21.0)

    // MARK: - Calendar padding

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        return formatter
    }()

    private static func parseDay(_ key: String) -> Date? {
        guard let date = dayFormatter.date(from: key), dayFormatter.string(from: date) == key else { return nil }
        return date
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// Calendar-align (day, value) rows keyed "yyyy-MM-dd" into a nightly series with nil for
    /// every absent day, so the baseline's staleness logic actually sees wear gaps. Stored rows
    /// simply skip days the strap wasn't worn; without padding, a user returning after two months
    /// would be banded against an ancient still-"trusted" baseline. Malformed day keys are dropped.
    /// Pure: fixed UTC math over the day keys only (no device clock).
    public static func calendarSeries(_ rows: [(day: String, value: Double?)]) -> [Double?] {
        calendarRows(rows).map { $0.value }
    }

    private static func calendarRows(_ rows: [(day: String, value: Double?)]) -> [(day: String, value: Double?)] {
        let f = dayFormatter
        let cal = utcCalendar
        let dates = rows.compactMap { parseDay($0.day) }
        guard let first = dates.min(), let last = dates.max() else { return [] }
        // Last write wins for a duplicated day key, matching the dictionary the Kotlin port builds.
        var byDay: [String: Double?] = [:]
        for r in rows where parseDay(r.day) != nil { byDay[r.day] = r.value }
        var out: [(day: String, value: Double?)] = []
        var d = first
        while d <= last {
            let day = f.string(from: d)
            out.append((day: day, value: byDay[day] ?? nil))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }
}
