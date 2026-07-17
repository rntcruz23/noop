import XCTest
@testable import StrandAnalytics

/// Pins the manual-sheet reference pre-fill values (Avg HR / Calories). The expected numbers here
/// are duplicated verbatim in the Android `ManualWorkoutEstimatesTest` — the two tests together ARE
/// the cross-platform parity contract (same MET table, same formulas, same rounding), so a change
/// that moves one platform's numbers must move both tests in the same PR.
final class ManualWorkoutEstimatesTests: XCTestCase {

    func testReferenceCaloriesMatchesMetFormula() {
        // 10.3 MET × 75 kg × 1 h = 772.5 → 773 (round half up, same as Kotlin roundToInt).
        XCTAssertEqual(ManualWorkoutEstimates.referenceCalories(sport: "Jiu-Jitsu", durationMin: 60, weightKg: 75), 773)
        // 3.5 × 70 × 0.5 h = 122.5 → 123.
        XCTAssertEqual(ManualWorkoutEstimates.referenceCalories(sport: "Walking", durationMin: 30, weightKg: 70), 123)
        // 9.8 × 80 × 0.75 h = 588.
        XCTAssertEqual(ManualWorkoutEstimates.referenceCalories(sport: "Running", durationMin: 45, weightKg: 80), 588)
    }

    func testReferenceAvgHrMatchesFractionOfHrMax() {
        // Jiu-Jitsu: min(0.85, 0.45 + 0.035×10.3) = 0.8105; × 187 = 151.56 → 152.
        XCTAssertEqual(ManualWorkoutEstimates.referenceAvgHr(sport: "Jiu-Jitsu", hrMax: 187), 152)
        // Walking: 0.45 + 0.035×3.5 = 0.5725; × 187 = 107.06 → 107.
        XCTAssertEqual(ManualWorkoutEstimates.referenceAvgHr(sport: "Walking", hrMax: 187), 107)
    }

    func testMartialArtsFamilySharesOneMet() {
        for sport in ["Martial arts", "Jiu-Jitsu", "MMA", "Judo", "Karate",
                      "Kickboxing", "Muay Thai", "Taekwondo"] {
            XCTAssertEqual(ManualWorkoutEstimates.met(for: sport), 10.3, "\(sport) rides the Compendium 10.3")
        }
        XCTAssertEqual(ManualWorkoutEstimates.met(for: "Wrestling"), 6.0)
        XCTAssertEqual(ManualWorkoutEstimates.met(for: "Boxing"), 7.8)
    }

    func testLookupIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(ManualWorkoutEstimates.met(for: "  JIU-jitsu "), 10.3)
        XCTAssertEqual(ManualWorkoutEstimates.referenceAvgHr(sport: "muay THAI", hrMax: 187), 152)
    }

    func testNoReferenceForOtherFreeTextOrInvalidInputs() {
        // "Other" and off-catalogue sports have no honest reference — the fields stay blank.
        XCTAssertNil(ManualWorkoutEstimates.met(for: "Other"))
        XCTAssertNil(ManualWorkoutEstimates.referenceCalories(sport: "Zumba", durationMin: 60, weightKg: 75))
        XCTAssertNil(ManualWorkoutEstimates.referenceAvgHr(sport: "Zumba", hrMax: 187))
        // Non-positive inputs never pre-fill a value the sheet's validation would reject.
        XCTAssertNil(ManualWorkoutEstimates.referenceCalories(sport: "Running", durationMin: 0, weightKg: 75))
        XCTAssertNil(ManualWorkoutEstimates.referenceCalories(sport: "Running", durationMin: 60, weightKg: 0))
        XCTAssertNil(ManualWorkoutEstimates.referenceAvgHr(sport: "Running", hrMax: 0))
    }

    func testEveryTabledMetYieldsInRangeValues() {
        // Whatever the table holds, the pre-fill must satisfy the sheet's own validation
        // (HR 25–250, kcal 0–20,000) for sane profile inputs.
        for (sport, _) in ManualWorkoutEstimates.metBySport {
            let hr = ManualWorkoutEstimates.referenceAvgHr(sport: sport, hrMax: 187)
            XCTAssertNotNil(hr)
            XCTAssertTrue((25...250).contains(hr!), "\(sport) HR \(hr!) out of range")
            let kcal = ManualWorkoutEstimates.referenceCalories(sport: sport, durationMin: 60, weightKg: 75)
            XCTAssertNotNil(kcal)
            XCTAssertTrue((0...20_000).contains(kcal!), "\(sport) kcal \(kcal!) out of range")
        }
    }
}
