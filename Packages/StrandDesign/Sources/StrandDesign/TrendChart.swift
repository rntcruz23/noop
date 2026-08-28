#if !os(watchOS)
// TrendChart is a Swift Charts view with .onContinuousHover (unavailable on watchOS); the watch
// never shows it, so the whole file is excluded there. iOS/macOS unchanged.
import SwiftUI
import Charts

// MARK: - Trend Chart (§9.4 Trends)
//
// A line/area chart whose line is gradient-stroked by value — reusable for
// recovery / HRV / RHR / strain trends. The gradient defaults to the recovery
// scale (so a recovery-over-time line travels deep-gold → pale-gold by daily
// score), but any gradient + value-range can be supplied — pass the blue sleep
// ramp for sleep, the teal HRV scale for HRV, the amber strain ramp for strain.

/// One point on a trend line.
public struct TrendPoint: Identifiable, Sendable {
    public var date: Date
    public var value: Double
    /// Sequential line-segment identity. Points with different ids are rendered as separate lines, so a
    /// metric can retain history without drawing a false transition across incompatible methods.
    public var segment: String

    /// Stable, content-derived identity (one point per date in a series). A random
    /// `UUID()` defeats Swift Charts' diffing — every render re-identifies all marks
    /// and replays the draw animation; keying on the date lets Charts diff by data.
    public var id: Date { date }

    public init(date: Date, value: Double, segment: String = "default") {
        self.date = date
        self.value = value
        self.segment = segment
    }
}

public enum TrendChartChrome: Sendable, Equatable {
    case detail
    case summary
}

public enum TrendChartGapPolicy: Sendable, Equatable {
    case none
    case daily
}

public struct TrendChart: View {

    public var points: [TrendPoint]
    /// The gradient the line/area is stroked with (defaults to the recovery scale).
    public var gradient: Gradient
    /// The value range mapped onto the gradient (0 → bottom color, max → top color).
    public var valueRange: ClosedRange<Double>
    /// Whether to draw the soft area fill below the line.
    public var showsArea: Bool
    /// Draw vertical bars from the axis baseline instead of the line + area + points. One value-ramp-
    /// filled `BarMark` per (down-sampled) sample. Display-only — the plotted series is identical; only
    /// the mark geometry changes. Default false (the classic line). `showsArea` is ignored in bar mode.
    public var showsBars: Bool
    public var height: CGFloat
    /// Whether hovering reveals a crosshair + tooltip for the nearest point.
    public var showsHover: Bool
    /// Formats a point's value for the tooltip's bold line (default: rounded int).
    public var valueFormat: (Double) -> String
    /// Formats a point's date for the tooltip's secondary line.
    public var dateFormat: (Date) -> String
    /// Optional human-readable series name for VoiceOver (e.g. "HRV trend"). When nil the
    /// element falls back to a generic "Trend" label so it's never unlabeled.
    public var accessibilityLabel: String?
    /// When set, draws a glowing "now" end-cap on the most-recent point — IN the chart's own
    /// coordinate space (via the overlay proxy), so it sits exactly on the line. nil = no cap.
    /// (#458: an earlier sibling-overlay cap guessed the plot insets and floated off the line.)
    public var nowCapColor: Color?
    /// Y-axis domain when it should differ from `valueRange` — e.g. an axis fitted to the data
    /// window (with a little headroom) while the gradient stays anchored to the metric's full
    /// scale. nil = `valueRange`. Widening the TOP of this domain is how a caller keeps a peak
    /// curve and the top axis label clear of the plot clip (see #974); done purely in data space
    /// so it needs no macOS14/iOS17 plot-dimension padding API — works on our macOS13/iOS16 floor.
    public var yDomain: ClosedRange<Double>?
    /// Summary mode removes persistent chart chrome while preserving the historical detail defaults.
    public var chrome: TrendChartChrome
    /// Caller-owned context geometry; analytics meaning remains outside this primitive.
    public var contextRange: ClosedRange<Double>?
    public var contextRangeColor: Color
    /// Optional full selected-window domain, including dates without observations.
    public var xDomain: ClosedRange<Date>?
    /// Reports the full-resolution selected point, or nil when inspection ends.
    public var onSelectionChange: ((TrendPoint?) -> Void)?
    /// Optional card-level semantics including period, context, and coverage.
    public var accessibilityValue: String?

