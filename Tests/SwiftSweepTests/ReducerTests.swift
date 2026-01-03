import XCTest

@testable import SwiftSweepCore

final class ReducerTests: XCTestCase {

  // MARK: - Navigation Reducer Tests

  func testNavigationRequestUninstall() {
    var state = NavigationState()
    let url = URL(fileURLWithPath: "/Applications/Test.app")

    state = navigationReducer(state, .requestUninstall(url))

    XCTAssertEqual(state.pendingUninstallURL, url)
  }

  func testNavigationClearUninstallRequest() {
    var state = NavigationState(pendingUninstallURL: URL(fileURLWithPath: "/test"))

    state = navigationReducer(state, .clearUninstallRequest)

    XCTAssertNil(state.pendingUninstallURL)
  }

  // MARK: - Uninstall Reducer Tests

  func testUninstallStartScan() {
    var state = UninstallState()

    state = uninstallReducer(state, .startScan)

    XCTAssertEqual(state.phase, .scanning)
  }

  func testUninstallScanCompleted() {
    var state = UninstallState()
    state.phase = .scanning

    let apps = [
      UninstallEngine.InstalledApp(
        name: "Test.app", bundleID: "com.test", path: "/Applications/Test.app",
        size: 1000, lastUsed: nil)
    ]

    state = uninstallReducer(state, .scanCompleted(apps))

    XCTAssertEqual(state.phase, .scanned)
    XCTAssertEqual(state.apps.count, 1)
    XCTAssertEqual(state.apps.first?.name, "Test.app")
  }

  func testUninstallSelectApp() {
    var state = UninstallState()
    let app = UninstallEngine.InstalledApp(
      name: "Test.app", bundleID: "com.test", path: "/Applications/Test.app",
      size: 1000, lastUsed: nil)
    state.apps = [app]

    state = uninstallReducer(state, .selectApp(app.id))

    XCTAssertEqual(state.selectedAppID, app.id)
    XCTAssertTrue(state.residuals.isEmpty)
    XCTAssertNil(state.deletionPlan)
  }

  func testUninstallPendingSelectionAppliedOnScan() {
    var state = UninstallState()
    let pendingURL = URL(fileURLWithPath: "/Applications/Test.app")
    state.pendingSelectionURL = pendingURL

    let app = UninstallEngine.InstalledApp(
      name: "Test.app", bundleID: "com.test", path: "/Applications/Test.app",
      size: 1000, lastUsed: nil)

    state = uninstallReducer(state, .scanCompleted([app]))

    XCTAssertEqual(state.selectedAppID, app.id)
    XCTAssertNil(state.pendingSelectionURL)
  }

  func testUninstallCancelUninstall() {
    var state = UninstallState()
    state.deletionPlan = DeletionPlan(
      app: UninstallEngine.InstalledApp(
        name: "Test.app", bundleID: "com.test", path: "/test", size: 0, lastUsed: nil),
      items: [])

    state = uninstallReducer(state, .cancelUninstall)

    XCTAssertNil(state.deletionPlan)
    XCTAssertNil(state.deletionResult)
  }

  func testUninstallReset() {
    var state = UninstallState()
    state.phase = .done
    state.selectedAppID = UUID()
    state.residuals = [UninstallEngine.ResidualFile(path: "/test", size: 100, type: .cache)]

    state = uninstallReducer(state, .reset)

    XCTAssertEqual(state.phase, .idle)
    XCTAssertNil(state.selectedAppID)
    XCTAssertTrue(state.residuals.isEmpty)
  }

  // MARK: - Cleanup Reducer Tests

  func testCleanupStartScan() {
    var state = CleanupState()
    state.items = [
      CleanupEngine.CleanupItem(name: "Old", path: "/old", size: 1, itemCount: 1, category: .logs)
    ]

    state = cleanupReducer(state, .startScan)

    XCTAssertEqual(state.phase, .scanning)
    XCTAssertTrue(state.items.isEmpty)
    XCTAssertNil(state.cleanResult)
  }

