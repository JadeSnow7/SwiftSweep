import Foundation

public protocol WorkspaceBrowsingService: Sendable {
  func list(url: URL, options: ListOptions) async throws -> [WorkspaceItem]
  func search(root: URL, query: WorkspaceQuery) async throws -> [WorkspaceItem]
}

public enum WorkspaceBrowsingError: Error, LocalizedError, Sendable {
  case invalidURL
  case permissionDenied

  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid location."
    case .permissionDenied:
      return "Permission denied for this location."
    }
  }
}

public actor LocalWorkspaceBrowsingService: WorkspaceBrowsingService {
  public static let shared = LocalWorkspaceBrowsingService()

  private let fileManager = FileManager.default

  public init() {}

  public func list(url: URL, options: ListOptions = .init()) async throws -> [WorkspaceItem] {
    guard fileManager.fileExists(atPath: url.path) else {
      throw WorkspaceBrowsingError.invalidURL
    }

    let keys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isVolumeKey,
      .nameKey,
      .contentModificationDateKey,
      .isHiddenKey,
      .fileSizeKey,
      .totalFileAllocatedSizeKey,
    ]

    let contents: [URL]
    do {
      contents = try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: keys,
        options: options.includeHidden ? [] : [.skipsHiddenFiles]
      )
    } catch {
      throw WorkspaceBrowsingError.permissionDenied
    }

    var items = contents.compactMap { makeWorkspaceItem(from: $0, tags: []) }

    if !options.sort.orderIsNaturalForField {
      items.sort(by: itemComparator(sort: options.sort))
    } else {
      items.sort(by: itemComparator(sort: options.sort))
    }

    return items
  }

  public func search(root: URL, query: WorkspaceQuery) async throws -> [WorkspaceItem] {
    guard fileManager.fileExists(atPath: root.path) else {
      throw WorkspaceBrowsingError.invalidURL
    }

    let keys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isVolumeKey,
      .nameKey,
      .contentModificationDateKey,
      .isHiddenKey,
      .fileSizeKey,
      .totalFileAllocatedSizeKey,
    ]

    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: query.includeHidden ? [] : [.skipsHiddenFiles]
      )
    else {
      throw WorkspaceBrowsingError.permissionDenied
    }

    var results: [WorkspaceItem] = []
    let urls = enumerator.allObjects.compactMap { $0 as? URL }

    for url in urls {
      if Task.isCancelled { break }

      guard let item = makeWorkspaceItem(from: url, tags: []) else { continue }
      if !query.allowedKinds.isEmpty && !query.allowedKinds.contains(item.kind) {
        continue
      }

      if let minSize = query.minSize {
        let size = item.size ?? 0
        if size < minSize { continue }
      }

      if let maxSize = query.maxSize {
        let size = item.size ?? 0
        if size > maxSize { continue }
      }

      if let modifiedAfter = query.modifiedAfter,
        let modifiedAt = item.modifiedAt,
        modifiedAt < modifiedAfter
      {
        continue
      }

      if let modifiedBefore = query.modifiedBefore,
        let modifiedAt = item.modifiedAt,
        modifiedAt > modifiedBefore
      {
        continue
      }

      if !query.text.isEmpty {
        let text = query.text.lowercased()
        let haystack = "\(url.lastPathComponent.lowercased()) \(url.path.lowercased())"
        if !haystack.contains(text) {
          continue
        }
      }

      results.append(item)
      if results.count >= query.maxResults {
        break
      }
    }

    return results
  }

  private func makeWorkspaceItem(from url: URL, tags: [String]) -> WorkspaceItem? {
    let values = try? url.resourceValues(forKeys: [
      .isDirectoryKey,
      .isVolumeKey,
      .isHiddenKey,
      .contentModificationDateKey,
      .fileSizeKey,
      .totalFileAllocatedSizeKey,
    ])

    let isDirectory = values?.isDirectory ?? false
    let isVolume = values?.isVolume ?? false

    let kind: WorkspaceItemKind
    if isVolume {
      kind = .volume
    } else if url.pathExtension.lowercased() == "app" {
      kind = .app
    } else if isDirectory {
      kind = .folder
    } else {
      kind = .file
    }

    let size: Int64?
    if isDirectory {
      size = nil
    } else if let allocated = values?.totalFileAllocatedSize {
      size = Int64(allocated)
    } else if let fileSize = values?.fileSize {
      size = Int64(fileSize)
    } else {
      size = nil
    }

    return WorkspaceItem(
      id: url.path,
      url: url,
      kind: kind,
      size: size,
      modifiedAt: values?.contentModificationDate,
      tags: tags,
      isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix(".")
    )
  }

  private func itemComparator(sort: WorkspaceSortDescriptor) -> (WorkspaceItem, WorkspaceItem) -> Bool {
    return { lhs, rhs in
      let ascending = sort.order == .ascending
      switch sort.field {
      case .name:
        let result = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
        return ascending ? result == .orderedAscending : result == .orderedDescending
      case .size:
        let l = lhs.size ?? -1
        let r = rhs.size ?? -1
        return ascending ? l < r : l > r
      case .kind:
        let result = lhs.kind.rawValue.localizedCaseInsensitiveCompare(rhs.kind.rawValue)
        return ascending ? result == .orderedAscending : result == .orderedDescending
      case .modifiedAt:
        let l = lhs.modifiedAt ?? .distantPast
        let r = rhs.modifiedAt ?? .distantPast
        return ascending ? l < r : l > r
      }
    }
  }
}

private extension WorkspaceSortDescriptor {
  var orderIsNaturalForField: Bool {
    field == .name && order == .ascending
  }
}
