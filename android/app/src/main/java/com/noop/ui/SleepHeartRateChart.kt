package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import com.noop.R
import com.noop.data.HrBucket
import kotlin.math.roundToInt

/** Overnight HR with stage-coloured time bands and matching highlighted sections of the measured line. */
@Composable
internal fun SleepHeartRateChart(
    buckets: List<HrBucket>,
    segments: List<PersistedSegment>,
    onsetTs: Long?,
    wakeTs: Long?,
    selectedStage: String?,
    palette: SleepStagePalette = SleepStagePalette.NOOP,
) {
    if (onsetTs == null || wakeTs == null || wakeTs <= onsetTs) return
    val plot = remember(buckets, onsetTs, wakeTs) { sleepHeartRatePlot(buckets, onsetTs, wakeTs) }
    val highlights = remember(segments, selectedStage, onsetTs, wakeTs) {
        sleepStageHighlights(segments, selectedStage, onsetTs, wakeTs)
    }
    val title = uiString(R.string.sleep_sleeping_heart_rate)
    val range = if (plot.points.isEmpty()) uiString(R.string.today_no_data) else uiString(
        R.string.sleep_heart_rate_range,
        plot.points.minOf { it.bpm }.roundToInt(), plot.points.maxOf { it.bpm }.roundToInt(),
    )
    val highlightColor = selectedStage?.let { stageColorForRamp(it, palette) } ?: Palette.metricRose
    val lineColor = if (selectedStage == null) Palette.metricRose else Palette.textTertiary
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.space6)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(title, style = NoopType.overline, color = Palette.textSecondary)
            Spacer(Modifier.weight(1f))
            Text(range, style = NoopType.captionNumber, color = Palette.textPrimary)
        }
        Box(
            Modifier.fillMaxWidth().height(Metrics.compactChartHeight).clipToBounds()
                .semantics {
                    contentDescription = "$title, $range"
                    stateDescription = selectedStage.orEmpty()
                }
                .drawWithCache {
                    val pad = Metrics.space4.toPx()
                    val stroke = Stroke(Metrics.space2.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
                    val domainSpan = plot.domain.endInclusive - plot.domain.start
                    val positions = plot.points.map {
                        Offset(size.width * it.x,
                            pad + (size.height - pad * 2) * (1.0 - (it.bpm - plot.domain.start) / domainSpan).toFloat())
                    }
                    val runs = plot.points.indices.groupBy { plot.points[it].run }.values
                    val paths = runs.map { indices ->
                        Path().apply {
                            indices.forEachIndexed { index, pointIndex ->
                                val point = positions[pointIndex]
                                if (index == 0) moveTo(point.x, point.y) else lineTo(point.x, point.y)
                            }
                        }
                    }
                    onDrawBehind {
                        listOf(0f, 0.5f, 1f).forEach { fraction ->
                            val y = pad + (size.height - pad * 2) * fraction
                            drawLine(Palette.hairline, Offset(0f, y), Offset(size.width, y), Metrics.divider.toPx())
                        }
                        highlights.forEach { (start, end) ->
                            drawRect(highlightColor.copy(alpha = StrandAlpha.selectedFill),
                                Offset(start * size.width, 0f), Size((end - start) * size.width, size.height))
                        }
                        paths.forEach { drawPath(it, lineColor, style = stroke) }
                        runs.filter { it.size == 1 }.forEach { indices ->
                            drawCircle(lineColor, Metrics.space2.toPx(), positions[indices.first()])
                        }
                        highlights.forEach { (start, end) ->
                            clipRect(left = start * size.width, right = end * size.width) {
                                paths.forEach { drawPath(it, highlightColor, style = stroke) }
                                runs.filter { it.size == 1 }.forEach { indices ->
                                    drawCircle(highlightColor, Metrics.space2.toPx(), positions[indices.first()])
                                }
                            }
                        }
                    }
                },
        )
        ClockLabelRow(onsetTs, wakeTs)
    }
}
