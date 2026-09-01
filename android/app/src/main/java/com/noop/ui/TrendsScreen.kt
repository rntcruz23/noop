package com.noop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import kotlinx.coroutines.launch
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.Baselines
import com.noop.analytics.MetricCfg
import com.noop.analytics.TrendWindow
import com.noop.analytics.VitalBands
import com.noop.analytics.WeeklyDigestEngine
import com.noop.ble.SourceCoordinator
import com.noop.data.DailyMetric
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.roundToInt

// MARK: - Trends
//
// The longitudinal view, ported from Strand/Screens/TrendsView.swift onto the locked
// Android component system: one global range, one selectable hero, four compact peer rows,
// the weekly narrative, and long-horizon context.
//
// Windows are taken relative to the phone's actual local day. Every selected-range metric honors the
// exact same calendar interval; sparse data remains sparse and is never replaced with older history.
//
// Data: full history is loaded once via repo.days("my-whoop"); until it arrives the
// reactive recentDays flow backs the charts, so the screen is never empty when data exists.
//
// Difference from macOS: the macOS Trends footer carries a YearHeatStrip calendar
// (a bespoke 53-week heat grid) that has no Android foundation equivalent. Rather than
// fake it, the "Recovery history" card renders the real per-day recovery series as a
// bar strip over the same window, with a short note pointing at the macOS calendar view.

// MARK: - Liquid hero tokens (the liquid Trends restyle)
//
// The Charge hero card floats over the day-of-sky, so it carries the liquid translucent near-black fill
// (rgba(13,14,20,.80)) rather than the classic frosted surface — the card does the contrast work so the
// crisp line chart + the count-up vessel accent read clean over the sky. Radius 26 + a white@0.11 hairline
// give it the frosted-glass edge. Mirrors the liquid Today heroCard (LiquidTodayView / TodayScreen).
private val LIQUID_HERO_RADIUS: Dp = 26.dp

internal enum class TrendsMetric(val detailKey: String) {
    CHARGE("recovery"), HRV("hrv"), RHR("rhr"), REST("rest"), EFFORT("strain"),
}

internal fun defaultTrendsMetric(): TrendsMetric = TrendsMetric.CHARGE
internal fun secondaryTrendMetrics(selected: TrendsMetric): List<TrendsMetric> =
    TrendsMetric.entries.filterNot { it == selected }
internal fun selectedOrLatestTrendIndex(selected: Int?, count: Int): Int? = when {
    count <= 0 -> null
    selected != null && selected in 0 until count -> selected
    else -> count - 1
}
internal fun hasAnyTrendData(vararg counts: Int): Boolean = counts.any { it > 0 }

