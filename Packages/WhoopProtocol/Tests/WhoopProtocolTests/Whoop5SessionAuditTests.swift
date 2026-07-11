import XCTest
@testable import WhoopProtocol

/// Verdict + report tests for the WHOOP 5/MG protocol health check.
///
/// The `testReportParityFixture` report string is the CROSS-PLATFORM CONTRACT: the Android twin
/// (Whoop5SessionAuditTest.kt) replays the exact same event sequence and asserts the exact same
/// bytes, so a report is comparable no matter which platform produced it. Change one, change both.
final class Whoop5SessionAuditTests: XCTestCase {

    private func verdict(_ audit: Whoop5SessionAudit, _ id: String) -> Whoop5SessionAudit.Verdict? {
        audit.checks.first { $0.id == id }?.verdict
    }

    func testFreshRunIsAllSkipped() {
        let a = Whoop5SessionAudit()
        XCTAssertEqual(a.checks.count, 9)
        for c in a.checks {
            XCTAssertEqual(c.verdict, .skip, "fresh run should skip \(c.id)")
        }
    }

    func testHealthySessionAllPass() {
        let a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted: true)
        for _ in 0..<10 { a.noteLiveHeartRateSample() }
        a.noteClockCorrelated()
        // 2 command acks, 5 historical v18 records, all CRC-clean.
        a.notePuffinFrame(crcOK: true, typeByte: 0x24, versionByte: 0)
        a.notePuffinFrame(crcOK: true, typeByte: 0x24, versionByte: 0)
        for _ in 0..<5 { a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 18) }
        a.noteR22SequenceSent(totalFlags: 16)
        for _ in 0..<16 { a.noteR22FlagAck() }
        a.noteOffloadEnded(reason: .completed, bankedRows: 5, rejectedRecordsThisConnection: 0)

        for c in a.checks {
            XCTAssertEqual(c.verdict, .pass, "\(c.id) should pass, got \(c.verdict): \(c.detail)")
        }
    }

    func testLiveHROnlyLinkIsPartialBond() {
        let a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted: false)   // #69/#266 live-HR-only shortcut (or macOS)
        a.noteLiveHeartRateSample()
        XCTAssertEqual(verdict(a, "bond"), .partial)
        XCTAssertEqual(verdict(a, "clock"), .skip)      // clock needs the bond — skip, not fail
        XCTAssertEqual(verdict(a, "live_hr"), .pass)    // live HR works without a bond
    }

    func testBondedButSilentCommandChannelFails() {
        let a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted: true)
        // Frames flow but no COMMAND_RESPONSE and no clock: both are real failures once bonded.
        for _ in 0..<3 { a.notePuffinFrame(crcOK: true, typeByte: 40, versionByte: 0) }
        XCTAssertEqual(verdict(a, "commands"), .fail)
        XCTAssertEqual(verdict(a, "clock"), .fail)
    }

    func testCRCFailuresGradeFraming() {
        let a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK: false, typeByte: 0, versionByte: 0)
        XCTAssertEqual(verdict(a, "framing"), .fail)
        a.notePuffinFrame(crcOK: true, typeByte: 40, versionByte: 0)
        XCTAssertEqual(verdict(a, "framing"), .partial)
    }

    func testBadCRCFrameCountsNothingElse() {
        let a = Whoop5SessionAudit()
        // A corrupt frame must not count as a command ack or a historical record.
        a.notePuffinFrame(crcOK: false, typeByte: 0x24, versionByte: 18)
        XCTAssertEqual(verdict(a, "commands"), .skip)
        XCTAssertEqual(verdict(a, "decode"), .skip)
    }

    func testR22Verdicts() {
        let a = Whoop5SessionAudit()
        XCTAssertEqual(verdict(a, "r22_unlock"), .skip)
        a.noteR22SequenceSent(totalFlags: 16)
        XCTAssertEqual(verdict(a, "r22_unlock"), .fail)     // sent, nothing acked yet
        for _ in 0..<9 { a.noteR22FlagAck() }
        XCTAssertEqual(verdict(a, "r22_unlock"), .partial)  // 9/16
        for _ in 0..<7 { a.noteR22FlagAck() }
        XCTAssertEqual(verdict(a, "r22_unlock"), .pass)     // 16/16
        // A fresh attempt restarts the count (mirrors r22FlagsAccepted reset).
        a.noteR22SequenceSent(totalFlags: 16)
        XCTAssertEqual(verdict(a, "r22_unlock"), .fail)
    }

    func testEmptyOffloadIsPartialNotFail() {
        let a = Whoop5SessionAudit()
        a.noteOffloadEnded(reason: .timedOut, bankedRows: 0, rejectedRecordsThisConnection: 0)
        let c = a.checks.first { $0.id == "offload" }!
        XCTAssertEqual(c.verdict, .partial)                 // the #580 case — honest, not an error
        XCTAssertTrue(c.detail.contains("#580"))
        a.noteOffloadEnded(reason: .completed, bankedRows: 12, rejectedRecordsThisConnection: 0)
        XCTAssertEqual(verdict(a, "offload"), .pass)
    }

    func testUnmappedLayoutAndRejectsArePartialDecode() {
        let a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 18)
        XCTAssertEqual(verdict(a, "decode"), .pass)
        a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 33)   // unknown layout
        let c = a.checks.first { $0.id == "decode" }!
        XCTAssertEqual(c.verdict, .partial)
        XCTAssertTrue(c.detail.contains("v33"))
        XCTAssertTrue(c.detail.contains("#103"))
    }

    func testV26OnlyIsPassWithPPGNote() {
        let a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 26)
        let c = a.checks.first { $0.id == "decode" }!
        XCTAssertEqual(c.verdict, .pass)
        XCTAssertTrue(c.detail.contains("raw PPG"))
    }

    func testRejectedRecordsUseLatestValueNotSum() {
        let a = Whoop5SessionAudit()
        a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 18)
        // The connection-cumulative tally is reported at each offload exit — latest wins.
        a.noteOffloadEnded(reason: .completed, bankedRows: 1, rejectedRecordsThisConnection: 3)
        a.noteOffloadEnded(reason: .completed, bankedRows: 1, rejectedRecordsThisConnection: 3)
        XCTAssertEqual(a.snapshot().rejectedRecords, 3)
    }

    func testResetClearsEverything() {
        let a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted: true)
        a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 18)
        a.reset()
        for c in a.checks { XCTAssertEqual(c.verdict, .skip) }
        XCTAssertEqual(a.snapshot(), Whoop5SessionAudit().snapshot())
    }

    func testSnapshotEqualityDrivesPublishing() {
        let a = Whoop5SessionAudit()
        let s1 = a.snapshot()
        XCTAssertEqual(s1, a.snapshot())            // no events, no change
        a.noteLiveHeartRateSample()
        XCTAssertNotEqual(s1, a.snapshot())         // event changes the snapshot
    }

    /// THE cross-platform fixture. The Kotlin twin replays this exact sequence and asserts this
    /// exact string. Deliberately exercises every line of the report: partial R22, one empty
    /// timeout offload plus one banking completion, an unmapped layout, and a CRC failure.
    func testReportParityFixture() {
        let a = Whoop5SessionAudit()
        a.noteHandshake()
        a.noteBond(encrypted: true)
        for _ in 0..<642 { a.noteLiveHeartRateSample() }
        a.noteClockCorrelated()
        for _ in 0..<18 { a.notePuffinFrame(crcOK: true, typeByte: 0x24, versionByte: 0) }
        for _ in 0..<780 { a.notePuffinFrame(crcOK: true, typeByte: 40, versionByte: 0) }
        for _ in 0..<12 { a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 18) }
        for _ in 0..<2 { a.notePuffinFrame(crcOK: true, typeByte: 47, versionByte: 33) }
        a.notePuffinFrame(crcOK: false, typeByte: 0, versionByte: 0)
        a.noteR22SequenceSent(totalFlags: 16)
        for _ in 0..<9 { a.noteR22FlagAck() }
        a.noteOffloadEnded(reason: .timedOut, bankedRows: 0, rejectedRecordsThisConnection: 0)
        a.noteOffloadEnded(reason: .completed, bankedRows: 12, rejectedRecordsThisConnection: 2)

        let expected = """
        NOOP WHOOP 5/MG PROTOCOL CHECK (experimental)
        schema=1
        [PASS] handshake: CLIENT_HELLO completed
        [PASS] bond: encrypted bond established
        [PASS] live_hr: 642 samples over the standard 0x2A37 profile
        [PASS] clock: GET_CLOCK reply received
        [PART] framing: 812 frames CRC-verified, 1 failed
        [PASS] commands: 18 COMMAND_RESPONSE acks
        [PART] r22_unlock: 9/16 enable_r22 flags acked
        [PASS] offload: completed=1 timeouts=1 banked_rows=12
        [PART] decode: unmapped layout(s): v33; 2 records not decodable; share a strap log/capture (#103)
        summary: pass=6 partial=3 fail=0 skipped=0
        hist_versions: v18=12 v33=2
        counters: frames_ok=812 frames_bad=1 live_hr=642 cmd_acks=18 r22_acks=9/16 offloads=2 banked_rows=12 rejected=2
        Share this report (with your strap log) on the WHOOP 5/MG deep-data issue: #103
        """
        XCTAssertEqual(a.report(), expected)
    }
}
