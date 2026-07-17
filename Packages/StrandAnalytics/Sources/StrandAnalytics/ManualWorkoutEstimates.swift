import Foundation

/// Reference pre-fill values for the manual workout sheet's optional Avg HR / Calories fields.
///
/// When a workout is logged by hand there is no HR trace to feed `Calories.estimateBoutCalories`,
/// so the sheet pre-fills a plainly-editable REFERENCE value instead of leaving the fields blank:
///  - Calories from the classic MET formula (1 MET ≈ 1 kcal/kg/h): `MET × weight(kg) × hours`,
///    using a fixed Compendium-of-Physical-Activities-style MET per catalogue sport.
///  - Avg HR as a typical fraction of the user's HR-max (itself age-derived via Tanaka unless
///    overridden), mapped from the same MET so one table drives both numbers.
///
/// APPROXIMATE — a starting point the user is expected to adjust, not a measurement. The values
/// never feed a downstream gate on their own: they land in the same optional avgHr/energyKcal
/// fields the user could have typed, strain stays null (`buildManualRow` never fabricates one),
/// and the #598 rescore replaces them with real strap-derived numbers whenever the strap actually
/// covered the window.
///
/// PARITY: mirrored byte-for-byte by Android `ManualWorkoutEstimates.kt` — same MET table, same
/// formulas, same rounding — so a manual workout pre-filled on either platform reads identically.
public enum ManualWorkoutEstimates {

    /// MET by catalogue sport (lowercased `WorkoutCatalog` / `WorkoutSport` name). Off-catalogue
    /// free-text sports and the generic "Other" are absent on purpose: no honest reference exists,
    /// so the fields stay blank. Values follow the Compendium of Physical Activities (general /
    /// moderate effort codes), lightly rounded.
    static let metBySport: [String: Double] = [
        "running": 9.8,
        "walking": 3.5,
        "hiking": 6.0,
        "cycling": 7.5,
        "open-water swim": 8.0,
        "rowing": 7.0,
        "treadmill run": 9.0,
        "treadmill walk": 3.8,
        "indoor cycle": 7.0,
        "pool swim": 7.0,
        "row machine": 7.0,
        "elliptical": 5.0,
        "strength": 5.0,
        "bodybuilding": 5.0,
        "weightlifting": 5.0,
        "hiit": 8.0,
        "yoga": 3.0,
        "pilates": 3.0,
        "boxing": 7.8,
        "basketball": 6.5,
        "soccer": 7.0,
        "baseball": 5.0,
        "ice hockey": 8.0,
        "badminton": 5.5,
        "tennis": 7.3,
        "squash": 9.0,
        "racquetball": 7.0,
        "table tennis": 4.0,
        "volleyball": 4.0,
        // The martial-arts family shares the Compendium's 10.3 (judo/jujitsu/karate/kick boxing/
        // tae kwan do code); wrestling has its own lower match-play code.
        "martial arts": 10.3,
        "jiu-jitsu": 10.3,
        "mma": 10.3,
        "judo": 10.3,
        "karate": 10.3,
        "kickboxing": 10.3,
        "muay thai": 10.3,
        "taekwondo": 10.3,
        "wrestling": 6.0,
        "dancing": 5.5,
        "golf": 4.8,
        "climbing": 8.0,
        "stretching": 2.3,
        "skiing": 7.0,
        "snowboarding": 5.3,
        "padel": 6.0,
        "pickleball": 6.0,
        "bowling": 3.0,
    ]

    /// The MET for a (possibly free-typed) sport label, or nil for an off-catalogue sport / "Other".
    /// Case-insensitive, whitespace-trimmed — the same fold the catalogue lookup uses.
    public static func met(for sport: String) -> Double? {
        metBySport[sport.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Reference calories (kcal) for `sport` over `durationMin` at `weightKg`:
    /// `MET × weight × hours`, rounded to the nearest whole kcal. nil when the sport has no MET or
    /// an input is non-positive (never pre-fill a value the sheet's own validation would reject).
    public static func referenceCalories(sport: String, durationMin: Int, weightKg: Double) -> Int? {
        guard let met = met(for: sport), durationMin > 0, weightKg > 0 else { return nil }
        return Int((met * weightKg * Double(durationMin) / 60.0).rounded())
    }

    /// Reference average HR (bpm) for `sport` given the user's `hrMax`: a typical session fraction
    /// of HR-max mapped linearly from the sport's MET — `min(0.85, 0.45 + 0.035 × MET)` — so light
    /// sports sit near 55–60 % and hard mat/interval sports near the 0.85 cap. Rounded to the
    /// nearest bpm; nil when the sport has no MET or `hrMax` is non-positive.
    public static func referenceAvgHr(sport: String, hrMax: Int) -> Int? {
        guard let met = met(for: sport), hrMax > 0 else { return nil }
        let fraction = min(0.85, 0.45 + 0.035 * met)
        return Int((fraction * Double(hrMax)).rounded())
    }
}
