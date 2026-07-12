package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [displaySmoothedWeights], the pure display-smoothing behind the Sleep hero's
 * "Sleep cycles" staircase — the Kotlin twin of the Swift `Hypnogram.displaySmoothed`. Smoothing
 * is render-only: adjacent same-stage runs coalesce, then each sub-threshold fragment is absorbed
 * into its longer neighbour (ties into the previous), and the summed weight is always preserved.
 */
class SleepCyclesSmoothingTest {

    private fun total(segs: List<Pair<String, Float>>) = segs.map { it.second }.sum()

    @Test
    fun coalescesAdjacentSameStageRuns() {
        val out = displaySmoothedWeights(
            listOf("deep" to 10f, "deep" to 20f, "light" to 30f),
            minMinutes = 5f,
        )
        assertEquals(listOf("deep" to 30f, "light" to 30f), out)
    }

    @Test
    fun absorbsShortFragmentIntoLongerNeighbour() {
        val out = displaySmoothedWeights(
            listOf("light" to 30f, "rem" to 2f, "light" to 40f),
            minMinutes = 5f,
        )
        // rem (2m) is below threshold; its longer neighbour is the trailing light run, then the
        // two light runs coalesce into one block covering the whole span.
        assertEquals(listOf("light" to 72f), out)
    }

    @Test
    fun tieAbsorbsIntoPreviousNeighbour() {
        val out = displaySmoothedWeights(
            listOf("light" to 10f, "rem" to 4f, "deep" to 10f),
            minMinutes = 5f,
        )
        // Equal neighbours: the PREVIOUS one wins (Swift's `p.duration >= n.duration`).
        assertEquals(listOf("light" to 14f, "deep" to 10f), out)
    }

    @Test
    fun nightAboveThresholdIsUntouched() {
        val night = listOf("light" to 30f, "deep" to 40f, "rem" to 20f, "awake" to 6f)
        assertEquals(night, displaySmoothedWeights(night, minMinutes = 5f))
    }

    @Test
    fun preservesTotalWeightOnAFragmentedNight() {
        // A comb of sub-threshold flickers: everything must merge without losing a minute.
        val night = listOf(
            "light" to 12f, "deep" to 1f, "light" to 2f, "deep" to 25f, "rem" to 3f,
            "deep" to 1.5f, "light" to 18f, "awake" to 0.5f, "light" to 9f, "rem" to 22f,
        )
        val out = displaySmoothedWeights(night, minMinutes = 5f)
        assertEquals(total(night), total(out), 1e-3f)
        // Every surviving block clears the threshold.
        out.forEach { (_, w) -> assertTrue("block below threshold: $w", w >= 5f) }
        // No adjacent same-stage runs survive.
        out.zipWithNext().forEach { (a, b) -> assertTrue(a.first != b.first) }
    }

    @Test
    fun twoSegmentsOrFewerReturnUnchanged() {
        val short = listOf("light" to 3f, "deep" to 2f)
        assertEquals(short, displaySmoothedWeights(short, minMinutes = 5f))
    }
}