@Composable
fun TrendsScreen(vm: AppViewModel, onOpenMetric: (String) -> Unit = {}) {
    // Reactive cache (oldest → newest) as the immediate backing.
    val reactiveDays by vm.recentDays.collectAsStateWithLifecycle()
    val publishedActiveStrapId by vm.activeStrapIdFlow.collectAsStateWithLifecycle()
    val activeStrapId = publishedActiveStrapId ?: vm.activeStrapId
    var hrvHistory by remember { mutableStateOf<List<Pair<String, Double?>>>(emptyList()) }
    var rhrHistory by remember { mutableStateOf<List<Pair<String, Double?>>>(emptyList()) }
    var activeIsWhoop by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(activeStrapId) {
        activeIsWhoop = null
        hrvHistory = emptyList()
        rhrHistory = emptyList()
        activeIsWhoop = SourceCoordinator.isWhoop(activeStrapId, vm.pairedDevices())
    }

    // Full history loaded once for the long (1Y / ALL) ranges; falls back to the flow
    // until it lands so the screen is populated on first frame when any data exists.
    var fullHistory by remember { mutableStateOf<List<DailyMetric>?>(null) }
    LaunchedEffect(activeStrapId) {
        fullHistory = null
        // Merged: imported WHOOP days win; on-device computed days gap-fill the trends. Reads the registry's
        // ACTIVE strap id so daysMerged resolves the active-id ∪ canonical "my-whoop" union (SPINE / #814) ,
        // a re-added strap's data and the canonical import both surface; a single-WHOOP install is unchanged.
        fullHistory = vm.repo.daysMerged(activeStrapId)
    }
    val days = fullHistory ?: reactiveDays

    // Effort display scale (#268) , routes the Effort small-multiple's numbers + unit. Display-only.
    val trendsCtx = LocalContext.current
    val effortScale = UnitPrefs.effortScale(trendsCtx)

    // Day-cycle sky backdrop (#698). Default ON. When off, Trends drops the liquid sky and the scaffold
    // paints the plain dark surface canvas instead. SharedPreferences isn't reactive, so this is read once
    // into local state (mirrors Today's showDayCycleBackground gate).
    val showDayCycleBackground = remember { NoopPrefs.showDayCycleBackground(trendsCtx) }
    // Sky-behind-cards (#434 family): when on, the sky fills the whole viewport so the transparent
    // cards reveal it the whole way down, exactly like Today and the metric-detail screens.
    val skyBehindCards = remember { NoopPrefs.skyBehindCards(trendsCtx) }

    var range by remember { mutableStateOf(TrendsRange.Quarter) }
    var selectedMetric by remember { mutableStateOf(defaultTrendsMetric()) }

    // #710 , browse previous weeks in the Week-in-review digest. 0 = the week containing today; each step
    // back is one Mon–Sun week earlier, clamped so it never runs past the earliest day we hold. The Trends
    // RANGE control above scopes the long charts; this only moves the weekly digest at the top.
    var weekOffset by remember { mutableStateOf(0) }
    // Re-clamp the offset whenever the loaded history changes (e.g. an import lands more weeks), so a
    // stored offset can never point past the new earliest week. Mirrors the iOS minWeekOffset clamp.
    val minWeekOffset = remember(days) { minWeekOffset(days) }
    LaunchedEffect(minWeekOffset) { weekOffset = weekOffset.coerceIn(minWeekOffset, 0) }

    // Project each metric's window ONCE per composition and reuse below. HOISTED above the lazy scaffold: these
    // are @Composable `remember` hooks, which can't run inside the LazyListScope content lambda. They're
    // cheap memoized projections (no-ops over empty input), so the empty branch below simply ignores them.
    val todayKey = LocalDate.now().toString()
    // HRV/RHR are the Phase-2 reference cards: these project the exact selected calendar window
    // ending today and never widen to make a sparse chart look fuller.
    val hrvEpoch = NoopPrefs.of(trendsCtx).getLong(Baselines.hrvBaselineEpochKey, 0L).toDouble()
    val recoveryEpoch = NoopPrefs.of(trendsCtx).getLong(Baselines.recoveryBaselineEpochKey, 0L).toDouble()
    LaunchedEffect(activeStrapId, activeIsWhoop, days) {
        if (activeIsWhoop != true) {
            hrvHistory = emptyList()
            rhrHistory = emptyList()
        } else {
            hrvHistory = runCatching {
                vm.repo.resolvedSeries("hrv", "my-whoop", "0000-00-00", "9999-99-99",
                    strapDeviceId = activeStrapId).values.map { it.first to it.second }
            }.getOrDefault(emptyList())
            rhrHistory = runCatching {
                vm.repo.resolvedSeries("rhr", "my-whoop", "0000-00-00", "9999-99-99",
                    strapDeviceId = activeStrapId).values.map { it.first to it.second }
            }.getOrDefault(emptyList())
        }
    }
    // Rest = the sleep_performance composite, loaded for the active strap across full history.
    var sleepPerfByDay by remember { mutableStateOf<Map<String, Double>>(emptyMap()) }
    LaunchedEffect(activeStrapId, days) {
        sleepPerfByDay = emptyMap()
        sleepPerfByDay = runCatching {
            vm.repo.resolvedSeries("sleep_performance", "my-whoop", "0000-00-00", "9999-99-99",
                strapDeviceId = activeStrapId)
                .values.associate { it.first to it.second }
        }.getOrDefault(emptyMap())
    }
    val sharedDomainStart = remember(days, hrvHistory, rhrHistory, sleepPerfByDay, range, todayKey) {
        if (range.days != null) null else {
            (days.mapNotNull { day -> if (day.recovery != null || day.strain != null) day.day else null } +
                hrvHistory.map { it.first } + rhrHistory.map { it.first } + sleepPerfByDay.keys)
                .filter { it <= todayKey }
                .minOrNull()
        }
    }
    val hrvTrend = remember(hrvHistory, range, todayKey, hrvEpoch, sharedDomainStart) {
        vitalTrendSummary(
            hrvHistory, todayKey, range.days,
            40.0..120.0, Baselines.hrvCfg, hrvEpoch, sharedDomainStart,
        )
    }
    val rhrTrend = remember(rhrHistory, range, todayKey, recoveryEpoch, sharedDomainStart) {
        vitalTrendSummary(
            rhrHistory, todayKey, range.days,
            40.0..60.0, Baselines.restingHRCfg, recoveryEpoch, sharedDomainStart,
        )
    }
    val recovery = remember(days, range, todayKey, sharedDomainStart) {
        metricTrendSummary(days.map { it.day to it.recovery }, todayKey, range.days, sharedDomainStart)
    }
    val strain = remember(days, range, todayKey, sharedDomainStart) {
        metricTrendSummary(days.map { it.day to it.strain }, todayKey, range.days, sharedDomainStart)
    }
    val rest = remember(range, sleepPerfByDay, todayKey, sharedDomainStart) {
        metricTrendSummary(sleepPerfByDay.map { it.key to it.value }, todayKey, range.days, sharedDomainStart)
    }
    val selectedWindow = when (selectedMetric) {
        TrendsMetric.CHARGE -> recovery.window
        TrendsMetric.HRV -> hrvTrend.window
        TrendsMetric.RHR -> rhrTrend.window
        TrendsMetric.REST -> rest.window
        TrendsMetric.EFFORT -> strain.window
    }
    val canShowAllHistory = range != TrendsRange.All &&
        selectedWindow.observed == 0 && selectedWindow.hasOlderHistory
    val rangeSubtitle = range.days?.let { dayCount ->
        stringResource(R.string.trends_trailing_days, dayCount)
    } ?: stringResource(R.string.trends_all_history)

    LazyScreenScaffold(
        title = stringResource(R.string.nav_trends),
        subtitle = stringResource(R.string.trends_subtitle),
        // LIQUID SKY BACKDROP (the pilot pattern — LiquidScreenSky.kt): the time-of-day liquid sky settles
        // into the theme canvas behind the header + top rows, full-bleed via the scaffold's topBackground
        // plumbing. Static (LiquidSkyStatic, inside the helper) — never an animated sky behind a scrolling
        // list. Gated on the same day-cycle pref as Today; when off, the scaffold paints the flat canvas.
        topBackground = screenBackdropSlot(showDayCycleBackground, skyBehindCards),
        // Sky-behind-cards fills the viewport so the transparent cards reveal the sky the whole way down
        // (Today / metric-detail parity — the same two prefs drive the same two behaviours everywhere).
        fullBleedBackground = screenBackdropFullBleed(showDayCycleBackground, skyBehindCards),
    ) {
        val recoveryCount = days.count { it.recovery != null }
        val effortCount = days.count { it.strain != null }
        if (!hasAnyTrendData(recoveryCount, hrvHistory.size, rhrHistory.size, sleepPerfByDay.size, effortCount)) {
            item { EmptyTrends() }
            return@LazyScreenScaffold
        }

        // The main card list ripples in once on appear (Reduce-Motion safe), mirroring the iOS
        // staggeredAppear sequence , each top-level section is one staggered child.

        // --- Range control ---
        item {
            Column(
                modifier = Modifier.staggeredAppear(index = 0),
                verticalArrangement = Arrangement.spacedBy(Metrics.space8),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SegmentedPillControl(
                        items = TrendsRange.entries.toList(),
                        selection = range,
                        label = { it.label },
                        onSelect = { range = it },
                    )
                    Spacer(Modifier.weight(1f))
                    TrendsRangeCaption(range = range, fullSubtitle = rangeSubtitle)
                }
                if (canShowAllHistory) {
                    NoopButton(
                        text = stringResource(R.string.trends_show_all_history),
                        kind = NoopButtonKind.Secondary,
                        onClick = { range = TrendsRange.All },
                    )
                }
            }
        }

        // The selected metric owns the one hero; its selected/latest reading replaces aggregate stats.
        item {
            SelectableTrendHero(
                metric = selectedMetric,
                recovery = recovery, hrv = hrvTrend, rhr = rhrTrend, rest = rest, effort = strain,
                effortScale = effortScale,
                onOpenDetail = { onOpenMetric(selectedMetric.detailKey) },
                modifier = Modifier.staggeredAppear(index = 1),
            )
        }

        // --- Small multiples , HRV / Resting HR / Effort. HRV/RHR are Charge sub-signals; the card
        // surface is neutral (EXP-004) and each line keeps its metric hue; Effort is the WHOOP blue
        // strain world. ---
        // No trailing window label , the range bar's overline already states it.
        item {
            Column(
                modifier = Modifier.staggeredAppear(index = 2),
                verticalArrangement = Arrangement.spacedBy(Metrics.gap),
            ) {
                SectionHeader(stringResource(R.string.trends_daily_signals), overline = stringResource(R.string.nav_trends))
                secondaryTrendMetrics(selectedMetric).forEach { metric ->
                    CompactTrendRow(
                        metric = metric,
                        recovery = recovery, hrv = hrvTrend, rhr = rhrTrend, rest = rest, effort = strain,
                        effortScale = effortScale,
                        onSelect = { selectedMetric = metric },
                        onOpenDetail = { onOpenMetric(metric.detailKey) },
                    )
                }
            }
        }

        // The weekly narrative follows the metric comparison instead of competing with the hero.
        item {
            Column(modifier = Modifier.staggeredAppear(index = 3)) {
                WeeklyDigestNav(
                    days = days,
                    weekOffset = weekOffset,
                    minWeekOffset = minWeekOffset,
                    onStep = { delta -> weekOffset = (weekOffset + delta).coerceIn(minWeekOffset, 0) },
                )
            }
        }

        // --- Long-horizon training load (CTL/ATL/TSB). Full history warms the model; displayed points
        // remain inside the selected range. Twin of the Apple TrainingLoadCard. ---
        item {
            TrainingLoadCard(
                days = days,
                displayStartDay = recovery.displayStartDay,
                displayEndDay = recovery.window.endDay,
                modifier = Modifier.staggeredAppear(index = 4),
            )
        }

        // --- Recovery history strip (stands in for the macOS YearHeatStrip) ---
        item {
            Column(modifier = Modifier.staggeredAppear(index = 5)) {
                RecoveryHistoryCard(resolved = recovery, allHistory = range == TrendsRange.All)
            }
        }

        // --- Export trends report (#436) , the shareable offline PDF exporter. Mirrors the iOS
        // TrendsView.exportReportRow footer; the same composable Settings hosts, so both surfaces
        // offer it. Routed through NoopButton like every other CTA (no gold). ---
        item {
            Column(modifier = Modifier.staggeredAppear(index = 6)) {
                TrendsReportExportSection(vm)
            }
        }
    }
}

@Composable
private fun trendMetricLabel(metric: TrendsMetric): String = stringResource(when (metric) {
    TrendsMetric.CHARGE -> R.string.trends_charge
    TrendsMetric.HRV -> R.string.trends_hrv_full
    TrendsMetric.RHR -> R.string.trends_resting_hr_full
    TrendsMetric.REST -> R.string.trends_rest
    TrendsMetric.EFFORT -> R.string.trends_effort
})

