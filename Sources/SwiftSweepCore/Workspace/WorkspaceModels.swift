import Foundation

public enum WorkspaceItemKind: String, Sendable, Codable, CaseIterable {
  case file
  case folder
  case app
  case volume
}

public enum WorkspacePane: String, Sendable, Codable, CaseIterable {
  case left
  case right
}

public enum WorkspaceSortField: String, Sendable, Codable, CaseIterable {
  case name
  case size
  case kind
  case modifiedAt
}

public enum WorkspaceSortOrder: String, Sendable, Codable {
  case ascending
  case descending
}

public struct WorkspaceSortDescriptor: Sendable, Codable, Equatable {
  public var field: WorkspaceSortField
  public var order: WorkspaceSortOrder

  public init(field: WorkspaceSortField = .name, order: WorkspaceSortOrder = .ascending) {
    self.field = field
    self.order = order
  }
}

public struct ListOptions: Sendable, Codable, Equatable {
  public var includeHidden: Bool
  public var recursive: Bool
  public var sort: WorkspaceSortDescriptor

  public init(
    includeHidden: Bool = false,
    recursive: Bool = false,
    sort: WorkspaceSortDescriptor = .init()
  ) {
    self.includeHidden = includeHidden
    self.recursive = recursive
    self.sort = sort
  }
}

public struct WorkspaceQuery: Sendable, Codable, Equatable {
  public var text: String
  public var includeHidden: Bool
  public var allowedKinds: Set<WorkspaceItemKind>
  public var maxResults: Int
  public var minSize: Int64?
  public var maxSize: Int64?
  public var modifiedAfter: Date?
  public var modifiedBefore: Date?

  public init(
    text: String = "",
    includeHidden: Bool = false,
    allowedKinds: Set<WorkspaceItemKind> = [],
    maxResults: Int = 1_000,
    minSize: Int64? = nil,
    maxSize: Int64? = nil,
    modifiedAfter: Date? = nil,
    modifiedBefore: Date? = nil
  ) {
    self.text = text
    self.includeHidden = includeHidden
    self.allowedKinds = allowedKinds
    self.maxResults = maxResults
    self.minSize = minSize
    self.maxSize = maxSize
    self.modifiedAfter = modifiedAfter
    self.modifiedBefore = modifiedBefore
  }
}

public struct WorkspaceItem: Identifiable, Sendable, Hashable, Codable {
  public let id: String
  public let url: URL
  public let kind: WorkspaceItemKind
  public let size: Int64?
  public let modifiedAt: Date?
  public let tags: [String]
  public let isHidden: Bool

  public init(
    id: String,
    url: URL,
    kind: WorkspaceItemKind,
    size: Int64?,
    modifiedAt: Date?,
    tags: [String],
    isHidden: Bool
  ) {
    self.id = id
    self.url = url
    self.kind = kind
    self.size = size
    self.modifiedAt = modifiedAt
    self.tags = tags
    self.isHidden = isHidden
  }
}

public enum FileOperationType: String, Sendable, Codable {
  case copy
  case move
  case rename
  case trash
}

public enum FileConflictPolicy: String, Sendable, Codable {
  case keepBoth
  case replace
  case skip
}

public struct FileOperationRequest: Sendable, Codable, Equatable {
  public let id: UUID
  public let type: FileOperationType
  public let sources: [URL]
  public let destination: URL?
  public let conflictPolicy: FileConflictPolicy

  public init(
    id: UUID = UUID(),
    type: FileOperationType,
    sources: [URL],
    destination: URL?,
    conflictPolicy: FileConflictPolicy
  ) {
    self.id = id
    self.type = type
    self.sources = sources
    self.destination = destination
    self.conflictPolicy = conflictPolicy
  }
}

public struct FileOperationProgress: Sendable, Codable, Equatable {
  public let requestID: UUID
  public let processedCount: Int
  public let totalCount: Int
  public let transferredBytes: Int64
  public let status: Status

  public enum Status: Sendable, Codable, Equatable {
    case queued
    case running
    case paused
    case completed
    case failed(String)
    case cancelled
  }

  public init(
    requestID: UUID,
    processedCount: Int,
    totalCount: Int,
    transferredBytes: Int64,
    status: Status
  ) {
    self.requestID = requestID
    self.processedCount = processedCount
    self.totalCount = totalCount
    self.transferredBytes = transferredBytes
    self.status = status
  }
}

public struct WorkspaceBookmark: Sendable, Codable, Equatable, Identifiable {
  public let id: String
  public let path: String
  public let createdAt: Date

