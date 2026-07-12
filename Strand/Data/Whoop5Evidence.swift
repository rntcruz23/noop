import Foundation

/// EXPERIMENTAL 5/MG honesty upgrade (#103): persisted, per-strap, evidence-backed capability facts.
///
/// NOOP already tracks NEGATIVE 5/MG evidence per session (#580's `historySyncExperimental`), but it
/// forgot POSITIVE proof the moment the session ended: a strap that banks dated history, decodes
/// every record and acks the whole R22 sequence still read as generically "experimental". These
/// facts remember what THIS strap has actually demonstrated, so the Devices card and Settings can
/// state evidence ("history sync verified, 1,273 records last sync") instead of a blanket
/// disclaimer. The blanket wording stays wherever no evidence exists — the claim is only ever as
/// wide as the proof.
///
/// Honesty rules: facts are keyed by the REGISTRY device id (never a raw BLE address), only ever
/// written from a live 5/MG session that just demonstrated the capability, and cleared with the
/// device's data. Deliberately NOT in the `.noopbak` backup whitelist: restored onto another phone
/// they would claim proof that environment never reproduced (and the whitelist is a byte-identical
/// cross-platform contract). Twin: android com.noop.ble.Whoop5Evidence.
enum Whoop5Evidence {

    /// The proven facts for one strap. `nil`/0 = never demonstrated on this strap.
    struct Facts: Equatable {
        var liveHRAt: Date?
        var historyAt: Date?
        var historyRows: Int
        var decodeCleanAt: Date?
        var r22AcceptedAt: Date?

        var anyVerified: Bool {
            liveHRAt != nil || historyAt != nil || decodeCleanAt != nil || r22AcceptedAt != nil
        }
    }

    private static func key(_ field: String, _ deviceId: String) -> String {
        "whoop5.evidence.\(field).\(deviceId)"
    }

    private static let fields = ["liveHRAt", "historyAt", "historyRows", "decodeCleanAt", "r22AcceptedAt"]

    static func facts(for deviceId: String) -> Facts {
        let d = UserDefaults.standard
        func date(_ f: String) -> Date? {
            let t = d.double(forKey: key(f, deviceId))
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        return Facts(liveHRAt: date("liveHRAt"),
                     historyAt: date("historyAt"),
                     historyRows: d.integer(forKey: key("historyRows", deviceId)),
                     decodeCleanAt: date("decodeCleanAt"),
                     r22AcceptedAt: date("r22AcceptedAt"))
    }

    /// Live HR flowed over the standard profile on this strap (recorded once per connection).
    static func recordLiveHR(deviceId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key("liveHRAt", deviceId))
    }

    /// A HISTORY_COMPLETE offload banked `rows` decoded sensor rows from this strap.
    static func recordHistory(rows: Int, deviceId: String) {
        guard rows > 0 else { return }
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: key("historyAt", deviceId))
        d.set(rows, forKey: key("historyRows", deviceId))
    }

    /// A banking offload finished with ZERO undecodable records — every layout this strap emitted
    /// is mapped. Recorded only alongside a banking sync (an empty sync proves nothing).
    static func recordDecodeClean(deviceId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key("decodeCleanAt", deviceId))
    }

    /// The strap ACKed the full enable_r22 SET_CONFIG sequence.
    static func recordR22Accepted(deviceId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key("r22AcceptedAt", deviceId))
    }

    /// Forget everything proven about this strap — called when the user deletes the device's data,
    /// so a later re-add starts from zero evidence like the data did.
    static func clear(deviceId: String) {
        let d = UserDefaults.standard
        for f in fields { d.removeObject(forKey: key(f, deviceId)) }
    }
}
