package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrendsHierarchyTest {
    @Test fun chargeIsTheDefaultHero() {
        assertEquals(TrendsMetric.CHARGE, defaultTrendsMetric())
    }

    @Test fun secondaryRowsContainEveryMetricExceptTheHeroInStableOrder() {
        assertEquals(
            listOf(TrendsMetric.HRV, TrendsMetric.RHR, TrendsMetric.REST, TrendsMetric.EFFORT),
            secondaryTrendMetrics(TrendsMetric.CHARGE),
        )
        TrendsMetric.entries.forEach { selected ->
            val secondary = secondaryTrendMetrics(selected)
            assertEquals(4, secondary.size)
            assertFalse(secondary.contains(selected))
            assertEquals(TrendsMetric.entries.filterNot { it == selected }, secondary)
            assertTrue((secondary + selected).containsAll(TrendsMetric.entries))
        }
    }

    @Test fun everyMetricMapsToItsExistingDetailRoute() {
        assertEquals("recovery", TrendsMetric.CHARGE.detailKey)
        assertEquals("hrv", TrendsMetric.HRV.detailKey)
        assertEquals("rhr", TrendsMetric.RHR.detailKey)
        assertEquals("rest", TrendsMetric.REST.detailKey)
        assertEquals("strain", TrendsMetric.EFFORT.detailKey)
    }

    @Test fun selectedPointFallsBackToLatestAndRejectsStaleIndices() {
        assertEquals(2, selectedOrLatestTrendIndex(null, 3))
        assertEquals(1, selectedOrLatestTrendIndex(1, 3))
        assertEquals(2, selectedOrLatestTrendIndex(8, 3))
        assertEquals(null, selectedOrLatestTrendIndex(null, 0))
    }

    @Test fun emptyStateAccountsForEveryHeroMetricSource() {
        assertFalse(hasAnyTrendData(0, 0, 0, 0, 0))
        assertTrue(hasAnyTrendData(0, 0, 0, 1, 0))
    }

    @Test fun everyMetricUsesFixedSemanticGeometry() {
        assertEquals(TrendMetricGeometry.CHARGE_ZONES, trendMetricGeometry(TrendsMetric.CHARGE))
        assertEquals(TrendMetricGeometry.LINE, trendMetricGeometry(TrendsMetric.HRV))
        assertEquals(TrendMetricGeometry.LINE, trendMetricGeometry(TrendsMetric.RHR))
        assertEquals(TrendMetricGeometry.LINE, trendMetricGeometry(TrendsMetric.REST))
        assertEquals(TrendMetricGeometry.BARS, trendMetricGeometry(TrendsMetric.EFFORT))
    }
}