    /// Mean of all point values, computed once in `init` so the area fill's gradient
    /// stop doesn't run an O(n) reduce for every mark on every render.
    private let averageValue: Double

    /// One-line VoiceOver summary (count + mean + range), built once in `init`.
    private let a11ySummary: String

    public init(
        points: [TrendPoint],
        gradient: Gradient = StrandPalette.recoveryGradient,
        valueRange: ClosedRange<Double> = 0...100,
        showsArea: Bool = true,
        showsBars: Bool = false,
        height: CGFloat = 220,
        showsHover: Bool = true,
        valueFormat: @escaping (Double) -> String = { String(Int($0.rounded())) },
        dateFormat: @escaping (Date) -> String = { TrendChart.defaultDateString($0) },
        accessibilityLabel: String? = nil,
        nowCapColor: Color? = nil,
        yDomain: ClosedRange<Double>? = nil,
        chrome: TrendChartChrome = .detail,
        contextRange: ClosedRange<Double>? = nil,
        contextRangeColor: Color = StrandPalette.hairlineStrong,
        xDomain: ClosedRange<Date>? = nil,
        gapPolicy: TrendChartGapPolicy = .none,
        calendar: Calendar = .current,
        onSelectionChange: ((TrendPoint?) -> Void)? = nil,
        accessibilityValue: String? = nil
    ) {
        let sortedInput = points.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        let sorted = gapPolicy == .daily
            ? ChartGeometry.applyingDailySegments(to: sortedInput, calendar: calendar)
            : sortedInput
        self.points = sorted
        self.gradient = gradient
        self.valueRange = valueRange
        self.showsArea = showsArea
        self.showsBars = showsBars
        self.height = height
        self.showsHover = showsHover
        self.valueFormat = valueFormat
        self.dateFormat = dateFormat
        self.accessibilityLabel = accessibilityLabel
        self.nowCapColor = nowCapColor
        self.yDomain = yDomain
        self.chrome = chrome
        self.contextRange = contextRange
        self.contextRangeColor = contextRangeColor
        self.xDomain = xDomain
        self.onSelectionChange = onSelectionChange
        self.accessibilityValue = accessibilityValue
        let avg = sorted.isEmpty
            ? valueRange.lowerBound
            : sorted.map(\.value).reduce(0, +) / Double(sorted.count)
        self.averageValue = avg

        // The point set handed to the marks: full resolution up to the threshold, else min/max-bucketed
        // to ~the plot pixel width (pixel-identical line, far fewer GPU vertices). Computed once here.
        self.displayPoints = ChartDownsample.minMaxBucketed(sorted, threshold: ChartDownsample.markThreshold,
                                                            targetCount: ChartDownsample.targetVertices)

        // VoiceOver one-liner: count + mean + range — formatted with the SAME valueFormat the
        // tooltip uses, so units match. Computed once here, not per render.
        if sorted.isEmpty {
            self.a11ySummary = String(localized: "No data", bundle: .module)
        } else {
            let vals = sorted.map(\.value)
            let lo = vals.min()!, hi = vals.max()!
            self.a11ySummary = String(localized: "\(sorted.count) points, mean \(valueFormat(avg)), range \(valueFormat(lo)) to \(valueFormat(hi))", bundle: .module)
        }
    }

    /// The x-position the cursor is hovering, in chart-local coordinates.
    @State private var hoverX: CGFloat? = nil

