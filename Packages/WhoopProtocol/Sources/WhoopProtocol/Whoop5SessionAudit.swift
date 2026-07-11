import Foundation

/// EXPERIMENTAL (#174 / #103): one WHOOP 5.0/MG session distilled into a per-feature verdict — the
/// "protocol health check" a 5/MG owner runs to see whether NOOP's implemented 5/MG paths
/// (handshake, bond, live HR, clock, CRC framing, command channel, R22 unlock, history offload,
/// type-47 decode) actually work against THEIR strap and firmware, and to produce a shareable
/// report for the deep-data tracking issue.
///
/// Pure aggregation: no CoreBluetooth, no clock reads, no IO — it only counts what the app feeds
/// it — so it unit-tests in this package on Linux and twins with the Android
/// `Whoop5SessionAudit` (byte-identical `report()` output; see Whoop5SessionAuditTests /
/// Whoop5SessionAuditTest). Nothing here writes to a strap: the audit OBSERVES the session the
/// app was already having.
///
/// Not thread-safe by design — the owner (BLEManager / WhoopBleClient) feeds it from its own
/// single BLE callback context, matching how the rest of the session state is mutated.
public final class Whoop5SessionAudit {

    /// Type-47 layout versions `decodeWhoop5Historical` can decode today. v26 is the raw-PPG block:
    /// it parses (so it is "mapped") but stores no per-second rows by design. Keep in lockstep with
    /// the Interpreter's version dispatch and the Kotlin twin.
    public static let mappedHistoricalVersions: Set<Int> = [18, 20, 21, 26]

    public enum Verdict: String, Equatable {
        case pass, partial, fail, skip

        /// Fixed-width tag used by `report()` — identical across platforms.
        var tag: String {
            switch self {
            case .pass:    return "[PASS]"
            case .partial: return "[PART]"
            case .fail:    return "[FAIL]"
            case .skip:    return "[SKIP]"
            }
        }
    }

    /// One rendered check row: a stable snake_case id (shared with Android), the verdict, and a
    /// deterministic English detail line (report-stable, like log lines — the UI localizes its own
    /// labels instead).
    public struct Check: Equatable {
        public let id: String
        public let verdict: Verdict
        public let detail: String
    }

    /// Value snapshot for UI publication: recompute after each feed, publish only when changed.
    public struct Snapshot: Equatable {
        public let checks: [Check]
        public let framesOK: Int
        public let framesBad: Int
        public let liveHRSamples: Int
        public let commandAcks: Int
        public let r22Acks: Int
        public let r22Total: Int
        public let offloadsCompleted: Int
        public let offloadsTimedOut: Int
        public let bankedRows: Int
        public let rejectedRecords: Int
        public let histVersionCounts: [Int: Int]
    }

    public enum OffloadReason: Equatable {
        case completed   // HISTORY_COMPLETE
        case timedOut    // idle-watchdog exit
    }

    // MARK: - Fed state

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
    private var histVersionCounts: [Int: Int] = [:]

    public init() {}

    /// Fresh run — the app calls this when the user starts a check.
    public func reset() {
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
        histVersionCounts = [:]
    }

    // MARK: - Feed events (each maps to ONE existing app seam)

    /// The 5/MG post-bond branch flipped `connectHandshakeDone` (CLIENT_HELLO answered).
    public func noteHandshake() { handshakeSeen = true }

    /// Bond state became known. `encrypted=false` is the live-HR-only link (#69/#266): the strap is
    /// reachable but still owned by the official app (or the platform can't bond, e.g. macOS).
    public func noteBond(encrypted: Bool) {
        bondReported = true
        if encrypted { encryptedBond = true }
    }

    /// One standard-profile (0x2A37) heart-rate sample landed.
    public func noteLiveHeartRateSample() { liveHRSamples += 1 }

    /// The strap answered GET_CLOCK (on a 5/MG the reply rides the puffin notify chars; timestamps
    /// are already real unix, so a reply IS the proof the clock path works).
    public func noteClockCorrelated() { clockCorrelated = true }

    /// One reassembled puffin frame, CRC-verified by the caller (`verifyFrame(_:family:.whoop5)`).
    /// `typeByte` = frame[8], `versionByte` = frame[9] (only meaningful for type 47).
    public func notePuffinFrame(crcOK: Bool, typeByte: Int, versionByte: Int) {
        if crcOK { framesOK += 1 } else { framesBad += 1 }
        guard crcOK else { return }
        if typeByte == 0x24 { commandAcks += 1 }
        if typeByte == 47 { histVersionCounts[versionByte, default: 0] += 1 }
    }