  public init(id: String, path: String, createdAt: Date) {
    self.id = id
    self.path = path
    self.createdAt = createdAt
  }
}

public enum PinnedLaunchItemType: String, Sendable, Codable {
  case app
  case folder
}

public struct PinnedLaunchItem: Sendable, Codable, Equatable, Identifiable {
  public let id: UUID
  public let type: PinnedLaunchItemType
  public let path: String
  public let title: String
  public let createdAt: Date
  public let order: Int

  public init(
    id: UUID = UUID(),
    type: PinnedLaunchItemType,
    path: String,
    title: String,
    createdAt: Date = Date(),
    order: Int = 0
  ) {
    self.id = id
    self.type = type
    self.path = path
    self.title = title
    self.createdAt = createdAt
    self.order = order
  }
}

public struct WorkspaceSavedSearch: Sendable, Codable, Equatable, Identifiable {
  public let id: UUID
  public let name: String
  public let query: DocumentQuery
  public let createdAt: Date

  public init(id: UUID = UUID(), name: String, query: DocumentQuery, createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.query = query
    self.createdAt = createdAt
  }
}

public struct DocumentQuery: Sendable, Codable, Equatable {
  public var text: String
  public var extensions: Set<String>
  public var minSize: Int64?
  public var maxSize: Int64?
  public var modifiedAfter: Date?
  public var modifiedBefore: Date?
  public var requiredTags: Set<String>
  public var favoritesOnly: Bool

  public init(
    text: String = "",
    extensions: Set<String> = [],
    minSize: Int64? = nil,
    maxSize: Int64? = nil,
    modifiedAfter: Date? = nil,
    modifiedBefore: Date? = nil,
    requiredTags: Set<String> = [],
    favoritesOnly: Bool = false
  ) {
    self.text = text
    self.extensions = extensions
    self.minSize = minSize
    self.maxSize = maxSize
    self.modifiedAfter = modifiedAfter
    self.modifiedBefore = modifiedBefore
    self.requiredTags = requiredTags
    self.favoritesOnly = favoritesOnly
  }
}

public struct DocumentRecord: Sendable, Codable, Equatable, Identifiable {
  public let id: String
  public let path: String
  public let name: String
  public let fileExtension: String
  public let size: Int64
  public let modifiedAt: Date?
  public let tags: [String]
  public let isFavorite: Bool

  public init(
    id: String,
    path: String,
    name: String,
    fileExtension: String,
    size: Int64,
    modifiedAt: Date?,
    tags: [String],
    isFavorite: Bool
  ) {
    self.id = id
    self.path = path
    self.name = name
    self.fileExtension = fileExtension
    self.size = size
    self.modifiedAt = modifiedAt
    self.tags = tags
    self.isFavorite = isFavorite
  }
}

public struct DocumentCatalogPage: Sendable, Codable, Equatable {
  public let records: [DocumentRecord]
  public let page: Int
  public let pageSize: Int
  public let totalCount: Int

  public init(records: [DocumentRecord], page: Int, pageSize: Int, totalCount: Int) {
    self.records = records
    self.page = page
    self.pageSize = pageSize
    self.totalCount = totalCount
  }
}

public enum WorkspaceMediaKind: String, Sendable, Codable, CaseIterable {
  case image
  case video
  case audio
}

public struct MediaLibraryItem: Sendable, Codable, Equatable, Identifiable {
  public let id: String
  public let path: String
  public let kind: WorkspaceMediaKind
  public let size: Int64
  public let modifiedAt: Date?
  public let createdAt: Date?

  public init(
    id: String,
    path: String,
    kind: WorkspaceMediaKind,
    size: Int64,
    modifiedAt: Date?,
    createdAt: Date?
  ) {
    self.id = id
    self.path = path
    self.kind = kind
    self.size = size
    self.modifiedAt = modifiedAt
    self.createdAt = createdAt
  }
}

public struct WorkspaceFileOperationHistoryEntry: Sendable, Codable, Equatable, Identifiable {
  public let id: UUID
  public let type: FileOperationType
  public let sources: [String]
  public let destination: String?
  public let status: String
  public let transferredBytes: Int64
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    type: FileOperationType,
    sources: [String],
    destination: String?,
    status: String,
    transferredBytes: Int64,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.type = type
    self.sources = sources
    self.destination = destination
    self.status = status
    self.transferredBytes = transferredBytes
    self.createdAt = createdAt
  }
}