    /// PERF: a 365-day (or longer) series feeds Swift Charts hundreds of LineMark/AreaMark vertices, each
    /// catmullRom-interpolated — far more than the ~360pt plot has pixels, so most are sub-pixel and pure
    /// draw cost. `displayPoints` is the point set actually handed to the marks: full resolution up to a
    /// threshold, else min/max-per-bucket down to roughly the plot pixel width. Min/max bucketing keeps
    /// every visible peak and trough, so the rendered line is pixel-identical on a normal-width chart.
    /// Computed ONCE in `init` (not per body/hover eval), so it's memoized on `points`; hover / now-cap /
    /// accessibility stay on the full-resolution `points` so those readouts are unchanged.
    private let displayPoints: [TrendPoint]

    private static let sharedDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    /// Default tooltip date format ("EEE d MMM"), exposed so it can seed the
    /// `dateFormat` default argument.
    public static func defaultDateString(_ date: Date) -> String {
        sharedDateFormatter.string(from: date)
    }

    /// The point nearest a given chart-local x, using the proxy to map back.
    private func nearestPoint(toX x: CGFloat, proxy: ChartProxy, plot: CGRect) -> TrendPoint? {
        guard !points.isEmpty else { return nil }
        // Map the cursor x (relative to the plot area) back to a Date.
        let relX = x - plot.minX
        guard let date: Date = proxy.value(atX: relX) else { return nil }
        // Find the TrendPoint whose date is closest.
        return points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    // Map data values onto the unit interval for gradient stops.
    private func unit(_ value: Double) -> Double {
        let lo = valueRange.lowerBound, hi = valueRange.upperBound
        guard hi > lo else { return 0 }
        return min(max((value - lo) / (hi - lo), 0), 1)
    }

    // A vertical gradient keyed to the value axis so the stroke color tracks value.
    private var valueGradient: LinearGradient {
        LinearGradient(gradient: gradient, startPoint: .bottom, endPoint: .top)
    }

    /// The Y domain actually applied to the axis + plot clip: the explicit `yDomain` when a caller
    /// supplied one (e.g. a data-fitted axis with top headroom), else the gradient's `valueRange`.
    /// Exposed internally so a unit test can pin the resolution without rendering the chart.
    var resolvedYDomain: ClosedRange<Double> { yDomain ?? valueRange }

    /// `resolvedYDomain`, floored at (or below) 0 in bar mode so a `BarMark`'s length stays
    /// proportional to its value — see the `.chartYScale` comment in `body` for why. Line mode is
    /// unaffected. Exposed internally alongside `resolvedYDomain` for the same test-without-rendering
    /// reason.
    var plotYDomain: ClosedRange<Double> {
        let domain = ChartGeometry.expandingDomain(resolvedYDomain, toInclude: contextRange)
        return showsBars ? min(0, domain.lowerBound)...domain.upperBound : domain
    }

    var rendersArea: Bool { chrome == .detail && showsArea }
    var rendersPersistentYAxis: Bool { chrome == .detail }
    var rendersAllPointMarkers: Bool { chrome == .detail && points.count <= 60 }
    var rendersTooltip: Bool { chrome == .detail && showsHover }

    private var resolvedXDomain: ClosedRange<Date>? {
        xDomain ?? points.first.map { $0.date...(points.last?.date ?? $0.date) }
    }

    private var summaryAxisDates: [Date] {
        guard chrome == .summary, let resolvedXDomain else { return [] }
        return ChartGeometry.summaryAxisDates(domain: resolvedXDomain)
    }

    public var body: some View {
        Chart {
            if let contextRange,
               let clipped = ChartGeometry.clippedRange(contextRange, to: plotYDomain),
               let resolvedXDomain {
                RectangleMark(
                    xStart: .value("Range start", resolvedXDomain.lowerBound),
                    xEnd: .value("Range end", resolvedXDomain.upperBound),
                    yStart: .value("Range lower", clipped.lowerBound),
                    yEnd: .value("Range upper", clipped.upperBound)
                )
                .foregroundStyle(contextRangeColor.opacity(0.14))
            }
            if showsBars {
                // Bar mode: one value-ramp-filled BarMark per (down-sampled) sample, from the baseline.
                // The line, area and point marks are all replaced. The same `displayPoints` feed it, so a
                // dense window is min/max-bucketed to the vertex budget exactly as the line is; hover, the
                // axes, the domain and accessibility are unchanged (they read the full `points`).
                ForEach(displayPoints) { p in
                    BarMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value)
                    )
                    .foregroundStyle(valueGradient)
                }
            } else {
                if rendersArea {
                    ForEach(displayPoints) { p in
                        AreaMark(
                            x: .value("Date", p.date),
                            y: .value("Value", p.value),
                            series: .value("Segment", p.segment)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    StrandPalette.sample(stops: gradient.toStops(), at: unit(averageValue)).opacity(0.28),
                                    Color.clear
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
                ForEach(displayPoints) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value),
                        series: .value("Segment", p.segment)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(valueGradient)
                }
                // 18pt dots are invisible on dense series (e.g. a 365-day year) but still cost the
                // GPU a mark each — hide them past a threshold; the line carries the data there. The gate
                // stays on the full `points.count` (≤60 is never downsampled, so displayPoints == points).
                if rendersAllPointMarkers {
                    ForEach(displayPoints) { p in
                        PointMark(
                            x: .value("Date", p.date),
                            y: .value("Value", p.value)
                        )
                        .symbolSize(18)
                        .foregroundStyle(StrandPalette.sample(stops: gradient.toStops(), at: unit(p.value)))
                    }
                }
            }
        }
        // Domain drives BOTH the axis extent and the plot clip. A caller that wants a top-of-range
        // peak (and the top axis label) to clear the clip passes a `yDomain` whose upper bound sits a
        // little above the data — pure data-space headroom, so no macOS14/iOS17 plot-dimension endPadding
        // API is needed (#974). The value→color gradient still keys off `valueRange`, unchanged.
        // Bars must read from a zero baseline to be truthful: a BarMark's length is only proportional to
        // its value when 0 is in the domain. The LINE uses a data-FITTED domain (often non-zero — e.g. an
        // RHR window of ~48…61) to show variation; reusing that for bars would float every bar near full
        // height with the real differences squashed into the top. So in bar mode we drop the floor to 0
        // (or below, should a caller ever plot negatives), matching Android's zero-based BarChart. The
        // upper bound (with the caller's headroom) is unchanged, so the line's domain is untouched.
        .chartYScale(domain: plotYDomain)
        .modifier(OptionalChartXDomain(domain: xDomain))
        // Clip the plot to its own bounds. catmullRom interpolation overshoots past the data extremes
        // on sharp turns, and the AreaMark gradient is drawn UNCLIPPED — so on a spiky HR curve the
        // rose fill bled down the page behind the cards below the chart. Clipping the plot area bounds
        // every mark (line, area, points, overshoot) to the chart rectangle.
        .chartPlotStyle { plotArea in plotArea.clipped() }
        .chartXAxis {
            if chrome == .summary {
                AxisMarks(values: summaryAxisDates) { _ in
                    AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                        .font(StrandFont.footnote)
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(0.4))
                    AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                        .font(StrandFont.footnote)
                }
            }
        }
        .chartYAxis {
            if rendersPersistentYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(0.4))
                    AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                        .font(StrandFont.footnote)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotRectCompat(in: geo)
                ZStack(alignment: .topLeading) {
                    if showsHover,
                       let hx = hoverX,
                       let p = nearestPoint(toX: hx, proxy: proxy, plot: plot),
                       let px = proxy.position(forX: p.date),
                       let py = proxy.position(forY: p.value) {
                        let cx = px + plot.minX
                        let cy = py + plot.minY
                        let color = StrandPalette.sample(stops: gradient.toStops(), at: unit(p.value))

                        // Vertical crosshair at the nearest x.
                        CrosshairRule(x: cx, height: geo.size.height)

                        // Highlighted dot on the line.
                        HighlightDot(color: color)
                            .position(x: cx, y: cy)

                        // Tooltip near the point, kept in bounds.
                        if rendersTooltip {
                            PositionedTooltip(
                                anchor: CGPoint(x: cx, y: cy),
                                container: geo.size,
                                tooltip: ChartTooltip(
                                    value: valueFormat(p.value),
                                    label: dateFormat(p.date),
                                    accent: color
                                )
                            )
                        }
                    }

                    // "Now" end-cap on the latest point (#458). Positioned with the SAME proxy mapping the
                    // line uses (position(forX:/forY:) + plot origin), so it lands exactly on the curve —
                    // not via a sibling overlay guessing the axis insets, which floated it left/below.
                    if !showsBars,
                       let capColor = nowCapColor ?? (chrome == .summary ? contextRangeColor : nil),
                       let last = ChartGeometry.selectedOrLatestPoint(selectedDate: nil, points: points),
                       let px = proxy.position(forX: last.date),
                       let py = proxy.position(forY: last.value) {
                        NowCapDot(color: capColor)
                            .position(x: px + plot.minX, y: py + plot.minY)
                            .allowsHitTesting(false)
                    }
                }
                .animation(StrandMotion.fade, value: hoverX)
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    guard showsHover else { return }
                    // Update the hover position in a NON-animating transaction. Otherwise entering or
                    // leaving the chart flips hoverX inside an animated context, the body re-evaluates,
                    // and SwiftUI Charts re-runs the line's draw-on animation — flickering the curve to a
                    // flat baseline and back as the cursor crosses the plot edge (#104). The crosshair's
                    // own fade is the overlay's .animation(value: hoverX) above and is unaffected by this.
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        switch phase {
                        case .active(let location):
                            hoverX = location.x
                            onSelectionChange?(nearestPoint(toX: location.x, proxy: proxy, plot: plot))
                        case .ended:
                            hoverX = nil
                            onSelectionChange?(nil)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            guard showsHover else { return }
                            hoverX = value.location.x
                            onSelectionChange?(nearestPoint(toX: value.location.x, proxy: proxy, plot: plot))
                        }
                        .onEnded { _ in
                            hoverX = nil
                            onSelectionChange?(nil)
                        }
                )
            }
        }
        .frame(height: height)
        // NOTE: no outer `.clipped()` here. The PLOT is already clipped to its own bounds by
        // `.chartPlotStyle { plotArea.clipped() }` above (that's what contains the catmullRom overshoot +
        // the unclipped AreaMark bleed). An additional clip on the WHOLE chart also cropped the axis-label
        // gutter — cutting the top y-axis value (e.g. "90") in half and clipping the first/last x-axis
        // labels ("Apr 19"…"May") at the frame edges (#1019). Dropping it lets Swift Charts render the
        // reserved label regions in full; the marks stay contained by the plot clip, so nothing bleeds.
        // Collapse the Charts marks (line/area/points) into ONE meaningful VoiceOver element instead
        // of letting VoiceOver walk raw per-mark axis values with no series context. The decorative
        // stacked under-glow copy (showsHover:false, no label) is hidden so the same series isn't
        // double-announced; the crisp interactive copy passes showsHover:true (default) and speaks.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel.map(Text.init) ?? Text("Trend", bundle: .module))
        .accessibilityValue(Text(accessibilityValue ?? a11ySummary))
        .accessibilityHidden(!showsHover && accessibilityLabel == nil)
    }
}

