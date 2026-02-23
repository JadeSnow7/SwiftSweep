import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum WorkspaceDatabaseError: Error, LocalizedError, Sendable {
  case unableToOpen(String)
  case sqlite(String)

  public var errorDescription: String? {
    switch self {
    case .unableToOpen(let message):
      return "Unable to open workspace database: \(message)"
    case .sqlite(let message):
      return message
    }
  }
}

public actor WorkspaceDatabase {
  public static let shared = WorkspaceDatabase()

  public let databaseURL: URL

  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(baseDirectory: URL? = nil) {
    let root: URL
    if let baseDirectory {
      root = baseDirectory
    } else {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
      root = appSupport
        .appendingPathComponent("SwiftSweep", isDirectory: true)
        .appendingPathComponent("Workspace", isDirectory: true)
    }

    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    self.databaseURL = root.appendingPathComponent("workspace.sqlite")
  }

  public func setupSchema() throws {
    try withConnection { db in
      try execute(
        db,
        sql: """
          PRAGMA journal_mode=WAL;
          PRAGMA synchronous=NORMAL;
          PRAGMA foreign_keys=ON;
        """
      )

      let currentVersion = try readUserVersion(db)
      if currentVersion >= 1 {
        return
      }

      try execute(
        db,
        sql: """
          CREATE TABLE IF NOT EXISTS bookmarks (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            bookmark BLOB,
            created_at REAL NOT NULL
          );

          CREATE TABLE IF NOT EXISTS pinned_launch_items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            path TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            order_index INTEGER NOT NULL
          );

          CREATE TABLE IF NOT EXISTS file_tags (
            path TEXT NOT NULL,
            tag TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (path, tag)
          );

          CREATE TABLE IF NOT EXISTS saved_searches (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            query_json TEXT NOT NULL,
            created_at REAL NOT NULL
          );

          CREATE TABLE IF NOT EXISTS file_operation_history (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            sources_json TEXT NOT NULL,
            destination TEXT,
            status TEXT NOT NULL,
            transferred_bytes INTEGER NOT NULL,
            created_at REAL NOT NULL
          );
        """
      )

      try execute(db, sql: "PRAGMA user_version=1;")
    }
  }

  // MARK: - Bookmarks

  public func upsertBookmark(path: String, bookmarkData: Data?) throws {
    let sql = """
      INSERT INTO bookmarks(id, path, bookmark, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(path) DO UPDATE SET
        bookmark = excluded.bookmark,
        created_at = excluded.created_at;
    """

    let id = UUID().uuidString
    let now = Date().timeIntervalSince1970

    try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, id, -1, sqliteTransient)
      sqlite3_bind_text(stmt, 2, path, -1, sqliteTransient)
      if let bookmarkData {
        _ = bookmarkData.withUnsafeBytes { bytes in
          sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(bookmarkData.count), sqliteTransient)
        }
      } else {
        sqlite3_bind_null(stmt, 3)
      }
      sqlite3_bind_double(stmt, 4, now)

      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw sqliteError(db)
      }
    }
  }

  public func loadBookmarks() throws -> [WorkspaceBookmark] {
    let sql = "SELECT id, path, created_at FROM bookmarks ORDER BY created_at DESC;"

    return try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      var bookmarks: [WorkspaceBookmark] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        bookmarks.append(
          WorkspaceBookmark(
            id: stringColumn(stmt, index: 0),
            path: stringColumn(stmt, index: 1),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
          )
        )
      }
      return bookmarks
    }
  }

  // MARK: - Pinned Launch Items

  public func loadPinnedLaunchItems() throws -> [PinnedLaunchItem] {
    let sql = """
      SELECT id, type, path, title, created_at, order_index
      FROM pinned_launch_items
      ORDER BY order_index ASC, created_at ASC;
    """

    return try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      var results: [PinnedLaunchItem] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        let idText = stringColumn(stmt, index: 0)
        let typeText = stringColumn(stmt, index: 1)
        let item = PinnedLaunchItem(
          id: UUID(uuidString: idText) ?? UUID(),
          type: PinnedLaunchItemType(rawValue: typeText) ?? .folder,
          path: stringColumn(stmt, index: 2),
          title: stringColumn(stmt, index: 3),
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
          order: Int(sqlite3_column_int(stmt, 5))
        )
        results.append(item)
      }

      return results
    }
  }

  public func savePinnedLaunchItems(_ items: [PinnedLaunchItem]) throws {
    try withConnection { db in
      try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
      defer {
        _ = try? execute(db, sql: "COMMIT;")
      }

      try execute(db, sql: "DELETE FROM pinned_launch_items;")

      let insertSQL = """
        INSERT INTO pinned_launch_items(id, type, path, title, created_at, order_index)
        VALUES (?, ?, ?, ?, ?, ?);
      """

      for (index, item) in items.enumerated() {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
          throw sqliteError(db)
        }

        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, item.type.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, item.path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, item.title, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 6, Int32(index))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
          sqlite3_finalize(stmt)
          throw sqliteError(db)
        }
        sqlite3_finalize(stmt)
      }
    }
  }

  // MARK: - Tags

  public func loadTags(forPath path: String) throws -> [String] {
    let sql = "SELECT tag FROM file_tags WHERE path = ? ORDER BY tag ASC;"

    return try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)

      var tags: [String] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        tags.append(stringColumn(stmt, index: 0))
      }
      return tags
    }
  }

  public func replaceTags(forPath path: String, tags: [String]) throws {
    try withConnection { db in
      try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
      defer {
        _ = try? execute(db, sql: "COMMIT;")
      }

      let deleteSQL = "DELETE FROM file_tags WHERE path = ?;"
      var deleteStmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      sqlite3_bind_text(deleteStmt, 1, path, -1, sqliteTransient)
      guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
        sqlite3_finalize(deleteStmt)
        throw sqliteError(db)
      }
      sqlite3_finalize(deleteStmt)

      let insertSQL = "INSERT INTO file_tags(path, tag, created_at) VALUES (?, ?, ?);"
      for tag in tags {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
          throw sqliteError(db)
        }
        sqlite3_bind_text(stmt, 1, path, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, tag, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
          sqlite3_finalize(stmt)
          throw sqliteError(db)
        }
        sqlite3_finalize(stmt)
      }
    }
  }

  // MARK: - Saved Searches

  public func loadSavedSearches() throws -> [WorkspaceSavedSearch] {
    let sql = "SELECT id, name, query_json, created_at FROM saved_searches ORDER BY created_at DESC;"

    return try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      var results: [WorkspaceSavedSearch] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        let idText = stringColumn(stmt, index: 0)
        let name = stringColumn(stmt, index: 1)
        let queryJSON = stringColumn(stmt, index: 2)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

        if let data = queryJSON.data(using: .utf8),
          let query = try? decoder.decode(DocumentQuery.self, from: data)
        {
          results.append(
            WorkspaceSavedSearch(
              id: UUID(uuidString: idText) ?? UUID(),
              name: name,
              query: query,
              createdAt: createdAt
            )
          )
        }
      }

      return results
    }
  }

  public func upsertSavedSearch(_ search: WorkspaceSavedSearch) throws {
    let queryData = try encoder.encode(search.query)
    let queryJSON = String(data: queryData, encoding: .utf8) ?? "{}"

    let sql = """
      INSERT INTO saved_searches(id, name, query_json, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        query_json = excluded.query_json,
        created_at = excluded.created_at;
    """

    try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, search.id.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(stmt, 2, search.name, -1, sqliteTransient)
      sqlite3_bind_text(stmt, 3, queryJSON, -1, sqliteTransient)
      sqlite3_bind_double(stmt, 4, search.createdAt.timeIntervalSince1970)

      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw sqliteError(db)
      }
    }
  }

  public func deleteSavedSearch(id: UUID) throws {
    let sql = "DELETE FROM saved_searches WHERE id = ?;"

    try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)

      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw sqliteError(db)
      }
    }
  }

  // MARK: - File Operation History

  public func appendFileOperationHistory(
    request: FileOperationRequest,
    status: String,
    transferredBytes: Int64
  ) throws {
    let entry = WorkspaceFileOperationHistoryEntry(
      id: request.id,
      type: request.type,
      sources: request.sources.map(\.path),
      destination: request.destination?.path,
      status: status,
      transferredBytes: transferredBytes,
      createdAt: Date()
    )

    let sourcesData = try encoder.encode(entry.sources)
    let sourcesJSON = String(data: sourcesData, encoding: .utf8) ?? "[]"

    let sql = """
      INSERT OR REPLACE INTO file_operation_history(
        id, type, sources_json, destination, status, transferred_bytes, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
    """

    try withConnection { db in
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw sqliteError(db)
      }
      defer { sqlite3_finalize(stmt) }

      sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, sqliteTransient)
      sqlite3_bind_text(stmt, 2, entry.type.rawValue, -1, sqliteTransient)
      sqlite3_bind_text(stmt, 3, sourcesJSON, -1, sqliteTransient)
      if let destination = entry.destination {
        sqlite3_bind_text(stmt, 4, destination, -1, sqliteTransient)
      } else {
        sqlite3_bind_null(stmt, 4)
      }
      sqlite3_bind_text(stmt, 5, entry.status, -1, sqliteTransient)
      sqlite3_bind_int64(stmt, 6, entry.transferredBytes)
      sqlite3_bind_double(stmt, 7, entry.createdAt.timeIntervalSince1970)

      guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw sqliteError(db)
      }
    }
  }

  // MARK: - Helpers

  private func withConnection<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
    var db: OpaquePointer?

    guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
      let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
      if let db { sqlite3_close(db) }
      throw WorkspaceDatabaseError.unableToOpen(message)
    }

    defer {
      sqlite3_close(db)
    }

    return try body(db)
  }

  @discardableResult
  private func execute(_ db: OpaquePointer?, sql: String) throws -> Int32 {
    var errorMessage: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

    if result != SQLITE_OK {
      let message = errorMessage.map { String(cString: $0) } ?? "sqlite error"
      sqlite3_free(errorMessage)
      throw WorkspaceDatabaseError.sqlite(message)
    }

    return result
  }

  private func readUserVersion(_ db: OpaquePointer?) throws -> Int {
    let sql = "PRAGMA user_version;"
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      throw sqliteError(db)
    }
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW else {
      return 0
    }

    return Int(sqlite3_column_int(stmt, 0))
  }

  private func sqliteError(_ db: OpaquePointer?) -> WorkspaceDatabaseError {
    WorkspaceDatabaseError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error")
  }

  private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
    guard let cString = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: cString)
  }
}
