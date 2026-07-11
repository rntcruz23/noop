package com.noop.protocol

// EXPERIMENTAL (#174 / #103): one WHOOP 5.0/MG session distilled into a per-feature verdict — the
// "protocol health check" a 5/MG owner runs to see whether NOOP's implemented 5/MG paths
// (handshake, bond, live HR, clock, CRC framing, command channel, R22 unlock, history offload,
// type-47 decode) actually work against THEIR strap and firmware, and to produce a shareable
// report for the deep-data tracking issue.
//
// Direct twin of the Swift `Whoop5SessionAudit` (Packages/WhoopProtocol). Pure aggregation: no
// Bluetooth, no clock reads, no IO — it only counts what the client feeds it — so it unit-tests on
// the JVM, and `report()` output is BYTE-IDENTICAL to the Swift twin for the same event sequence
// (asserted by the shared parity fixture in Whoop5SessionAuditTest / Whoop5SessionAuditTests).
// Nothing here writes to a strap: the audit OBSERVES the session the client was already having.
//
// Not thread-safe by design — the owner (WhoopBleClient) feeds it from its own single GATT
// callback context, matching how the rest of the session state is mutated.
class Whoop5SessionAudit {

    companion object {
        /** Type-47 layout versions the historical decoder can decode today. v26 is the raw-PPG
         *  block: it parses (so it is "mapped") but stores no per-second rows by design. Keep in
         *  lockstep with the decoder's version dispatch and the Swift twin. */
        val MAPPED_HISTORICAL_VERSIONS: Set<Int> = setOf(18, 20, 21, 26)
    }

    enum class Verdict(val tag: String) {
        PASS("[PASS]"), PARTIAL("[PART]"), FAIL("[FAIL]"), SKIP("[SKIP]")
    }

    /** One rendered check row: a stable snake_case id (shared with the Swift twin), the verdict,
     *  and a deterministic English detail line (report-stable, like log lines — the UI localizes
     *  its own labels instead). */
    data class Check(val id: String, val verdict: Verdict, val detail: String)

    /** Value snapshot for UI publication: recompute after each feed, publish only when changed. */
    data class Snapshot(
        val checks: List<Check>,
        val framesOK: Int,
        val framesBad: Int,
        val liveHRSamples: Int,
        val commandAcks: Int,
        val r22Acks: Int,
        val r22Total: Int,
        val offloadsCompleted: Int,
        val offloadsTimedOut: Int,
        val bankedRows: Int,
        val rejectedRecords: Int,
        val histVersionCounts: Map<Int, Int>,
    )

    enum class OffloadReason { COMPLETED, TIMED_OUT }

    // Fed state

    private var handshakeSeen = false
    private var bondReported = false
    private var encryptedBond = false
    private var liveHRSamples = 0
    private var clockCorrelated = false
    private var framesOK = 0
    private var framesBad = 0
    private var commandAcks = 0
    private var r22Attempted = false
    private var r22Total = 0
    private var r22Acks = 0
    private var offloadsCompleted = 0
    private var offloadsTimedOut = 0
    private var bankedRows = 0
    private var rejectedRecords = 0
    private val histVersionCounts = mutableMapOf<Int, Int>()

    /** Fresh run — the client calls this when the user starts a check. */
    fun reset() {
        handshakeSeen = false
        bondReported = false
        encryptedBond = false
        liveHRSamples = 0
        clockCorrelated = false
        framesOK = 0
        framesBad = 0
        commandAcks = 0
        r22Attempted = false
        r22Total = 0
        r22Acks = 0
        offloadsCompleted = 0
        offloadsTimedOut = 0
        bankedRows = 0
        rejectedRecords = 0
        histVersionCounts.clear()
    }

    // Feed events (each maps to ONE existing client seam)

    /** The 5/MG post-bond branch completed the CLIENT_HELLO handshake. */
    fun noteHandshake() { handshakeSeen = true }

    /** Bond state became known. `encrypted=false` is the live-HR-only link (#69/#266): the strap
     *  is reachable but still owned by the official app. */
    fun noteBond(encrypted: Boolean) {
        bondReported = true
        if (encrypted) encryptedBond = true
    }

    /** One standard-profile (0x2A37) heart-rate sample landed. */
    fun noteLiveHeartRateSample() { liveHRSamples += 1 }