    /// The enable_r22 SET_CONFIG sequence was sent (`totalFlags` = Whoop5Config.enableR22Sequence.count).
    public func noteR22SequenceSent(totalFlags: Int) {
        r22Attempted = true
        r22Total = totalFlags
        r22Acks = 0
    }

    /// The strap ACKed one enable_r22 flag (COMMAND_RESPONSE to SET_CONFIG).
    public func noteR22FlagAck() { r22Acks += 1 }

    /// One offload session ended. `rejectedRecordsThisConnection` is the connection-cumulative
    /// undecodable-record tally at exit time (latest value wins — not summed).
    public func noteOffloadEnded(reason: OffloadReason, bankedRows rows: Int,
                                 rejectedRecordsThisConnection: Int) {
        switch reason {
        case .completed: offloadsCompleted += 1
        case .timedOut:  offloadsTimedOut += 1
        }
        bankedRows += rows
        rejectedRecords = max(rejectedRecords, rejectedRecordsThisConnection)
    }

    // MARK: - Verdicts

    private var anyFrames: Bool { framesOK + framesBad > 0 }

    private func checkHandshake() -> Check {
        handshakeSeen
            ? Check(id: "handshake", verdict: .pass, detail: "CLIENT_HELLO completed")
            : Check(id: "handshake", verdict: .skip, detail: "no 5/MG connection this run yet")
    }

    private func checkBond() -> Check {
        if encryptedBond {
            return Check(id: "bond", verdict: .pass, detail: "encrypted bond established")
        }
        if bondReported {
            return Check(id: "bond", verdict: .partial,
                         detail: "live-HR-only link (no encrypted bond; deep features unavailable)")
        }
        return Check(id: "bond", verdict: .skip, detail: "no bond attempt seen yet")
    }

    private func checkLiveHR() -> Check {
        liveHRSamples > 0
            ? Check(id: "live_hr", verdict: .pass,
                    detail: "\(liveHRSamples) samples over the standard 0x2A37 profile")
            : Check(id: "live_hr", verdict: .skip, detail: "no live HR samples yet")
    }

    private func checkClock() -> Check {
        if clockCorrelated {
            return Check(id: "clock", verdict: .pass, detail: "GET_CLOCK reply received")
        }
        if encryptedBond && anyFrames {
            return Check(id: "clock", verdict: .fail,
                         detail: "bonded but no GET_CLOCK reply; history cannot be dated")
        }
        return Check(id: "clock", verdict: .skip, detail: "needs the encrypted bond first")
    }

    private func checkFraming() -> Check {
        if !anyFrames {
            return Check(id: "framing", verdict: .skip, detail: "no puffin frames seen yet")
        }
        if framesBad == 0 {
            return Check(id: "framing", verdict: .pass,
                         detail: "\(framesOK) frames CRC-verified, 0 failed")
        }
        if framesOK == 0 {
            return Check(id: "framing", verdict: .fail,
                         detail: "all \(framesBad) frames failed CRC; framing mismatch, share a capture")
        }
        return Check(id: "framing", verdict: .partial,
                     detail: "\(framesOK) frames CRC-verified, \(framesBad) failed")
    }

    private func checkCommands() -> Check {
        if commandAcks > 0 {
            return Check(id: "commands", verdict: .pass, detail: "\(commandAcks) COMMAND_RESPONSE acks")
        }
        if encryptedBond && anyFrames {
            return Check(id: "commands", verdict: .fail,
                         detail: "no COMMAND_RESPONSE seen despite the encrypted bond")
        }
        return Check(id: "commands", verdict: .skip, detail: "no command acks yet")
    }

    private func checkR22() -> Check {
        if !r22Attempted {
            return Check(id: "r22_unlock", verdict: .skip,
                         detail: "not attempted (Settings > Experimental > deep data)")
        }
        if r22Acks >= r22Total && r22Total > 0 {
            return Check(id: "r22_unlock", verdict: .pass,
                         detail: "\(r22Acks)/\(r22Total) enable_r22 flags acked")
        }
        if r22Acks == 0 {
            return Check(id: "r22_unlock", verdict: .fail,
                         detail: "sequence sent but 0/\(r22Total) flags acked")
        }
        return Check(id: "r22_unlock", verdict: .partial,
                     detail: "\(r22Acks)/\(r22Total) enable_r22 flags acked")
    }

