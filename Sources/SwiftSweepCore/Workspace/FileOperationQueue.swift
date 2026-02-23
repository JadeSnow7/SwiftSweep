import Foundation

public enum FileOperationQueueError: Error, LocalizedError, Sendable {
  case missingDestination
  case invalidRenameRequest

  public var errorDescription: String? {
    switch self {
    case .missingDestination:
      return "Destination is required for this file operation."
    case .invalidRenameRequest:
      return "Rename operation requires exactly one source and one destination."
    }
  }
}

public actor FileOperationQueue {
  public static let shared = FileOperationQueue()

  private let fileManager = FileManager.default

  private var requests: [UUID: FileOperationRequest] = [:]
  private var progressByID: [UUID: FileOperationProgress] = [:]
  private var queueOrder: [UUID] = []

  private var pausedRequests: Set<UUID> = []
  private var cancelledRequests: Set<UUID> = []
  private var tasks: [UUID: Task<Void, Never>] = [:]

  public init() {}

  public func enqueue(_ request: FileOperationRequest) async {
    requests[request.id] = request
    queueOrder.append(request.id)

    progressByID[request.id] = FileOperationProgress(
      requestID: request.id,
      processedCount: 0,
      totalCount: max(1, request.sources.count),
      transferredBytes: 0,
      status: .queued
    )

    startTaskIfNeeded(for: request.id)
  }

  public func pause(_ id: UUID) async {
    guard progressByID[id] != nil else { return }
    pausedRequests.insert(id)
    updateProgress(id: id, status: .paused)
  }

  public func resume(_ id: UUID) async {
    guard progressByID[id] != nil else { return }
    pausedRequests.remove(id)
    updateProgress(id: id, status: .running)
    startTaskIfNeeded(for: id)
  }

  public func cancel(_ id: UUID) async {
    cancelledRequests.insert(id)
    tasks[id]?.cancel()
    updateProgress(id: id, status: .cancelled)

    if let request = requests[id] {
      try? await WorkspaceDatabase.shared.appendFileOperationHistory(
        request: request,
        status: "cancelled",
        transferredBytes: progressByID[id]?.transferredBytes ?? 0
      )
    }
  }

  public func snapshot() async -> [FileOperationProgress] {
    queueOrder.compactMap { progressByID[$0] }
  }

  // MARK: - Worker

  private func startTaskIfNeeded(for id: UUID) {
    guard tasks[id] == nil else { return }
    guard requests[id] != nil else { return }

    tasks[id] = Task {
      await self.runOperation(id: id)
    }
  }

  private func runOperation(id: UUID) async {
    defer {
      tasks[id] = nil
    }

    guard let request = requests[id] else { return }

    updateProgress(id: id, status: .running)

    do {
      var processed = 0
      var transferred: Int64 = 0

      for source in request.sources {
        try Task.checkCancellation()

        if cancelledRequests.contains(id) {
          updateProgress(id: id, status: .cancelled)
          try? await WorkspaceDatabase.shared.appendFileOperationHistory(
            request: request,
            status: "cancelled",
            transferredBytes: transferred
          )
          return
        }

        try await waitIfPaused(id: id)
        try Task.checkCancellation()

        let bytes = try performSingleOperation(request: request, source: source)
        processed += 1
        transferred += bytes

        progressByID[id] = FileOperationProgress(
          requestID: id,
          processedCount: processed,
          totalCount: max(1, request.sources.count),
          transferredBytes: transferred,
          status: .running
        )
      }

      updateProgress(id: id, status: .completed)
      try? await WorkspaceDatabase.shared.appendFileOperationHistory(
        request: request,
        status: "completed",
        transferredBytes: transferred
      )
    } catch is CancellationError {
      updateProgress(id: id, status: .cancelled)
      try? await WorkspaceDatabase.shared.appendFileOperationHistory(
        request: request,
        status: "cancelled",
        transferredBytes: progressByID[id]?.transferredBytes ?? 0
      )
    } catch {
      updateProgress(id: id, status: .failed(error.localizedDescription))
      try? await WorkspaceDatabase.shared.appendFileOperationHistory(
        request: request,
        status: "failed: \(error.localizedDescription)",
        transferredBytes: progressByID[id]?.transferredBytes ?? 0
      )
    }
  }

  private func performSingleOperation(request: FileOperationRequest, source: URL) throws -> Int64 {
    switch request.type {
    case .copy:
      guard let destination = request.destination else {
        throw FileOperationQueueError.missingDestination
      }
      if let target = try resolveTarget(source: source, destinationRoot: destination, policy: request.conflictPolicy) {
        try fileManager.copyItem(at: source, to: target)
        return fileSize(at: target)
      }
      return 0

    case .move:
      guard let destination = request.destination else {
        throw FileOperationQueueError.missingDestination
      }
      if let target = try resolveTarget(source: source, destinationRoot: destination, policy: request.conflictPolicy) {
        try fileManager.moveItem(at: source, to: target)
        return fileSize(at: target)
      }
      return 0

    case .rename:
      guard request.sources.count == 1, let destination = request.destination else {
        throw FileOperationQueueError.invalidRenameRequest
      }

      let target: URL
      switch request.conflictPolicy {
      case .replace:
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        target = destination
      case .keepBoth:
        target = uniqueDestinationURL(base: destination)
      case .skip:
        if fileManager.fileExists(atPath: destination.path) {
          return 0
        }
        target = destination
      }

      try fileManager.moveItem(at: source, to: target)
      return fileSize(at: target)

    case .trash:
      let sourceSize = fileSize(at: source)
      try fileManager.trashItem(at: source, resultingItemURL: nil)
      return sourceSize
    }
  }

  private func resolveTarget(
    source: URL,
    destinationRoot: URL,
    policy: FileConflictPolicy
  ) throws -> URL? {
    let candidate = destinationRoot.appendingPathComponent(source.lastPathComponent)

    if !fileManager.fileExists(atPath: candidate.path) {
      return candidate
    }

    switch policy {
    case .skip:
      return nil
    case .replace:
      try fileManager.removeItem(at: candidate)
      return candidate
    case .keepBoth:
      return uniqueDestinationURL(base: candidate)
    }
  }

  private func uniqueDestinationURL(base: URL) -> URL {
    guard fileManager.fileExists(atPath: base.path) else { return base }

    let directory = base.deletingLastPathComponent()
    let ext = base.pathExtension
    let stem = base.deletingPathExtension().lastPathComponent

    var index = 1
    while true {
      let suffix = index == 1 ? " copy" : " copy \(index)"
      let candidateName = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
      let candidate = directory.appendingPathComponent(candidateName)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  private func waitIfPaused(id: UUID) async throws {
    while pausedRequests.contains(id) {
      try Task.checkCancellation()
      if cancelledRequests.contains(id) {
        throw CancellationError()
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private func fileSize(at url: URL) -> Int64 {
    if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]),
      let size = values.totalFileAllocatedSize ?? values.fileSize
    {
      return Int64(size)
    }

    if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? NSNumber
    {
      return size.int64Value
    }

    return 0
  }

  private func updateProgress(id: UUID, status: FileOperationProgress.Status) {
    guard let old = progressByID[id] else { return }
    progressByID[id] = FileOperationProgress(
      requestID: old.requestID,
      processedCount: old.processedCount,
      totalCount: old.totalCount,
      transferredBytes: old.transferredBytes,
      status: status
    )
  }
}
