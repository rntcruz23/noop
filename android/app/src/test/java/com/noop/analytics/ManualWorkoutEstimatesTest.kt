package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the manual-dialog reference pre-fill values (Avg HR / Calories). The expected numbers here
 * are duplicated verbatim in the Swift `ManualWorkoutEstimatesTests` — the two tests together ARE
 * the cross-platform parity contract (same MET table, same formulas, same rounding), so a change
 * that moves one platform's numbers must move both tests in the same PR.
 */
class ManualWorkoutEstimatesTest {

    @Test fun referenceCalories_matchesMetFormula() {
        // 10.3 MET × 75 kg × 1 h = 772.5 → 773 (round half up, same as Swift .rounded()).
        assertEquals(773, ManualWorkoutEstimates.referenceCalories("Jiu-Jitsu", 60, 75.0))
        // 3.5 × 70 × 0.5 h = 122.5 → 123.
        assertEquals(123, ManualWorkoutEstimates.referenceCalories("Walking", 30, 70.0))
        // 9.8 × 80 × 0.75 h = 588.
        assertEquals(588, ManualWorkoutEstimates.referenceCalories("Running", 45, 80.0))
    }

    @Test fun referenceAvgHr_matchesFractionOfHrMax() {
        // Jiu-Jitsu: min(0.85, 0.45 + 0.035×10.3) = 0.8105; × 187 = 151.56 → 152.
        assertEquals(152, ManualWorkoutEstimates.referenceAvgHr("Jiu-Jitsu", 187))
        // Walking: 0.45 + 0.035×3.5 = 0.5725; × 187 = 107.06 → 107.
        assertEquals(107, ManualWorkoutEstimates.referenceAvgHr("Walking", 187))
    }

    @Test fun martialArtsFamily_sharesOneMet() {
        listOf(
            "Martial arts", "Jiu-Jitsu", "MMA", "Judo", "Karate",
            "Kickboxing", "Muay Thai", "Taekwondo",
        ).forEach { assertEquals("$it rides the Compendium 10.3", 10.3, ManualWorkoutEstimates.met(it)!!, 0.0) }
        assertEquals(6.0, ManualWorkoutEstimates.met("Wrestling")!!, 0.0)
        assertEquals(7.8, ManualWorkoutEstimates.met("Boxing")!!, 0.0)
    }

    @Test fun lookup_isCaseAndWhitespaceInsensitive() {
        assertEquals(10.3, ManualWorkoutEstimates.met("  JIU-jitsu ")!!, 0.0)
        assertEquals(152, ManualWorkoutEstimates.referenceAvgHr("muay THAI", 187))
    }

    @Test fun noReference_forOtherFreeTextOrInvalidInputs() {
        // "Other" and off-catalogue sports have no honest reference — the fields stay blank.
        assertNull(ManualWorkoutEstimates.met("Other"))
        assertNull(ManualWorkoutEstimates.referenceCalories("Zumba", 60, 75.0))
        assertNull(ManualWorkoutEstimates.referenceAvgHr("Zumba", 187))
        // Non-positive inputs never pre-fill a value the dialog's validation would reject.
        assertNull(ManualWorkoutEstimates.referenceCalories("Running", 0, 75.0))
        assertNull(ManualWorkoutEstimates.referenceCalories("Running", 60, 0.0))
        assertNull(ManualWorkoutEstimates.referenceAvgHr("Running", 0))
    }

    /** Every catalogue sport except the generic "Other" carries a MET, so the pre-fill covers the
     *  whole picker; and every pre-fill satisfies the dialog's own validation ranges. */
    @Test fun everyCatalogueSportExceptOther_hasInRangeReferences() {
        WorkoutSport.all.filter { it.name != "Other" }.forEach { sport ->
            val met = ManualWorkoutEstimates.met(sport.name)
            assertNotNull("${sport.name} must have a MET", met)
            val hr = ManualWorkoutEstimates.referenceAvgHr(sport.name, 187)!!
            assertTrue("${sport.name} HR $hr out of range", hr in 25..250)
            val kcal = ManualWorkoutEstimates.referenceCalories(sport.name, 60, 75.0)!!
            assertTrue("${sport.name} kcal $kcal out of range", kcal in 0..20_000)
        }
    }
}
