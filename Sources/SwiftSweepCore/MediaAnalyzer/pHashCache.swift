import Foundation
import SQLite3

// MARK: - pHash Cache

/// pHash 持久缓存（SQLite）
/// 使用 inode + mtime 作为缓存失效策略
public actor pHashCache {
  public static let shared = pHashCache()

  private var db: OpaquePointer?
  private let maxEntries: Int

  public init(maxEntries: Int = 100_000) {
    self.maxEntries = maxEntries
    // Setup database synchronously during init
    self.db = Self.openDatabase()
  }

  // MARK: - Setup

  private static func openDatabase() -> OpaquePointer? {
    let fileManager = FileManager.default
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let cacheDir = appSupport.appendingPathComponent("SwiftSweep", isDirectory: true)

    try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

    let dbPath = cacheDir.appendingPathComponent("phash_cache.db").path

    var db: OpaquePointer?
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
      return nil
    }

    // 创建表
    let createSQL = """
      CREATE TABLE IF NOT EXISTS phash_cache (
          path TEXT PRIMARY KEY,
          inode INTEGER NOT NULL,
          mtime REAL NOT NULL,
          hash INTEGER NOT NULL,
          created_at REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_created_at ON phash_cache(created_at);
      """

    sqlite3_exec(db, createSQL, nil, nil, nil)
    return db
  }

  deinit {
    if let db = db {
      sqlite3_close(db)
    }
  }

  // MARK: - Query

  /// 查询缓存（基于 inode + mtime）
  public func get(path: String, inode: UInt64, mtime: Date) -> UInt64? {
    guard let db = db else { return nil }

    let query = "SELECT hash FROM phash_cache WHERE path = ? AND inode = ? AND mtime = ?"
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
      return nil
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int64(stmt, 2, Int64(bitPattern: inode))
    sqlite3_bind_double(stmt, 3, mtime.timeIntervalSince1970)

    if sqlite3_step(stmt) == SQLITE_ROW {
      return UInt64(bitPattern: sqlite3_column_int64(stmt, 0))
    }

    return nil
  }

  // MARK: - Insert

  /// 存入缓存
  public func set(path: String, inode: UInt64, mtime: Date, hash: UInt64) {
    guard let db = db else { return }

    let insert = """
      INSERT OR REPLACE INTO phash_cache (path, inode, mtime, hash, created_at)
      VALUES (?, ?, ?, ?, ?)
      """
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else {
      return
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_int64(stmt, 2, Int64(bitPattern: inode))
    sqlite3_bind_double(stmt, 3, mtime.timeIntervalSince1970)
    sqlite3_bind_int64(stmt, 4, Int64(bitPattern: hash))
    sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

    sqlite3_step(stmt)

    // 如果超过最大条目，删除最旧的
    pruneIfNeeded()
  }

  // MARK: - Maintenance

  /// 清除过期条目
  public func pruneIfNeeded() {
    guard let db = db else { return }

    // 获取当前条目数
    var countStmt: OpaquePointer?
    guard
      sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM phash_cache", -1, &countStmt, nil) == SQLITE_OK
    else { return }
    defer { sqlite3_finalize(countStmt) }

    guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
    let count = sqlite3_column_int(countStmt, 0)

    if count > maxEntries {
      // 删除最旧的 10%
      let deleteCount = count / 10
      let deleteSQL =
        "DELETE FROM phash_cache WHERE path IN (SELECT path FROM phash_cache ORDER BY created_at LIMIT ?)"
      var deleteStmt: OpaquePointer?

      guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(deleteStmt) }

      sqlite3_bind_int(deleteStmt, 1, deleteCount)
      sqlite3_step(deleteStmt)
    }
  }

  /// 清除所有缓存
  public func clear() {
    guard let db = db else { return }
    sqlite3_exec(db, "DELETE FROM phash_cache", nil, nil, nil)
  }

  /// 获取缓存统计
  public func stats() -> (count: Int, sizeBytes: Int64) {
    guard let db = db else { return (0, 0) }

    var countStmt: OpaquePointer?
    guard
      sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM phash_cache", -1, &countStmt, nil) == SQLITE_OK
    else { return (0, 0) }
    defer { sqlite3_finalize(countStmt) }

    var count = 0
    if sqlite3_step(countStmt) == SQLITE_ROW {
      count = Int(sqlite3_column_int(countStmt, 0))
    }

    // 估算大小：每条约 200 字节
    let estimatedSize = Int64(count * 200)

    return (count, estimatedSize)
  }
}
