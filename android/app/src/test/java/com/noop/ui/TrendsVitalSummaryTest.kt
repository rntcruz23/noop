package com.noop.ui

import com.noop.analytics.Baselines
import com.noop.analytics.VitalBands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrendsVitalSummaryTest {
    @Test fun selectedWindowEndsTodayAndDoesNotWidenToOlderHistory() {
        val summary = vitalTrendSummary(
            rows = listOf(
                "2026-07-24" to 45.0,
                "2026-07-25" to 52.0,
                "2026-07-31" to 61.0,
                "2026-08-01" to 99.0,
            ),
            todayKey = "2026-07-31",
            dayCount = 7,
            populationRange = 40.0..120.0,
            cfg = Baselines.hrvCfg,
        )

        assertEquals(listOf("2026-07-25", "2026-07-31"), summary.window.points.map { it.day })
        assertEquals(2, summary.window.observed)
        assertEquals(7, summary.window.expected)
        assertTrue(summary.window.hasOlderHistory)
        assertEquals(listOf(0f, 1f), summary.xPositions)
        assertEquals(listOf("2026-07-24"), summary.previousPoints.map { it.day })
    }

    @Test fun eachDisplayedPointUsesOnlyEarlierHistoryForItsRange() {
        val rows = (1..15).map { day -> "2026-07-${day.toString().padStart(2, '0')}" to 35.0 } +
            listOf("2026-07-16" to 70.0)
        val summary = vitalTrendSummary(
            rows = rows,
            todayKey = "2026-07-16",
            dayCount = 7,
            populationRange = 40.0..120.0,
            cfg = Baselines.hrvCfg,
        )

        assertEquals(VitalBands.Basis.POPULATION, summary.presentations.first().basis)
        assertEquals(VitalBands.Basis.PERSONAL, summary.presentations.last().basis)
        assertFalse(summary.presentations.last().lowerBound <= 70.0 && 70.0 <= summary.presentations.last().upperBound)
    }

    @Test fun allHistoryCoverageUsesInclusiveCalendarSpan() {
        val summary = vitalTrendSummary(
            rows = listOf("2026-07-28" to 55.0, "2026-07-31" to 58.0),
            todayKey = "2026-07-31",
            dayCount = null,
            populationRange = 40.0..60.0,
            cfg = Baselines.restingHRCfg,
        )

        assertEquals(2, summary.window.observed)
        assertEquals(4, summary.window.expected)
        assertEquals(listOf(0f, 1f), summary.xPositions)
        assertTrue(summary.allHistory)
    }

    @Test fun axisLabelsUseSelectedCalendarBoundariesNotObservationDates() {
        assertEquals(
            listOf("2026-07-25", "2026-07-28", "2026-07-31"),
            vitalAxisLabels("2026-07-25", "2026-07-31").map { it.day },
        )
    }
}
