import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Trends
//
// The longitudinal view, rebuilt on the locked Noop component system so every
// surface, height and gap is identical: one SegmentedPillControl for the range,
// a hero recovery ChartCard, a uniform grid of HRV / Resting HR / Day Strain
// ChartCards (all NoopMetrics.chartHeight tall), and the whole history as a
// recovery YearHeatStrip in a NoopCard. No hand-sized cards anywhere.

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
    @State private var selectedHRVDate: Date?
    @State private var selectedRHRDate: Date?
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
    // Trend chart style (line vs bar) — display-only; flips every trend card between the gradient line
    // and value-ramp bars. Read here at the screen root so a Settings change re-renders on return.
    @AppStorage(UnitPrefs.trendChartStyleKey) private var trendChartStyleRaw = TrendChartStyle.line.rawValue
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

    private func mean(_ pts: [TrendPoint]) -> Double? {
        guard !pts.isEmpty else { return nil }
        return pts.map(\.value).reduce(0, +) / Double(pts.count)
    }

    /// The window's trend as a signed mean-of-recent-half minus mean-of-earlier-half. Drives a
    /// TrendChip so the card reads its direction at a glance, like Today's deltas. nil for a window
    /// too short to split. `higherIsBetter == nil` (e.g. Effort) keeps the chip neutral.
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

    /// A TrendChip for a window's period change, coloured green/rose by whether the move is good for
    /// THIS metric (`higherIsBetter`); neutral when direction has no valence or the change is flat.
    @ViewBuilder
    private func changeChip(_ pts: [TrendPoint], higherIsBetter: Bool?, fmt: @escaping (Double) -> String) -> some View {
        if let d = periodChange(pts), abs(d) > 0.0001 {
            let sign = d >= 0 ? "+" : "−"
            let deltaText = "\(sign)\(fmt(abs(d)))"
            let color: Color = {
                guard let better = higherIsBetter else { return StrandPalette.textTertiary }
                return (d > 0) == better ? StrandPalette.statusPositive : StrandPalette.metricRose
            }()
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                // Match the neighbouring ChartFooter columns so the delta is self-describing instead
                // of appearing as an unlabeled pill at the edge of the statistics row.
                Text("Trend")
                    .textCase(.uppercase)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                TrendChip(text: deltaText, color: color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(String(localized: "Trend")): \(deltaText)"))
        }
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
            if repo.days.isEmpty && hrvHistory.isEmpty && rhrHistory.isEmpty {
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
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    // The main card list ripples in once on appear (Reduce-Motion safe).
                    Group {
                        // Week-in-review digest (#208) with prev/next week browsing (#710) — self-hides
                        // only when NO week in history has data. Past weeks render in the same format.
                        weeklyDigestNav
                            .staggeredAppear(index: 0)
                        // The Charge / Effort / Rest trio, presented in NOOP's pip language.
                        weekInReview(charge: recovery, effort: strain, rest: rest)
                            .staggeredAppear(index: 1)
                        rangeBar(recovery: recovery)
                            .staggeredAppear(index: 2)
                        heroRecovery(recovery: recovery)
                            .staggeredAppear(index: 3)
                        smallMultiples(hrv: hrv, rhr: rhr, strain: strain)
                            .staggeredAppear(index: 4)
                        // Training load keeps the selected display interval but receives full history
                        // as model warm-up so CTL/ATL remain mathematically valid at the left boundary.
                        TrainingLoadCard(days: repo.days, displayDomain: selectedXDomain)
                            .staggeredAppear(index: 5)
                        yearStrip
                            .staggeredAppear(index: 6)
                        exportReportRow
                            .staggeredAppear(index: 7)
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

    // MARK: Week in Review — the Charge / Effort / Rest trio in pip language

    /// The three daily scores as NOOP pip rows over the exact selected window: Charge (recovery, 0–100),
    /// Effort (strain, shown on the WHOOP 0–21 scale per the unit toggle) and Rest (sleep_performance
    /// composite, 0–100 — the same metric the Today Rest score shows, #732). Each value ticks up via
    /// `CountUpText`; the segmented `PipBar` cascades on appear. With no selected-window values it stays
    /// visible only when older observations make the explicit all-history action useful.
    @ViewBuilder
    private func weekInReview(charge: SelectedTrendMetric, effort: SelectedTrendMetric,
                              rest: SelectedTrendMetric) -> some View {
        let chargeAvg = mean(charge.points)
        let effortAvg = mean(effort.points)   // stored 0–100 internal Effort scale
        let restAvg = mean(rest.points)
        let hasOlderHistory = [charge, effort, rest].contains { showAllHistoryAvailable($0.result) }
        if chargeAvg != nil || effortAvg != nil || restAvg != nil || hasOlderHistory {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    SectionHeader("Week in review", overline: "Charge · Effort · Rest")
                    if let v = chargeAvg {
                        pipScoreRow(label: "Charge", value: v, range: 0...100,
                                    tint: StrandPalette.chargeColor, frac: v / 100,
                                    format: { "\(Int($0.rounded()))" })
                    }
                    metricCoverageRow(label: "Charge", result: charge.result)
                    if let v = effortAvg {
                        // Effort is stored 0–100 but reads on the WHOOP 0–21 scale per the unit toggle:
                        // convert the displayed number + bar position to the user's chosen Effort scale so
                        // the pip fill and the count-up value agree (both on the same scale).
                        let display = UnitFormatter.effortValue(v, scale: effortScale)
                        let maxV = UnitFormatter.effortValue(100, scale: effortScale)
                        // On the 0–21 WHOOP scale Effort reads to one decimal (e.g. "9.0"); on the 0–100
                        // scale it's a whole number — match `effortScaleMax` so the count-up format agrees.
                        let oneDecimal = effortScale == .whoop
                        // The vessel fills off the stored 0–100 internal scale (v), so it agrees with the
                        // Charge/Rest vessels regardless of the displayed Effort unit.
                        pipScoreRow(label: "Effort", value: display, range: 0...maxV,
                                    tint: StrandPalette.effortColor, frac: v / 100,
                                    format: { oneDecimal ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" })
                    }
                    metricCoverageRow(label: "Effort", result: effort.result)
                    if let v = restAvg {
                        pipScoreRow(label: "Rest", value: v, range: 0...100,
                                    tint: StrandPalette.restColor, frac: v / 100,
                                    format: { "\(Int($0.rounded()))" })
                    }
                    metricCoverageRow(label: "Rest", result: rest.result, expectedUnit: "nights")
                    if hasOlderHistory { showAllHistoryButton }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// One pip row matching `PipBarRow`'s layout, but with the value driven by `CountUpText` so the big
    /// number ticks up. UPPERCASE label + a small liquid vessel (the score as a fill) beside the big white
    /// count-up value, over the segmented count-up bar. `frac` (0…1) is the score on the shared 0–100
    /// internal scale so the three vessels read against the same fill — a small liquid accent on a single
    /// headline metric, exactly where it reads well (not on a chart).
    private func pipScoreRow(label: LocalizedStringKey, value: Double, range: ClosedRange<Double>,
                             tint: Color, frac: Double, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(label)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: NoopMetrics.space3) {
                // Static (posed) vessel — a small liquid gauge, not a live 60fps canvas, so the three
                // in this card cost a single cached frame each (same call as Today's small vessels).
                LiquidVessel(value: max(0, min(1, frac)), tint: tint, animated: false)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                CountUpText(value: value, format: format,
                            font: StrandFont.number(30, weight: .bold),
                            color: StrandPalette.textPrimary)
            }
            PipBar(value: value, range: range, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(format(value)))
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

    private func rangeBar(recovery: SelectedTrendMetric) -> some View {
        let cap = String(localized: "Charge · \(coverage(recovery.result))")
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
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
            Text(cap)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityLabel(cap)
        }
    }

    // MARK: Hero — recovery over time

    @ViewBuilder
    private func heroRecovery(recovery: SelectedTrendMetric) -> some View {
        let pts = recovery.points
        let avg = mean(pts)
        // Charge world — the WHOOP recovery value scale (red→yellow→green) drawn as a crisp flat line
        // with a bright "now" cap. No glow.
        let card = ChartCard(
            title: "Charge",
            // The range bar above already prints the authoritative reading-count caption;
            // the hero only names its window so the count isn't doubled in one card height.
            subtitle: rangeSubtitle,
            trailing: avg.map { "\(Int($0.rounded()))" },
            height: NoopMetrics.chartHeight,
            chart: {
                if !pts.isEmpty {
                    glowChart(points: pts,
                              gradient: StrandPalette.recoveryGradient,
                              // Lift the ceiling ~6% so a near-100 peak and the now-cap halo
                              // clear the top gridline, matching the padded small multiples.
                              valueRange: 0...106,
                              tip: StrandPalette.chargeBright,
                              valueFormat: { "\(Int($0.rounded()))" },
                              accessibilityLabel: String(localized: "Charge trend"),
                              xDomain: recovery.xDomain)
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack {
                        ChartFooter([
                            ("Avg", avg.map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Peak", pts.map(\.value).max().map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Low", pts.map(\.value).min().map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Days", "\(pts.count)"),
                        ])
                        changeChip(pts, higherIsBetter: true, fmt: { "\(Int($0.rounded()))" })
                    }
                    Text(coverage(recovery.result))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        )
        // Tap the hero to open the full Charge (recovery) metric detail — matching Today's card taps.
        // LiquidPressStyle gives the physical settle-inward on press (the liquid tap language). The card's
        // own rich labels (title + chart series + footer stats) are surfaced by the link's button element,
        // with a hint that a tap opens the detail.
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            NavigationLink(value: TabRoute.metric("recovery")) { card }
                .buttonStyle(LiquidPressStyle())
                .accessibilityHint(Text(String(localized: "Opens the full Charge metric.")))
            if showAllHistoryAvailable(recovery.result) { showAllHistoryButton }
        }
    }

    // MARK: Small multiples — HRV / Resting HR / Day Strain

    private func smallMultiples(hrv: SelectedTrendMetric, rhr: SelectedTrendMetric,
                                strain: SelectedTrendMetric) -> some View {
        let cols = [GridItem(.adaptive(minimum: 320), spacing: NoopMetrics.gap)]
        let strainPts = strain.points

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // No trailing window label — the range bar's overline already states it.
            SectionHeader("Daily signals", overline: "Trends")
            LazyVGrid(columns: cols, alignment: .leading, spacing: NoopMetrics.gap) {
                vitalTrendCard(
                    title: "Heart rate variability", unit: "ms",
                    accessibilityTitle: String(localized: "Heart rate variability"),
                    metricKey: "hrv", metric: hrv, selectedDate: $selectedHRVDate,
                    populationRange: 40...120, cfg: Baselines.hrvCfg,
                    color: StrandPalette.metricPurple
                )
                vitalTrendCard(
                    title: "Resting heart rate", unit: "bpm",
                    accessibilityTitle: String(localized: "Resting heart rate"),
                    metricKey: "rhr", metric: rhr, selectedDate: $selectedRHRDate,
                    populationRange: 40...60, cfg: Baselines.restingHRCfg,
                    color: StrandPalette.metricRose
                )
                metricChart(
                    // Plotted points + range stay on the stored 0–100 scale (line shape unchanged); only the
                    // displayed numbers + unit follow the Effort-scale toggle, converted inside `fmt`. (#268)
                    title: "Effort", unit: "/ \(UnitFormatter.effortScaleMax(effortScale))",
                    accessibilityTitle: String(localized: "Effort"),
                    metricKey: "strain",
                    metric: strain,
                    // WHOOP: Effort/Strain is always BLUE — a deep→bright blue line, not the amber ramp.
                    gradient: gradient(StrandPalette.effortColor),
                    tip: StrandPalette.effortColor,
                    tint: StrandPalette.effortColor,
                    higherIsBetter: nil,
                    range: valueRange(strainPts, fallback: 0...100),
                    fmt: { UnitFormatter.effortDisplay($0, scale: effortScale) }
                )
            }
        }
    }

    @ViewBuilder
    private func vitalTrendCard(
        title: LocalizedStringKey,
        unit: String,
        accessibilityTitle: String,
        metricKey: String,
        metric: SelectedTrendMetric,
        selectedDate: Binding<Date?>,
        populationRange: ClosedRange<Double>,
        cfg: MetricCfg,
        color: Color
    ) -> some View {
        let displayed = selectedDate.wrappedValue.flatMap { selected in
            metric.points.first { $0.date == selected }
        } ?? metric.points.last
        let displayedDay = displayed.map { Self.dayParser.string(from: $0.date) }
        let presentation = displayedDay.map { day in
            VitalBands.presentation(
                value: displayed?.value,
                historyRows: (metricKey == "hrv" ? hrvHistory : rhrHistory)
                    .map { ($0.day, Optional($0.value)) },
                displayedDay: day,
                populationRange: populationRange,
                cfg: cfg,
                baselineEpoch: metricKey == "hrv"
                    ? Baselines.hrvBaselineEpoch() : Baselines.recoveryBaselineEpoch()
            )
        }
        let context = presentation.map { vitalContext($0, unit: unit) }
        let coverage = vitalCoverage(metric.result)
        let dateLabel = displayed.map { vitalDateLabel($0.date) }
        let valueLabel = displayed.map { "\(Int($0.value.rounded()))" } ?? "—"
        let a11y = String(localized: "\(dateLabel ?? String(localized: "No reading")) · \(context ?? String(localized: "No reading")) · \(coverage)")

        let card = NoopCard(tint: color) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text(title).strandOverline()
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(valueLabel)
                        .font(StrandFont.number(30, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if displayed != nil {
                        Text(unit)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer()
                    Text(dateLabel ?? String(localized: "No reading"))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let context {
                    Text(context)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if metric.points.isEmpty {
                    sparsePlaceholder.frame(height: NoopMetrics.chartHeight)
                } else {
                    TrendChart(
                        points: metric.points,
                        gradient: gradient(color),
                        valueRange: valueRange(metric.points, fallback: populationRange),
                        showsArea: false,
                        showsBars: false,
                        height: NoopMetrics.chartHeight,
                        valueFormat: { "\(Int($0.rounded())) \(unit)" },
                        accessibilityLabel: String(localized: "\(accessibilityTitle) trend"),
                        chrome: .summary,
                        contextRange: presentation.map { $0.lowerBound...$0.upperBound },
                        contextRangeColor: color,
                        xDomain: metric.xDomain,
                        gapPolicy: .daily,
                        calendar: Self.utcCalendar,
                        onSelectionChange: { selectedDate.wrappedValue = $0?.date },
                        accessibilityValue: String(localized: "\(valueLabel) \(unit). \(a11y)")
                    )
                }
                Text(coverage)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            NavigationLink(value: TabRoute.metric(metricKey)) { card }
                .buttonStyle(LiquidPressStyle())
                .accessibilityHint(Text("Opens metric details."))
            if showAllHistoryAvailable(metric.result) { showAllHistoryButton }
        }
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func vitalCoverage(_ result: TrendWindow.Result) -> String {
        let coverage = String(localized: "\(result.observed) of \(result.expected) nights")
        if range == .all {
            return "\(String(localized: "All history")) · \(coverage)"
        }
        return coverage
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

    private func metricCoverageRow(label: LocalizedStringKey, result: TrendWindow.Result,
                                   expectedUnit: String = "days") -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(coverage(result, expectedUnit: expectedUnit))
        }
        .font(StrandFont.footnote)
        .foregroundStyle(StrandPalette.textTertiary)
        .accessibilityElement(children: .combine)
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

    @ViewBuilder
    private func metricChart(
        title: LocalizedStringKey, unit: String,
        // Plain-string series name for VoiceOver (the `title` is a LocalizedStringKey and can't be
        // re-read as a String); supplied by callers so the line announces e.g. "HRV trend".
        accessibilityTitle: String,
        // MetricCatalog key this small-multiple taps through to (its full MetricDetailView).
        metricKey: String,
        metric: SelectedTrendMetric,
        subtitle: String? = nil,
        gradient: Gradient,
        tip: Color,
        tint: Color?,
        higherIsBetter: Bool?,
        range: ClosedRange<Double>,
        fmt: @escaping (Double) -> String
    ) -> some View {
        let pts = metric.points
        let avg = mean(pts)
        let card = ChartCard(
            title: title,
            subtitle: subtitle,
            trailing: avg.map(fmt),
            height: NoopMetrics.chartHeight,
            tint: tint,
            chart: {
                if !pts.isEmpty {
                    glowChart(points: pts, gradient: gradient, valueRange: range,
                              tip: tip, valueFormat: { "\(fmt($0)) \(unit)" },
                              accessibilityLabel: String(localized: "\(accessibilityTitle) trend"),
                              xDomain: metric.xDomain)
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack {
                        ChartFooter([
                            // Plain "MEAN" to match the bare MIN/MAX columns; the unit moves into
                            // the value (e.g. "58 ms") so uppercasing can't render a shouty "MEAN MS".
                            ("Mean", avg.map { "\(fmt($0)) \(unit)" } ?? "—"),
                            ("Min", pts.map(\.value).min().map(fmt) ?? "—"),
                            ("Max", pts.map(\.value).max().map(fmt) ?? "—"),
                        ])
                        changeChip(pts, higherIsBetter: higherIsBetter, fmt: fmt)
                    }
                    Text(coverage(metric.result))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        )
        // Each small-multiple taps through to its own metric detail (like Today's cards / Explore's rows),
        // with the liquid press settle. The chart itself is left uncluttered — no vessel over it (task).
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            NavigationLink(value: TabRoute.metric(metricKey)) { card }
                .buttonStyle(LiquidPressStyle())
                .accessibilityHint(Text(String(localized: "Opens the full \(accessibilityTitle) metric.")))
            if showAllHistoryAvailable(metric.result) { showAllHistoryButton }
        }
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

    /// A domain-tinted `TrendChart` with a crisp flat line and a bright end-cap dot at the latest
    /// point. WHOOP-flat: no underglow blur layer — the single crisp line carries the data and the
    /// fill contrast does the rest. The "now" end-cap is a small dot pinned to the final sample.
    /// Pure presentation: it forwards every value to the locked `TrendChart` unchanged.
    @ViewBuilder
    private func glowChart(points pts: [TrendPoint], gradient: Gradient, valueRange: ClosedRange<Double>,
                           tip: Color, valueFormat: @escaping (Double) -> String,
                           accessibilityLabel: String,
                           xDomain: ClosedRange<Date>?) -> some View {
        // One crisp, interactive line + area — flat, no blurred glow copy underneath (WHOOP language).
        // The "now" end-cap is drawn INSIDE this chart (nowCapColor) so it's mapped by the chart's own
        // scales and lands on the line — the previous sibling overlay guessed the plot insets and
        // floated the dot left/below the curve (#458).
        TrendChart(points: pts, gradient: gradient, valueRange: valueRange,
                   showsArea: true,
                   showsBars: TrendChartStyle(rawValue: trendChartStyleRaw) == .bar,
                   height: NoopMetrics.chartHeight, valueFormat: valueFormat,
                   accessibilityLabel: accessibilityLabel, nowCapColor: tip,
                   chrome: .summary, xDomain: xDomain, gapPolicy: .daily,
                   calendar: Self.utcCalendar)
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
