import XCTest
@testable import WhoopStore

/// #65 undo, the DB half. The Repository (app target, unrunnable headless) resolves the owning
/// namespace and drives these store calls; these tests pin the store-level guarantees the undo relies
/// on: (a) a deleted row restores VERBATIM into whichever namespace owned it, (b) restoring a
/// `userEdited` night preserves the flag so the next analyze pass does NOT re-score it as a detected
/// twin (HAZARD 2), and (c) the delete + restore never leaks into the OTHER namespace. Paired with
/// `DismissedSleepSpansTests` (the tombstone-lift half) this covers the whole undo path.
final class SleepDeleteUndoStoreTests: XCTestCase {

    private let computed = "my-whoop-noop"
    private let imported = "my-whoop"

    private func session(start: Int, end: Int, edited: Bool = false, stages: String? = "[]",
                         startAdjusted: Int? = nil) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: 0.9, restingHr: 50,
                           avgHrv: 60, stagesJSON: stages, userEdited: edited,
                           startTsAdjusted: startAdjusted)
    }

    // MARK: - Restore into the ORIGINAL namespace (HAZARD 2)

    func testUndoRestoresComputedRowIntoComputedNamespaceOnly() async throws {
        let store = try await WhoopStore.inMemory()
        let row = session(start: 1000, end: 5000)
        try await store.upsertSleepSessions([row], deviceId: computed)

        // Delete (the delete half of deleteSleepSession) resolves computed-first.
        let deleted = try await store.deleteSleepSession(deviceId: computed, startTs: 1000)
        XCTAssertEqual(deleted, 1)

        // Undo restores the snapshot into the SAME (computed) namespace.
        _ = try await store.upsertSleepSessions([row], deviceId: computed)

        let computedRows = try await store.sleepSessions(deviceId: computed, from: 0, to: 100_000, limit: 100)
        let importedRows = try await store.sleepSessions(deviceId: imported, from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(computedRows, [row], "restored verbatim into computed")
        XCTAssertTrue(importedRows.isEmpty, "undo never leaks into the imported namespace")
    }

    func testUndoRestoresImportedRowIntoImportedNamespaceOnly() async throws {
        let store = try await WhoopStore.inMemory()
        let row = session(start: 2000, end: 8000)
        try await store.upsertSleepSessions([row], deviceId: imported)

        // The delete resolves computed-first (0 rows), then falls back to imported.
        let computedDeleted = try await store.deleteSleepSession(deviceId: computed, startTs: 2000)
        XCTAssertEqual(computedDeleted, 0, "no computed row owns this night")
        let importedDeleted = try await store.deleteSleepSession(deviceId: imported, startTs: 2000)
        XCTAssertEqual(importedDeleted, 1)

        // Undo restores into imported, NOT computed (the bug the brief guards against).
        _ = try await store.upsertSleepSessions([row], deviceId: imported)

        let computedRows = try await store.sleepSessions(deviceId: computed, from: 0, to: 100_000, limit: 100)
        let importedRows = try await store.sleepSessions(deviceId: imported, from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(importedRows, [row], "restored verbatim into imported")
        XCTAssertTrue(computedRows.isEmpty, "an imported night must never resurrect as a computed twin")
    }

    // MARK: - userEdited preserved on restore (HAZARD 2)

    func testUndoRestoresUserEditedNightWithFlagIntact() async throws {
        let store = try await WhoopStore.inMemory()
        // A hand-corrected night: userEdited, an adjusted onset, custom stages.
        let edited = session(start: 3000, end: 9000, edited: true,
                             stages: "[{\"start\":3200,\"end\":9000,\"stage\":\"deep\"}]",
                             startAdjusted: 3200)
        try await store.upsertSleepSessions([edited], deviceId: computed)

        _ = try await store.deleteSleepSession(deviceId: computed, startTs: 3000)
        // Undo re-inserts the snapshot verbatim.
        _ = try await store.upsertSleepSessions([edited], deviceId: computed)

        let rows = try await store.sleepSessions(deviceId: computed, from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].userEdited, "the correction flag survives undo so analyze won't re-detect a twin")
        XCTAssertEqual(rows[0].startTsAdjusted, 3200)
        XCTAssertEqual(rows[0].endTs, 9000)
        XCTAssertEqual(rows[0].stagesJSON, edited.stagesJSON)
    }
}