private struct OptionalChartXDomain: ViewModifier {
    var domain: ClosedRange<Date>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let domain, domain.lowerBound < domain.upperBound {
            content.chartXScale(domain: domain)
        } else {
            content
        }
    }
}

// MARK: - Shared chart geometry (pure)

enum ChartGeometry {
    static func dailySegmentIds(dates: [Date], calendar: Calendar = .current) -> [String] {
        guard !dates.isEmpty else { return [] }
        var run = 0
        var result = ["0"]
        for index in dates.indices.dropFirst() {
            let previous = calendar.startOfDay(for: dates[index - 1])
            let current = calendar.startOfDay(for: dates[index])
            if calendar.dateComponents([.day], from: previous, to: current).day != 1 {
                run += 1
            }
            result.append(String(run))
        }
        return result
    }

    static func applyingDailySegments(to points: [TrendPoint], calendar: Calendar = .current) -> [TrendPoint] {
        let dayRuns = dailySegmentIds(dates: points.map(\.date), calendar: calendar)
        guard dayRuns.count == points.count else { return points }
        var previousSource: String?
        var previousDayRun: String?
        var combinedRun = -1
        return points.enumerated().map { index, point in
            if point.segment != previousSource || dayRuns[index] != previousDayRun {
                combinedRun += 1
            }
            previousSource = point.segment
            previousDayRun = dayRuns[index]
            return TrendPoint(date: point.date, value: point.value, segment: "\(combinedRun):\(point.segment)")
        }
    }

