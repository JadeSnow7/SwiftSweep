import XCTest

@testable import SwiftSweepCore

final class LauncherViewModelTests: XCTestCase {
  func testAddPinnedFolderAvoidsDuplicatePath() {
    var state = WorkspaceLauncherState()
    let folder = URL(fileURLWithPath: "/Users/test/Documents")

    state = workspaceLauncherReducer(state, .addPinnedFolder(folder))
    state = workspaceLauncherReducer(state, .addPinnedFolder(folder))

    XCTAssertEqual(state.pinnedItems.count, 1)
    XCTAssertEqual(state.pinnedItems.first?.type, .folder)
  }

  func testRemovePinnedReindexesOrder() {
    var state = WorkspaceLauncherState()

    state = workspaceLauncherReducer(
      state,
      .addPinnedApp(path: "/Applications/A.app", title: "A")
    )
    state = workspaceLauncherReducer(
      state,
      .addPinnedApp(path: "/Applications/B.app", title: "B")
    )

    let removeID = state.pinnedItems.first!.id
    state = workspaceLauncherReducer(state, .removePinned(removeID))

    XCTAssertEqual(state.pinnedItems.count, 1)
    XCTAssertEqual(state.pinnedItems.first?.order, 0)
    XCTAssertEqual(state.pinnedItems.first?.title, "B")
  }
}
