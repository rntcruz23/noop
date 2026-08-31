package com.noop.analytics

/*
 * VitalBands.kt — personal-baseline banding for the Health Monitor's vital tiles.
 * Faithful Kotlin port of StrandAnalytics/VitalBands.swift (verified on macOS).
 *
 * In-range is judged against the user's OWN trailing baseline (the Winsorized EWMA the rest
 * of [Baselines] builds) once it is trusted — minNightsTrust (14) valid nights and not stale.
 * Until then, and again whenever a wear gap makes the baseline stale, the fixed population
 * range is the fallback.
 *
 * MetricCfg's physiological bounds stay an absolute outer guard either way. They are
 * deliberately NOT used as the in-range band: that would resurrect the exact false positive
 * this fixes — a perfectly normal personal HRV of 35 ms reading permanently out-of-range
 * against the 40–120 population band. The bounds only catch values implausible for any human.
 *
 * Outputs are APPROXIMATE and not medical advice.
 */
object VitalBands {

    enum class Band(val raw: String) {
        IN_RANGE("inRange"), OUT_OF_RANGE("outOfRange"), NO_DATA("noData")
    }

    /** How the band was judged — drives the tile's caption wording. */
    enum class Basis(val raw: String) { PERSONAL("personal"), POPULATION("population") }

    data class Result(val band: Band, val basis: Basis, val nights: Int)

    enum class Position(val raw: String) {
        BELOW("below"), WITHIN("within"), ABOVE("above"), NO_DATA("noData")
    }

    /** Read-only context for presenting a vital without changing its scoring classification. */
    data class Presentation(
        val band: Band,
        val basis: Basis,
        val status: BaselineStatus?,
        val center: Double?,
        val lowerBound: Double,
        val upperBound: Double,
        val position: Position,
        val nights: Int,
    )

    /** |z| at or below this is in-range vs the personal baseline (~95% of the user's own
     *  normal nights; the |z| <= 1 of [Baselines.deviation] would flag ~32% — too noisy for
     *  a passive tile). */
    const val sigmaK: Double = 2.0

    /**
     * Band a single vital [value].
     *
     * [history] is nightly values oldest→newest EXCLUDING the displayed day (null = missing
     * night; run [calendarSeries] first to pad real wear gaps so staleness sees them).
     * [populationRange] is the typical-adult fallback used until the baseline is trusted.
     * A null [cfg] disables the personal path entirely (SpO₂ stays population-only — there is
     * no SpO₂ MetricCfg and an absolute floor is meaningful regardless of personal history).
     */
    fun band(
        value: Double?,
        history: List<Double?>,
        populationRange: ClosedFloatingPointRange<Double>,
        cfg: MetricCfg?,
    ): Result {
        val context = presentation(value, history, populationRange, cfg)
        return Result(context.band, context.basis, context.nights)
    }

    /** Exposes the exact bounds and baseline state used by [band] for presentation-only context. */
    fun presentation(
        value: Double?,
        history: List<Double?>,
        populationRange: ClosedFloatingPointRange<Double>,
        cfg: MetricCfg?,
    ): Presentation {
        if (value == null) {
            return Presentation(
                Band.NO_DATA, Basis.POPULATION, null, null,
                populationRange.start, populationRange.endInclusive, Position.NO_DATA, 0,
            )
        }
        if (cfg == null) {
            val position = position(value, populationRange)
            return Presentation(
                if (position == Position.WITHIN) Band.IN_RANGE else Band.OUT_OF_RANGE,
                Basis.POPULATION, null, null, populationRange.start, populationRange.endInclusive,
                position, 0,
            )
        }
        val state = Baselines.foldHistory(history, cfg)
        val physiologicallyValid = value in cfg.minVal..cfg.maxVal
        if (state.trusted && physiologicallyValid) {
            val radius = sigmaK * 1.253 * state.spread
            val range = maxOf(cfg.minVal, state.baseline - radius)..minOf(cfg.maxVal, state.baseline + radius)
            val position = position(value, range)
            return Presentation(
                if (position == Position.WITHIN) Band.IN_RANGE else Band.OUT_OF_RANGE,
                Basis.PERSONAL, state.status, state.baseline, range.start, range.endInclusive,
                position, state.nValid,
            )
        }
        val position = position(value, populationRange)
        return Presentation(
            if (physiologicallyValid && position == Position.WITHIN) Band.IN_RANGE else Band.OUT_OF_RANGE,
            Basis.POPULATION, state.status, null, populationRange.start, populationRange.endInclusive,
            position, state.nValid,
        )
    }

