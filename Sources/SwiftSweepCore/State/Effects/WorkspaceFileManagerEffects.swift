import Foundation

@MainActor
public func workspaceFileManagerEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .workspaceFileManager(let workspaceAction) = action else { return }

  switch workspaceAction {
  case .boot:
    store.dispatch(.workspaceFileManager(.refreshVolumes))

    if let leftTab = store.state.workspaceFileManager.leftPane.selectedTab {
      store.dispatch(.workspaceFileManager(.openLocation(leftTab.locationURL, pane: .left)))
    }

    if let rightTab = store.state.workspaceFileManager.rightPane.selectedTab {
      store.dispatch(.workspaceFileManager(.openLocation(rightTab.locationURL, pane: .right)))
    }

    let snapshot = await FileOperationQueue.shared.snapshot()
    store.dispatch(.workspaceFileManager(.queueSnapshotUpdated(snapshot)))

  case .refreshVolumes:
    let volumeKeys: [URLResourceKey] = [.volumeLocalizedNameKey]
    let volumes = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: volumeKeys,
      options: [.skipHiddenVolumes]
    ) ?? []
    store.dispatch(.workspaceFileManager(.volumesUpdated(volumes)))

  case .openLocation(let location, let pane):
    await runOpenLocationEffect(location: location, pane: pane, store: store)

  case .createTab(let pane, _):
    if let tab = currentSelectedTab(for: pane, in: store.state.workspaceFileManager) {
      store.dispatch(.workspaceFileManager(.openLocation(tab.locationURL, pane: pane)))
    }

  case .selectTab(let pane, _):
    if let tab = currentSelectedTab(for: pane, in: store.state.workspaceFileManager), tab.items.isEmpty {
      store.dispatch(.workspaceFileManager(.openLocation(tab.locationURL, pane: pane)))
    }

  case .setSort(let pane, _, _):
    if let tab = currentSelectedTab(for: pane, in: store.state.workspaceFileManager) {
      store.dispatch(.workspaceFileManager(.openLocation(tab.locationURL, pane: pane)))
    }

  case .enqueueOperation(let type, let sources, let destination, let conflictPolicy):
    guard !sources.isEmpty else { return }

    let request = FileOperationRequest(
      type: type,
      sources: sources,
      destination: destination,
      conflictPolicy: conflictPolicy ?? .keepBoth
    )

    await FileOperationQueue.shared.enqueue(request)
    let snapshot = await FileOperationQueue.shared.snapshot()
    store.dispatch(.workspaceFileManager(.queueSnapshotUpdated(snapshot)))

  case .pauseOperation(let id):
    await FileOperationQueue.shared.pause(id)
    let snapshot = await FileOperationQueue.shared.snapshot()
    store.dispatch(.workspaceFileManager(.queueSnapshotUpdated(snapshot)))

  case .resumeOperation(let id):
    await FileOperationQueue.shared.resume(id)
    let snapshot = await FileOperationQueue.shared.snapshot()
    store.dispatch(.workspaceFileManager(.queueSnapshotUpdated(snapshot)))

  case .cancelOperation(let id):
    await FileOperationQueue.shared.cancel(id)
    let snapshot = await FileOperationQueue.shared.snapshot()
    store.dispatch(.workspaceFileManager(.queueSnapshotUpdated(snapshot)))

  case .showQueueSheet,
    .setActivePane,
    .toggleDualPane,
    .closeTab,
    .updateSelection,
    .setPreview,
    .queueSnapshotUpdated,
    .openCompleted,
    .openFailed,
    .volumesUpdated:
    break
  }
}

@MainActor
private func runOpenLocationEffect(location: URL, pane: WorkspacePane?, store: AppStore) async {
  let resolvedPane = pane ?? store.state.workspaceFileManager.activePane
  guard let tab = currentSelectedTab(for: resolvedPane, in: store.state.workspaceFileManager) else {
    return
  }

  do {
    var options = ListOptions()
    options.sort = tab.sort

    let items = try await LocalWorkspaceBrowsingService.shared.list(url: location, options: options)
    store.dispatch(
      .workspaceFileManager(
        .openCompleted(
          pane: resolvedPane,
          tabID: tab.id,
          location: location,
          items: items
        )
      )
    )
  } catch {
    store.dispatch(.workspaceFileManager(.openFailed(error.localizedDescription)))
  }
}

private func currentSelectedTab(
  for pane: WorkspacePane,
  in state: WorkspaceFileManagerState
) -> WorkspaceTabState? {
  switch pane {
  case .left:
    return state.leftPane.selectedTab
  case .right:
    return state.rightPane.selectedTab
  }
}
