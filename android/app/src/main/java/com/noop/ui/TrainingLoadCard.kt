package com.noop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import com.noop.R
import com.noop.analytics.TrainingLoadEngine
import com.noop.data.DailyMetric
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.max

/**
 * Training Load card (CTL / ATL / TSB) — the first UI surface for [TrainingLoadEngine], twin of the
 * Apple `TrainingLoadCard`. Overlays chronic load (CTL, 42-day fitness proxy) and acute load (ATL,
 * 7-day fatigue proxy) on ONE shared y-scale, so the vertical gap between the lines reads as the TSB /
 * "form" (CTL − ATL), surfaced as the headline number + a footer stat.
 *
 * Descriptive only: CTL/ATL/TSB never feed the Charge/Readiness score, and the load is NOOP's daily
 * Effort/strain — not TRIMP. It models full history for warm-up, clips displayed points to the range
 * window, and shows an honest "needs N more days" state until 14+ contiguous days exist.
 */
@Composable
fun TrainingLoadCard(
    days: List<DailyMetric>,
    displayStartDay: String? = null,
    displayEndDay: String? = null,
    modifier: Modifier = Modifier,
) {
    // Model straight from the training-load engine — NOT the paired evaluateWithTrainingLoad, which
    // would also run the full Readiness synthesis this card never uses. DailyMetric.strain is the load.
    val loads = days.map { TrainingLoadEngine.DailyLoad(it.day, it.strain) }
    val result = TrainingLoadEngine.evaluate(loads)
    val displayPoints = result.points.filter { point ->
        (displayStartDay == null || point.day >= displayStartDay) &&
            (displayEndDay == null || point.day <= displayEndDay)
    }
    val latest = displayPoints.lastOrNull()

    val subtitle = when (result.state) {
        TrainingLoadEngine.State.ESTABLISHED -> stringResource(R.string.trends_tl_established)
        TrainingLoadEngine.State.BUILDING ->
            stringResource(R.string.trends_tl_building, result.contiguousDays, TrainingLoadEngine.standard.establishedDays)
        TrainingLoadEngine.State.UNAVAILABLE -> stringResource(R.string.trends_tl_unavailable)
    }

    NoopCard(modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(Metrics.space12)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Overline(text = stringResource(R.string.trends_training_load))
                    Text(subtitle, style = NoopType.footnote, color = Palette.textTertiary)
                }
                if (latest != null) {
                    Text(signed(latest.balance), style = NoopType.bodyNumber, color = Palette.textPrimary)
                }
            }

            if (!result.isAvailable) {
                Text(
                    stringResource(
                        R.string.trends_tl_needs,
                        TrainingLoadEngine.standard.minimumDays,
                        result.contiguousDays,
                    ),
                    style = NoopType.body,
                    color = Palette.textTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(vertical = Metrics.space12),
                )
            } else if (displayPoints.isEmpty()) {
                Text(
                    stringResource(R.string.trends_not_enough_data),
                    style = NoopType.body,
                    color = Palette.textTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(vertical = Metrics.space12),
                )
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(Metrics.space12)) {
                    LegendDot(Palette.gold, stringResource(R.string.trends_tl_legend_ctl))
                    LegendDot(Palette.metricAmber, stringResource(R.string.trends_tl_legend_atl))
                }
                TwoLineChart(
                    displayPoints,
                    displayStartDay,
                    displayEndDay,
                    Modifier.fillMaxWidth().height(Metrics.chartHeight),
                )
                Row(Modifier.fillMaxWidth()) {
                    // CTL/ATL are universal training-science acronyms (like HRV/SpO2) — same in every language.
                    Stat("CTL", latest?.let { fmt(it.chronicLoad) } ?: "—")
                    Stat("ATL", latest?.let { fmt(it.acuteLoad) } ?: "—")
                    Stat(stringResource(R.string.trends_tl_form), latest?.let { signed(it.balance) } ?: "—")
                    Stat(stringResource(R.string.trends_days), "${result.contiguousDays}")
                }
            }
        }
    }
}

@Composable
private fun TwoLineChart(
    points: List<TrainingLoadEngine.Point>,
    displayStartDay: String?,
    displayEndDay: String?,
    modifier: Modifier,
) {
    val ctl = Palette.gold
    val atl = Palette.metricAmber
    // Shared y-scale over BOTH series so the gap between the lines is a faithful TSB.
    val maxY = points.fold(1.0) { acc, p -> max(acc, max(p.chronicLoad, p.acuteLoad)) }
    Canvas(modifier) {
        val n = points.size
        if (n == 0) return@Canvas
        val w = size.width
        val h = size.height
        val start = displayStartDay?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        val end = displayEndDay?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        val span = if (start != null && end != null) ChronoUnit.DAYS.between(start, end).coerceAtLeast(1) else null
        fun x(index: Int, point: TrainingLoadEngine.Point): Float {
            if (start != null && span != null) {
                val day = runCatching { LocalDate.parse(point.day) }.getOrNull()
                if (day != null) return (ChronoUnit.DAYS.between(start, day).toFloat() / span).coerceIn(0f, 1f) * w
            }
            return if (n == 1) w / 2f else w * index / (n - 1)
        }
        fun path(value: (TrainingLoadEngine.Point) -> Double): Path {
            val p = Path()
            points.forEachIndexed { i, pt ->
                val x = x(i, pt)
                val y = h - (value(pt) / maxY).toFloat() * h
                if (i == 0) p.moveTo(x, y) else p.lineTo(x, y)
            }
            return p
        }
        if (n == 1) {
            val point = points.first()
            val pointX = x(0, point)
            drawCircle(ctl, radius = 4f, center = Offset(pointX, h - (point.chronicLoad / maxY).toFloat() * h))
            drawCircle(atl, radius = 4f, center = Offset(pointX, h - (point.acuteLoad / maxY).toFloat() * h))
        } else {
            drawPath(path { it.chronicLoad }, color = ctl, style = Stroke(width = 3f))
            drawPath(path { it.acuteLoad }, color = atl, style = Stroke(width = 3f))
        }
    }
}

@Composable
private fun LegendDot(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Metrics.space4)) {
        Spacer(Modifier.size(8.dp).clip(CircleShape).background(color))
        Text(label, style = NoopType.footnote, color = Palette.textTertiary)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.Stat(label: String, value: String) {
    Column(Modifier.weight(1f)) {
        Text(label, style = NoopType.footnote, color = Palette.textTertiary)
        Text(value, style = NoopType.captionNumber, color = Palette.textSecondary)
    }
}

private fun fmt(v: Double): String = String.format(java.util.Locale.US, "%.1f", v)
private fun signed(v: Double): String = String.format(java.util.Locale.US, "%+.1f", v)