  func testCleanupScanCompleted() {
    var state = CleanupState()
    state.phase = .scanning

    let items = [
      CleanupEngine.CleanupItem(
        name: "Cache", path: "/cache", size: 1000, itemCount: 1, category: .userCache)
    ]

    state = cleanupReducer(state, .scanCompleted(items))

    XCTAssertEqual(state.phase, .scanned)
    XCTAssertEqual(state.items.count, 1)
  }

  func testCleanupToggleItem() {
    var state = CleanupState()
    var item = CleanupEngine.CleanupItem(
      name: "Cache", path: "/cache", size: 1000, itemCount: 1, category: .userCache)
    item.isSelected = true
    state.items = [item]

    state = cleanupReducer(state, .toggleItem(item.id))

    XCTAssertFalse(state.items.first!.isSelected)
  }

  func testCleanupSelectAll() {
    var state = CleanupState()
    var item1 = CleanupEngine.CleanupItem(
      name: "Cache1", path: "/cache1", size: 100, itemCount: 1, category: .userCache)
    var item2 = CleanupEngine.CleanupItem(
      name: "Cache2", path: "/cache2", size: 200, itemCount: 1, category: .logs)
    item1.isSelected = false
    item2.isSelected = false
    state.items = [item1, item2]

    state = cleanupReducer(state, .selectAll)

    XCTAssertTrue(state.items.allSatisfy { $0.isSelected })
  }

  func testCleanupDeselectAll() {
    var state = CleanupState()
    state.items = [
      CleanupEngine.CleanupItem(
        name: "Cache1", path: "/cache1", size: 100, itemCount: 1, category: .userCache),
      CleanupEngine.CleanupItem(
        name: "Cache2", path: "/cache2", size: 200, itemCount: 1, category: .logs),
    ]

    state = cleanupReducer(state, .deselectAll)

    XCTAssertTrue(state.items.allSatisfy { !$0.isSelected })
  }

  func testCleanupCleanCompleted() {
    var state = CleanupState()
    state.phase = .cleaning
    var item1 = CleanupEngine.CleanupItem(
      name: "Cache1", path: "/cache1", size: 100, itemCount: 1, category: .userCache)
    item1.isSelected = true
    var item2 = CleanupEngine.CleanupItem(
      name: "Cache2", path: "/cache2", size: 200, itemCount: 1, category: .logs)
    item2.isSelected = false
    state.items = [item1, item2]

    let result = CleanupResult(successCount: 1, failedCount: 0, freedBytes: 100)
    state = cleanupReducer(state, .cleanCompleted(result))

    XCTAssertEqual(state.phase, .completed)
    XCTAssertEqual(state.cleanResult?.successCount, 1)
    XCTAssertEqual(state.items.count, 1)  // Only unselected item remains
    XCTAssertEqual(state.items.first?.name, "Cache2")
  }

  func testCleanupReset() {
    var state = CleanupState()
    state.phase = .completed
    state.items = [
      CleanupEngine.CleanupItem(
        name: "Cache", path: "/cache", size: 100, itemCount: 1, category: .userCache)
    ]
    state.cleanResult = CleanupResult(successCount: 1, failedCount: 0, freedBytes: 100)

    state = cleanupReducer(state, .reset)

    XCTAssertEqual(state.phase, .idle)
    XCTAssertTrue(state.items.isEmpty)
    XCTAssertNil(state.cleanResult)
  }

  // MARK: - App Reducer Tests (Root)

  func testAppReducerRoutesToUninstall() {
    var state = AppState()

    state = appReducer(state, .uninstall(.startScan))

    XCTAssertEqual(state.uninstall.phase, .scanning)
  }

  func testAppReducerRoutesToCleanup() {
    var state = AppState()

    state = appReducer(state, .cleanup(.startScan))

    XCTAssertEqual(state.cleanup.phase, .scanning)
  }

  func testAppReducerRoutesToNavigation() {
    var state = AppState()
    let url = URL(fileURLWithPath: "/test")

    state = appReducer(state, .navigation(.requestUninstall(url)))

    XCTAssertEqual(state.navigation.pendingUninstallURL, url)
  }
}
