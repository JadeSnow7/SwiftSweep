import XCTest

@testable import SwiftSweepCore

final class MediaManagerIntegrationTests: XCTestCase {
  func testWorkspaceMediaServiceDetectsMediaKinds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftSweep-media-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let image = root.appendingPathComponent("photo.jpg")
    let video = root.appendingPathComponent("clip.mp4")
    let nonMedia = root.appendingPathComponent("notes.txt")

    try Data(repeating: 1, count: 16).write(to: image)
    try Data(repeating: 2, count: 32).write(to: video)
    try Data(repeating: 3, count: 8).write(to: nonMedia)

    let service = WorkspaceMediaService(scanner: .shared)
    let items = await service.scanLibrary(root: root)

    XCTAssertTrue(items.contains(where: { $0.path == image.path && $0.kind == .image }))
    XCTAssertTrue(items.contains(where: { $0.path == video.path && $0.kind == .video }))
    XCTAssertFalse(items.contains(where: { $0.path == nonMedia.path }))

    try? FileManager.default.removeItem(at: root)
  }

  func testWorkspaceMediaReducerFlow() {
    var state = WorkspaceMediaState()
    let root = URL(fileURLWithPath: "/tmp")

    state = workspaceMediaReducer(state, .setRoot(root))
    XCTAssertEqual(state.phase, .scanning)
    XCTAssertEqual(state.rootURL, root)

    let item = MediaLibraryItem(
      id: "1",
      path: "/tmp/a.jpg",
      kind: .image,
      size: 100,
      modifiedAt: Date(),
      createdAt: Date()
    )

    state = workspaceMediaReducer(state, .scanCompleted([item]))
    XCTAssertEqual(state.phase, .ready)
    XCTAssertEqual(state.items.count, 1)
  }
}
