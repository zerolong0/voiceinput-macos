import Foundation
import ApplicationServices
import SQLite3

enum AccessibilityTrust {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        // Source of truth must be AX runtime API.
        // TCC DB is used for diagnostics only and can be stale across rebuild/signing changes.
        return AXIsProcessTrustedWithOptions(options)
    }

    static func tccAccessibilityAllowed(bundleID: String) -> Bool {
        let dbPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        let sql = "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client=? ORDER BY last_modified DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bundleID, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        return sqlite3_column_int(stmt, 0) == 2
    }
}
