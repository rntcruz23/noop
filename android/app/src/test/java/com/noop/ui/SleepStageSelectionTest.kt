package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepStageSelectionTest {
    @Test
    fun noSelectionLeavesEveryStageAtFullAlpha() {
        assertEquals(1f, stageSelectionAlpha("REM", null), 0f)
        assertFalse(stageSelectionVisual("REM", null).selected)
        assertFalse(stageSelectionVisual("REM", null).dimmed)
    }

    @Test
    fun selectedStageStaysBrightAndOtherStagesDim() {
        val selected = stageSelectionVisual("rem", "REM")
        val other = stageSelectionVisual("Deep", "REM")

        assertTrue(selected.selected)
        assertEquals(1f, selected.alpha, 0f)
        assertTrue(other.dimmed)
        assertEquals(0.28f, other.alpha, 0f)
    }

    @Test
    fun wakeAndAwakeShareSelectionIdentity() {
        assertTrue(stageSelectionVisual("wake", "Awake").selected)
    }
}