private fun metricColor(metric: TrendsMetric): Color = when (metric) {
    TrendsMetric.CHARGE -> Palette.chargeColor
    TrendsMetric.HRV -> Palette.metricPurple
    TrendsMetric.RHR -> Palette.metricRose
    TrendsMetric.REST -> Palette.restColor
    TrendsMetric.EFFORT -> Palette.effortColor
}

internal fun chargeColor(value: Double): Color = when (chargeZone(value)) {
    ChargeZone.LOW -> Palette.statusCritical
    ChargeZone.MEDIUM -> Palette.statusWarning
    ChargeZone.HIGH -> Palette.statusPositive
    null -> Palette.textTertiary
}

private fun metricSummary(
    metric: TrendsMetric,
    recovery: MetricTrendSummary,
    rest: MetricTrendSummary,
    effort: MetricTrendSummary,
): MetricTrendSummary = when (metric) {
    TrendsMetric.CHARGE -> recovery
    TrendsMetric.REST -> rest
    TrendsMetric.EFFORT -> effort
    else -> error("Vital metrics have a VitalTrendSummary")
}

@Composable
private fun SelectableTrendHero(
    metric: TrendsMetric,
    recovery: MetricTrendSummary,
    hrv: VitalTrendSummary,
    rhr: VitalTrendSummary,
    rest: MetricTrendSummary,
    effort: MetricTrendSummary,
    effortScale: EffortScale,
    onOpenDetail: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vital = when (metric) {
        TrendsMetric.HRV -> hrv
        TrendsMetric.RHR -> rhr
        else -> null
    }
    val regular = if (vital == null) metricSummary(metric, recovery, rest, effort) else null
    val points = vital?.window?.points ?: regular!!.window.points
    var selectedIndex by remember(metric, points) { mutableStateOf<Int?>(null) }
    val displayIndex = selectedOrLatestTrendIndex(selectedIndex, points.size)
    val displayed = displayIndex?.let(points::get)
    val presentation = displayIndex?.let { vital?.presentations?.getOrNull(it) }
    val label = trendMetricLabel(metric)
    val unit = when (metric) {
        TrendsMetric.HRV -> "ms"
        TrendsMetric.RHR -> "bpm"
        TrendsMetric.EFFORT -> "/ ${UnitFormatter.effortScaleMax(effortScale)}"
        else -> ""
    }
    val format: (Double) -> String = if (metric == TrendsMetric.EFFORT) {
        { UnitFormatter.effortDisplay(it, effortScale) }
    } else {
        { "${it.roundToInt()}" }
    }
    val valueText = displayed?.let { point ->
        val value = format(point.value)
        if (unit.isEmpty()) value else "$value $unit"
    } ?: EM_DASH
    val coverage = if ((vital?.allHistory ?: regular?.allHistory) == true) {
        stringResource(
            if (metric == TrendsMetric.REST) R.string.trends_coverage_all
            else R.string.trends_coverage_all_days,
            points.size,
            vital?.window?.expected ?: regular!!.window.expected,
        )
    } else {
        stringResource(
            if (metric == TrendsMetric.HRV || metric == TrendsMetric.RHR || metric == TrendsMetric.REST)
                R.string.trends_coverage else R.string.trends_coverage_days,
            points.size,
            vital?.window?.expected ?: regular!!.window.expected,
        )
    }
    val context = presentation?.let { p ->
        val state = vitalStateText(p.position)
        val bounds = "${format(p.lowerBound)}–${format(p.upperBound)} $unit"
        stringResource(R.string.today_source_count_joiner, state, stringResource(
            if (p.basis == VitalBands.Basis.PERSONAL) R.string.trends_your_typical_range
            else R.string.trends_general_range,
            bounds,
        ))
    } ?: periodChange(points.map { it.value })?.let { change ->
        val sign = if (change >= 0) "+" else "−"
        stringResource(R.string.trends_trend_a11y, "$sign${format(kotlin.math.abs(change))}")
    }
    val dates = points.map { it.day }
    val values = points.map { it.value }
    val xPositions = vital?.xPositions ?: regular?.xPositions
    val previousReading = stringResource(R.string.trends_previous_reading)
    val nextReading = stringResource(R.string.trends_next_reading)
    val shape = RoundedCornerShape(LIQUID_HERO_RADIUS)
    Box(
        modifier = modifier.fillMaxWidth().clip(shape)
            .background(Palette.heroFill.copy(alpha = Palette.heroFill.alpha * CardAppearance.opacity))
            .border(Metrics.divider, Palette.heroBorder.copy(alpha = Palette.heroBorder.alpha * CardAppearance.opacity), shape)
            .padding(Metrics.cardPadding)
            .semantics(mergeDescendants = true) {
                contentDescription = listOfNotNull(label, valueText, displayed?.day?.let(::prettyAxisDate), context, coverage)
                    .joinToString(", ")
                customActions = listOf(
                    CustomAccessibilityAction(previousReading) {
                        val current = selectedOrLatestTrendIndex(selectedIndex, points.size) ?: return@CustomAccessibilityAction false
                        if (current <= 0) false else {
                            selectedIndex = current - 1
                            true
                        }
                    },
                    CustomAccessibilityAction(nextReading) {
                        val current = selectedOrLatestTrendIndex(selectedIndex, points.size) ?: return@CustomAccessibilityAction false
                        if (current >= points.lastIndex) false else {
                            selectedIndex = current + 1
                            true
                        }
                    },
                )
            },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space12)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Overline(label)
                    Text(displayed?.day?.let(::prettyAxisDate) ?: stringResource(R.string.trends_no_reading),
                        style = NoopType.footnote, color = Palette.textTertiary)
                }
                Text(valueText, style = NoopType.title2, color = Palette.textPrimary)
                IconButton(onClick = onOpenDetail) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = label, tint = Palette.accent)
                }
            }
            if (context != null) Text(context, style = NoopType.footnote, color = Palette.textSecondary)
            Text(coverage, style = NoopType.footnote, color = Palette.textTertiary)
            if (values.isEmpty()) {
                SparsePlaceholder()
            } else {
                if (metric == TrendsMetric.CHARGE || metric == TrendsMetric.EFFORT) {
                    BarChart(
                        values = values,
                        modifier = Modifier.fillMaxWidth().height(Metrics.chartHeight),
                        color = metricColor(metric),
                        selectionEnabled = true,
                        selectionLabels = dates.map(::prettyAxisDate),
                        formatValue = format,
                        xPositions = xPositions,
                        fixedMaximum = 100.0,
                        pointColor = if (metric == TrendsMetric.CHARGE) ::chargeColor else null,
                        showFloatingLabel = false,
                        onSelectionChange = { selectedIndex = it },
                    )
                } else {
                    LineChart(
                        values = values,
                        modifier = Modifier.fillMaxWidth().height(Metrics.chartHeight),
                        color = metricColor(metric),
                        fill = true,
                        selectionEnabled = true,
                        selectionLabels = dates.map(::prettyAxisDate),
                        formatValue = format,
                        xPositions = xPositions,
                        dayKeys = dates,
                        gapPolicyDaily = true,
                        rangeBand = presentation?.let { it.lowerBound..it.upperBound },
                        mode = LineChartMode.SUMMARY,
                        onSelectionChange = { selectedIndex = it },
                    )
                }
                val axisLabels = vitalAxisLabels(
                    vital?.window?.startDay ?: regular?.displayStartDay,
                    vital?.window?.endDay ?: regular!!.window.endDay,
                )
                if (axisLabels.isNotEmpty()) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        axisLabels.forEach { axis ->
                            Text(
                                prettyAxisDate(axis.day), style = NoopType.footnote,
                                color = Palette.textTertiary, modifier = Modifier.weight(1f),
                                textAlign = when (axis.anchor) {
                                    TrendAxisAnchor.START -> TextAlign.Start
                                    TrendAxisAnchor.CENTER -> TextAlign.Center
                                    TrendAxisAnchor.END -> TextAlign.End
                                }, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CompactTrendRow(
    metric: TrendsMetric,
    recovery: MetricTrendSummary,
    hrv: VitalTrendSummary,
    rhr: VitalTrendSummary,
    rest: MetricTrendSummary,
    effort: MetricTrendSummary,
    effortScale: EffortScale,
    onSelect: () -> Unit,
    onOpenDetail: () -> Unit,
) {
    val vital = when (metric) {
        TrendsMetric.HRV -> hrv
        TrendsMetric.RHR -> rhr
        else -> null
    }
    val regular = if (vital == null) metricSummary(metric, recovery, rest, effort) else null
    val points = vital?.window?.points ?: regular!!.window.points
    val latest = points.lastOrNull()
    val presentation = vital?.presentations?.lastOrNull()
    val label = trendMetricLabel(metric)
    val unit = when (metric) {
        TrendsMetric.HRV -> " ms"
        TrendsMetric.RHR -> " bpm"
        TrendsMetric.EFFORT -> " / ${UnitFormatter.effortScaleMax(effortScale)}"
        else -> ""
    }
    val format: (Double) -> String = if (metric == TrendsMetric.EFFORT) {
        { UnitFormatter.effortDisplay(it, effortScale) }
    } else { { "${it.roundToInt()}" } }
    val valueText = latest?.let { format(it.value) + unit } ?: EM_DASH
    val comparison = presentation?.let {
        val state = vitalStateText(it.position)
        val bounds = "${format(it.lowerBound)}–${format(it.upperBound)}${unit}"
        stringResource(R.string.today_source_count_joiner, state, stringResource(
            if (it.basis == VitalBands.Basis.PERSONAL) R.string.trends_your_typical_range
            else R.string.trends_general_range,
            bounds,
        ))
    }
        ?: periodChange(points.map { it.value })?.let { change ->
            val sign = if (change >= 0) "+" else "−"
            stringResource(R.string.trends_trend_a11y, "$sign${format(kotlin.math.abs(change))}")
        }
        ?: stringResource(R.string.trends_not_enough_comparison)
    val expected = vital?.window?.expected ?: regular!!.window.expected
    val allHistory = vital?.allHistory ?: regular!!.allHistory
    val coverage = stringResource(
        when {
            allHistory && metric == TrendsMetric.REST -> R.string.trends_coverage_all
            allHistory -> R.string.trends_coverage_all_days
            metric == TrendsMetric.REST -> R.string.trends_coverage
            else -> R.string.trends_coverage_days
        },
        points.size, expected,
    )
    val accessibilitySummary = stringResource(
        R.string.trends_chart_accessibility,
        label,
        valueText,
        latest?.day?.let(::prettyAxisDate) ?: stringResource(R.string.trends_no_reading),
        comparison,
        coverage,
    )
    NoopCard(padding = Metrics.cardPadding) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                modifier = Modifier.weight(1f)
                    .clickable(role = Role.Button, onClickLabel = label, onClick = onSelect)
                    .clearAndSetSemantics {
                        contentDescription = accessibilitySummary
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Overline(label)
                    Text(valueText, style = NoopType.bodyNumber, color = Palette.textPrimary)
                    Text(comparison, style = NoopType.footnote, color = Palette.textSecondary)
                    Text(coverage, style = NoopType.footnote, color = Palette.textTertiary)
                }
                if (points.isEmpty()) {
                    Box(Modifier.size(Metrics.trendStripHeight, Metrics.sparklineHeight)) {
                        SparsePlaceholder(height = Metrics.sparklineHeight)
                    }
                } else {
                    if (metric == TrendsMetric.CHARGE || metric == TrendsMetric.EFFORT) {
                        BarChart(
                            values = points.map { it.value },
                            modifier = Modifier.size(Metrics.trendStripHeight, Metrics.sparklineHeight),
                            color = metricColor(metric),
                            formatValue = format,
                            xPositions = vital?.xPositions ?: regular?.xPositions,
                            fixedMaximum = 100.0,
                            pointColor = if (metric == TrendsMetric.CHARGE) ::chargeColor else null,
                            showFloatingLabel = false,
                        )
                    } else {
                        LineChart(
                            values = points.map { it.value },
                            modifier = Modifier.size(Metrics.trendStripHeight, Metrics.sparklineHeight),
                            color = metricColor(metric),
                            selectionEnabled = false,
                            formatValue = format,
                            xPositions = vital?.xPositions ?: regular?.xPositions,
                            dayKeys = points.map { it.day },
                            gapPolicyDaily = true,
                            rangeBand = presentation?.let { it.lowerBound..it.upperBound },
                            mode = LineChartMode.SUMMARY,
                        )
                    }
                }
            }
            IconButton(onClick = onOpenDetail) {
                Icon(Icons.Filled.ChevronRight, contentDescription = label, tint = Palette.accent)
            }
        }
    }
}

