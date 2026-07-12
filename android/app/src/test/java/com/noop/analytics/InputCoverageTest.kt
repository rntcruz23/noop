package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Coverage classification + summary tests — twin of the Swift `InputCoverageTests`.
 * `summaryParityFixture` is the CROSS-PLATFORM CONTRACT: the Swift twin classifies the same
 * counts and asserts the same summary bytes. Change one, change both.
 */
class InputCoverageTest {

    @Test
    fun thresholdBoundaries() {
        val rows = InputCoverage.classify(
            mapOf(
                "hr" to 3600,        // exactly the regular threshold
                "rr" to 119,         // one under -> sparse
                "motion" to 1,       // any trickle -> sparse
                "skin_temp" to 0,    // explicit zero -> missing
                // resp/spo2/steps omitted -> missing
            ),
        )
        val byId = rows.associate { it.id to it.status }
        assertEquals(InputCoverage.Status.REGULAR, byId["hr"])
        assertEquals(InputCoverage.Status.SPARSE, byId["rr"])
        assertEquals(InputCoverage.Status.SPARSE, byId["motion"])
        assertEquals(InputCoverage.Status.MISSING, byId["skin_temp"])
        assertEquals(InputCoverage.Status.MISSING, byId["resp"])
        assertEquals(InputCoverage.Status.MISSING, byId["spo2"])
        assertEquals(InputCoverage.Status.MISSING, byId["steps"])
    }

    @Test
    fun rowsKeepFixedDisplayOrder() {
        assertEquals(
            listOf("hr", "rr", "motion", "skin_temp", "resp", "spo2", "steps"),
            InputCoverage.classify(emptyMap()).map { it.id },
        )
    }

    @Test
    fun fetchLimitMatchesRegularThreshold() {
        assertEquals(3600, InputCoverage.fetchLimit("hr"))
        assertEquals(24, InputCoverage.fetchLimit("skin_temp"))
        assertEquals(1, InputCoverage.fetchLimit("nonsense"))   // unknown id stays harmless
    }

    @Test
    fun allMissingCollapsesToNoDataSentence() {
        assertEquals(
            "No sensor data from this strap in the last 24 hours.",
            InputCoverage.summary(InputCoverage.classify(emptyMap())),
        )
    }

    @Test
    fun emptyGroupsAreOmitted() {
        val allRegular = InputCoverage.classify(
            mapOf(
                "hr" to 4000, "rr" to 200, "motion" to 4000, "skin_temp" to 30,
                "resp" to 30, "spo2" to 30, "steps" to 30,
            ),
        )
        assertEquals(
            "Feeding your scores: Heart rate, R-R intervals, Motion, Skin temp, Respiratory, Blood oxygen, Steps.",
            InputCoverage.summary(allRegular),
        )
    }

    /** THE cross-platform fixture — same counts, same bytes as the Swift twin. */
    @Test
    fun summaryParityFixture() {
        val rows = InputCoverage.classify(
            mapOf("hr" to 3600, "rr" to 42, "motion" to 3600, "skin_temp" to 3),
        )
        assertEquals(
            "Feeding your scores: Heart rate, Motion. " +
                "Sparse: R-R intervals, Skin temp. " +
                "Missing: Respiratory, Blood oxygen, Steps.",
            InputCoverage.summary(rows),
        )
    }
}
