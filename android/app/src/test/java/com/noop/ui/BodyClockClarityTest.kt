package com.noop.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale
import java.util.TimeZone

class BodyClockClarityTest {
    @Test
    fun estimatedWindowUsesLocaleAwareClockStyle() {
        val oldLocale = Locale.getDefault()
        val oldZone = TimeZone.getDefault()
        try {
            Locale.setDefault(Locale.US)
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            assertEquals("23:30", clockHourLabel(23.5, is24h = true))
            assertEquals("11:30 PM", clockHourLabel(23.5, is24h = false))
            assertEquals("6:15 AM", clockHourLabel(6.25, is24h = false))
        } finally {
            Locale.setDefault(oldLocale)
            TimeZone.setDefault(oldZone)
        }
    }
}