// MARK: - Week-in-review digest with prev/next week browsing (#710)

/**
 * The most-negative weekOffset allowed: the number of whole Mon–Sun weeks between the earliest day we
 * hold and this week. Beyond it there's no data to digest, so the back chevron disables. 0 when history
 * is empty or unparseable (so we stay on this week). `days` is oldest → newest. Mirrors iOS minWeekOffset.
 */
private fun minWeekOffset(days: List<DailyMetric>): Int {
    val earliest = days.firstOrNull()?.day ?: return 0
    val earliestMon = WeeklyDigestEngine.mondayOfWeek(earliest) ?: return 0
    val thisMon = WeeklyDigestEngine.mondayOfWeek(logicalDayKeyNow()) ?: return 0
    var off = 0
    var mon = thisMon
    // Walk weeks back until we pass the earliest week. Hard cap ~10 years so a bad date can't spin.
    while (mon > earliestMon && off > -520) {
        mon = WeeklyDigestEngine.addDays(mon, -7)
        off -= 1
    }
    return off
}

/**
 * The Week-in-review digest for the selected week, with prev/next chevrons in its header. The digest for
 * the offset week is built straight from the shared [buildWeeklyDigest] (the same builder
 * WeeklyDigestCard uses) so past weeks render in the identical format. The whole block self-hides only
 * when the WHOLE history is empty; an empty PAST week still shows the chevrons so the user can step on.
 * Mirrors iOS TrendsView.weeklyDigestNav.
 */
@Composable
private fun WeeklyDigestNav(
    days: List<DailyMetric>,
    weekOffset: Int,
    minWeekOffset: Int,
    onStep: (Int) -> Unit,
) {
    if (days.isEmpty()) return
    // Anchor day for this offset = today shifted back by weekOffset whole weeks; the engine snaps it to
    // that week's Monday. Memoised so the (cheap but non-trivial) digest rebuild only runs on a real change.
    val anchorDay = remember(weekOffset) {
        WeeklyDigestEngine.addDays(logicalDayKeyNow(), weekOffset * 7)
    }
    // #268/#463: past weeks quote Effort on the user's display scale too, same as the live card.
    val context = LocalContext.current
    val factor = effortDisplayFactor(UnitPrefs.effortScale(context))
    val digest = remember(days, anchorDay, factor) {
        buildWeeklyDigest(days, anchorDay, effortDisplayFactor = factor)
    }
    // "Share recap" capture: track the card's on-screen bounds, then draw the Compose host view + crop
    // (RecapShare.captureCropped) — the Compose-1.7 GraphicsLayer capture API isn't in this 1.6.8 build.
    val scope = rememberCoroutineScope()
    val hostView = LocalView.current
    var cardBounds by remember { mutableStateOf<Rect?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        WeekNavBar(weekOffset = weekOffset, minWeekOffset = minWeekOffset, onStep = onStep)
        if (digest.isEmpty) {
            DataPendingNote(
                title = stringResource(R.string.trends_no_readings_this_week),
                body = stringResource(R.string.trends_no_readings_body),
            )
        } else {
            Box(modifier = Modifier.onGloballyPositioned { cardBounds = it.boundsInRoot() }) {
                NoopCard { WeeklyDigestContent(digest = digest, compact = true) }
            }
            NoopButton(
                text = "Share recap",
                leadingIcon = Icons.Filled.IosShare,
                kind = NoopButtonKind.Secondary,
                onClick = {
                    val bounds = cardBounds
                    val bmp = bounds?.let { RecapShare.captureCropped(hostView, it) }
                    if (bmp != null) scope.launch { RecapShare.share(context, bmp, anchorDay) }
                },
            )
        }
    }
}

