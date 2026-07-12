package com.noop.analytics

// "What feeds your scores" (#103): classify the last 24 hours of per-stream sensor rows into an
// honest coverage readout — which inputs actually arrived from the active strap, so the analysis
// screens' depth can be judged by evidence rather than assumed. Twin of the Swift
// StrandAnalytics.InputCoverage; the summary string is byte-identical across platforms and pinned
// by parity tests (InputCoverageTest / InputCoverageTests). Pure classification over counts the
// app queries — no database, no Android dependencies.
//
// Thresholds are deliberately coarse diagnostics, not physiology: a strap that syncs once a day
// delivers history in bursts, so "regular" is set well below a full day of samples, and any
// nonzero trickle reads "sparse" rather than being rounded to missing.
object InputCoverage {

    enum class Status { REGULAR, SPARSE, MISSING }

    /** One classified stream: stable id (query key), display label, status, and the (capped)
     *  count that produced it. */
    data class Row(val id: String, val label: String, val status: Status, val count: Int)

    private data class Stream(val id: String, val label: String, val regularPer24h: Int)

    /** Fixed display order. `regularPer24h` doubles as the query cap: fetching `fetchLimit(id)`
     *  rows is exactly enough to decide "regular", so no caller ever pulls an unbounded day of
     *  ~1 Hz samples to render one card row. */
    private val STREAMS = listOf(
        Stream("hr", "Heart rate", 3600),          // ~1 Hz banked; an hour's worth in 24 h = regular
        Stream("rr", "R-R intervals", 120),        // sparse by nature on the history path
        Stream("motion", "Motion", 3600),          // v18 gravity is per-second alongside HR
        Stream("skin_temp", "Skin temp", 24),      // ~minutes cadence, overnight-weighted
        Stream("resp", "Respiratory", 24),
        Stream("spo2", "Blood oxygen", 24),
        Stream("steps", "Steps", 24),
    )

    val streamIds: List<String> get() = STREAMS.map { it.id }

    /** How many rows a caller needs to fetch (at most) for [id] — the "regular" threshold. */
    fun fetchLimit(id: String): Int = STREAMS.firstOrNull { it.id == id }?.regularPer24h ?: 1

    /** Classify per-stream counts (missing keys read as 0). Counts may be capped at [fetchLimit]. */
    fun classify(counts: Map<String, Int>): List<Row> = STREAMS.map { s ->
        val n = counts[s.id] ?: 0
        val status = when {
            n >= s.regularPer24h -> Status.REGULAR
            n > 0 -> Status.SPARSE
            else -> Status.MISSING
        }
        Row(s.id, s.label, status, n)
    }

    /** The one-line honest readout, byte-identical across platforms (parity-tested):
     *  "Feeding your scores: Heart rate, Motion. Sparse: R-R intervals. Missing: Blood oxygen."
     *  Empty groups are omitted; all-missing collapses to the no-data sentence. */
    fun summary(rows: List<Row>): String {
        val regular = rows.filter { it.status == Status.REGULAR }.map { it.label }
        val sparse = rows.filter { it.status == Status.SPARSE }.map { it.label }
        val missing = rows.filter { it.status == Status.MISSING }.map { it.label }
        if (regular.isEmpty() && sparse.isEmpty()) {
            return "No sensor data from this strap in the last 24 hours."
        }
        val parts = mutableListOf<String>()
        if (regular.isNotEmpty()) parts.add("Feeding your scores: " + regular.joinToString(", ") + ".")
        if (sparse.isNotEmpty()) parts.add("Sparse: " + sparse.joinToString(", ") + ".")
        if (missing.isNotEmpty()) parts.add("Missing: " + missing.joinToString(", ") + ".")
        return parts.joinToString(" ")
    }
}
