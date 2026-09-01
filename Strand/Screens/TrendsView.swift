import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Trends
//
// The longitudinal view has one selectable hero and four compact peer rows. The global period owns
// every projection; compact charts retain calendar gaps but omit detail chrome and statistics.

enum TrendsMetric: String, CaseIterable, Hashable {
    case charge, hrv, rhr, rest, effort

    static let defaultHero: TrendsMetric = .charge

    static func secondary(to hero: TrendsMetric) -> [TrendsMetric] {
        allCases.filter { $0 != hero }
    }

    static func selectedOrLatestIndex(selected: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let selected, (0..<count).contains(selected) else { return count - 1 }
        return selected
    }

    static func hasAnyData(_ counts: [Int]) -> Bool {
        counts.contains { $0 > 0 }
    }

    static func hasAnyData(recovery: Int, hrv: Int, rhr: Int, rest: Int, effort: Int) -> Bool {
        hasAnyData([recovery, hrv, rhr, rest, effort])
    }

    var detailKey: String {
        switch self {
        case .charge: return "recovery"
        case .hrv: return "hrv"
        case .rhr: return "rhr"
        case .rest: return "sleep_performance"
        case .effort: return "strain"
        }
    }
}

struct TrendsView: View {
    @EnvironmentObject var repo: Repository
    // NOTE: deliberately does NOT observe LiveState — Trends shows historical data only, and
    // observing it forced a full re-render of this subtree on every ~1 Hz live-HR tick.