/**
 * Prev/next week stepper. Back is clamped at the earliest week we hold; forward at this week (no future
 * weeks). Flat accent chevrons, mirroring the iOS FullDayChart day stepper (#597).
 */
@Composable
private fun WeekNavBar(weekOffset: Int, minWeekOffset: Int, onStep: (Int) -> Unit) {
    val atOldest = weekOffset <= minWeekOffset
    val atNewest = weekOffset >= 0
    val label = when {
        weekOffset == 0 -> stringResource(R.string.trends_this_week)
        weekOffset == -1 -> stringResource(R.string.trends_last_week)
        else -> pluralStringResource(R.plurals.trends_weeks_ago, -weekOffset, -weekOffset)
    }
    // liquidPress on the two week-step chevrons (the screen's tappable controls): each settles inward on
    // press, wired to the SAME interactionSource the IconButton uses for its own ripple, matching the pilot.
    val prevInteraction = remember { MutableInteractionSource() }
    val nextInteraction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = Metrics.space4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(
            onClick = { onStep(-1) },
            enabled = !atOldest,
            interactionSource = prevInteraction,
            modifier = Modifier.liquidPress(prevInteraction),
        ) {
            Icon(
                Icons.Filled.ChevronLeft,
                contentDescription = stringResource(R.string.trends_previous_week),
                tint = if (atOldest) Palette.textTertiary else Palette.accent,
            )
        }
        Spacer(Modifier.weight(1f))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(label, style = NoopType.headline, color = Palette.textPrimary)
            Overline(stringResource(R.string.trends_week_in_review), color = Palette.textSecondary)
        }
        Spacer(Modifier.weight(1f))
        IconButton(
            onClick = { onStep(1) },
            enabled = !atNewest,
            interactionSource = nextInteraction,
            modifier = Modifier.liquidPress(nextInteraction),
        ) {
            Icon(
                Icons.Filled.ChevronRight,
                contentDescription = stringResource(R.string.trends_next_week),
                tint = if (atNewest) Palette.textTertiary else Palette.accent,
            )
        }
    }
}

// MARK: - Range control model (ported from TrendsView.Range)

/** W(7) / M(30) / 3M(90) / 6M(180) / 1Y(365) / ALL. */
private enum class TrendsRange(val days: Int?, val label: String) {
    Week(7, "W"),
    Month(30, "M"),
    Quarter(90, "3M"),
    Half(180, "6M"),
    Year(365, "1Y"),
    All(null, "ALL");

}

@Composable
private fun TrendsRangeCaption(range: TrendsRange, fullSubtitle: String) {
    val days = range.days
    if (days == null) {
        Overline(fullSubtitle, color = Palette.textTertiary)
    } else {
        // Keep both lines leading-aligned while the row's weighted spacer pins this
        // intrinsic-width column to the shared trailing content edge.
        Column(
            modifier = Modifier.clearAndSetSemantics {
                contentDescription = fullSubtitle
            },
            horizontalAlignment = Alignment.Start,
        ) {
            Overline(stringResource(R.string.trends_trailing), color = Palette.textTertiary)
            Overline(
                pluralStringResource(R.plurals.trends_n_days, days, days),
                color = Palette.textTertiary,
            )
        }
    }
}

// MARK: - Exact selected-window metric projection

internal data class MetricTrendSummary(
    val window: TrendWindow.Result,
    val xPositions: List<Float>?,
    val displayStartDay: String? = window.startDay,
    val allHistory: Boolean = false,
) {
    val values: List<Double> get() = window.points.map { it.value }
    val dates: List<String> get() = window.points.map { it.day }
}

internal fun metricTrendSummary(
    rows: List<Pair<String, Double?>>,
    todayKey: String,
    dayCount: Int?,
    domainStart: String? = null,
): MetricTrendSummary {
    val window = TrendWindow.project(rows, todayKey, dayCount)
    val positions = (domainStart ?: window.startDay)?.let { start ->
        normalizedCalendarXPositions(window.points.map { it.day }, start, window.endDay)
    }
    return MetricTrendSummary(window, positions, domainStart ?: window.startDay, dayCount == null)
}

// MARK: - ChartCard , the uniform fixed-height trend card
//
// A NoopCard holding a header (overline-styled title + caption + trailing read-out), a
// fixed-height LineChart, and a divided footer of labelled stats. Mirrors the macOS
// ChartCard used across Trends so every card is Metrics.chartHeight-class and identical.

@Composable
private fun ChartCard(
    title: String,
    subtitle: String?,
    trailing: String?,
    color: Color,
    values: List<Double>,
    footer: List<Pair<String, String>>,
    modifier: Modifier = Modifier,
    dates: List<String> = emptyList(),
    formatY: (Double) -> String = { "${it.roundToInt()}" },
    // Bevel: a domain card wash, a bright end-cap "now" colour, and an optional window-change TrendChip.
    tint: Color? = null,
    tipColor: Color = color,
    change: Double? = null,
    higherIsBetter: Boolean? = null,
    changeFmt: (Double) -> String = { "${it.roundToInt()}" },
    // Fraction of the plot height left empty above the peak , the Android stand-in for the iOS
    // hero's `valueRange: 0...106` padded ceiling, so the peak + now-cap halo clear the top
    // gridline. 0 keeps the curve filling the full height (the small multiples). (#458/parity)
    chartHeadroom: Float = 0f,
    // LIQUID: the hero card only. When true the card carries the liquid translucent-black frosted wrapper
    // (rgba(13,14,20,.80), radius 26, white@0.11 hairline) instead of the classic NoopCard surface, and the
    // trailing readout becomes a small count-up Charge vessel filled to [headlineValue] (0..100). Every
    // small-multiple card leaves this false → identical classic NoopCard + plain text readout as before.
    liquidHero: Boolean = false,
    headlineValue: Double? = null,
    xPositions: List<Float>? = null,
    windowStart: String? = null,
    windowEnd: String? = null,
) {
    // The card body — one composable reused by both the classic and the liquid-hero container so the
    // header / chart / footer layout is byte-identical between them; only the surface + the header readout
    // treatment differ.
    val body: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // Header.
            Row(verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Overline(title)
                    if (subtitle != null) {
                        Text(subtitle, style = NoopType.footnote, color = Palette.textTertiary)
                    }
                }
                if (liquidHero && headlineValue != null) {
                    // The one liquid accent on this screen: a small Charge vessel filled to the window
                    // average, the value counting up over it (white, tabular, soft shadow, hit-transparent).
                    // Same value + charge tint as the plain readout it replaces — the chart stays crisp.
                    HeadlineVessel(value = headlineValue, tint = Palette.recoveryColor(headlineValue))
                } else if (trailing != null) {
                    // Neutral 15pt readout (matches iOS TrendsView) , not the 22sp tinted figure.
                    Text(trailing, style = NoopType.bodyNumber, color = Palette.textPrimary)
                }
            }

            // Chart (fixed height) or sparse placeholder. The chart is flanked by a max/avg/min
            // Y-axis column on the left and a first/mid/last date X-axis row underneath, so the
            // line reads against real numbers and dates instead of a bare unlabelled curve.
            if (values.isNotEmpty()) {
                ChartWithAxes(
                    values = values,
                    dates = dates,
                    color = color,
                    tipColor = tipColor,
                    formatY = formatY,
                    headroom = chartHeadroom,
                    xPositions = xPositions,
                    windowStart = windowStart,
                    windowEnd = windowEnd,
                )
            } else {
                SparsePlaceholder()
            }

            // Footer stats + a window-change chip aligned to the trailing edge.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(modifier = Modifier.weight(1f)) { ChartFooter(footer) }
                ChangeChip(change, higherIsBetter, changeFmt)
            }
        }
    }

    if (liquidHero) {
        // The liquid hero surface: a translucent near-black that floats over the day-of-sky so the crisp
        // chart + the vessel accent read clean — the card does the contrast work, not a muted sky. Radius 26
        // + a faint white hairline give the frosted-glass edge of the iOS liquid heroCard. Mirrors Today.
        Box(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(LIQUID_HERO_RADIUS))
                .background(Palette.heroFill.copy(alpha = Palette.heroFill.alpha * CardAppearance.opacity))
                .border(1.dp, Palette.heroBorder.copy(alpha = Palette.heroBorder.alpha * CardAppearance.opacity), RoundedCornerShape(LIQUID_HERO_RADIUS))
                .padding(Metrics.cardPadding),
        ) {
            body()
        }
    } else {
        NoopCard(modifier = modifier, padding = Metrics.cardPadding, tint = tint) { body() }
    }
}

