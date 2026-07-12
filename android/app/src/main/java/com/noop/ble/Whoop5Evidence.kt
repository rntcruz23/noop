package com.noop.ble

import android.content.Context
import android.content.SharedPreferences

// EXPERIMENTAL 5/MG honesty upgrade (#103): persisted, per-strap, evidence-backed capability facts.
// Twin of the Swift Whoop5Evidence (Strand/Data/Whoop5Evidence.swift) — see that header for the
// full rationale. Short version: NOOP tracked NEGATIVE 5/MG evidence (#580) but forgot POSITIVE
// proof, so a strap that banks dated history, decodes cleanly and acks the whole R22 sequence still
// read as generically "experimental". These facts let the Devices card and Settings state evidence
// instead of a blanket disclaimer — and the blanket wording stays wherever no evidence exists.
//
// Honesty rules: keyed by the REGISTRY device id (never a raw BLE address), written only from a
// live 5/MG session that just demonstrated the capability, cleared with the device's data, and
// deliberately NOT in the `.noopbak` backup whitelist (restored proof would be a claim the new
// environment never reproduced; the whitelist is a byte-identical cross-platform contract).
class Whoop5Evidence(private val prefs: SharedPreferences) {

    companion object {
        fun from(context: Context): Whoop5Evidence =
            Whoop5Evidence(context.getSharedPreferences("noop_whoop5_evidence", Context.MODE_PRIVATE))

        private val FIELDS = listOf("liveHRAt", "historyAt", "historyRows", "decodeCleanAt", "r22AcceptedAt")
    }

    /** The proven facts for one strap. null/0 = never demonstrated on this strap. */
    data class Facts(
        val liveHRAt: Long?,
        val historyAt: Long?,
        val historyRows: Int,
        val decodeCleanAt: Long?,
        val r22AcceptedAt: Long?,
    ) {
        val anyVerified: Boolean
            get() = liveHRAt != null || historyAt != null || decodeCleanAt != null || r22AcceptedAt != null
    }

    private fun key(field: String, deviceId: String) = "whoop5.evidence.$field.$deviceId"

    private fun at(field: String, deviceId: String): Long? =
        prefs.getLong(key(field, deviceId), 0L).takeIf { it > 0L }

    fun facts(deviceId: String): Facts = Facts(
        liveHRAt = at("liveHRAt", deviceId),
        historyAt = at("historyAt", deviceId),
        historyRows = prefs.getInt(key("historyRows", deviceId), 0),
        decodeCleanAt = at("decodeCleanAt", deviceId),
        r22AcceptedAt = at("r22AcceptedAt", deviceId),
    )

    private fun now(): Long = System.currentTimeMillis() / 1000L

    /** Live HR flowed over the standard profile on this strap (recorded once per connection). */
    fun recordLiveHR(deviceId: String) {
        prefs.edit().putLong(key("liveHRAt", deviceId), now()).apply()
    }

    /** A HISTORY_COMPLETE offload banked [rows] decoded sensor rows from this strap. */
    fun recordHistory(rows: Int, deviceId: String) {
        if (rows <= 0) return
        prefs.edit()
            .putLong(key("historyAt", deviceId), now())
            .putInt(key("historyRows", deviceId), rows)
            .apply()
    }

    /** A banking offload finished with ZERO undecodable records — every layout this strap emitted
     *  is mapped. Recorded only alongside a banking sync (an empty sync proves nothing). */
    fun recordDecodeClean(deviceId: String) {
        prefs.edit().putLong(key("decodeCleanAt", deviceId), now()).apply()
    }

    /** The strap ACKed the full enable_r22 SET_CONFIG sequence. */
    fun recordR22Accepted(deviceId: String) {
        prefs.edit().putLong(key("r22AcceptedAt", deviceId), now()).apply()
    }

    /** Forget everything proven about this strap — called when the user deletes the device's data,
     *  so a later re-add starts from zero evidence like the data did. */
    fun clear(deviceId: String) {
        val e = prefs.edit()
        for (f in FIELDS) e.remove(key(f, deviceId))
        e.apply()
    }
}
