package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhaseFiveChartSemanticsTest {
    @Test fun sleepNeedReferenceUsesOnlyFinitePositiveNeeds() {
        assertEquals(8.0, chartReferenceAverage(listOf(7.5, Double.NaN, -1.0, 8.5))!!, 0.0)
        assertNull(chartReferenceAverage(listOf(Double.NaN, 0.0, -1.0)))
    }

    @Test fun deviationDomainIsSymmetricAroundZeroAndIncludesBand() {
        assertEquals(-0.8..0.8, symmetricZeroDomain(listOf(-0.2, 0.7), -0.6..0.6))
        assertEquals(-1.0..1.0, symmetricZeroDomain(emptyList(), null))
    }

    @Test fun stressDomainAndZonesAreFixed() {
        assertEquals(0.0..3.0, stressChartDomain())
        assertEquals(StressChartZone.CALM, stressChartZone(0.0))
        assertEquals(StressChartZone.CALM, stressChartZone(0.999))
        assertEquals(StressChartZone.STEADY, stressChartZone(1.0))
        assertEquals(StressChartZone.ELEVATED, stressChartZone(2.0))
        assertEquals(StressChartZone.ELEVATED, stressChartZone(3.0))
        assertNull(stressChartZone(Double.NaN))
    }

    @Test fun stepReferenceIsThePersonalAverageOfValidDays() {
        assertEquals(8_000.0, chartReferenceAverage(listOf(7_000.0, 8_000.0, 9_000.0))!!, 0.0)
    }

    @Test fun deviationBandUsesOnlyPriorDeviationReadings() {
        val readings = listOf(
            VitalReading("2026-08-01", -0.2, "strap"),
            VitalReading("2026-08-02", 0.1, "strap"),
        )
        val result = skinDeviationPresentation(readings)!!
        assertEquals(-0.6, result.lowerBound, 0.0)
        assertEquals(0.6, result.upperBound, 0.0)
    }

    @Test fun calendarPositionedBarsSelectNearestVisibleBar() {
        assertEquals(1, nearestBarIndexForX(3, 100f, 55f, listOf(0f, 0.6f, 1f)))
        assertEquals(2, nearestBarIndexForX(3, 100f, 92f, listOf(0f, 0.6f, 1f)))
    }

    @Test fun hypnogramRanksHaveFixedClinicalMeaning() {
        assertEquals(0, hypnogramStageRank("awake"))
        assertEquals(0, hypnogramStageRank("wake"))
        assertEquals(1, hypnogramStageRank("REM"))
        assertEquals(2, hypnogramStageRank("light"))
        assertEquals(3, hypnogramStageRank("deep"))
        assertEquals(2, hypnogramStageRank("unknown"))
    }
}