    static func normalizedCalendarPositions(
        dates: [Date],
        domain: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [Double]? {
        let start = calendar.startOfDay(for: domain.lowerBound)
        let end = calendar.startOfDay(for: domain.upperBound)
        guard let span = calendar.dateComponents([.day], from: start, to: end).day, span > 0 else { return nil }
        var last = -Double.infinity
        var result: [Double] = []
        for date in dates {
            guard let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day else {
                return nil
            }
            let position = Double(offset) / Double(span)
            guard position >= 0, position <= 1, position >= last else { return nil }
            result.append(position)
            last = position
        }
        return result
    }

    static func summaryAxisDates(domain: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: domain.lowerBound)
        let end = calendar.startOfDay(for: domain.upperBound)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day, days > 0 else { return [start] }
        let middle = calendar.date(byAdding: .day, value: days / 2, to: start) ?? start
        return Array(Set([start, middle, end])).sorted()
    }

    static func clippedRange(_ range: ClosedRange<Double>, to domain: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              domain.lowerBound.isFinite, domain.upperBound.isFinite else { return nil }
        let lower = max(range.lowerBound, domain.lowerBound)
        let upper = min(range.upperBound, domain.upperBound)
        return lower <= upper ? lower...upper : nil
    }

    static func expandingDomain(
        _ domain: ClosedRange<Double>,
        toInclude range: ClosedRange<Double>?
    ) -> ClosedRange<Double> {
        guard let range, range.lowerBound.isFinite, range.upperBound.isFinite else { return domain }
        return min(domain.lowerBound, range.lowerBound)...max(domain.upperBound, range.upperBound)
    }

