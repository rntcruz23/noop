package com.noop.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Verdict + report tests for the WHOOP 5/MG protocol health check — twin of the Swift
 * `Whoop5SessionAuditTests`.
 *
 * `reportParityFixture` is the CROSS-PLATFORM CONTRACT: the Swift twin replays the exact same
 * event sequence and asserts the exact same bytes, so a report is comparable no matter which
 * platform produced it. Change one, change both.
 */
class Whoop5SessionAuditTest {

    private fun verdict(a: Whoop5SessionAudit, id: String): Whoop5SessionAudit.Verdict? =
        a.checks.firstOrNull { it.id == id }?.verdict

    @Test
    fun freshRunIsAllSkipped() {
        val a = Whoop5SessionAudit()
        assertEquals(9, a.checks.size)
        a.checks.forEach { assertEquals("fresh run should skip ${it.id}", Whoop5SessionAudit.Verdict.SKIP, it.verdict) }
    }

    @Test
    fun healthySessionAllPass() {
        val a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted = true)
        repeat(10) { a.noteLiveHeartRateSample() }
        a.noteClockCorrelated()
        a.notePuffinFrame(crcOK = true, typeByte = 0x24, versionByte = 0)
        a.notePuffinFrame(crcOK = true, typeByte = 0x24, versionByte = 0)
        repeat(5) { a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 18) }
        a.noteR22SequenceSent(totalFlags = 16)
        repeat(16) { a.noteR22FlagAck() }
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.COMPLETED, bankedRows = 5, rejectedRecordsThisConnection = 0)

        a.checks.forEach {
            assertEquals("${it.id} should pass: ${it.detail}", Whoop5SessionAudit.Verdict.PASS, it.verdict)
        }
    }

    @Test
    fun liveHROnlyLinkIsPartialBond() {
        val a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted = false)   // #69/#266 live-HR-only shortcut
        a.noteLiveHeartRateSample()
        assertEquals(Whoop5SessionAudit.Verdict.PARTIAL, verdict(a, "bond"))
        assertEquals(Whoop5SessionAudit.Verdict.SKIP, verdict(a, "clock"))   // clock needs the bond
        assertEquals(Whoop5SessionAudit.Verdict.PASS, verdict(a, "live_hr")) // live HR works without a bond
    }

    @Test
    fun bondedButSilentCommandChannelFails() {
        val a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted = true)
        repeat(3) { a.notePuffinFrame(crcOK = true, typeByte = 40, versionByte = 0) }
        assertEquals(Whoop5SessionAudit.Verdict.FAIL, verdict(a, "commands"))
        assertEquals(Whoop5SessionAudit.Verdict.FAIL, verdict(a, "clock"))
    }

    @Test
    fun crcFailuresGradeFraming() {
        val a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK = false, typeByte = 0, versionByte = 0)
        assertEquals(Whoop5SessionAudit.Verdict.FAIL, verdict(a, "framing"))
        a.notePuffinFrame(crcOK = true, typeByte = 40, versionByte = 0)
        assertEquals(Whoop5SessionAudit.Verdict.PARTIAL, verdict(a, "framing"))
    }

    @Test
    fun badCRCFrameCountsNothingElse() {
        val a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK = false, typeByte = 0x24, versionByte = 18)
        assertEquals(Whoop5SessionAudit.Verdict.SKIP, verdict(a, "commands"))
        assertEquals(Whoop5SessionAudit.Verdict.SKIP, verdict(a, "decode"))
    }

    @Test
    fun r22Verdicts() {
        val a = Whoop5SessionAudit()
        assertEquals(Whoop5SessionAudit.Verdict.SKIP, verdict(a, "r22_unlock"))
        a.noteR22SequenceSent(totalFlags = 16)
        assertEquals(Whoop5SessionAudit.Verdict.FAIL, verdict(a, "r22_unlock"))
        repeat(9) { a.noteR22FlagAck() }
        assertEquals(Whoop5SessionAudit.Verdict.PARTIAL, verdict(a, "r22_unlock"))
        repeat(7) { a.noteR22FlagAck() }
        assertEquals(Whoop5SessionAudit.Verdict.PASS, verdict(a, "r22_unlock"))
        // A fresh attempt restarts the count (mirrors r22FlagsAccepted reset).
        a.noteR22SequenceSent(totalFlags = 16)
        assertEquals(Whoop5SessionAudit.Verdict.FAIL, verdict(a, "r22_unlock"))
    }

    @Test
    fun emptyOffloadIsPartialNotFail() {
        val a = Whoop5SessionAudit()
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.TIMED_OUT, bankedRows = 0, rejectedRecordsThisConnection = 0)
        val c = a.checks.first { it.id == "offload" }
        assertEquals(Whoop5SessionAudit.Verdict.PARTIAL, c.verdict)   // the #580 case — honest, not an error
        assertTrue(c.detail.contains("#580"))
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.COMPLETED, bankedRows = 12, rejectedRecordsThisConnection = 0)
        assertEquals(Whoop5SessionAudit.Verdict.PASS, verdict(a, "offload"))
    }

    @Test
    fun unmappedLayoutAndRejectsArePartialDecode() {
        val a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 18)
        assertEquals(Whoop5SessionAudit.Verdict.PASS, verdict(a, "decode"))
        a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 33)   // unknown layout
        val c = a.checks.first { it.id == "decode" }
        assertEquals(Whoop5SessionAudit.Verdict.PARTIAL, c.verdict)
        assertTrue(c.detail.contains("v33"))
        assertTrue(c.detail.contains("#103"))
    }

    @Test
    fun v26OnlyIsPassWithPPGNote() {
        val a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 26)
        val c = a.checks.first { it.id == "decode" }
        assertEquals(Whoop5SessionAudit.Verdict.PASS, c.verdict)
        assertTrue(c.detail.contains("raw PPG"))
    }

    @Test
    fun rejectedRecordsUseLatestValueNotSum() {
        val a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 18)
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.COMPLETED, bankedRows = 1, rejectedRecordsThisConnection = 3)
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.COMPLETED, bankedRows = 1, rejectedRecordsThisConnection = 3)
        assertEquals(3, a.snapshot().rejectedRecords)
    }

    @Test
    fun resetClearsEverything() {
        val a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted = true)
        a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 18)
        a.reset()
        a.checks.forEach { assertEquals(Whoop5SessionAudit.Verdict.SKIP, it.verdict) }
        assertEquals(Whoop5SessionAudit().snapshot(), a.snapshot())
    }

    @Test
    fun snapshotEqualityDrivesPublishing() {
        val a = Whoop5SessionAudit()
        val s1 = a.snapshot()
        assertEquals(s1, a.snapshot())
        a.noteLiveHeartRateSample()
        assertNotEquals(s1, a.snapshot())
    }

    /** THE cross-platform fixture — same events, same bytes as the Swift twin's
     *  `testReportParityFixture`. */
    @Test
    fun reportParityFixture() {
        val a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted = true)
        repeat(642) { a.noteLiveHeartRateSample() }
        a.noteClockCorrelated()
        repeat(18) { a.notePuffinFrame(crcOK = true, typeByte = 0x24, versionByte = 0) }
        repeat(780) { a.notePuffinFrame(crcOK = true, typeByte = 40, versionByte = 0) }
        repeat(12) { a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 18) }
        repeat(2) { a.notePuffinFrame(crcOK = true, typeByte = 47, versionByte = 33) }
        a.notePuffinFrame(crcOK = false, typeByte = 0, versionByte = 0)
        a.noteR22SequenceSent(totalFlags = 16)
        repeat(9) { a.noteR22FlagAck() }
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.TIMED_OUT, bankedRows = 0, rejectedRecordsThisConnection = 0)
        a.noteOffloadEnded(Whoop5SessionAudit.OffloadReason.COMPLETED, bankedRows = 12, rejectedRecordsThisConnection = 2)

        val expected = listOf(
            "NOOP WHOOP 5/MG PROTOCOL CHECK (experimental)",
            "schema=1",
            "[PASS] handshake: CLIENT_HELLO completed",
            "[PASS] bond: encrypted bond established",
            "[PASS] live_hr: 642 samples over the standard 0x2A37 profile",
            "[PASS] clock: GET_CLOCK reply received",
            "[PART] framing: 812 frames CRC-verified, 1 failed",
            "[PASS] commands: 18 COMMAND_RESPONSE acks",
            "[PART] r22_unlock: 9/16 enable_r22 flags acked",
            "[PASS] offload: completed=1 timeouts=1 banked_rows=12",
            "[PART] decode: unmapped layout(s): v33; 2 records not decodable; share a strap log/capture (#103)",
            "summary: pass=6 partial=3 fail=0 skipped=0",
            "hist_versions: v18=12 v33=2",
            "counters: frames_ok=812 frames_bad=1 live_hr=642 cmd_acks=18 r22_acks=9/16 offloads=2 banked_rows=12 rejected=2",
            "Share this report (with your strap log) on the WHOOP 5/MG deep-data issue: #103",
        ).joinToString("\n")
        assertEquals(expected, a.report())
    }
}
