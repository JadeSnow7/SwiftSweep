import Foundation

@MainActor
public func workspaceLauncherEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .workspaceLauncher(let launcherAction) = action else { return }

  switch launcherAction {
  case .loadPinned:
    do {
      let pinned = try await WorkspaceDatabase.shared.loadPinnedLaunchItems()
      store.dispatch(.workspaceLauncher(.pinnedLoaded(pinned)))
    } catch {
      store.dispatch(.workspaceLauncher(.failed(error.localizedDescription)))
    }

  case .addPinnedFolder, .addPinnedApp, .removePinned, .movePinned, .savePinned:
    await persistPinnedItems(store)

  case .pinnedLoaded, .failed:
    break
  }
}

@MainActor
private func persistPinnedItems(_ store: AppStore) async {
  do {
    let items = store.state.workspaceLauncher.pinnedItems
    try await WorkspaceDatabase.shared.savePinnedLaunchItems(items)
  } catch {
    store.dispatch(.workspaceLauncher(.failed(error.localizedDescription)))
  }
}