    static func selectedOrLatestPoint(selectedDate: Date?, points: [TrendPoint]) -> TrendPoint? {
        let valid = points.filter { $0.value.isFinite }.sorted { $0.date < $1.date }
        guard let selectedDate else { return valid.last }
        return valid.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    static func segmentRanges(points: [TrendPoint]) -> [ClosedRange<Int>] {
        guard !points.isEmpty else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start = 0
        for index in points.indices.dropFirst() where points[index].segment != points[index - 1].segment {
            ranges.append(start...(index - 1))
            start = index
        }
        ranges.append(start...(points.count - 1))
        return ranges
    }
}

// MARK: - Chart downsampling (pure)
//
// Reduces a dense point series to roughly the plot's pixel width BEFORE it reaches Swift Charts, so the
// GPU draws ~one vertex per pixel instead of hundreds it can't resolve. Uses MIN/MAX-per-bucket: each
// bucket contributes its lowest and highest sample (in time order), so every visible peak and trough
// survives and the rendered envelope is identical at normal chart widths. First and last points are
// always kept so the line spans the full domain. Pure + deterministic — same input → same output.

enum ChartDownsample {
    /// Above this many points we downsample; at or below it the series is passed through untouched (so
    /// the common 7/30/90-day trends and the ≤60-point dotted series are byte-for-byte unchanged).
    static let markThreshold = 120
    /// Target drawn-vertex budget — a touch above a typical ~360pt plot so the line stays crisp.
    static let targetVertices = 400