    /** The strap answered GET_CLOCK (on a 5/MG the reply rides the puffin notify chars; timestamps
     *  are already real unix, so a reply IS the proof the clock path works). */
    fun noteClockCorrelated() { clockCorrelated = true }

    /** One reassembled puffin frame, CRC-verified by the caller (family-aware verifyFrame).
     *  `typeByte` = frame[8], `versionByte` = frame[9] (only meaningful for type 47). */
    fun notePuffinFrame(crcOK: Boolean, typeByte: Int, versionByte: Int) {
        if (crcOK) framesOK += 1 else framesBad += 1
        if (!crcOK) return
        if (typeByte == 0x24) commandAcks += 1
        if (typeByte == 47) histVersionCounts[versionByte] = (histVersionCounts[versionByte] ?: 0) + 1
    }

    /** The enable_r22 SET_CONFIG sequence was sent (`totalFlags` = Whoop5Config.enableR22Sequence.size). */
    fun noteR22SequenceSent(totalFlags: Int) {
        r22Attempted = true
        r22Total = totalFlags
        r22Acks = 0
    }

    /** The strap ACKed one enable_r22 flag (COMMAND_RESPONSE to SET_CONFIG). */
    fun noteR22FlagAck() { r22Acks += 1 }

    /** One offload session ended. `rejectedRecordsThisConnection` is the connection-cumulative
     *  undecodable-record tally at exit time (latest value wins — not summed). */
    fun noteOffloadEnded(reason: OffloadReason, bankedRows: Int, rejectedRecordsThisConnection: Int) {
        when (reason) {
            OffloadReason.COMPLETED -> offloadsCompleted += 1
            OffloadReason.TIMED_OUT -> offloadsTimedOut += 1
        }
        this.bankedRows += bankedRows
        rejectedRecords = maxOf(rejectedRecords, rejectedRecordsThisConnection)
    }

    // Verdicts

    private val anyFrames: Boolean get() = framesOK + framesBad > 0

    private fun checkHandshake(): Check =
        if (handshakeSeen) Check("handshake", Verdict.PASS, "CLIENT_HELLO completed")
        else Check("handshake", Verdict.SKIP, "no 5/MG connection this run yet")

    private fun checkBond(): Check = when {
        encryptedBond -> Check("bond", Verdict.PASS, "encrypted bond established")
        bondReported -> Check("bond", Verdict.PARTIAL,
            "live-HR-only link (no encrypted bond; deep features unavailable)")
        else -> Check("bond", Verdict.SKIP, "no bond attempt seen yet")
    }

    private fun checkLiveHR(): Check =
        if (liveHRSamples > 0) Check("live_hr", Verdict.PASS,
            "$liveHRSamples samples over the standard 0x2A37 profile")
        else Check("live_hr", Verdict.SKIP, "no live HR samples yet")

    private fun checkClock(): Check = when {
        clockCorrelated -> Check("clock", Verdict.PASS, "GET_CLOCK reply received")
        encryptedBond && anyFrames -> Check("clock", Verdict.FAIL,
            "bonded but no GET_CLOCK reply; history cannot be dated")
        else -> Check("clock", Verdict.SKIP, "needs the encrypted bond first")
    }

    private fun checkFraming(): Check = when {
        !anyFrames -> Check("framing", Verdict.SKIP, "no puffin frames seen yet")
        framesBad == 0 -> Check("framing", Verdict.PASS, "$framesOK frames CRC-verified, 0 failed")
        framesOK == 0 -> Check("framing", Verdict.FAIL,
            "all $framesBad frames failed CRC; framing mismatch, share a capture")
        else -> Check("framing", Verdict.PARTIAL, "$framesOK frames CRC-verified, $framesBad failed")
    }

    private fun checkCommands(): Check = when {
        commandAcks > 0 -> Check("commands", Verdict.PASS, "$commandAcks COMMAND_RESPONSE acks")
        encryptedBond && anyFrames -> Check("commands", Verdict.FAIL,
            "no COMMAND_RESPONSE seen despite the encrypted bond")
        else -> Check("commands", Verdict.SKIP, "no command acks yet")
    }