    private func checkOffload() -> Check {
        let sessions = offloadsCompleted + offloadsTimedOut
        if sessions == 0 {
            return Check(id: "offload", verdict: .skip, detail: "no offload session yet")
        }
        let detail = "completed=\(offloadsCompleted) timeouts=\(offloadsTimedOut) banked_rows=\(bankedRows)"
        return bankedRows > 0
            ? Check(id: "offload", verdict: .pass, detail: detail)
            : Check(id: "offload", verdict: .partial,
                    detail: detail + " (empty offload; see #580)")
    }

    private func checkDecode() -> Check {
        if histVersionCounts.isEmpty {
            return Check(id: "decode", verdict: .skip, detail: "no type-47 records seen yet")
        }
        let unmapped = histVersionCounts.keys
            .filter { !Self.mappedHistoricalVersions.contains($0) }
            .sorted()
        var problems: [String] = []
        if !unmapped.isEmpty {
            problems.append("unmapped layout(s): " + unmapped.map { "v\($0)" }.joined(separator: ","))
        }
        if rejectedRecords > 0 {
            problems.append("\(rejectedRecords) records not decodable")
        }
        if problems.isEmpty {
            var detail = "all type-47 layouts mapped"
            if histVersionCounts.keys.contains(26) {
                detail += " (v26 is raw PPG; stores no rows by design)"
            }
            return Check(id: "decode", verdict: .pass, detail: detail)
        }
        return Check(id: "decode", verdict: .partial,
                     detail: problems.joined(separator: "; ") + "; share a strap log/capture (#103)")
    }

    /// All checks, fixed order (report + UI both render this order).
    public var checks: [Check] {
        [checkHandshake(), checkBond(), checkLiveHR(), checkClock(), checkFraming(),
         checkCommands(), checkR22(), checkOffload(), checkDecode()]
    }

    public func snapshot() -> Snapshot {
        Snapshot(checks: checks,
                 framesOK: framesOK, framesBad: framesBad,
                 liveHRSamples: liveHRSamples, commandAcks: commandAcks,
                 r22Acks: r22Acks, r22Total: r22Total,
                 offloadsCompleted: offloadsCompleted, offloadsTimedOut: offloadsTimedOut,
                 bankedRows: bankedRows, rejectedRecords: rejectedRecords,
                 histVersionCounts: histVersionCounts)
    }

    // MARK: - Report

    /// The shareable plain-text report. Deterministic and BYTE-IDENTICAL with the Android twin for
    /// the same event sequence (parity-tested), so reports are comparable regardless of platform.
    public func report() -> String {
        var lines: [String] = []
        lines.append("NOOP WHOOP 5/MG PROTOCOL CHECK (experimental)")
        lines.append("schema=1")
        let all = checks
        for c in all {
            lines.append("\(c.verdict.tag) \(c.id): \(c.detail)")
        }
        let tally = all.reduce(into: [Verdict.pass: 0, .partial: 0, .fail: 0, .skip: 0]) {
            $0[$1.verdict, default: 0] += 1
        }
        lines.append("summary: pass=\(tally[.pass] ?? 0) partial=\(tally[.partial] ?? 0)"
                     + " fail=\(tally[.fail] ?? 0) skipped=\(tally[.skip] ?? 0)")
        if !histVersionCounts.isEmpty {
            let hist = histVersionCounts.keys.sorted()
                .map { "v\($0)=\(histVersionCounts[$0] ?? 0)" }
                .joined(separator: " ")
            lines.append("hist_versions: \(hist)")
        }
        lines.append("counters: frames_ok=\(framesOK) frames_bad=\(framesBad)"
                     + " live_hr=\(liveHRSamples) cmd_acks=\(commandAcks)"
                     + " r22_acks=\(r22Acks)/\(r22Total)"
                     + " offloads=\(offloadsCompleted + offloadsTimedOut)"
                     + " banked_rows=\(bankedRows) rejected=\(rejectedRecords)")
        lines.append("Share this report (with your strap log) on the WHOOP 5/MG deep-data issue: #103")
        return lines.joined(separator: "\n")
    }
}
