package com.noop.ui

import com.noop.data.HrBucket

internal data class SleepHeartRatePoint(val timestamp: Long, val bpm: Double, val x: Float, val run: Int)

internal data class SleepHeartRatePlot(
    val points: List<SleepHeartRatePoint>,
    val domain: ClosedFloatingPointRange<Double>,
)

/** Minute-bucket HR on the night's wall-clock axis; missing buckets break rather than stretch the line. */
internal fun sleepHeartRatePlot(buckets: List<HrBucket>, onsetTs: Long, wakeTs: Long): SleepHeartRatePlot {
    if (wakeTs <= onsetTs) return SleepHeartRatePlot(emptyList(), 0.0..1.0)
    val span = (wakeTs - onsetTs).toDouble()
    val clean = buckets.filter {
        it.avgBpm.isFinite() && it.avgBpm > 0.0 && it.bucket < wakeTs && it.bucket + 60 > onsetTs
    }.sortedBy { it.bucket }.distinctBy { it.bucket }
    var run = 0
    val points = clean.mapIndexed { index, bucket ->
        if (index > 0 && bucket.bucket - clean[index - 1].bucket > 60) run++
        // The DAO floors bucket starts to a minute; the first bucket can overlap the edited onset.
        val timestamp = maxOf(onsetTs, bucket.bucket)
        SleepHeartRatePoint(timestamp, bucket.avgBpm, ((timestamp - onsetTs) / span).toFloat(), run)
    }
    val values = points.map { it.bpm }
    val low = values.minOrNull() ?: 0.0
    val high = values.maxOrNull() ?: 1.0
    val padding = maxOf(1.0, (high - low) * 0.1)
    return SleepHeartRatePlot(points, (low - padding)..(high + padding))
}

/** Selected stage bands use recorded timestamps, never proportional totals or invented gap stages. */
internal fun sleepStageHighlights(
    segments: List<PersistedSegment>, selectedStage: String?, onsetTs: Long, wakeTs: Long,
): List<Pair<Float, Float>> {
    if (selectedStage == null || wakeTs <= onsetTs) return emptyList()
    val span = (wakeTs - onsetTs).toDouble()
    return segments.asSequence()
        .filter { canonicalStage(it.stage) == canonicalStage(selectedStage) }
        .map { maxOf(it.start, onsetTs) to minOf(it.end, wakeTs) }
        .filter { (start, end) -> end > start }
        .sortedBy { it.first }
        .map { (start, end) -> ((start - onsetTs) / span).toFloat() to ((end - onsetTs) / span).toFloat() }
        .toList()
}
