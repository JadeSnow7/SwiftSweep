import Foundation

public actor DocumentCatalogService {
  public static let shared = DocumentCatalogService()

  public static let supportedExtensions: Set<String> = [
    "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md", "rtf",
  ]

  private let browser: WorkspaceBrowsingService
  private let database: WorkspaceDatabase

  public init(
    browser: WorkspaceBrowsingService = LocalWorkspaceBrowsingService.shared,
    database: WorkspaceDatabase = .shared
  ) {
    self.browser = browser
    self.database = database
  }

  public func scan(
    root: URL,
    query: DocumentQuery = .init(),
    page: Int = 0,
    pageSize: Int = 200
  ) async throws -> DocumentCatalogPage {
    let searchQuery = WorkspaceQuery(
      text: query.text,
      includeHidden: false,
      allowedKinds: [.file],
      maxResults: 20_000,
      minSize: query.minSize,
      maxSize: query.maxSize,
      modifiedAfter: query.modifiedAfter,
      modifiedBefore: query.modifiedBefore
    )

    let scanned = try await browser.search(root: root, query: searchQuery)

    var records: [DocumentRecord] = []
    records.reserveCapacity(scanned.count)

    for item in scanned {
      let ext = item.url.pathExtension.lowercased()
      guard Self.supportedExtensions.contains(ext) else { continue }

      if !query.extensions.isEmpty, !query.extensions.contains(ext) {
        continue
      }

      let canonicalPath = WorkspacePath.canonicalize(url: item.url)
      let tags = (try? await database.loadTags(forPath: canonicalPath)) ?? []
      let isFavorite = tags.contains("favorite")

      if query.favoritesOnly && !isFavorite {
        continue
      }

      if !query.requiredTags.isEmpty {
        let tagSet = Set(tags)
        if !query.requiredTags.isSubset(of: tagSet) {
          continue
        }
      }

      let displayPath = WorkspacePath.displayPath(for: canonicalPath, under: root)
      records.append(
        DocumentRecord(
          id: canonicalPath,
          path: displayPath,
          name: item.url.lastPathComponent,
          fileExtension: ext,
          size: item.size ?? 0,
          modifiedAt: item.modifiedAt,
          tags: tags,
          isFavorite: isFavorite
        )
      )
    }

    records.sort { lhs, rhs in
      let leftDate = lhs.modifiedAt ?? .distantPast
      let rightDate = rhs.modifiedAt ?? .distantPast
      if leftDate == rightDate {
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      return leftDate > rightDate
    }

    let total = records.count
    let safePageSize = max(1, pageSize)
    let start = min(max(0, page) * safePageSize, total)
    let end = min(start + safePageSize, total)
    let pageRecords = Array(records[start..<end])

    return DocumentCatalogPage(records: pageRecords, page: page, pageSize: safePageSize, totalCount: total)
  }

  public func setFavorite(path: String, isFavorite: Bool) async throws {
    let canonicalPath = WorkspacePath.canonicalize(path)
    var tags = try await database.loadTags(forPath: canonicalPath)

    if isFavorite {
      if !tags.contains("favorite") {
        tags.append("favorite")
      }
    } else {
      tags.removeAll { $0 == "favorite" }
    }

    try await database.replaceTags(forPath: canonicalPath, tags: tags)
  }

  public func replaceTags(path: String, tags: [String]) async throws {
    let canonicalPath = WorkspacePath.canonicalize(path)
    try await database.replaceTags(forPath: canonicalPath, tags: tags)
  }

  public func loadSavedSearches() async throws -> [WorkspaceSavedSearch] {
    try await database.loadSavedSearches()
  }

  public func saveSearch(name: String, query: DocumentQuery) async throws {
    let search = WorkspaceSavedSearch(name: name, query: query)
    try await database.upsertSavedSearch(search)
  }

  public func deleteSearch(id: UUID) async throws {
    try await database.deleteSavedSearch(id: id)
  }
}
