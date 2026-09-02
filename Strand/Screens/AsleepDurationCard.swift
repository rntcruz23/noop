import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Asleep duration trend (#today-hosted-cards)
//
// The Sleep tab's "Asleep duration" card, extracted into a standalone view so it can ALSO be hosted in
// the Today tab. Both the Sleep tab and the Today host render THIS view from the SAME `AsleepDurationData`,
// so the number can never diverge between the two surfaces (the parity contract). The card body is a
// verbatim lift of the former `SleepView.durationTrend`; the data builder is a verbatim lift of
// `SleepView.durationTrendPoints` + `typicalTotalMin`.

/// Pure inputs for the asleep-duration card: trailing-30-night sleep hours + the typical mean minutes.
/// Built identically by the Sleep tab and by a Today host so the two never diverge.
struct AsleepDurationData {
    let points: [TrendPoint]
    let typicalTotalMin: Double?
    let sleepNeedMin: Double

    var plottedAverageHours: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var coverageText: String {
        String(localized: "\(points.count) of 30 nights recorded")
    }

    /// yyyy-MM-dd → Date (en_US_POSIX, UTC) — matches `SleepView.dayParser`.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Fixed trailing 30 calendar days of total sleep in HOURS. Missing nights remain missing; the chart
    /// never widens the window to make sparse coverage look fuller. The displayed average is derived from
    /// these exact plotted points.
    static func build(days: [DailyMetric]) -> AsleepDurationData {
        let dated = days.compactMap { day -> (metric: DailyMetric, date: Date)? in
            guard let date = dayParser.date(from: day.day) else { return nil }
            return (day, date)
        }
        let latest = dated.map(\.date).max()
        let cutoff = latest.flatMap {
            Calendar(identifier: .gregorian).date(byAdding: .day, value: -29, to: $0)
        }
        let points = dated.compactMap { row -> TrendPoint? in
            guard let cutoff, row.date >= cutoff,
                  let mins = row.metric.totalSleepMin, mins > 0 else { return nil }
            return TrendPoint(date: row.date, value: mins / 60.0)
        }
        let plottedMinutes = points.map { $0.value * 60 }
        let typical = plottedMinutes.isEmpty ? nil : plottedMinutes.reduce(0, +) / Double(plottedMinutes.count)
        return AsleepDurationData(points: points, typicalTotalMin: typical,
                                  sleepNeedMin: SleepModel.debtNeedMin(days: days))
    }
}

/// The "Asleep duration" trend card. Renders [AsleepDurationData] with the shared chart components.
struct AsleepDurationCard: View {
    let data: AsleepDurationData

    var body: some View {
        let pts = data.points
        let avg = data.plottedAverageHours
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Asleep duration", overline: "Trend")
            ChartCard(
                title: "Hours asleep",
                subtitle: String(localized: "Trailing 30 calendar days · \(data.coverageText)"),
                trailing: avg.map { String(localized: "\($0.formatted(.number.precision(.fractionLength(1)))) h avg") },
                height: NoopMetrics.chartHeight,
                tint: StrandPalette.restColor,
                chart: {
                    if pts.count >= 2 {
                        TrendChart(points: pts,
                                   gradient: StrandPalette.restGradient,
                                   valueRange: 0...max(Self.trendRange(pts).upperBound, data.sleepNeedMin / 60),
                                   markStyle: .bars,
                                   height: NoopMetrics.chartHeight,
                                   valueFormat: { String(format: "%.1f h", $0) },
                                   accessibilityLabel: String(localized: "Hours asleep trend"),
                                   referenceValue: data.sleepNeedMin / 60,
                                   referenceColor: StrandPalette.restColor)
                    } else {
                        Self.sparsePlaceholder
                    }
                },
                footer: {
                    HStack {
                        ChartFooter([
                            ("Need",   String(format: "%.1f h", data.sleepNeedMin / 60)),
                            ("Min",    pts.map(\.value).min().map { String(format: "%.1f h", $0) } ?? "—"),
                            ("Max",    pts.map(\.value).max().map { String(format: "%.1f h", $0) } ?? "—"),
                            ("Nights", "\(pts.count)"),
                        ])
                        durationTrendStat(pts)
                    }
                }
            )
        }
    }

    /// A padded value range so the line isn't flat against the axis (verbatim of `SleepView.trendRange`).
    private static func trendRange(_ pts: [TrendPoint]) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        let lo = Swift.max(0, (vals.min() ?? 0) - 1)
        let hi = (vals.max() ?? 9) + 1
        return lo...Swift.max(hi, lo + 1)
    }

    private static var sparsePlaceholder: some View {
        Text("Not enough nights yet.")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(NoopPanelSurface(tint: StrandPalette.restColor, cornerRadius: 12))
    }

    /// Recent-half mean minus earlier-half mean (verbatim of `SleepView.durationTrendChange`). Direction
    /// is neutral: more sleep isn't automatically better, so the chip conveys movement without a verdict.
    private static func durationTrendChange(_ points: [TrendPoint]) -> Double? {
        guard points.count >= 4 else { return nil }
        let midpoint = points.count / 2
        let earlier = points.prefix(midpoint).map(\.value)
        let recent = points.suffix(points.count - midpoint).map(\.value)
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
            - earlier.reduce(0, +) / Double(earlier.count)
    }

    @ViewBuilder
    private func durationTrendStat(_ points: [TrendPoint]) -> some View {
        let delta = Self.durationTrendChange(points)
        let deltaText = delta.map {
            let sign = $0 >= 0 ? "+" : "−"
            return "\(sign)\(String(format: "%.1f h", abs($0)))"
        }
        VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
            Text("Trend")
                .textCase(.uppercase)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
            if let deltaText {
                TrendChip(text: deltaText, color: StrandPalette.textTertiary)
            } else {
                Text("—")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Trend")): \(deltaText ?? "—")"))
    }
}
