import Foundation

private let scheduler = ConcurrentScheduler.shared

@MainActor
public func cleanupEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .cleanup(let cleanupAction) = action else { return }

  switch cleanupAction {
  case .startScan:
    await runCleanupScanEffect(store)

  case .startClean:
    await runCleanEffect(store)

  // State-only actions don't trigger effects
  case .scanCompleted, .scanFailed, .toggleItem, .selectAll, .deselectAll,
    .confirmClean, .cancelClean, .cleanCompleted, .reset:
    break
  }
}

// MARK: - Scan Effect

@MainActor
private func runCleanupScanEffect(_ store: AppStore) async {
  do {
    let items = try await scheduler.schedule(priority: .normal) {
      try await CleanupEngine.shared.scanForCleanableItems()
    }
    store.dispatch(.cleanup(.scanCompleted(items)))
  } catch {
    store.dispatch(.cleanup(.scanFailed(error.localizedDescription)))
  }
}

// MARK: - Clean Effect

@MainActor
private func runCleanEffect(_ store: AppStore) async {
  let selectedItems = store.state.cleanup.selectedItems
  guard !selectedItems.isEmpty else { return }

  var successCount = 0
  var failedCount = 0
  var freedBytes: Int64 = 0
  let fm = FileManager.default

  for item in selectedItems {
    do {
      try fm.removeItem(atPath: item.path)
      successCount += 1
      freedBytes += item.size
    } catch {
      failedCount += 1
      print("Failed to delete \(item.path): \(error)")
    }
  }

  let result = CleanupResult(
    successCount: successCount,
    failedCount: failedCount,
    freedBytes: freedBytes
  )
  store.dispatch(.cleanup(.cleanCompleted(result)))
}