    // The shared range control: W(7) / M(30) / 3M(90) / 6M(180) / 1Y(365) / ALL.
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Trailing-day window, or nil for "all history".
        var days: Int? { self == .all ? nil : rawValue }
    }

    @State private var range: Range = .quarter
    @State private var heroMetric: TrendsMetric = .defaultHero
    @State private var selectedHeroDate: Date?
    /// Canonically resolved, full-history vital series. These deliberately do not ride `repo.days`:
    /// that cache follows the active device and can omit imported/computed fallback days.
    @State private var hrvHistory: [(day: String, value: Double)] = []
    @State private var rhrHistory: [(day: String, value: Double)] = []

    // #436 — shareable offline trends report (PDF over a date range). The sheet owns its
    // own range picker; this just presents it with the loaded history.
    @State private var showingReport = false
    /// Current appearance, passed into the off-screen recap render so the shared PNG matches the app.
    @Environment(\.colorScheme) private var colorScheme

    /// Rest's per-day series, keyed by "yyyy-MM-dd". Rest is the sleep_performance COMPOSITE (the same
    /// number the Today Rest score + the Sleep Rest-detail plot, #614 follow-up) — NOT raw efficiency,
    /// which read differently under the same "Rest" label and made the Trends Rest graph disagree with
    /// the Today Rest score (#732). sleep_performance is a metricSeries, not a DailyMetric field, so load
    /// it once (mirroring TodayView's restScore source) and key by day for the projection below.
    @State private var sleepPerfByDay: [String: Double] = [:]

    // #710 — browse previous weeks in the Week-in-review digest. 0 = the week containing today; each step
    // back is one Mon–Sun week earlier. Clamped so it never runs past the earliest day we hold (see
    // `weekAnchorDay` / `stepWeek`). The Trends RANGE control below is independent of this — it scopes the
    // long-form charts; this only moves the weekly digest at the top.
    @State private var weekOffset = 0

    // Effort display scale (#268) — routes the Effort small-multiple's numbers + unit. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // yyyy-MM-dd → Date (en_US_POSIX, UTC), per task spec.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    // MARK: Exact selected-window projection

    /// One today-anchored projection. Every selected-range metric uses this same shape: observations
    /// stay inside the requested interval, missing dates remain absent for the chart's daily gap policy,
    /// and stale history is reported rather than silently substituted.
    private struct SelectedTrendMetric {
        var points: [TrendPoint]
        var result: TrendWindow.Result
        var xDomain: ClosedRange<Date>?
    }

    private func selectedTrend(_ rows: [(day: String, value: Double?)]) -> SelectedTrendMetric {
        let result = TrendWindow.project(
            rows: rows,
            todayKey: Repository.localDayKey(Date()),
            dayCount: range.days
        )
        let points = result.points.compactMap { point in
            date(point.day).map { TrendPoint(date: $0, value: point.value) }
        }
        return SelectedTrendMetric(points: points, result: result, xDomain: selectedXDomain)
    }

    private func selectedTrend(_ rows: [(day: String, value: Double)]) -> SelectedTrendMetric {
        selectedTrend(rows.map { ($0.day, Optional($0.value)) })
    }

    /// The shared horizontal interval for every selected-period chart. Fixed ranges always span the
    /// same trailing dates. All-history begins at the earliest observation among the displayed metrics,
    /// so cards with shorter histories do not stretch their samples over a different time scale.
    private var selectedXDomain: ClosedRange<Date>? {
        let todayKey = Repository.localDayKey(Date())
        if let days = range.days {
            let window = TrendWindow.project(rows: [], todayKey: todayKey, dayCount: days)
            return window.startDay.flatMap(date).flatMap { start in date(window.endDay).map { start...$0 } }
        }
        guard let end = date(todayKey) else { return nil }
        let candidates = repo.days.compactMap { day in
            day.recovery != nil || day.strain != nil ? day.day : nil
        } + hrvHistory.map(\.day) + rhrHistory.map(\.day) + Array(sleepPerfByDay.keys)
        guard let start = candidates.compactMap(date).filter({ $0 <= end }).min() else { return nil }
        return start...end
    }

    /// A padded value range for a series so the line isn't flat against the axis.
    private func valueRange(_ pts: [TrendPoint], fallback: ClosedRange<Double>, pad: Double = 0.12) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * pad)...(hi + span * pad)
    }


    /// The window's trend as a signed mean-of-recent-half minus mean-of-earlier-half. Supplies the
    /// muted comparison beneath each primary reading; nil for a window too short to split.
    private func periodChange(_ pts: [TrendPoint]) -> Double? {
        guard pts.count >= 4 else { return nil }
        let mid = pts.count / 2
        let earlier = pts.prefix(mid).map(\.value)
        let recent = pts.suffix(pts.count - mid).map(\.value)
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }
        let e = earlier.reduce(0, +) / Double(earlier.count)
        let r = recent.reduce(0, +) / Double(recent.count)
        return r - e
    }


    /// "Trailing 90 days" / "All history" — used as a card subtitle.
    private var rangeSubtitle: String {
        guard let n = range.days else { return String(localized: "All history") }
        return String(localized: "Trailing \(n) days")
    }

    /// The compact selector caption is intentionally split into two intrinsic-width lines.
    /// Its leading edges line up while the surrounding spacer pins the widest line to the
    /// screen's shared trailing content edge.
    @ViewBuilder
    private var rangeCaption: some View {
        if let days = range.days {
            VStack(alignment: .leading, spacing: .zero) {
                Text("Trailing")
                    .strandOverline()
                    .lineLimit(1)
                Text("\(days) days")
                    .strandOverline()
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rangeSubtitle)
        } else {
            Text(rangeSubtitle)
                .strandOverline()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        // The liquid metric cards now tap through to their MetricDetailView (matching Today's card
        // taps + Explore's rows). On iOS each tab already supplies a NavigationStack, so those pushes
        // land in the ambient stack. On macOS the .trends detail pane has NO enclosing NavigationStack
        // (RootView), so — exactly like MetricExplorerView (#753) — wrap the scaffold in one here so the
        // pushes get Back chrome instead of hanging. The SAME shared scaffold renders on both.
        #if os(macOS)
        // Register the value routes at THIS stack's root; on iOS the tab shell's stack registers
        // them instead (once per stack — a double registration double-pushes, #38).
        NavigationStack { scaffold.tabRouteDestinations() }
        #else
        scaffold
        #endif
    }

    private var scaffold: some View {
        ScreenScaffold(title: "Trends", subtitle: "The thread of you over time.",
                       // PERF (scroll): lazy column — byte-identical layout (LazyVStack == eager VStack
                       // alignment/spacing/header). The content is one inner eager VStack, so the staggered
                       // section reveal is unchanged; this only defers building that stack until it scrolls in.
                       onRefresh: { await repo.refresh() },
                       lazy: true,
                       topBackground: liquidScaffoldSky()) {
            let recoveryCount = repo.days.lazy.compactMap(\.recovery).count
            let effortCount = repo.days.lazy.compactMap(\.strain).count
            if !TrendsMetric.hasAnyData(
                recovery: recoveryCount, hrv: hrvHistory.count, rhr: rhrHistory.count,
                rest: sleepPerfByDay.count, effort: effortCount
            ) {
                ComingSoon(what: repo.loaded
                    ? "Trends need history to draw. Import your WHOOP export in Data Sources to see weeks, months and years instantly."
                    : "Loading your history…")
            } else {
                // Project every selected-range metric onto one today-anchored interval. Null dates stay
                // absent so TrendChart's daily policy can break the line instead of inventing continuity.
                let recovery = selectedTrend(repo.days.map { ($0.day, $0.recovery) })
                let hrv = selectedTrend(hrvHistory)
                let rhr = selectedTrend(rhrHistory)
                let strain = selectedTrend(repo.days.map { ($0.day, $0.strain) })
                // Rest = the sleep_performance composite — the same number the Today Rest score shows
                // (#732); see sleepPerfByDay. Its sparse dates remain sparse in the selected window.
                let rest = selectedTrend(sleepPerfByDay.map { ($0.key, Optional($0.value)) })
                let metrics: [TrendsMetric: SelectedTrendMetric] = [
                    .charge: recovery, .hrv: hrv, .rhr: rhr, .rest: rest, .effort: strain,
                ]
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    // The main card list ripples in once on appear (Reduce-Motion safe).
                    Group {
                        rangeBar
                            .staggeredAppear(index: 0)
                        metricHero(metric: heroMetric, data: metrics[heroMetric]!)
                            .staggeredAppear(index: 1)
                        compactMetricRows(metrics: metrics)
                            .staggeredAppear(index: 2)
                        // Weekly narrative follows the primary hierarchy instead of competing with it.
                        weeklyDigestNav
                            .staggeredAppear(index: 3)
                        // Training load keeps the selected display interval but receives full history
                        // as model warm-up so CTL/ATL remain mathematically valid at the left boundary.
                        TrainingLoadCard(days: repo.days, displayDomain: selectedXDomain)
                            .staggeredAppear(index: 4)
                        exportReportRow
                            .staggeredAppear(index: 5)
                        yearStrip
                            .staggeredAppear(index: 6)
                    }
                }
            }
        }
        // #436 — present the offline trends-report exporter (range picker + PDF export).
        .sheet(isPresented: $showingReport) {
            TrendsReportSheet(days: repo.days)
        }
        // #732 — load the resolved sleep_performance series so Rest plots the SAME composite the Today
        // Rest score uses (not raw efficiency). Mirrors TodayView's restScore read. Keyed on the day
        // repository generation so a newly-banked/-scored night or source switch refreshes every series.
        .task(id: "\(repo.deviceId)|\(repo.refreshSeq)") {
            hrvHistory = []
            rhrHistory = []
            sleepPerfByDay = [:]
            let s = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop", fullHistory: true)
            sleepPerfByDay = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
            // Phase 2 belongs to canonical WHOOP cards only. Classify the active registry row rather than
            // excluding one known alternate source: Oura, Apple Watch, and generic straps must not inherit
            // canonical WHOOP history merely because they expose an HRV/RHR-shaped metric.
            let activeIsWhoop: Bool
            if let store = await repo.storeHandle() {
                let devices = (try? DeviceRegistryStore(dbQueue: store.registryWriter).all()) ?? []
                activeIsWhoop = devices.first(where: { $0.id == repo.deviceId })
                    .map(SourceCoordinator.isWhoop) ?? true
            } else {
                activeIsWhoop = true
            }
            guard activeIsWhoop else {
                hrvHistory = []
                rhrHistory = []
                return
            }
            async let hrv = repo.resolvedSeries(key: "hrv", source: Repository.whoopSource,
                                                fullHistory: true)
            async let rhr = repo.resolvedSeries(key: "rhr", source: Repository.whoopSource,
                                                fullHistory: true)
            let (hrvResolution, rhrResolution) = await (hrv, rhr)
            hrvHistory = hrvResolution.values
            rhrHistory = rhrResolution.values
        }
    }

    // MARK: Week-in-review digest with prev/next week browsing (#710)

    /// The earliest "yyyy-MM-dd" we hold (history is oldest → newest), used to clamp how far back the
    /// week stepper can go.
    private var earliestDay: String? { repo.days.first?.day }

    /// The most negative `weekOffset` allowed: the number of whole weeks between the earliest day's week
    /// and this week. Beyond that there's no data to digest, so the back chevron disables. 0 when history
    /// is empty or unparseable (so we stay on this week).
    private var minWeekOffset: Int {
        guard
            let earliest = earliestDay,
            let earliestMon = WeeklyDigestEngine.mondayOfWeek(containing: earliest),
            let thisMon = WeeklyDigestEngine.mondayOfWeek(containing: Repository.localDayKey(Date()))
        else { return 0 }
        // Walk weeks back from this Monday until we pass the earliest week. Bounded by history length.
        var off = 0
        var mon = thisMon
        while mon > earliestMon && off > -520 {           // hard cap ~10 years so a bad date can't spin
            mon = WeeklyDigestEngine.addDays(mon, -7)
            off -= 1
        }
        return off
    }

    /// The anchor day (any day in the target week) for the current `weekOffset`: today shifted back by
    /// `weekOffset` whole weeks. The engine snaps it to that week's Monday.
    private var weekAnchorDay: String {
        WeeklyDigestEngine.addDays(Repository.localDayKey(Date()), weekOffset * 7)
    }

    /// Move the digest one week earlier (-1) or later (+1), clamped to [minWeekOffset, 0] — never into a
    /// future week, never past the earliest week we hold.
    private func stepWeek(_ delta: Int) {
        let next = weekOffset + delta
        weekOffset = max(minWeekOffset, min(0, next))
    }

    /// The week-in-review digest for the selected week, with prev/next chevrons in its header. The digest
    /// for `weekAnchorDay` is built straight from the shared `WeeklyDigestSource` (the same builder the
    /// standalone WeeklyDigestCard uses) so past weeks render in the identical format. The whole block
    /// self-hides only when there's no data in ANY week (an all-empty history), matching the old card.
    @ViewBuilder
    private var weeklyDigestNav: some View {
        let digest = WeeklyDigestSource.digest(from: repo.days, anchorDay: weekAnchorDay)
        // Only hide the navigation entirely when the WHOLE history is empty — an empty PAST week still
        // shows the header + chevrons so the user can step to a week that does hold data.
        if repo.days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                weekNavBar(digest: digest)
                if digest.isEmpty {
                    // This particular week had no readings — keep the chevrons above so the user can move on.
                    DataPendingNote(
                        title: "No readings this week",
                        message: "Step to another week with the arrows above to see its review.")
                } else {
                    WeeklyDigestContent(digest: digest, compact: true, showsHeader: false)
                        .padding(.top, NoopMetrics.space1)
                    // Share this week's recap as an image. Renders the digest card (with its header) to a
                    // PNG off-screen and hands it to the share sheet / Save panel — reuses TrendsReport's
                    // ImageRenderer path. Only offered when the week actually holds data.
                    NoopButton("Share recap", systemImage: "square.and.arrow.up", kind: .secondary) {
                        let page = WeeklyDigestContent(digest: digest, compact: true, showsHeader: true)
                            .frame(width: 380)
                            .padding(24)
                            .background(StrandPalette.surfaceBase)
                            .environment(\.colorScheme, colorScheme)
                        TrendsReportRenderer.exportPNG(page: page, suggestedName: "noop-recap-\(weekAnchorDay).png")
                    }
                }
            }
        }
    }

    /// Prev/next week stepper. Back is clamped at the earliest week we hold; forward is clamped at this
    /// week (no future weeks). Mirrors the FullDayChartView day stepper's flat accent chevrons (#597).
    private func weekNavBar(digest: WeeklyDigest) -> some View {
        let atOldest = weekOffset <= minWeekOffset
        let atNewest = weekOffset >= 0
        let daysSummary = String(localized: "\(digest.daysWithData)/7 days")
        let daysAccessibility = String(localized: "\(digest.daysWithData) of 7 days had data")
        return HStack(spacing: NoopMetrics.cardInnerSpacing) {
            Button { stepWeek(-1) } label: {
                Image(systemName: "chevron.left").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(atOldest ? StrandPalette.textTertiary : StrandPalette.accent)
            .disabled(atOldest)
            .accessibilityLabel("Previous week")

            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? String(localized: "This week") : weekOffsetLabel)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("\(weeklyDigestRangeLabel(digest)) · \(daysSummary)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel("\(weeklyDigestRangeLabel(digest)), \(daysAccessibility)")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            Spacer()

            Button { stepWeek(1) } label: {
                Image(systemName: "chevron.right").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(atNewest ? StrandPalette.textTertiary : StrandPalette.accent)
            .disabled(atNewest)
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, NoopMetrics.space1)
        .accessibilityElement(children: .contain)
    }

    /// "Last week" for -1, else the count of weeks back ("3 weeks ago") for the stepper's centre label.
    private var weekOffsetLabel: String {
        let n = -weekOffset
        if n == 1 { return String(localized: "Last week") }
        return String(localized: "\(n) weeks ago")
    }


    // MARK: Export trends report (#436)

    /// A footer entry that opens the shareable-report sheet. Flat WHOOP card with a blue accent
    /// action — the icon, label and "Export" CTA all read in the accent (blue) world, no gold.
    private var exportReportRow: some View {
        NoopCard(tint: StrandPalette.accent) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: "doc.richtext")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Export trends report").strandOverline()
                    Text("A shareable one-page PDF of recovery, sleep, HRV, resting HR and strain over a range, saved on your \(Platform.deviceNoun).")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoopMetrics.space2)
                // The card's call-to-action — routed through the unified button system (secondary kind:
                // a quiet raised capsule that reads as the card action, not the one primary on the page).
                NoopButton("Export", systemImage: "square.and.arrow.up", kind: .secondary) {
                    showingReport = true
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Range control

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space2) {
                // Six ranges plus the trailing-window caption need to share a compact iPhone row.
                // Let the segmented control collapse to equal-width cells instead of squeezing the
                // caption narrower than one word (which wrapped the final G in TRAILING by itself).
                SegmentedPillControl(Range.allCases, selection: $range,
                                     adaptsToAvailableWidth: true) { $0.label }
                // Keep the caption's two lines internally leading-aligned, but anchor the whole
                // caption column to the page's trailing edge.
                Spacer(minLength: NoopMetrics.space2)
                rangeCaption
            }
        }
    }

    // MARK: Selectable metric hierarchy

    private func metricTitle(_ metric: TrendsMetric) -> LocalizedStringKey {
        switch metric {
        case .charge: return "Charge"
        case .hrv: return "Heart rate variability"
        case .rhr: return "Resting heart rate"
        case .rest: return "Rest"
        case .effort: return "Effort"
        }
    }

    private func metricUnit(_ metric: TrendsMetric) -> String {
        switch metric {
        case .hrv: return "ms"
        case .rhr: return "bpm"
        case .effort: return "/ \(UnitFormatter.effortScaleMax(effortScale))"
        case .charge, .rest: return ""
        }
    }

    private func metricColor(_ metric: TrendsMetric) -> Color {
        switch metric {
        case .charge: return StrandPalette.chargeColor
        case .hrv: return StrandPalette.metricPurple
        case .rhr: return StrandPalette.metricRose
        case .rest: return StrandPalette.restColor
        case .effort: return StrandPalette.effortColor
        }
    }

    private func metricGradient(_ metric: TrendsMetric) -> Gradient {
        metric == .charge ? StrandPalette.recoveryGradient : gradient(metricColor(metric))
    }

    private func metricMarkStyle(_ metric: TrendsMetric) -> TrendChartMarkStyle {
        switch metric {
        case .charge: return .chargeZones
        case .effort: return .bars
        default: return .line
        }
    }

    private func metricDomain(_ metric: TrendsMetric, points: [TrendPoint]) -> ClosedRange<Double> {
        switch metric {
        case .charge, .effort: return 0...100
        default: return valueRange(points, fallback: 0...100)
        }
    }

    private func formattedValue(_ value: Double, for metric: TrendsMetric) -> String {
        metric == .effort
            ? UnitFormatter.effortDisplay(value, scale: effortScale)
            : "\(Int(value.rounded()))"
    }

    private func displayedPoint(in data: SelectedTrendMetric) -> TrendPoint? {
        guard let index = TrendsMetric.selectedOrLatestIndex(
            selected: selectedHeroDate.flatMap { date in data.points.firstIndex { $0.date == date } },
            count: data.points.count
        ) else { return nil }
        return data.points[index]
    }

    private func metricContext(_ metric: TrendsMetric, data: SelectedTrendMetric,
                               displayed: TrendPoint?) -> String {
        if (metric == .hrv || metric == .rhr), let displayed {
            let rows = metric == .hrv ? hrvHistory : rhrHistory
            let population: ClosedRange<Double> = metric == .hrv ? 40...120 : 40...60
            let cfg = metric == .hrv ? Baselines.hrvCfg : Baselines.restingHRCfg
            let epoch = metric == .hrv ? Baselines.hrvBaselineEpoch() : Baselines.recoveryBaselineEpoch()
            let presentation = VitalBands.presentation(
                value: displayed.value, historyRows: rows.map { ($0.day, Optional($0.value)) },
                displayedDay: Self.dayParser.string(from: displayed.date), populationRange: population,
                cfg: cfg, baselineEpoch: epoch
            )
            return vitalContext(presentation, unit: metricUnit(metric))
        }
        guard let change = periodChange(data.points), abs(change) > 0.0001 else {
            return String(localized: "Not enough data for comparison")
        }
        let sign = change >= 0 ? "+" : "−"
        return String(localized: "\(sign)\(formattedValue(abs(change), for: metric)) vs earlier in period")
    }

    @ViewBuilder
    private func metricHero(metric: TrendsMetric, data: SelectedTrendMetric) -> some View {
        let displayed = displayedPoint(in: data)
        let color = metricColor(metric)
        NoopCard(tint: color) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text(metricTitle(metric)).strandOverline()
                        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                            Text(displayed.map { formattedValue($0.value, for: metric) } ?? "—")
                                .font(StrandFont.title1.monospacedDigit())
                                .foregroundStyle(StrandPalette.textPrimary)
                            if displayed != nil && !metricUnit(metric).isEmpty {
                                Text(metricUnit(metric)).font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    Text(displayed.map { vitalDateLabel($0.date) } ?? String(localized: "No reading"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                Text(metricContext(metric, data: data, displayed: displayed))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                if data.points.isEmpty {
                    sparsePlaceholder.frame(height: NoopMetrics.chartHeight)
                } else {
                    TrendChart(
                        points: data.points, gradient: metricGradient(metric),
                        valueRange: metricDomain(metric, points: data.points), showsArea: false,
                        markStyle: metricMarkStyle(metric), markColor: color,
                        height: NoopMetrics.chartHeight,
                        valueFormat: { formattedValue($0, for: metric) },
                        accessibilityLabel: metricTitleText(metric),
                        nowCapColor: color, chrome: .summary,
                        contextRange: heroContextRange(metric, displayed: displayed),
                        contextRangeColor: color, xDomain: data.xDomain, gapPolicy: .daily,
                        calendar: Self.utcCalendar,
                        onSelectionChange: { selectedHeroDate = $0?.date },
                        accessibilityValue: heroAccessibilityValue(
                            metric, displayed: displayed, data: data
                        )
                    )
                }
                HStack {
                    Text(coverage(data.result, expectedUnit: metric == .rest ? "nights" : "days"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    NavigationLink(value: TabRoute.metric(metric.detailKey)) {
                        HStack(spacing: NoopMetrics.space1) {
                            Text("Open")
                            Image(systemName: "chevron.right")
                        }
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if showAllHistoryAvailable(data.result) { showAllHistoryButton }
    }

    private func heroContextRange(_ metric: TrendsMetric, displayed: TrendPoint?) -> ClosedRange<Double>? {
        guard (metric == .hrv || metric == .rhr), let displayed else { return nil }
        let rows = metric == .hrv ? hrvHistory : rhrHistory
        let presentation = VitalBands.presentation(
            value: displayed.value, historyRows: rows.map { ($0.day, Optional($0.value)) },
            displayedDay: Self.dayParser.string(from: displayed.date),
            populationRange: metric == .hrv ? 40...120 : 40...60,
            cfg: metric == .hrv ? Baselines.hrvCfg : Baselines.restingHRCfg,
            baselineEpoch: metric == .hrv ? Baselines.hrvBaselineEpoch() : Baselines.recoveryBaselineEpoch()
        )
        return presentation.lowerBound...presentation.upperBound
    }

    private func metricTitleText(_ metric: TrendsMetric) -> String {
        switch metric {
        case .charge: return String(localized: "Charge")
        case .hrv: return String(localized: "Heart rate variability")
        case .rhr: return String(localized: "Resting heart rate")
        case .rest: return String(localized: "Rest")
        case .effort: return String(localized: "Effort")
        }
    }

    private func heroAccessibilityValue(
        _ metric: TrendsMetric, displayed: TrendPoint?, data: SelectedTrendMetric
    ) -> String {
        guard let displayed else { return String(localized: "No reading") }
        let value = "\(formattedValue(displayed.value, for: metric)) \(metricUnit(metric))"
            .trimmingCharacters(in: .whitespaces)
        return "\(value), \(vitalDateLabel(displayed.date)), \(metricContext(metric, data: data, displayed: displayed)), \(coverage(data.result, expectedUnit: metric == .rest ? "nights" : "days"))"
    }

    private func compactMetricRows(metrics: [TrendsMetric: SelectedTrendMetric]) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Daily signals", overline: "Select a metric")
            ForEach(TrendsMetric.secondary(to: heroMetric), id: \.self) { metric in
                if let data = metrics[metric] { compactMetricRow(metric, data: data) }
            }
        }
    }

    private func compactMetricRow(_ metric: TrendsMetric, data: SelectedTrendMetric) -> some View {
        let latest = data.points.last
        let color = metricColor(metric)
        return NoopCard(tint: color) {
            HStack(spacing: NoopMetrics.cardInnerSpacing) {
                Button {
                    selectedHeroDate = nil
                    heroMetric = metric
                } label: {
                    HStack(spacing: NoopMetrics.cardInnerSpacing) {
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(metricTitle(metric)).strandOverline()
                            Text(latest.map { "\(formattedValue($0.value, for: metric)) \(metricUnit(metric))" } ?? "—")
                                .font(StrandFont.title2.monospacedDigit())
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(metricContext(metric, data: data, displayed: latest))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(coverage(data.result, expectedUnit: metric == .rest ? "nights" : "days"))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if data.points.isEmpty {
                            sparsePlaceholder.frame(width: NoopMetrics.chartHeight / 2,
                                                    height: NoopMetrics.controlHeight)
                        } else {
                            TrendChart(
                                points: data.points, gradient: metricGradient(metric),
                                valueRange: metricDomain(metric, points: data.points), showsArea: false,
                                markStyle: metricMarkStyle(metric), height: NoopMetrics.controlHeight, showsHover: false,
                                accessibilityLabel: String(localized: "Compact metric trend"),
                                nowCapColor: color, chrome: .compact, xDomain: data.xDomain,
                                gapPolicy: .daily, calendar: Self.utcCalendar
                            )
                            .frame(width: NoopMetrics.chartHeight / 2)
                            .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Selects this metric as the primary chart.")
                NavigationLink(value: TabRoute.metric(metric.detailKey)) {
                    Image(systemName: "chevron.right")
                        .font(StrandFont.headline).foregroundStyle(StrandPalette.accent)
                        .frame(minWidth: NoopMetrics.controlHeight,
                               minHeight: NoopMetrics.controlHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(metricTitle(metric)))
                .accessibilityHint("Opens metric details.")
            }
        }
    }


    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }


    private func coverage(_ result: TrendWindow.Result, expectedUnit: String = "days") -> String {
        let count = expectedUnit == "nights"
            ? String(localized: "\(result.observed) of \(result.expected) nights")
            : String(localized: "\(result.observed) of \(result.expected) days")
        return range == .all ? "\(String(localized: "All history")) · \(count)" : count
    }

    private func showAllHistoryAvailable(_ result: TrendWindow.Result) -> Bool {
        range != .all && result.observed == 0 && result.hasOlderHistory
    }

    private var showAllHistoryButton: some View {
        NoopButton("Show all available history", systemImage: "clock.arrow.circlepath", kind: .secondary) {
            range = .all
        }
    }


    private func vitalDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }

    private func vitalContext(_ presentation: VitalBands.Presentation, unit: String) -> String {
        let bounds = "\(Int(presentation.lowerBound.rounded()))–\(Int(presentation.upperBound.rounded())) \(unit)"
        let rangeName = presentation.basis == .personal
            ? String(localized: "Your typical range")
            : String(localized: "General range")
        let position: String
        switch presentation.position {
        case .below: position = String(localized: "Below")
        case .within: position = String(localized: "Within")
        case .above: position = String(localized: "Above")
        case .noData: return String(localized: "\(rangeName) · \(bounds)")
        }
        return String(localized: "\(position) · \(rangeName) · \(bounds)")
    }


    // MARK: Year heat-strip

    private var yearStrip: some View {
        let projected = selectedTrend(repo.days.map { ($0.day, $0.recovery) })
        let scores = Dictionary(uniqueKeysWithValues: projected.result.points.map { ($0.day, $0.value) })
        let calendarStart = selectedXDomain?.lowerBound ?? projected.result.startDay.flatMap(date)
        let recoveryDays: [RecoveryDay] = calendarStart.flatMap { start in
            date(projected.result.endDay).map { end in
                var output: [RecoveryDay] = []
                var day = start
                while day <= end {
                    let key = Self.dayParser.string(from: day)
                    output.append(RecoveryDay(date: day, score: scores[key]))
                    day = Self.utcCalendar.date(byAdding: .day, value: 1, to: day)!
                }
                return output
            }
        } ?? []
        let title = range == .all ? String(localized: "Charge (all history)") : String(localized: "Charge")
        let observed = projected.result.observed
        let expected = projected.result.expected
        let coverageText = range == .all
            ? "\(String(localized: "All history")) · \(String(localized: "\(observed) of \(expected) days"))"
            : String(localized: "\(observed) of \(expected) days")
        return NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SectionHeader("\(title)", overline: "Calendar", trailing: coverageText)
                if recoveryDays.isEmpty {
                    sparsePlaceholder.frame(height: 120)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        YearHeatStrip(days: recoveryDays).padding(.vertical, NoopMetrics.space1 / 2)
                    }
                    Divider().overlay(StrandPalette.hairline)
                    legend
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Depleted")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize()
            LinearGradient(gradient: StrandPalette.recoveryGradient, startPoint: .leading, endPoint: .trailing)
                .frame(maxWidth: .infinity)
                .frame(height: NoopMetrics.indicatorTrackHeight)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            Text("Peaked")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Charge scale, depleted to peaked")
    }

    // MARK: Shared bits

    /// Single-color gradient (for metric lines that aren't a value ramp).
    private func gradient(_ color: Color) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(0.55), location: 0.0),
            .init(color: color, location: 1.0),
        ])
    }


    private var sparsePlaceholder: some View {
        Text("Not enough data for this window.")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(NoopPanelSurface(cornerRadius: 12))
    }
}

#if DEBUG
@MainActor
private func previewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let today = Date()
    var seeded: [DailyMetric] = []
    let span = 365 * 3
    for i in stride(from: span - 1, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let phase = Double(span - 1 - i)
        let rec = 55 + 28 * sin(phase / 11.0) + Double((Int(phase) * 31) % 17) - 8
        let hrv = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let rhr = 52 + 4 * sin(phase / 7.0) + Double((Int(phase) * 7) % 5) - 2
        let strain = 9 + 6 * sin(phase / 5.0 + 1.2) + Double((Int(phase) * 5) % 4) - 2
        let gap = Int(phase) % 23 == 0
        seeded.append(DailyMetric(
            day: fmt.string(from: d),
            totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 110, lightMin: 200,
            disturbances: 6, restingHr: gap ? nil : Int(rhr.rounded()),
            avgHrv: gap ? nil : max(15, hrv), recovery: gap ? nil : max(2, min(99, rec)),
            strain: gap ? nil : max(0, min(21, strain)), exerciseCount: 1
        ))
    }
    repo.days = seeded
    repo.loaded = true
    return repo
}

#Preview("Trends") {
    TrendsView()
        .environmentObject(previewRepo())
        .environmentObject(LiveState())
        .frame(width: 960, height: 960)
        .preferredColorScheme(.dark)
}
#endif