    /** Calendar-pads resolved history strictly before [displayedDay], including a trailing wear gap. */
    fun presentation(
        value: Double?,
        historyRows: List<Pair<String, Double?>>,
        displayedDay: String,
        populationRange: ClosedFloatingPointRange<Double>,
        cfg: MetricCfg?,
        baselineEpoch: Double = 0.0,
    ): Presentation {
        val displayed = parseDay(displayedDay)
            ?: return presentation(value, emptyList(), populationRange, cfg)
        val rows = historyRows.mapNotNull { (day, historicalValue) ->
            parseDay(day)
                ?.takeIf { it.isBefore(displayed) }
                ?.let { it.toString() to historicalValue }
        }.toMutableList()
        val priorKey = displayed.minusDays(1).toString()
        if (rows.none { it.first == priorKey }) rows += priorKey to null
        val calendarRows = calendarRows(rows)
        if (cfg == null || baselineEpoch <= 0.0) {
            return presentation(value, calendarRows.map { it.second }, populationRange, cfg)
        }
        val state = Baselines.foldHistory(
            calendarRows.map { it.second }, calendarRows.map { it.first }, cfg, baselineEpoch,
        )
        return presentation(value, state, populationRange, cfg)
    }

    private fun presentation(
        value: Double?,
        state: BaselineState,
        populationRange: ClosedFloatingPointRange<Double>,
        cfg: MetricCfg,
    ): Presentation {
        if (value == null) return Presentation(
            Band.NO_DATA, Basis.POPULATION, null, null,
            populationRange.start, populationRange.endInclusive, Position.NO_DATA, 0,
        )
        val physiologicallyValid = value in cfg.minVal..cfg.maxVal
        if (state.trusted && physiologicallyValid) {
            val radius = sigmaK * 1.253 * state.spread
            val range = maxOf(cfg.minVal, state.baseline - radius)..minOf(cfg.maxVal, state.baseline + radius)
            val pointPosition = position(value, range)
            return Presentation(
                if (pointPosition == Position.WITHIN) Band.IN_RANGE else Band.OUT_OF_RANGE,
                Basis.PERSONAL, state.status, state.baseline, range.start, range.endInclusive,
                pointPosition, state.nValid,
            )
        }
        val pointPosition = position(value, populationRange)
        return Presentation(
            if (physiologicallyValid && pointPosition == Position.WITHIN) Band.IN_RANGE else Band.OUT_OF_RANGE,
            Basis.POPULATION, state.status, null, populationRange.start, populationRange.endInclusive,
            pointPosition, state.nValid,
        )
    }

    private fun position(
        value: Double,
        range: ClosedFloatingPointRange<Double>,
    ): Position = when {
        !value.isFinite() -> Position.NO_DATA
        value < range.start -> Position.BELOW
        value > range.endInclusive -> Position.ABOVE
        else -> Position.WITHIN
    }

    // ── Skin temp (mixed semantics: absolute °C from CSV import vs ±°C on-device deviation) ──

    /** A skin-temp value >= 20 °C is read as ABSOLUTE skin temperature; smaller magnitudes as a
     *  ±°C deviation. The WHOOP CSV export stores absolute °C while the on-device pipeline stores
     *  a deviation — a merged series is bimodal, so the displayed value picks which kind its
     *  history keeps. Heuristic but physically safe: no real wrist temp is below 20 °C and no
     *  real deviation reaches ±20 °C. */
    fun isAbsoluteSkinTemp(v: Double): Boolean = v >= 20.0

    /** Keep only history entries of the SAME kind (absolute vs deviation) as the displayed
     *  [value]; entries of the other kind become null (missing nights) so the baseline isn't
     *  folded across two incompatible scales. */
    fun skinTempHistory(value: Double, history: List<Double?>): List<Double?> {
        val absolute = isAbsoluteSkinTemp(value)
        return history.map { v ->
            if (v != null && isAbsoluteSkinTemp(v) == absolute) v else null
        }
    }

    /** Deviation-semantics config for on-device skin-temp rows: ±°C around the personal mean,
     *  guarded to a physically sane ±8 °C. (The standard `skin_temp` config in [Baselines] is
     *  the ABSOLUTE-°C one, used for CSV-imported rows.) */
    val skinTempDeviationCfg = MetricCfg(
        minVal = -8.0, maxVal = 8.0, floorSpread = 0.3, halfLifeB = 14.0, halfLifeS = 21.0,
    )

    // ── Calendar padding ────────────────────────────────────────────────────────────────────

    /** Calendar-align (day, value) rows keyed "yyyy-MM-dd" into a nightly series with null for
     *  every absent day, so the baseline's staleness logic sees real wear gaps (otherwise a user
     *  returning after months would be banded against an ancient still-"trusted" baseline).
     *  Malformed keys are dropped; last write wins for a duplicated day. */
    fun calendarSeries(rows: List<Pair<String, Double?>>): List<Double?> =
        calendarRows(rows).map { it.second }

    private fun calendarRows(rows: List<Pair<String, Double?>>): List<Pair<String, Double?>> {
        val parsed = rows.mapNotNull { (day, v) ->
            parseDay(day)?.let { it to v }
        }
        val first = parsed.minOfOrNull { it.first } ?: return emptyList()
        val last = parsed.maxOfOrNull { it.first } ?: return emptyList()
        val byDay = parsed.associate { it.first to it.second }
        val out = ArrayList<Pair<String, Double?>>()
        var d = first
        while (!d.isAfter(last)) {
            out.add(d.toString() to byDay[d])
            d = d.plusDays(1)
        }
        return out
    }

    private fun parseDay(key: String): java.time.LocalDate? =
        runCatching { java.time.LocalDate.parse(key) }.getOrNull()?.takeIf { it.toString() == key }
}