/**
 * The screen's single liquid accent: a small [LiquidVessel] filled to [value] (0..100 → 0..1) in the
 * charge [tint], the number rolling up over it via [CountUpText] (white, tabular, a soft shadow so it reads
 * on the vessel, hit-transparent so a tap falls through to the vessel's own splash). The Trends echo of the
 * liquid Today `HeroScoreVessel`, sized down to a header readout so it accents the headline value without
 * competing with the crisp chart below.
 */
@Composable
private fun HeadlineVessel(value: Double, tint: Color) {
    val diameter = 44.dp
    Box(modifier = Modifier.size(diameter), contentAlignment = Alignment.Center) {
        LiquidVessel(
            value = (value / 100.0).coerceIn(0.0, 1.0),
            tint = tint,
            animated = true,
            modifier = Modifier.size(diameter),
        )
        CountUpText(
            value = value,
            format = { "${it.roundToInt()}" },
            style = NoopType.number(17f, weight = FontWeight.Bold)
                .copy(shadow = Shadow(color = Color.Black.copy(alpha = 0.5f), offset = Offset(0f, 1f), blurRadius = 6f)),
            color = Color.White,
            modifier = Modifier.clearAndSetSemantics {},
        )
    }
}

/** A TrendChip for a window's period change , green/rose by whether the move is good for THIS metric. */
@Composable
private fun ChangeChip(change: Double?, higherIsBetter: Boolean?, fmt: (Double) -> String) {
    if (change == null || kotlin.math.abs(change) <= 0.0001) return
    val sign = if (change >= 0) "+" else "−"
    val deltaText = uiString(R.string.l10n_trends_screen_sign_fmt_kotlin_math_abs_change_9ad2f71e, sign, fmt(kotlin.math.abs(change)))
    val color = when (higherIsBetter) {
        null -> Palette.textTertiary
        else -> if ((change > 0) == higherIsBetter) Palette.statusPositive else Palette.metricRose
    }
    // Parity with iOS #967 (fix(trends): label change indicators): a "Trend" overline above the delta chip
    // so it reads as a labeled statistic beside the ChartFooter columns instead of an unlabeled pill at the
    // card edge. Mirrors the sibling TrendsRangeCaption's leading-aligned Overline stack + merged a11y
    // announcement ("Trend: +5") so TalkBack reads it as one statistic, not two.
    val trendLabel = stringResource(R.string.trends_trend)
    // A11y announces the label + delta as ONE statistic ("Trend: +5"), in natural case (not the visible
    // all-caps, which readers may spell out). Routed through a format resource so the label + locale-correct
    // separator (e.g. French thin space, Chinese full-width colon) are localized — a bare "$label: $delta"
    // template is both un-localizable and flagged by the i18n regression gate.
    val trendA11y = stringResource(R.string.trends_trend_a11y, deltaText)
    Column(
        modifier = Modifier.clearAndSetSemantics { contentDescription = trendA11y },
        horizontalAlignment = Alignment.Start,
    ) {
        Overline(trendLabel, color = Palette.textTertiary)
        TrendChip(text = deltaText, color = color)
    }
}

/**
 * A [LineChart] with a max/avg/min Y-axis label column and a first/mid/last date X-axis row.
 * Shared by the hero + small-multiple trend cards so every chart gets the same axis treatment.
 * Date strings (ISO yyyy-MM-dd) are reformatted to "d MMM"; an unparseable string falls back to
 * its raw value so a non-ISO key never blanks a label.
 */
