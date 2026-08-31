package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins VitalBands — the Health Monitor's personal-baseline banding. Mirrors
 * StrandAnalyticsTests/VitalBandsTests.swift case-for-case with identical numbers, so the
 * two platforms can never band the same vital differently.
 */
class VitalBandsTest {

    private val hrvCfg = Baselines.metricCfg.getValue("hrv")
    private val hrvPop = 40.0..120.0

    @Test
    fun nullValue_isNoData() {
        val r = VitalBands.band(null, listOf(50.0), hrvPop, hrvCfg)
        assertEquals(VitalBands.Band.NO_DATA, r.band)
    }

    // THE MOTIVATING CASE: a personal-normal HRV of 35 ms with the population band at 40-120.
    // Below the trust gate it is still judged against the population, hence out-of-range.
    @Test
    fun lowHrv_below14Nights_populationOutOfRange() {
        val r = VitalBands.band(35.0, List(10) { 35.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Band.OUT_OF_RANGE, r.band)
        assertEquals(VitalBands.Basis.POPULATION, r.basis)
        assertEquals(10, r.nights)
    }

    // The fix: at 14 trusted nights the same 35 ms is in-range against the user's OWN baseline.
    @Test
    fun lowHrv_at14Nights_personalInRange() {
        val r = VitalBands.band(35.0, List(14) { 35.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Band.IN_RANGE, r.band)
        assertEquals(VitalBands.Basis.PERSONAL, r.basis)
        assertEquals(14, r.nights)
    }

    @Test
    fun personal_bigDeviation_outOfRange() {
        // Constant 35 → spread floors out; z(70) is far above the 2σ gate.
        val r = VitalBands.band(70.0, List(30) { 35.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Band.OUT_OF_RANGE, r.band)
        assertEquals(VitalBands.Basis.PERSONAL, r.basis)
    }

    @Test
    fun personal_justInside2Sigma_inRange() {
        val hist: List<Double?> = List(30) { 35.0 }
        val state = Baselines.foldHistory(hist, hrvCfg)
        // 1.99σ in σ-space (1.253×spread ≈ σ): strictly inside the 2σ gate.
        val edge = state.baseline + 1.99 * 1.253 * state.spread
        assertEquals(VitalBands.Band.IN_RANGE, VitalBands.band(edge, hist, hrvPop, hrvCfg).band)
    }

    @Test
    fun implausibleValue_alwaysOutOfRange_evenWithTrustedBaseline() {
        // hrv cfg bounds 5-250: 300 is implausible regardless of personal spread.
        val r = VitalBands.band(300.0, List(30) { 35.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Band.OUT_OF_RANGE, r.band)
        assertEquals(VitalBands.Basis.POPULATION, r.basis)
    }

    @Test
    fun nullCfg_spo2_staysPopulationOnly() {
        val r = VitalBands.band(93.0, emptyList(), 95.0..100.0, null)
        assertEquals(VitalBands.Band.OUT_OF_RANGE, r.band)
        assertEquals(VitalBands.Basis.POPULATION, r.basis)
    }

    @Test
    fun nullNights_doNotCountTowardTrust() {
        // 13 valid nights then 10 trailing skips → only 13 valid → provisional, still population.
        val hist: List<Double?> = (1..13).map { 35.0 } + List(10) { null }
        val r = VitalBands.band(35.0, hist, hrvPop, hrvCfg)
        assertEquals(VitalBands.Basis.POPULATION, r.basis)
    }

    @Test
    fun staleBaseline_fallsBackToPopulation() {
        // 20 valid nights then 20 missing (> staleDays = 14): status STALE → population.
        val hist: List<Double?> = List(20) { 35.0 } + List(20) { null }
        val r = VitalBands.band(35.0, hist, hrvPop, hrvCfg)
        assertEquals(VitalBands.Basis.POPULATION, r.basis)
    }

    @Test
    fun skinTempHistory_partitionsMixedSemantics() {
        // 34.1/33.8 are absolute °C; 0.2/-0.1 are deviations. Each displayed kind keeps only its own.
        val mixed: List<Double?> = listOf(34.1, 0.2, null, 33.8, -0.1)
        assertEquals(listOf(null, 0.2, null, null, -0.1), VitalBands.skinTempHistory(0.3, mixed))
        assertEquals(listOf(34.1, null, null, 33.8, null), VitalBands.skinTempHistory(34.0, mixed))
    }

    @Test
    fun calendarSeries_padsMissingDays() {
        val rows = listOf<Pair<String, Double?>>("2026-06-01" to 50.0, "2026-06-04" to 52.0)
        assertEquals(listOf(50.0, null, null, 52.0), VitalBands.calendarSeries(rows))
    }

    @Test
    fun calendarSeries_dropsMalformedKeys_emptyIsEmpty() {
        assertEquals(emptyList<Double?>(), VitalBands.calendarSeries(emptyList()))
        val rows = listOf<Pair<String, Double?>>(
            "not-a-date" to 1.0, "2026-6-01" to 2.0, "2026-02-30" to 3.0,
            "2026-06-01T00:00:00Z" to 4.0, "2026-06-01" to 50.0,
        )
        assertEquals(listOf(50.0), VitalBands.calendarSeries(rows))
    }

    @Test
    fun calendarSeries_duplicateDaysUseLastWriteIncludingNull() {
        val rows = listOf<Pair<String, Double?>>(
            "2026-06-01" to 40.0, "2026-06-01" to 41.0,
            "2026-06-02" to 42.0, "2026-06-02" to null,
        )
        assertEquals(listOf(41.0, null), VitalBands.calendarSeries(rows))
    }

    @Test
    fun nonfiniteCurrent_isOutOfRangeButNeverPresentedWithin() {
        listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY).forEach { value ->
            val result = VitalBands.presentation(value, List(14) { 50.0 }, hrvPop, hrvCfg)
            assertEquals(VitalBands.Band.OUT_OF_RANGE, result.band)
            assertEquals(VitalBands.Position.NO_DATA, result.position)
            assertEquals(
                VitalBands.Position.NO_DATA,
                VitalBands.presentation(value, emptyList(), 95.0..100.0, null).position,
            )
        }
    }

    @Test
    fun nonfiniteHistory_doesNotCountTowardBaseline() {
        val history: List<Double?> = List(13) { 50.0 } +
            listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)
        val result = VitalBands.presentation(50.0, history, hrvPop, hrvCfg)
        assertEquals(13, result.nights)
        assertEquals(VitalBands.Basis.POPULATION, result.basis)
    }

    @Test
    fun restingHeartRate_lowAndHighDirections() {
        val history: List<Double?> = List(14) { 50.0 }
        assertEquals(
            VitalBands.Position.BELOW,
            VitalBands.presentation(40.0, history, 40.0..60.0, Baselines.restingHRCfg).position,
        )
        assertEquals(
            VitalBands.Position.ABOVE,
            VitalBands.presentation(60.0, history, 40.0..60.0, Baselines.restingHRCfg).position,
        )
    }

    @Test
    fun restingHeartRate_physiologicalBoundariesAreInclusive() {
        listOf(30.0, 120.0).forEach { value ->
            assertEquals(
                VitalBands.Band.IN_RANGE,
                VitalBands.band(value, emptyList(), 30.0..120.0, Baselines.restingHRCfg).band,
            )
        }
        listOf(29.0, 121.0).forEach { value ->
            assertEquals(
                VitalBands.Band.OUT_OF_RANGE,
                VitalBands.band(value, emptyList(), 30.0..120.0, Baselines.restingHRCfg).band,
            )
        }
    }

    @Test
    fun presentation_exposesTrustedPersonalBoundsAndDirection() {
        val result = VitalBands.presentation(55.0, List(14) { 50.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Basis.PERSONAL, result.basis)
        assertEquals(BaselineStatus.TRUSTED, result.status)
        assertEquals(50.0, result.center!!, 0.000_001)
        assertEquals(37.47, result.lowerBound, 0.000_001)
        assertEquals(62.53, result.upperBound, 0.000_001)
        assertEquals(VitalBands.Position.WITHIN, result.position)
        assertEquals(14, result.nights)
    }

    @Test
    fun presentation_usesNamedPopulationFallbackWhileProvisional() {
        val result = VitalBands.presentation(35.0, List(10) { 35.0 }, hrvPop, hrvCfg)
        assertEquals(VitalBands.Basis.POPULATION, result.basis)
        assertEquals(BaselineStatus.PROVISIONAL, result.status)
        assertEquals(null, result.center)
        assertEquals(40.0, result.lowerBound, 0.0)
        assertEquals(120.0, result.upperBound, 0.0)
        assertEquals(VitalBands.Position.BELOW, result.position)
    }

    @Test
    fun presentation_padsTrailingGapThroughDisplayedDay() {
        val rows = (1..20).map { day -> "2026-06-${day.toString().padStart(2, '0')}" to 50.0 }
        val result = VitalBands.presentation(50.0, rows, "2026-07-06", hrvPop, hrvCfg)
        assertEquals(BaselineStatus.STALE, result.status)
        assertEquals(VitalBands.Basis.POPULATION, result.basis)
    }

    @Test
    fun presentation_matchesSharedExpectedFixture() {
        val cases = listOf(
            "cold" to VitalBands.presentation(35.0, List(3) { 35.0 }, hrvPop, hrvCfg),
            "provisional" to VitalBands.presentation(35.0, List(10) { 35.0 }, hrvPop, hrvCfg),
            "trusted" to VitalBands.presentation(55.0, List(14) { 50.0 }, hrvPop, hrvCfg),
            "stale" to VitalBands.presentation(50.0, List(20) { 50.0 } + List(15) { null }, hrvPop, hrvCfg),
        )
        val actual = cases.joinToString("\n") { (name, value) ->
            listOf(
                name, value.band.raw, value.basis.raw, value.status?.raw ?: "null",
                value.center?.let { String.format(java.util.Locale.US, "%.3f", it) } ?: "null",
                String.format(java.util.Locale.US, "%.3f", value.lowerBound),
                String.format(java.util.Locale.US, "%.3f", value.upperBound),
                value.position.raw, value.nights.toString(),
            ).joinToString("|")
        }
        val expectedFixture = """cold|outOfRange|population|calibrating|null|40.000|120.000|below|3
provisional|outOfRange|population|provisional|null|40.000|120.000|below|10
trusted|inRange|personal|trusted|50.000|37.470|62.530|within|14
stale|inRange|population|stale|null|40.000|120.000|within|20"""
        assertEquals(expectedFixture, actual)
    }

    @Test
    fun presentation_doesNotOverwritePreviousNightWhenPadding() {
        val rows = (1..14).map { day -> "2026-06-${day.toString().padStart(2, '0')}" to 50.0 }
        val result = VitalBands.presentation(50.0, rows, "2026-06-15", hrvPop, hrvCfg)
        assertEquals(BaselineStatus.TRUSTED, result.status)
        assertEquals(14, result.nights)
        assertEquals(VitalBands.Basis.PERSONAL, result.basis)
    }

    @Test
    fun presentation_honorsManualRecalibrationEpoch() {
        val rows = (1..14).map { day -> "2026-06-${day.toString().padStart(2, '0')}" to 50.0 }
        val epoch = java.time.Instant.parse("2026-06-10T00:00:00Z").epochSecond.toDouble()
        val result = VitalBands.presentation(
            50.0, rows, "2026-06-15", hrvPop, hrvCfg, baselineEpoch = epoch,
        )
        assertEquals(BaselineStatus.CALIBRATING, result.status)
        assertEquals(5, result.nights)
        assertEquals(VitalBands.Basis.POPULATION, result.basis)
    }
}