    /// Min/max-bucketed copy of `points` when it exceeds `threshold`, else `points` unchanged.
    /// Assumes `points` is already sorted by date (both chart callers sort in their init).
    static func minMaxBucketed(_ points: [TrendPoint], threshold: Int, targetCount: Int) -> [TrendPoint] {
        ChartGeometry.segmentRanges(points: points).flatMap { range in
            minMaxBucketedSingleSegment(Array(points[range]), threshold: threshold, targetCount: targetCount)
        }
    }

    private static func minMaxBucketedSingleSegment(
        _ points: [TrendPoint],
        threshold: Int,
        targetCount: Int
    ) -> [TrendPoint] {
        let n = points.count
        guard n > threshold, n > 2, targetCount >= 4 else { return points }

        // Reserve the first and last; bucket the interior. Each bucket yields up to 2 vertices (min+max),
        // so aim for ~targetCount/2 buckets to land near the vertex budget.
        let first = points[0]
        let last = points[n - 1]
        let interior = n - 2
        let bucketCount = max(1, (targetCount - 2) / 2)
        guard bucketCount < interior else { return points }

        var out: [TrendPoint] = []
        out.reserveCapacity(targetCount)
        out.append(first)

        var lastEmittedDate = first.date
        for b in 0..<bucketCount {
            // Interior indices [1 ... n-2] split into `bucketCount` contiguous ranges.
            let lo = 1 + (b * interior) / bucketCount
            let hi = 1 + ((b + 1) * interior) / bucketCount // exclusive
            guard lo < hi else { continue }

            // Find the min-value and max-value samples in this bucket.
            var minIdx = lo, maxIdx = lo
            var i = lo + 1
            while i < hi {
                if points[i].value < points[minIdx].value { minIdx = i }
                if points[i].value > points[maxIdx].value { maxIdx = i }
                i += 1
            }

            // Emit the two extremes in chronological order, skipping duplicates (monotone bucket → one
            // point) and any whose date would not advance (keeps `id: Date` unique for ForEach).
            let lowFirst = minIdx <= maxIdx
            let aIdx = lowFirst ? minIdx : maxIdx
            let bIdx = lowFirst ? maxIdx : minIdx
            for idx in [aIdx, bIdx] {
                let p = points[idx]
                if p.date > lastEmittedDate {
                    out.append(p)
                    lastEmittedDate = p.date
                }
            }
        }

        if last.date > lastEmittedDate { out.append(last) }
        return out
    }
}

// MARK: - Gradient → stops bridge

extension Gradient {
    /// Reconstruct ordered stops from a Gradient. SwiftUI does not expose `.stops`
    /// directly on all paths, so we use the public `stops` mirror when present.
    func toStops() -> [Gradient.Stop] {
        // `Gradient.stops` is public on macOS 13+; expose for our sampler.
        self.stops
    }
}

#if DEBUG
private func sampleTrend(days: Int, base: Double, swing: Double) -> [TrendPoint] {
    let cal = Calendar.current
    let today = Date()
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = base + swing * sin(Double(i) / 3.0) + Double((i * 17) % 9) - 4
        return TrendPoint(date: date, value: max(0, v))
    }
}

#Preview("TrendChart — recovery") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Recovery — 30 days").strandOverline()
        Text("Hover the line: crosshair + dot + date/value tooltip.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        TrendChart(points: sampleTrend(days: 30, base: 62, swing: 22))
    }
    .padding(28)
    .frame(width: 720, height: 340)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}

#Preview("TrendChart — HRV") {
    VStack(alignment: .leading, spacing: 12) {
        Text("HRV (ms) — 30 days").strandOverline()
        Text("Hover to read each day's HRV in ms.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        TrendChart(
            points: sampleTrend(days: 30, base: 58, swing: 14),
            gradient: StrandPalette.recoveryGradient,
            valueRange: 20...100,
            showsArea: true,
            valueFormat: { "\(Int($0.rounded())) ms" }
        )
    }
    .padding(28)
    .frame(width: 720, height: 340)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
#endif
