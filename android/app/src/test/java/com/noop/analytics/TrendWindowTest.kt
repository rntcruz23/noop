package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrendWindowTest {
    @Test
    fun fixedWindow_isInclusive_andDoesNotWiden() {
        val rows = listOf(
            "2026-06-01" to 1.0, "2026-06-23" to 2.0, "2026-06-24" to 3.0,
            "2026-06-30" to 4.0, "2026-07-01" to 5.0, "bad" to 6.0,
            "2026-06-29" to Double.NaN,
        )
        val result = TrendWindow.project(rows, "2026-06-30", 7)
        assertEquals("2026-06-24", result.startDay)
        assertEquals("2026-06-30", result.endDay)
        assertEquals(listOf("2026-06-24", "2026-06-30"), result.points.map { it.day })
        assertEquals(2, result.observed)
        assertEquals(7, result.expected)
        assertTrue(result.hasOlderHistory)
    }

    @Test
    fun duplicateDays_resolveLastFiniteValue() {
        val result = TrendWindow.project(
            listOf("2026-06-30" to 1.0, "2026-06-30" to 2.0), "2026-06-30", 7,
        )
        assertEquals(listOf(TrendWindow.Point("2026-06-30", 2.0)), result.points)
    }

    @Test
    fun all_startsAtEarliestValidObservation() {
        val result = TrendWindow.project(
            listOf("bad" to 1.0, "2026-02-28" to 2.0, "2026-06-30" to 3.0),
            "2026-06-30", null,
        )
        assertEquals("2026-02-28", result.startDay)
        assertEquals(123, result.expected)
        assertEquals(2, result.observed)
    }

    @Test
    fun previousPoints_usesEqualPrecedingCalendarInterval() {
        val result = TrendWindow.previousPoints(
            listOf(
                "2026-06-16" to 1.0,
                "2026-06-22" to 2.0,
                "2026-06-23" to 3.0,
                "2026-06-24" to 4.0,
            ),
            "2026-06-30",
            7,
        )
        assertEquals(listOf("2026-06-22", "2026-06-23"), result.map { it.day })
    }
    @Test
    fun onePointWindow() {
        val result = TrendWindow.project(listOf("2026-06-30" to 7.0), "2026-06-30", 1)
        assertEquals(listOf(TrendWindow.Point("2026-06-30", 7.0)), result.points)
        assertEquals("2026-06-30", result.startDay)
        assertEquals(1, result.expected)
        assertFalse(result.hasOlderHistory)
    }

    @Test
    fun fixedWindowWithNoData_stillReportsSelectedDates() {
        val result = TrendWindow.project(emptyList(), "2026-06-30", 7)
        assertEquals(emptyList<TrendWindow.Point>(), result.points)
        assertEquals("2026-06-24", result.startDay)
        assertEquals("2026-06-30", result.endDay)
        assertEquals(0, result.observed)
        assertEquals(7, result.expected)
    }

    @Test
    fun nonfiniteValues_areDropped() {
        val rows = listOf(
            "2026-06-28" to Double.POSITIVE_INFINITY,
            "2026-06-29" to Double.NEGATIVE_INFINITY,
            "2026-06-30" to Double.NaN,
        )
        assertEquals(emptyList<TrendWindow.Point>(), TrendWindow.project(rows, "2026-06-30", 3).points)
    }

    @Test
    fun invalidToday_returnsEmptyResult() {
        val result = TrendWindow.project(listOf("2026-06-30" to 1.0), "bad", 7)
        assertNull(result.startDay)
        assertEquals("bad", result.endDay)
        assertEquals(0, result.observed)
        assertEquals(0, result.expected)
    }

    @Test
    fun duplicateFiniteThenInvalid_keepsFiniteValue() {
        val rows = listOf("2026-06-30" to 1.0, "2026-06-30" to Double.NaN)
        assertEquals(
            listOf(TrendWindow.Point("2026-06-30", 1.0)),
            TrendWindow.project(rows, "2026-06-30", 7).points,
        )
    }

    @Test
    fun duplicateInvalidThenFinite_usesFiniteValue() {
        val rows = listOf("2026-06-30" to Double.POSITIVE_INFINITY, "2026-06-30" to 2.0)
        assertEquals(
            listOf(TrendWindow.Point("2026-06-30", 2.0)),
            TrendWindow.project(rows, "2026-06-30", 7).points,
        )
    }

    @Test
    fun allWithNoData_isEmpty() {
        val result = TrendWindow.project(emptyList(), "2026-06-30", null)
        assertNull(result.startDay)
        assertEquals(0, result.observed)
        assertEquals(0, result.expected)
        assertFalse(result.hasOlderHistory)
    }

    @Test
    fun dayKeys_mustBeCanonicalExactDates() {
        val rows = listOf(
            "2026-6-30" to 1.0, "2026-02-30" to 2.0,
            "2026-06-30T00:00:00Z" to 3.0, "2026-06-30" to 4.0,
        )
        val result = TrendWindow.project(rows, "2026-06-30", 1)
        assertEquals(listOf(TrendWindow.Point("2026-06-30", 4.0)), result.points)
        assertEquals(0, TrendWindow.project(rows, "2026-6-30", 1).expected)
    }
}
