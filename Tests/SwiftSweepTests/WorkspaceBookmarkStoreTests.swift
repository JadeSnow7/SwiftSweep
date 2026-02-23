import XCTest

@testable import SwiftSweepCore

final class WorkspaceBookmarkStoreTests: XCTestCase {
  func testBookmarkRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let db = WorkspaceDatabase(baseDirectory: root)
    try await db.setupSchema()

    try await db.upsertBookmark(path: "/tmp/test", bookmarkData: Data([0x1, 0x2]))
    let bookmarks = try await db.loadBookmarks()

    XCTAssertEqual(bookmarks.count, 1)
    XCTAssertEqual(bookmarks.first?.path, "/tmp/test")

    try? FileManager.default.removeItem(at: root)
  }

  func testTagsReplaceRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-db-tags-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let db = WorkspaceDatabase(baseDirectory: root)
    try await db.setupSchema()

    try await db.replaceTags(forPath: "/tmp/a.txt", tags: ["important", "favorite"])
    let tags = try await db.loadTags(forPath: "/tmp/a.txt")

    XCTAssertEqual(Set(tags), Set(["important", "favorite"]))

    try? FileManager.default.removeItem(at: root)
  }
}
