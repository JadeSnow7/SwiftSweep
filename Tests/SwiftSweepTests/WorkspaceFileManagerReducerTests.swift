import XCTest

@testable import SwiftSweepCore

final class WorkspaceFileManagerReducerTests: XCTestCase {
  func testBootTransitionsToLoading() {
    let initial = WorkspaceFileManagerState()

    let reduced = workspaceFileManagerReducer(initial, .boot)

    XCTAssertEqual(reduced.phase, .loading)
  }

  func testCreateTabSelectsNewTab() {
    var state = WorkspaceFileManagerState()
    let originalCount = state.leftPane.tabs.count

    state = workspaceFileManagerReducer(state, .createTab(pane: .left, location: nil))

    XCTAssertEqual(state.leftPane.tabs.count, originalCount + 1)
    XCTAssertEqual(state.leftPane.selectedTabID, state.leftPane.tabs.last?.id)
  }

  func testQueueSnapshotUpdate() {
    var state = WorkspaceFileManagerState()
    let progress = FileOperationProgress(
      requestID: UUID(),
      processedCount: 1,
      totalCount: 2,
      transferredBytes: 1024,
      status: .running
    )

    state = workspaceFileManagerReducer(state, .queueSnapshotUpdated([progress]))

    XCTAssertEqual(state.queueItems.count, 1)
    XCTAssertEqual(state.queueItems.first?.requestID, progress.requestID)
  }

  func testOpenCompletedUpdatesSelectedTabItems() {
    var state = WorkspaceFileManagerState()
    guard let selected = state.leftPane.selectedTab else {
      XCTFail("Missing left pane selected tab")
      return
    }

    let root = FileManager.default.homeDirectoryForCurrentUser
    let items = [
      WorkspaceItem(
        id: "b",
        url: root.appendingPathComponent("b.txt"),
        kind: .file,
        size: 20,
        modifiedAt: Date(),
        tags: [],
        isHidden: false
      ),
      WorkspaceItem(
        id: "a",
        url: root.appendingPathComponent("a.txt"),
        kind: .file,
        size: 10,
        modifiedAt: Date(),
        tags: [],
        isHidden: false
      ),
    ]

    state = workspaceFileManagerReducer(
      state,
      .openCompleted(pane: .left, tabID: selected.id, location: root, items: items)
    )

    XCTAssertEqual(state.phase, .loaded)
    XCTAssertEqual(state.leftPane.selectedTab?.items.count, 2)
  }
}
