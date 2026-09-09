package com.noop.ui

import com.noop.data.HrBucket
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepHeartRatePlotTest {
    @Test fun positionsUseTheWholeNightRatherThanSampleIndices() {
        val plot = sleepHeartRatePlot(listOf(HrBucket(120, 60.0), HrBucket(240, 65.0)), 0, 600)
        assertEquals(listOf(0.2f, 0.4f), plot.points.map { it.x })
    }

    @Test fun missingMinutesBreakTheLineWithoutCompressingTime() {
        val plot = sleepHeartRatePlot(
            listOf(HrBucket(0, 60.0), HrBucket(60, 62.0), HrBucket(240, 65.0)), 0, 600,
        )
        assertEquals(listOf(0, 0, 1), plot.points.map { it.run })
        assertEquals(0.4f, plot.points.last().x, 0f)
    }

    @Test fun sortsFiltersAndClipsOnlyTheOverlappingFirstBucket() {
        val plot = sleepHeartRatePlot(
            listOf(HrBucket(180, 65.0), HrBucket(60, 60.0), HrBucket(120, Double.NaN),
                HrBucket(240, 0.0), HrBucket(300, 70.0), HrBucket(0, 55.0)), 90, 300,
        )
        assertEquals(listOf(90L, 180L), plot.points.map { it.timestamp })
        assertEquals(0f, plot.points.first().x, 0f)
        assertEquals(listOf(0, 1), plot.points.map { it.run })
    }

    @Test fun highlightsUseRealStageTimesAndPreserveUnlabelledGaps() {
        val segments = listOf(
            PersistedSegment(400, 700, "Deep"), PersistedSegment(-60, 120, "deep"),
            PersistedSegment(120, 200, "light"),
        )
        val spans = sleepStageHighlights(segments, "DEEP", 0, 600)
        assertEquals(2, spans.size)
        assertEquals(0f, spans[0].first, 0f)
        assertEquals(0.2f, spans[0].second, 0f)
        assertEquals(400f / 600f, spans[1].first, 0.00001f)
        assertEquals(1f, spans[1].second, 0f)
    }

    @Test fun wakeAliasAndClearedSelectionAreHandled() {
        val segments = listOf(PersistedSegment(0, 60, "wake"))
        assertEquals(listOf(0f to 1f), sleepStageHighlights(segments, "Awake", 0, 60))
        assertTrue(sleepStageHighlights(segments, null, 0, 60).isEmpty())
        assertTrue(sleepStageHighlights(emptyList(), "Deep", 0, 60).isEmpty())
    }

    @Test fun invalidWindowIsEmptyAndConstantHeartRateHasAUsableDomain() {
        assertTrue(sleepHeartRatePlot(listOf(HrBucket(60, 60.0)), 60, 60).points.isEmpty())
        assertTrue(sleepStageHighlights(listOf(PersistedSegment(0, 60, "deep")), "deep", 60, 0).isEmpty())
        val plot = sleepHeartRatePlot(listOf(HrBucket(0, 60.0), HrBucket(60, 60.0)), 0, 120)
        assertTrue(plot.domain.start < 60.0)
        assertTrue(plot.domain.endInclusive > 60.0)
    }
}
