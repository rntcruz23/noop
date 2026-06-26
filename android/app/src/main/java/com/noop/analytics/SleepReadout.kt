package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample

// SleepReadout.kt - Kotlin twin of SleepReadout.swift. Pure values for the Sleep live-readout
// panel. No state, no IO, no em-dashes.

object SleepReadout {
    /** HR samples per minute over the stream's own span. 0 when fewer than 2 samples. */
    fun hrDensityPerMinute(hr: List<HrSample>): Double {
        if (hr.size < 2) return 0.0
        val sorted = hr.sortedBy { it.ts }
        val spanS = (sorted.last().ts - sorted.first().ts).toDouble()
        if (spanS <= 0) return 0.0
        return sorted.size / (spanS / 60.0)
    }

    /** Fraction of the HR window the gravity stream spans, in [0, 1]. Below SleepStager's
     *  sparseGravitySpanFrac means tonight's gravity is sparse. */
    fun gravityCoverageFraction(gravity: List<GravitySample>, hr: List<HrSample>): Double {
        if (gravity.size < 2 || hr.size < 2) return 0.0
        val g = gravity.sortedBy { it.ts }
        val h = hr.sortedBy { it.ts }
        val hrSpan = (h.last().ts - h.first().ts).toDouble()
        if (hrSpan <= 0) return 0.0
        val gravSpan = (g.last().ts - g.first().ts).toDouble()
        return maxOf(0.0, minOf(1.0, gravSpan / hrSpan))
    }

    /** The gate named by the most recent gate-trace line in the tagged log tail, or null. */
    fun lastGateFired(taggedTail: List<String>): String? {
        for (line in taggedTail.asReversed()) {
            val idx = line.indexOf("gate=")
            if (idx < 0) continue
            val after = line.substring(idx + "gate=".length)
            val token = after.takeWhile { it != ' ' }
            if (token.isNotEmpty()) return token
        }
        return null
    }
}