    private fun checkR22(): Check = when {
        !r22Attempted -> Check("r22_unlock", Verdict.SKIP,
            "not attempted (Settings > Experimental > deep data)")
        r22Acks >= r22Total && r22Total > 0 -> Check("r22_unlock", Verdict.PASS,
            "$r22Acks/$r22Total enable_r22 flags acked")
        r22Acks == 0 -> Check("r22_unlock", Verdict.FAIL,
            "sequence sent but 0/$r22Total flags acked")
        else -> Check("r22_unlock", Verdict.PARTIAL, "$r22Acks/$r22Total enable_r22 flags acked")
    }

    private fun checkOffload(): Check {
        val sessions = offloadsCompleted + offloadsTimedOut
        if (sessions == 0) return Check("offload", Verdict.SKIP, "no offload session yet")
        val detail = "completed=$offloadsCompleted timeouts=$offloadsTimedOut banked_rows=$bankedRows"
        return if (bankedRows > 0) Check("offload", Verdict.PASS, detail)
        else Check("offload", Verdict.PARTIAL, "$detail (empty offload; see #580)")
    }

    private fun checkDecode(): Check {
        if (histVersionCounts.isEmpty()) {
            return Check("decode", Verdict.SKIP, "no type-47 records seen yet")
        }
        val unmapped = histVersionCounts.keys.filter { it !in MAPPED_HISTORICAL_VERSIONS }.sorted()
        val problems = mutableListOf<String>()
        if (unmapped.isNotEmpty()) {
            problems.add("unmapped layout(s): " + unmapped.joinToString(",") { "v$it" })
        }
        if (rejectedRecords > 0) {
            problems.add("$rejectedRecords records not decodable")
        }
        if (problems.isEmpty()) {
            var detail = "all type-47 layouts mapped"
            if (26 in histVersionCounts) detail += " (v26 is raw PPG; stores no rows by design)"
            return Check("decode", Verdict.PASS, detail)
        }
        return Check("decode", Verdict.PARTIAL,
            problems.joinToString("; ") + "; share a strap log/capture (#103)")
    }

    /** All checks, fixed order (report + UI both render this order). */
    val checks: List<Check>
        get() = listOf(checkHandshake(), checkBond(), checkLiveHR(), checkClock(), checkFraming(),
            checkCommands(), checkR22(), checkOffload(), checkDecode())

    fun snapshot(): Snapshot = Snapshot(
        checks = checks,
        framesOK = framesOK, framesBad = framesBad,
        liveHRSamples = liveHRSamples, commandAcks = commandAcks,
        r22Acks = r22Acks, r22Total = r22Total,
        offloadsCompleted = offloadsCompleted, offloadsTimedOut = offloadsTimedOut,
        bankedRows = bankedRows, rejectedRecords = rejectedRecords,
        histVersionCounts = histVersionCounts.toMap(),
    )

    /** The shareable plain-text report. Deterministic and BYTE-IDENTICAL with the Swift twin for
     *  the same event sequence (parity-tested), so reports are comparable regardless of platform. */
    fun report(): String {
        val lines = mutableListOf<String>()
        lines.add("NOOP WHOOP 5/MG PROTOCOL CHECK (experimental)")
        lines.add("schema=1")
        val all = checks
        for (c in all) lines.add("${c.verdict.tag} ${c.id}: ${c.detail}")
        val tally = all.groupingBy { it.verdict }.eachCount()
        lines.add("summary: pass=${tally[Verdict.PASS] ?: 0} partial=${tally[Verdict.PARTIAL] ?: 0}" +
            " fail=${tally[Verdict.FAIL] ?: 0} skipped=${tally[Verdict.SKIP] ?: 0}")
        if (histVersionCounts.isNotEmpty()) {
            val hist = histVersionCounts.keys.sorted().joinToString(" ") { "v$it=${histVersionCounts[it]}" }
            lines.add("hist_versions: $hist")
        }
        lines.add("counters: frames_ok=$framesOK frames_bad=$framesBad" +
            " live_hr=$liveHRSamples cmd_acks=$commandAcks" +
            " r22_acks=$r22Acks/$r22Total" +
            " offloads=${offloadsCompleted + offloadsTimedOut}" +
            " banked_rows=$bankedRows rejected=$rejectedRecords")
        lines.add("Share this report (with your strap log) on the WHOOP 5/MG deep-data issue: #103")
        return lines.joinToString("\n")
    }
}
