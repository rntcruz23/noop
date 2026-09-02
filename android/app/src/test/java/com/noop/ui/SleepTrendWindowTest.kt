package com.noop.ui

import com.noop.data.DailyMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepTrendWindowTest {
    private fun day(key: String, asleepMin: Double?) = DailyMetric(
        deviceId = "d",
        day = key,
        totalSleepMin = asleepMin,
        deepMin = 60.0,
        remMin = 80.0,
        lightMin = 220.0,
        efficiency = 0.9,
    )

    @Test
    fun trendUsesTrailingFourteenCalendarDaysAndPreservesGaps() {
        val days = listOf(
            day("2026-05-01", 420.0),
            day("2026-06-01", 400.0),
            day("2026-06-10", 410.0),
            day("2026-06-14", 430.0),
        )

        val model = buildSleepModel(days, session = null, todayKey = "2026-06-15")!!

        assertEquals("2026-06-01", model.trendDates.first())
        assertEquals("2026-06-14", model.trendDates.last())
        assertEquals(14, model.trendDates.size)
        assertEquals(3, model.trendHours.size)
        assertEquals(listOf("2026-06-01", "2026-06-10", "2026-06-14"), model.trendValueDates)
        assertEquals(listOf(0f, 9f / 13f, 1f), model.trendPositions)
        assertEquals(3, model.trendCoverage)
    }

    @Test
    fun durationDomainIncludesNeedReference() {
        val domain = sleepDurationDomain(listOf(5.0, 6.0), referenceHours = 8.0)
        assertEquals(0.0, domain.start, 0.0)
        assertTrue(domain.endInclusive >= 8.0)
    }

}
