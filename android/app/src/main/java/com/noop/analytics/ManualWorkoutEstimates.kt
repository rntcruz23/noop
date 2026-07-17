package com.noop.analytics

import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Reference pre-fill values for the manual workout dialog's optional Avg HR / Calories fields.
 *
 * When a workout is logged by hand there is no HR trace to feed [Calories.estimateBoutCalories],
 * so the dialog pre-fills a plainly-editable REFERENCE value instead of leaving the fields blank:
 *  - Calories from the classic MET formula (1 MET ≈ 1 kcal/kg/h): `MET × weight(kg) × hours`,
 *    using a fixed Compendium-of-Physical-Activities-style MET per catalogue sport.
 *  - Avg HR as a typical fraction of the user's HR-max (itself age-derived via Tanaka unless
 *    overridden), mapped from the same MET so one table drives both numbers.
 *
 * APPROXIMATE — a starting point the user is expected to adjust, not a measurement. The values
 * never feed a downstream gate on their own: they land in the same optional avgHr/energyKcal
 * fields the user could have typed, strain stays null ([WorkoutEditing.buildManualRow] never
 * fabricates one), and the #598 rescore replaces them with real strap-derived numbers whenever
 * the strap actually covered the window.
 *
 * PARITY: mirrors the Swift `ManualWorkoutEstimates` byte-for-byte — same MET table, same
 * formulas, same rounding — so a manual workout pre-filled on either platform reads identically.
 */
object ManualWorkoutEstimates {

    /**
     * MET by catalogue sport (lowercased [WorkoutSport] name). Off-catalogue free-text sports and
     * the generic "Other" are absent on purpose: no honest reference exists, so the fields stay
     * blank. Values follow the Compendium of Physical Activities (general / moderate effort
     * codes), lightly rounded.
     */
    internal val MET_BY_SPORT: Map<String, Double> = mapOf(
        "running" to 9.8,
        "walking" to 3.5,
        "hiking" to 6.0,
        "cycling" to 7.5,
        "open-water swim" to 8.0,
        "rowing" to 7.0,
        "treadmill run" to 9.0,
        "treadmill walk" to 3.8,
        "indoor cycle" to 7.0,
        "pool swim" to 7.0,
        "row machine" to 7.0,
        "elliptical" to 5.0,
        "strength" to 5.0,
        "bodybuilding" to 5.0,
        "weightlifting" to 5.0,
        "hiit" to 8.0,
        "yoga" to 3.0,
        "pilates" to 3.0,
        "boxing" to 7.8,
        "basketball" to 6.5,
        "soccer" to 7.0,
        "baseball" to 5.0,
        "ice hockey" to 8.0,
        "badminton" to 5.5,
        "tennis" to 7.3,
        "squash" to 9.0,
        "racquetball" to 7.0,
        "table tennis" to 4.0,
        "volleyball" to 4.0,
        // The martial-arts family shares the Compendium's 10.3 (judo/jujitsu/karate/kick boxing/
        // tae kwan do code); wrestling has its own lower match-play code.
        "martial arts" to 10.3,
        "jiu-jitsu" to 10.3,
        "mma" to 10.3,
        "judo" to 10.3,
        "karate" to 10.3,
        "kickboxing" to 10.3,
        "muay thai" to 10.3,
        "taekwondo" to 10.3,
        "wrestling" to 6.0,
        "dancing" to 5.5,
        "golf" to 4.8,
        "climbing" to 8.0,
        "stretching" to 2.3,
        "skiing" to 7.0,
        "snowboarding" to 5.3,
        "padel" to 6.0,
        "pickleball" to 6.0,
        "bowling" to 3.0,
    )

    /**
     * The MET for a (possibly free-typed) sport label, or null for an off-catalogue sport /
     * "Other". Case-insensitive, whitespace-trimmed — the same fold the catalogue lookup uses.
     */
    fun met(sport: String): Double? = MET_BY_SPORT[sport.trim().lowercase()]

    /**
     * Reference calories (kcal) for [sport] over [durationMin] at [weightKg]:
     * `MET × weight × hours`, rounded to the nearest whole kcal. null when the sport has no MET or
     * an input is non-positive (never pre-fill a value the dialog's own validation would reject).
     */
    fun referenceCalories(sport: String, durationMin: Int, weightKg: Double): Int? {
        val met = met(sport) ?: return null
        if (durationMin <= 0 || weightKg <= 0.0) return null
        return (met * weightKg * durationMin / 60.0).roundToInt()
    }

    /**
     * Reference average HR (bpm) for [sport] given the user's [hrMax]: a typical session fraction
     * of HR-max mapped linearly from the sport's MET — `min(0.85, 0.45 + 0.035 × MET)` — so light
     * sports sit near 55–60 % and hard mat/interval sports near the 0.85 cap. Rounded to the
     * nearest bpm; null when the sport has no MET or [hrMax] is non-positive.
     */
    fun referenceAvgHr(sport: String, hrMax: Int): Int? {
        val met = met(sport) ?: return null
        if (hrMax <= 0) return null
        val fraction = min(0.85, 0.45 + 0.035 * met)
        return (fraction * hrMax).roundToInt()
    }
}