@Composable
private fun ChartWithAxes(
    values: List<Double>,
    dates: List<String>,
    color: Color,
    formatY: (Double) -> String,
    tipColor: Color = color,
    // See ChartCard.chartHeadroom , fraction of the plot left empty above the peak.
    headroom: Float = 0f,
    xPositions: List<Float>? = null,
    windowStart: String? = null,
    windowEnd: String? = null,
) {
    if (values.isEmpty()) return
    val maxV = values.max()
    val avgV = values.average()
    val minV = values.min()
    // Trend chart style (line vs bar). Read here at the single chart choke point (every trend card routes
    // through ChartWithAxes); SharedPreferences isn't reactive, but returning from Settings recomposes the
    // Trends screen, which re-reads it — the same read-on-recompose the Effort scale toggle relies on.
    val chartStyle = UnitPrefs.trendChartStyle(LocalContext.current)
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Column(
            modifier = Modifier.height(Metrics.chartHeight),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(formatY(maxV), style = NoopType.footnote, color = Palette.textTertiary, maxLines = 1)
            Text(formatY(avgV), style = NoopType.footnote, color = Palette.textTertiary, maxLines = 1)
            Text(formatY(minV), style = NoopType.footnote, color = Palette.textTertiary, maxLines = 1)
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // The shared LineChart with a glowing "now" end-cap drawn on top , the Bevel idiom from
            // Today's OverviewHRChart. The cap reproduces LineChart's own point geometry (same
            // strokePx/topPad/bottomPad) so the dot lands exactly on the line's final sample.
            //
            // headroom leaves the top fraction of the card empty and pins the plotting Box to the
            // bottom , the Android stand-in for the iOS hero's `valueRange: 0...106` (LineChart has
            // no value-domain hook, so we shrink its drawing box instead). Both LineChart and the
            // GlowEndCap fill this same Box, so the cap stays on the line.
            val plotHeight = Metrics.chartHeight * (1f - headroom.coerceIn(0f, 0.5f))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(Metrics.chartHeight),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Box(modifier = Modifier.fillMaxWidth().height(plotHeight)) {
                    if (chartStyle == TrendChartStyle.BAR) {
                        // Bar mode: value-ramp bars from the baseline. No GlowEndCap (the "now" halo is a
                        // line idiom). selectionEnabled is OFF so BarChart mean-bins a dense window (the
                        // multi-year "ALL" span) down to the pixel width — a clean silhouette instead of a
                        // 1000-bar sub-pixel smear. The max/avg/min axis column + footer carry the numbers.
                        BarChart(
                            values = values,
                            modifier = Modifier.fillMaxSize(),
                            color = color,
                            selectionEnabled = false,
                            xPositions = xPositions,
                        )
                    } else {
                        LineChart(
                            values = values,
                            modifier = Modifier.fillMaxSize(),
                            color = color,
                            fill = true,
                            selectionEnabled = true,
                            // #463: the pinpoint label goes through the SAME formatter as the axis column,
                            // so a tapped Effort day can't print the stored 0-100 value beside a 0-21 axis.
                            formatValue = formatY,
                            selectionLabels = dates.map(::prettyAxisDate),
                            xPositions = xPositions,
                            dayKeys = dates,
                            gapPolicyDaily = true,
                            mode = LineChartMode.SUMMARY,
                        )
                        GlowEndCap(values = values, tipColor = tipColor, xPositions = xPositions)
                    }
                }
            }
            val axisLabels = if (windowEnd != null) vitalAxisLabels(windowStart, windowEnd) else trendAxisLabels(dates)
            if (axisLabels.isNotEmpty()) {
                Row(modifier = Modifier.fillMaxWidth()) {
                    axisLabels.forEach { label ->
                        Text(
                            prettyAxisDate(label.day),
                            style = NoopType.footnote,
                            color = Palette.textTertiary,
                            modifier = Modifier.weight(1f),
                            textAlign = when (label.anchor) {
                                TrendAxisAnchor.START -> TextAlign.Start
                                TrendAxisAnchor.CENTER -> TextAlign.Center
                                TrendAxisAnchor.END -> TextAlign.End
                            },
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

internal enum class TrendAxisAnchor { START, CENTER, END }

internal data class TrendAxisLabel(val day: String, val anchor: TrendAxisAnchor)

/** Selects date labels and pins them to the corresponding start, middle, and end of the plot. */
internal fun trendAxisLabels(dates: List<String>): List<TrendAxisLabel> = when {
    dates.size < 2 -> emptyList()
    dates.size == 2 -> listOf(
        TrendAxisLabel(dates.first(), TrendAxisAnchor.START),
        TrendAxisLabel(dates.last(), TrendAxisAnchor.END),
    )
    else -> listOf(
        TrendAxisLabel(dates.first(), TrendAxisAnchor.START),
        TrendAxisLabel(dates[dates.lastIndex / 2], TrendAxisAnchor.CENTER),
        TrendAxisLabel(dates.last(), TrendAxisAnchor.END),
    )
}

/** ISO "yyyy-MM-dd" → "d MMM"; falls back to the raw string (or "" when null) if it doesn't parse. */
private fun prettyAxisDate(day: String?): String =
    day?.let {
        runCatching { LocalDate.parse(it).format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())) }
            .getOrDefault(it)
    }.orEmpty()

internal data class VitalTrendSummary(
    val window: TrendWindow.Result,
    val presentations: List<VitalBands.Presentation>,
    val xPositions: List<Float>?,
    val previousPoints: List<TrendWindow.Point>,
    val allHistory: Boolean,
    val displayStartDay: String? = window.startDay,
)

/** Pure UI projection for the HRV/RHR reference cards. Every point's range is evaluated from
 * calendar-padded history strictly before that point, so selecting an older reading cannot leak future
 * observations into its personal context. */
internal fun vitalTrendSummary(
    rows: List<Pair<String, Double?>>,
    todayKey: String,
    dayCount: Int?,
    populationRange: ClosedFloatingPointRange<Double>,
    cfg: MetricCfg,
    baselineEpoch: Double = 0.0,
    domainStart: String? = null,
): VitalTrendSummary {
    val window = TrendWindow.project(rows, todayKey, dayCount)
    val presentations = window.points.map { point ->
        VitalBands.presentation(point.value, rows, point.day, populationRange, cfg, baselineEpoch)
    }
    val positions = (domainStart ?: window.startDay)?.let { start ->
        normalizedCalendarXPositions(window.points.map { it.day }, start, window.endDay)
    }
    return VitalTrendSummary(
        window, presentations, positions, TrendWindow.previousPoints(rows, todayKey, dayCount), dayCount == null,
        domainStart ?: window.startDay,
    )
}

/** Labels summary charts at the selected calendar boundaries, not merely at observed samples. */
internal fun vitalAxisLabels(startDay: String?, endDay: String): List<TrendAxisLabel> {
    val start = startDay?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: return emptyList()
    val end = runCatching { LocalDate.parse(endDay) }.getOrNull() ?: return emptyList()
    if (end.isBefore(start)) return emptyList()
    if (start == end) return listOf(TrendAxisLabel(start.toString(), TrendAxisAnchor.CENTER))
    val span = ChronoUnit.DAYS.between(start, end)
    if (span == 1L) return listOf(
        TrendAxisLabel(start.toString(), TrendAxisAnchor.START),
        TrendAxisLabel(end.toString(), TrendAxisAnchor.END),
    )
    return listOf(
        TrendAxisLabel(start.toString(), TrendAxisAnchor.START),
        TrendAxisLabel(start.plusDays(span / 2).toString(), TrendAxisAnchor.CENTER),
        TrendAxisLabel(end.toString(), TrendAxisAnchor.END),
    )
}

/** HRV/RHR summary grammar: latest (or selected) reading first, explicit range context, compact
 * observed/expected coverage, a calendar-spaced gap-safe summary line, and no stats footer. */
@Composable
private fun VitalTrendCard(
    title: String,
    unit: String,
    color: Color,
    summary: VitalTrendSummary,
    fmt: (Double) -> String,
) {
    var selectedIndex by remember(summary.window.points) { mutableStateOf<Int?>(null) }
    val points = summary.window.points
    val displayIndex = selectedIndex?.takeIf { it in points.indices } ?: points.lastIndex
    val displayed = points.getOrNull(displayIndex)
    val presentation = summary.presentations.getOrNull(displayIndex)
    val values = points.map { it.value }
    val dates = points.map { it.day }
    val displayedDate = displayed?.day?.let(::prettyAxisDate)
    val state = presentation?.let { vitalStateText(it.position) }
    val coverage = if (summary.allHistory) {
        stringResource(R.string.trends_coverage_all, summary.window.observed, summary.window.expected)
    } else {
        stringResource(R.string.trends_coverage, summary.window.observed, summary.window.expected)
    }
    NoopCard(padding = Metrics.cardPadding) {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space10)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(modifier = Modifier.weight(1f)) {
                    Overline(title)
                    Text(
                        displayedDate ?: stringResource(R.string.trends_no_reading),
                        style = NoopType.footnote,
                        color = Palette.textTertiary,
                    )
                }
                Text(
                    displayed?.let { stringResource(R.string.trends_value_with_unit, fmt(it.value), unit) } ?: EM_DASH,
                    style = NoopType.bodyNumber,
                    color = Palette.textPrimary,
                )
            }
            if (presentation != null) {
                val bounds = "${fmt(presentation.lowerBound)}–${fmt(presentation.upperBound)} $unit"
                Text(
                    stringResource(R.string.today_source_count_joiner, state ?: "", stringResource(
                        if (presentation.basis == VitalBands.Basis.PERSONAL) R.string.trends_your_typical_range
                        else R.string.trends_general_range,
                        bounds,
                    )),
                    style = NoopType.footnote,
                    color = Palette.textSecondary,
                )
            }
            Text(
                coverage,
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )
            if (values.isNotEmpty()) {
                LineChart(
                    values = values,
                    modifier = Modifier.fillMaxWidth().height(Metrics.chartHeight),
                    color = color,
                    selectionEnabled = true,
                    selectionLabels = dates.map(::prettyAxisDate),
                    formatValue = fmt,
                    xPositions = summary.xPositions,
                    dayKeys = dates,
                    gapPolicyDaily = true,
                    rangeBand = presentation?.let { it.lowerBound..it.upperBound },
                    mode = LineChartMode.SUMMARY,
                    accessibilitySummary = stringResource(
                        R.string.trends_chart_accessibility,
                        title,
                        displayed?.let { stringResource(R.string.trends_value_with_unit, fmt(it.value), unit) }
                            ?: stringResource(R.string.trends_no_reading),
                        displayedDate ?: stringResource(R.string.trends_no_reading),
                        state ?: stringResource(R.string.trends_no_reading),
                        coverage,
                    ),
                    onSelectionChange = { selectedIndex = it },
                )
                val axisLabels = vitalAxisLabels(summary.displayStartDay, summary.window.endDay)
                if (axisLabels.isNotEmpty()) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        axisLabels.forEach { label ->
                            Text(
                                prettyAxisDate(label.day),
                                style = NoopType.footnote,
                                color = Palette.textTertiary,
                                modifier = Modifier.weight(1f),
                                textAlign = when (label.anchor) {
                                    TrendAxisAnchor.START -> TextAlign.Start
                                    TrendAxisAnchor.CENTER -> TextAlign.Center
                                    TrendAxisAnchor.END -> TextAlign.End
                                },
                                maxLines = 1,
                            )
                        }
                    }
                }
            } else {
                SparsePlaceholder()
            }
        }
    }
}

