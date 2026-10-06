import Foundation
import SQLite3

/// Copies only compatible compiled shader entries between OW120's private
/// caches. The previous database stays read-only; existing entries win.
enum ShaderCacheMigration {
    private static let table = "cache_24"
    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var db: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &db, flags | SQLITE_OPEN_URI, nil)
        guard code == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw OWError.message("无法打开着色器缓存数据库。")
        }
        sqlite3_busy_timeout(db, 3000)
        return db
    }
    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw OWError.message("着色器缓存操作失败：\(String(cString: sqlite3_errmsg(db)))")
        }
    }
    private static func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw OWError.message("着色器缓存格式不兼容。") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw OWError.message("无法读取着色器缓存。") }
        return Int(sqlite3_column_int64(statement, 0))
    }
    private static func validate(_ db: OpaquePointer) throws {
        guard try scalar(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='\(table)'") == 1,
              try scalar(db, "SELECT COUNT(*) FROM \(table) WHERE typeof(key) != 'blob' OR length(key) != 40 OR typeof(value) != 'blob' OR length(value) = 0") == 0 else {
            throw OWError.message("着色器缓存版本或条目格式不兼容。")
        }
    }
    static func merge(source: URL, destination: URL, backup: URL) throws -> Int {
        guard source.standardizedFileURL != destination.standardizedFileURL else { throw OWError.message("着色器缓存来源与目标不能相同。") }
        let previous = try open(source, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(previous) }
        try validate(previous)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = try open(destination, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(target) }
        let hasTable = try scalar(target, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='\(table)'") > 0
        if hasTable { try validate(target) }
        // SQLite's backup includes committed WAL entries; copying only .db
        // would silently omit them. Retain a recoverable destination snapshot.
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = try open(backup, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(saved) }
        guard let handle = sqlite3_backup_init(saved, "main", target, "main") else { throw OWError.message("无法备份当前着色器缓存。") }
        let copied = sqlite3_backup_step(handle, -1)
        let finished = sqlite3_backup_finish(handle)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else { throw OWError.message("着色器缓存备份失败，未合并条目。") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(target, "ATTACH DATABASE ? AS previous", -1, &statement, nil) == SQLITE_OK, let statement else { throw OWError.message("无法读取旧着色器缓存。") }
        let uri = source.absoluteString + "?mode=ro"
        let attached = uri.withCString { value -> Int32 in
            sqlite3_bind_text(statement, 1, value, -1, nil)
            let code = sqlite3_step(statement)
            sqlite3_finalize(statement)
            return code
        }
        guard attached == SQLITE_DONE else { throw OWError.message("无法以只读方式连接旧着色器缓存。") }
        try execute(target, "BEGIN IMMEDIATE")
        var committed = false
        defer { if !committed { try? execute(target, "ROLLBACK") } }
        if !hasTable { try execute(target, "CREATE TABLE \(table) (key BLOB PRIMARY KEY, value BLOB NOT NULL)") }
        try execute(target, "INSERT OR IGNORE INTO main.\(table) (key,value) SELECT key,value FROM previous.\(table)")
        let imported = Int(sqlite3_changes(target))
        try execute(target, "COMMIT"); committed = true
        return imported
    }
}
