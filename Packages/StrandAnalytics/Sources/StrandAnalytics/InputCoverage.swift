import Foundation

/// "What feeds your scores" (#103): classify the last 24 hours of per-stream sensor rows into an
/// honest coverage readout — which inputs actually arrived from the active strap, so the analysis
/// screens' depth can be judged by evidence rather than assumed. This is the live, per-strap
/// version of the README's WHOOP 5/MG analysis-limits table: a recovery/sleep score can only be as
/// deep as the rows behind it, and this states which rows exist.
///
/// Pure classification over counts the app queries (database-free, twin: android
/// com.noop.analytics.InputCoverage; the summary string is byte-identical across platforms and
/// pinned by parity tests). Thresholds are deliberately coarse diagnostics, not physiology: a
/// strap that syncs once a day delivers history in bursts, so "regular" is set well below a full
/// day of samples, and any nonzero trickle reads "sparse" rather than being rounded to missing.
public enum InputCoverage {

    public enum Status: String, Equatable {
        case regular, sparse, missing
    }

    /// One classified stream: stable id (query key), display label, status, and the (capped) count
    /// that produced it.
    public struct Row: Equatable {
        public let id: String
        public let label: String
        public let status: Status
        public let count: Int

        public init(id: String, label: String, status: Status, count: Int) {
            self.id = id
            self.label = label
            self.status = status
            self.count = count
        }
    }

    /// The classified streams, in fixed display order. `regularPer24h` doubles as the query cap:
    /// fetching `fetchLimit(id)` rows is exactly enough to decide "regular", so no caller ever
    /// pulls an unbounded day of ~1 Hz samples to render one card row.
    static let streams: [(id: String, label: String, regularPer24h: Int)] = [
        ("hr", "Heart rate", 3600),          // ~1 Hz banked; an hour's worth in 24 h = regular
        ("rr", "R-R intervals", 120),        // sparse by nature on the history path
        ("motion", "Motion", 3600),          // v18 gravity is per-second alongside HR
        ("skin_temp", "Skin temp", 24),      // ~minutes cadence, overnight-weighted
        ("resp", "Respiratory", 24),
        ("spo2", "Blood oxygen", 24),
        ("steps", "Steps", 24),
    ]

    public static let streamIds: [String] = streams.map { $0.id }

    /// How many rows a caller needs to fetch (at most) for `id` — the "regular" threshold.
    public static func fetchLimit(_ id: String) -> Int {
        streams.first { $0.id == id }?.regularPer24h ?? 1
    }

    /// Classify per-stream counts (missing keys read as 0). Counts may be capped at `fetchLimit`.
    public static func classify(counts: [String: Int]) -> [Row] {
        streams.map { s in
            let n = counts[s.id] ?? 0
            let status: Status = n >= s.regularPer24h ? .regular : (n > 0 ? .sparse : .missing)
            return Row(id: s.id, label: s.label, status: status, count: n)
        }
    }

    /// The one-line honest readout, byte-identical across platforms (parity-tested):
    ///   "Feeding your scores: Heart rate, Motion. Sparse: R-R intervals. Missing: Blood oxygen."
    /// Empty groups are omitted; all-missing collapses to the no-data sentence.
    public static func summary(rows: [Row]) -> String {
        let regular = rows.filter { $0.status == .regular }.map { $0.label }
        let sparse = rows.filter { $0.status == .sparse }.map { $0.label }
        let missing = rows.filter { $0.status == .missing }.map { $0.label }
        if regular.isEmpty && sparse.isEmpty {
            return "No sensor data from this strap in the last 24 hours."
        }
        var parts: [String] = []
        if !regular.isEmpty { parts.append("Feeding your scores: " + regular.joined(separator: ", ") + ".") }
        if !sparse.isEmpty { parts.append("Sparse: " + sparse.joined(separator: ", ") + ".") }
        if !missing.isEmpty { parts.append("Missing: " + missing.joined(separator: ", ") + ".") }
        return parts.joined(separator: " ")
    }
}
