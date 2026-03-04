import Foundation
import ApplicationServices
import SQLite3

enum AccessibilityTrust {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Attempt to clear stale TCC entry and re-prompt.
    /// Returns true if accessibility is granted after recovery.
    static func resetAndReauthorize() -> Bool {
        // Already trusted — no reset needed
        if AXIsProcessTrusted() { return true }

        // Try to clear stale TCC entry via tccutil
        let bundleID = Bundle.main.bundleIdentifier ?? "com.voiceinput.macos"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // tccutil failed — fall through to prompt
        }

        // Now re-prompt (should show fresh system dialog since stale entry was cleared)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
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