@Composable
internal fun vitalStateText(position: VitalBands.Position): String = stringResource(when (position) {
    VitalBands.Position.BELOW -> R.string.trends_state_below
    VitalBands.Position.WITHIN -> R.string.trends_state_within
    VitalBands.Position.ABOVE -> R.string.trends_state_above
    VitalBands.Position.NO_DATA -> R.string.trends_no_reading
})

/** A labelled metric-trend card built from an exact selected-window projection with mean / min / max. */
@Composable
private fun MetricTrendCard(
    title: String,
    unit: String,
    color: Color,
    resolved: MetricTrendSummary,
    fmt: (Double) -> String,
    tint: Color? = null,
    tipColor: Color = color,
    higherIsBetter: Boolean? = null,
) {
    val avg = resolved.values.averageOrNull()
    ChartCard(
        title = title,
        subtitle = null,
        trailing = avg?.let { fmt(it) },
        color = color,
        tint = tint,
        tipColor = tipColor,
        values = resolved.values,
        dates = resolved.dates,
        formatY = fmt,
        change = periodChange(resolved.values),
        higherIsBetter = higherIsBetter,
        changeFmt = fmt,
        xPositions = resolved.xPositions,
        windowStart = resolved.displayStartDay,
        windowEnd = resolved.window.endDay,
        footer = listOf(
            // Plain "Mean" to match the bare Min/Max columns; the unit moves into the value
            // (e.g. "58 ms") so uppercasing can't render a shouty "MEAN MS".
            stringResource(R.string.trends_mean) to (avg?.let { "${fmt(it)} $unit" } ?: EM_DASH),
            stringResource(R.string.trends_min) to (resolved.values.minOrNull()?.let { fmt(it) } ?: EM_DASH),
            stringResource(R.string.trends_max) to (resolved.values.maxOrNull()?.let { fmt(it) } ?: EM_DASH),
            stringResource(R.string.trends_days) to if (resolved.allHistory) {
                "${stringResource(R.string.trends_all_history)} · " +
                    stringResource(R.string.trends_coverage_days, resolved.window.observed, resolved.window.expected)
            } else {
                "${resolved.window.observed}/${resolved.window.expected}"
            },
        ),
    )
}

/**
 * The window's trend as a signed mean-of-recent-half minus mean-of-earlier-half , drives the card's
 * TrendChip so a glance reads the direction, like Today's deltas. null for a window too short to split.
 */
private fun periodChange(values: List<Double>): Double? {
    if (values.size < 4) return null
    val mid = values.size / 2
    val earlier = values.take(mid)
    val recent = values.drop(mid)
    if (earlier.isEmpty() || recent.isEmpty()) return null
    return recent.average() - earlier.average()
}

/** Evenly-spaced labelled stats under a chart, separated by a hairline rule. */
@Composable
private fun ChartFooter(items: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.space10)) {
        HorizontalDivider(color = Palette.hairline)
        Row(modifier = Modifier.fillMaxWidth()) {
            items.forEach { (label, value) ->
                Column(modifier = Modifier.weight(1f)) {
                    Overline(label, color = Palette.textTertiary)
                    Text(value, style = NoopType.bodyNumber, color = Palette.textPrimary)
                }
            }
        }
    }
}

// MARK: - Recovery history strip (stands in for the macOS YearHeatStrip)

/**
 * The recovery history card. macOS shows a YearHeatStrip (a 53-week calendar heat grid);
 * that bespoke component has no Android foundation equivalent, so we plot the real
 * per-day recovery series over the exact same selected calendar window.
 */
@Composable
private fun RecoveryHistoryCard(resolved: MetricTrendSummary, allHistory: Boolean) {
    val recovery = resolved.values
    val dates = resolved.dates
    val title = if (allHistory) {
        "${stringResource(R.string.trends_charge)} · ${stringResource(R.string.trends_all_history)}"
    } else {
        stringResource(R.string.trends_charge)
    }

    NoopCard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionHeader(
                title,
                overline = stringResource(R.string.trends_calendar),
                trailing = if (allHistory) {
                    "${stringResource(R.string.trends_all_history)} · " +
                        stringResource(R.string.trends_coverage_days, resolved.window.observed, resolved.window.expected)
                } else {
                    stringResource(R.string.trends_coverage_days, resolved.window.observed, resolved.window.expected)
                },
            )
            if (recovery.isNotEmpty()) {
                LineChart(
                    values = recovery,
                    modifier = Modifier.height(Metrics.trendStripHeight),
                    color = Palette.accent,
                    xPositions = resolved.xPositions,
                    dayKeys = dates,
                    gapPolicyDaily = true,
                    mode = LineChartMode.SUMMARY,
                )
            } else {
                SparsePlaceholder(height = Metrics.trendStripHeight)
            }
            HorizontalDivider(color = Palette.hairline)
            Text(
                stringResource(R.string.trends_calendar_footnote),
                style = NoopType.footnote,
                color = Palette.textTertiary,
            )
        }
    }
}

// MARK: - Shared bits

/**
 * A glowing dot pinned to a LineChart's latest sample , the Bevel "now" end-cap (a soft halo + bright
 * core + white centre), matching Today's OverviewHRChart. Drawn as a sibling overlay so the shared
 * LineChart stays untouched; it reproduces that chart's point geometry exactly (strokePx 2.5, top/
 * bottom pad strokePx+4, finite-value min/max) so the cap sits on the curve's final point.
 */
@Composable
private fun GlowEndCap(values: List<Double>, tipColor: Color, xPositions: List<Float>? = null) {
    val clean = remember(values) { values.filter { it.isFinite() } }
    if (clean.size < 2) return
    Canvas(modifier = Modifier.fillMaxSize()) {
        val strokePx = 2.5f
        val topPad = strokePx + 4f
        val bottomPad = strokePx + 4f
        val minV = clean.min()
        val maxV = clean.max()
        val span = (maxV - minV).takeIf { it > 0.0 } ?: 1.0
        val usableH = (size.height - topPad - bottomPad).coerceAtLeast(1f)
        val x = xPositions?.takeIf { it.size == clean.size }?.lastOrNull()?.times(size.width) ?: size.width
        val norm = ((clean.last() - minV) / span).toFloat().coerceIn(0f, 1f)
        val y = topPad + (1f - norm) * usableH
        val center = Offset(x, y)
        drawCircle(color = tipColor.copy(alpha = 0.30f), radius = 9f, center = center)
        drawCircle(color = tipColor.copy(alpha = 0.65f), radius = 5.5f, center = center)
        drawCircle(color = Palette.tipCore, radius = 2.4f, center = center)
    }
}

/** Inset well shown when a window has too few points to plot, mirroring sparsePlaceholder. */
@Composable
private fun SparsePlaceholder(height: Dp = Metrics.chartHeight) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(Metrics.cornerSm))
            .background(Palette.surfaceInset),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            stringResource(R.string.trends_not_enough_data),
            style = NoopType.subhead,
            color = Palette.textTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun EmptyTrends() {
    DataPendingNote(
        title = stringResource(R.string.trends_empty_title),
        body = stringResource(R.string.trends_empty_body),
    )
}

// MARK: - Small numeric helpers

private const val EM_DASH = ","

private fun List<Double>.averageOrNull(): Double? =
    if (isEmpty()) null else sum() / size
