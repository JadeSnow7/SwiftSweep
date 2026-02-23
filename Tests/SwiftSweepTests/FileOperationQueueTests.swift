import XCTest

@testable import SwiftSweepCore

final class FileOperationQueueTests: XCTestCase {
  func testCopyOperationCompletes() async throws {
    let queue = FileOperationQueue()

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-fileop-\(UUID().uuidString)")
    let sourceDir = root.appendingPathComponent("source", isDirectory: true)
    let destinationDir = root.appendingPathComponent("destination", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

    let sourceFile = sourceDir.appendingPathComponent("hello.txt")
    try Data("hello workspace".utf8).write(to: sourceFile)

    let request = FileOperationRequest(
      type: .copy,
      sources: [sourceFile],
      destination: destinationDir,
      conflictPolicy: .keepBoth
    )

    await queue.enqueue(request)
    try await waitForCompletion(queue: queue, requestID: request.id)

    let copiedFile = destinationDir.appendingPathComponent("hello.txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFile.path))

    try? FileManager.default.removeItem(at: root)
  }

  func testCancelMarksOperationCancelled() async throws {
    let queue = FileOperationQueue()

    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-fileop-cancel-\(UUID().uuidString)")
    let sourceDir = root.appendingPathComponent("source", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

    var files: [URL] = []
    for index in 0..<20 {
      let file = sourceDir.appendingPathComponent("f\(index).txt")
      try Data(repeating: UInt8(index), count: 1024 * 32).write(to: file)
      files.append(file)
    }

    let request = FileOperationRequest(
      type: .trash,
      sources: files,
      destination: nil,
      conflictPolicy: .keepBoth
    )

    await queue.enqueue(request)
    await queue.cancel(request.id)

    let snapshot = await queue.snapshot()
    let progress = snapshot.first(where: { $0.requestID == request.id })
    XCTAssertNotNil(progress)

    try? FileManager.default.removeItem(at: root)
  }

  private func waitForCompletion(
    queue: FileOperationQueue,
    requestID: UUID,
    timeout: TimeInterval = 8
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let snapshot = await queue.snapshot()
      if let progress = snapshot.first(where: { $0.requestID == requestID }) {
        switch progress.status {
        case .completed:
          return
        case .failed(let message):
          XCTFail("Operation failed: \(message)")
          return
        case .cancelled:
          XCTFail("Operation cancelled unexpectedly")
          return
        default:
          break
        }
      }

      try await Task.sleep(nanoseconds: 100_000_000)
    }

    XCTFail("Timed out waiting for operation completion")
  }
}
