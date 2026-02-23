import XCTest

@testable import SwiftSweepCore

final class DocumentCatalogServiceTests: XCTestCase {
  func testScanReturnsOnlySupportedDocumentTypes() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-docs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let files = [
      root.appendingPathComponent("a.pdf"),
      root.appendingPathComponent("b.docx"),
      root.appendingPathComponent("c.txt"),
      root.appendingPathComponent("movie.mp4"),
    ]

    for file in files {
      try Data("sample".utf8).write(to: file)
    }

    let db = WorkspaceDatabase(baseDirectory: root.appendingPathComponent("db", isDirectory: true))
    try await db.setupSchema()

    let service = DocumentCatalogService(
      browser: LocalWorkspaceBrowsingService.shared,
      database: db
    )

    let page = try await service.scan(root: root, page: 0, pageSize: 50)
    let names = Set(page.records.map(\.name))

    XCTAssertTrue(names.contains("a.pdf"))
    XCTAssertTrue(names.contains("b.docx"))
    XCTAssertTrue(names.contains("c.txt"))
    XCTAssertFalse(names.contains("movie.mp4"))

    try? FileManager.default.removeItem(at: root)
  }

  func testFavoriteFilter() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-docs-fav-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let doc = root.appendingPathComponent("favorite.pdf")
    try Data("doc".utf8).write(to: doc)

    let db = WorkspaceDatabase(baseDirectory: root.appendingPathComponent("db", isDirectory: true))
    try await db.setupSchema()

    let service = DocumentCatalogService(
      browser: LocalWorkspaceBrowsingService.shared,
      database: db
    )

    try await service.setFavorite(path: doc.path, isFavorite: true)

    let page = try await service.scan(
      root: root,
      query: DocumentQuery(favoritesOnly: true),
      page: 0,
      pageSize: 50
    )

    XCTAssertEqual(page.records.count, 1)
    XCTAssertEqual(page.records.first?.path, doc.path)

    try? FileManager.default.removeItem(at: root)
  }
}
