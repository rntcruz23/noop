package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LineChartGeometryTest {
    @Test fun calendarPositionsUseTheFullWindow() {
        assertEquals(
            listOf(0f, 0.1f, 1f),
            normalizedCalendarXPositions(
                dayKeys = listOf("2026-01-01", "2026-01-02", "2026-01-11"),
                windowStart = "2026-01-01",
                windowEnd = "2026-01-11",
            ),
        )
    }

    @Test fun calendarPositionsHandleLeapDayWithoutTimeZones() {
        assertEquals(
            listOf(0f, 0.5f, 1f),
            normalizedCalendarXPositions(
                dayKeys = listOf("2024-02-28", "2024-02-29", "2024-03-01"),
                windowStart = "2024-02-28",
                windowEnd = "2024-03-01",
            ),
        )
    }

    @Test fun invalidCalendarPositionsFallBackToLegacyGeometry() {
        assertNull(normalizedCalendarXPositions(listOf("not-a-day"), "2026-01-01", "2026-01-11"))
        assertNull(normalizedCalendarXPositions(listOf("2026-01-01"), "2026-01-11", "2026-01-01"))
    }

    @Test fun nearestSelectionUsesCalendarPositions() {
        assertEquals(
            2,
            nearestIndexForX(
                xPositions = listOf(0f, 0.1f, 1f),
                count = 3,
                width = 100f,
                x = 60f,
            ),
        )
    }

    @Test fun dailySegmentsComposeCalendarGapsAndExistingSegments() {
        assertEquals(
            listOf("0:a", "0:a", "1:a", "2:b", "3:a"),
            dailyLineSegmentIds(
                dayKeys = listOf("2026-01-01", "2026-01-02", "2026-01-04", "2026-01-05", "2026-01-06"),
                existingIds = listOf("a", "a", "a", "b", "a"),
            ),
        )
    }

    @Test fun summaryPolicySuppressesFillAndFallsBackToLatest() {
        val classic = lineChartRenderPolicy(LineChartMode.CLASSIC, requestedFill = true, selectedIndex = null, pointCount = 3)
        val summary = lineChartRenderPolicy(LineChartMode.SUMMARY, requestedFill = true, selectedIndex = null, pointCount = 3)

        assertTrue(classic.drawFill)
        assertNull(classic.markerIndex)
        assertFalse(summary.drawFill)
        assertEquals(2, summary.markerIndex)
        assertFalse(summary.drawFloatingLabel)
        assertEquals(
            0,
            lineChartRenderPolicy(LineChartMode.SUMMARY, true, null, 1).markerIndex,
        )
    }

    @Test fun contextualBandExpandsDomainAndMapsToCanvasCoordinates() {
        val domain = lineChartYDomain(listOf(50.0, 60.0), 40.0..80.0)
        assertEquals(40.0..80.0, domain)
        assertEquals(0f..1f, normalizedBandYRange(40.0..80.0, domain!!))
        assertEquals(0.25f..0.75f, normalizedBandYRange(50.0..70.0, domain))
        assertNull(normalizedBandYRange(10.0..20.0, domain))
    }
}
