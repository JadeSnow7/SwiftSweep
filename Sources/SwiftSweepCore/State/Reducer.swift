import Foundation

/// Root Reducer
public func appReducer(_ state: AppState, _ action: AppAction) -> AppState {
  var newState = state
  switch action {
  case .navigation(let action):
    newState.navigation = navigationReducer(state.navigation, action)
  case .uninstall(let action):
    newState.uninstall = uninstallReducer(state.uninstall, action)
  case .cleanup(let action):
    newState.cleanup = cleanupReducer(state.cleanup, action)
  case .insights(let action):
    newState.insights = insightsReducer(state.insights, action)
  case .status(let action):
    newState.status = statusReducer(state.status, action)
  case .workspaceFileManager(let action):
    newState.workspaceFileManager = workspaceFileManagerReducer(state.workspaceFileManager, action)
  case .workspaceLauncher(let action):
    newState.workspaceLauncher = workspaceLauncherReducer(state.workspaceLauncher, action)
  case .workspaceMedia(let action):
    newState.workspaceMedia = workspaceMediaReducer(state.workspaceMedia, action)
  case .workspaceDocuments(let action):
    newState.workspaceDocuments = workspaceDocumentsReducer(state.workspaceDocuments, action)
  }
  return newState
}

/// Navigation Reducer
public func navigationReducer(_ state: NavigationState, _ action: NavigationAction)
  -> NavigationState
{
  var state = state
  switch action {
  case .requestUninstall(let url):
    state.pendingUninstallURL = url
  case .clearUninstallRequest:
    state.pendingUninstallURL = nil
  }
  return state
}

/// Uninstall Feature Reducer
public func uninstallReducer(_ state: UninstallState, _ action: UninstallAction) -> UninstallState {
  var state = state
  switch action {
  case .startScan:
    state.phase = .scanning

  case .scanCompleted(let apps):
    state.apps = apps
    state.phase = .scanned
    // Handle pending selection after scan
    if let pendingURL = state.pendingSelectionURL {
      if let matchingApp = apps.first(where: { $0.path == pendingURL.path }) {
        state.selectedAppID = matchingApp.id
      }
      state.pendingSelectionURL = nil
    }

  case .setPendingSelection(let url):
    state.pendingSelectionURL = url

  case .selectApp(let id):
    state.selectedAppID = id
    // Clear old residuals/plans
    state.residuals = []
    state.deletionPlan = nil
    state.deletionResult = nil

  case .loadResidualsCompleted(let residuals):
    state.residuals = residuals

  case .prepareUninstall:
    // Moving to 'planning' or just keep scanned but clear old plan
    state.deletionPlan = nil
    state.deletionResult = nil

  case .planCreated(let plan):
    state.deletionPlan = plan

  case .cancelUninstall:
    state.deletionPlan = nil
    state.deletionResult = nil

  case .confirmUninstall, .startDelete:
    state.phase = .deleting
    state.deletionResult = nil

  case .deleteCompleted(let result):
    switch result {
    case .success(let deletionResult):
      state.deletionResult = deletionResult
      state.phase = .done
      // Optimization: remove deleted app from list to update UI immediately
      if let id = state.selectedAppID {
        state.apps.removeAll { $0.id == id }
        state.selectedAppID = nil
        state.residuals = []
        state.deletionPlan = nil
      }
    case .failure(let error):
      state.phase = .error(error.localizedDescription)
    }

  case .reset:
    state.phase = .idle
    state.selectedAppID = nil
    state.residuals = []
  }
  return state
}

/// Cleanup Feature Reducer
public func cleanupReducer(_ state: CleanupState, _ action: CleanupAction) -> CleanupState {
  var state = state
  switch action {
  case .startScan:
    state.phase = .scanning
    state.items = []
    state.cleanResult = nil

  case .scanCompleted(let items):
    state.items = items
    state.phase = .scanned

  case .scanFailed(let error):
    state.phase = .error(error)

  case .toggleItem(let id):
    if let index = state.items.firstIndex(where: { $0.id == id }) {
      state.items[index].isSelected.toggle()
    }

  case .selectAll:
    for i in state.items.indices {
      state.items[i].isSelected = true
    }

  case .deselectAll:
    for i in state.items.indices {
      state.items[i].isSelected = false
    }

  case .confirmClean:
    // UI handles showing confirmation sheet; no state change needed
    break

  case .cancelClean:
    // UI handles dismissing sheet; no state change needed
    break

  case .startClean:
    state.phase = .cleaning

  case .cleanCompleted(let result):
    state.cleanResult = result
    state.phase = .completed
    // Remove successfully deleted items
    state.items.removeAll { $0.isSelected }

  case .reset:
    state.phase = .idle
    state.items = []
    state.cleanResult = nil
  }
  return state
}

/// Insights Feature Reducer
public func insightsReducer(_ state: InsightsState, _ action: InsightsAction) -> InsightsState {
  var state = state
  switch action {
  case .startEvaluation:
    state.phase = .loading
    state.actionResult = nil

  case .evaluationCompleted(let recommendations, let isCacheHit, let cacheAge):
    state.recommendations = recommendations
    state.phase = .loaded
    state.isCacheHit = isCacheHit
    state.cacheAge = cacheAge

  case .evaluationFailed(let error):
    state.phase = .error(error)

  case .selectRecommendation(let recommendation):
    state.selectedRecommendation = recommendation

  case .selectCategory(let category):
    state.selectedCategory = category

  case .executeAction:
    state.actionInProgress = true
    state.actionResult = nil

  case .actionCompleted(let result):
    state.actionInProgress = false
    state.actionResult = result

  case .actionFailed(let error):
    state.actionInProgress = false
    state.actionResult = ActionResult(success: false, message: error)

  case .reset:
    state.phase = .idle
    state.recommendations = []
    state.selectedRecommendation = nil
    state.actionResult = nil
  }
  return state
}

/// Status/System Monitor Feature Reducer
public func statusReducer(_ state: StatusState, _ action: StatusAction) -> StatusState {
  var state = state
  switch action {
  case .startMonitoring:
    state.phase = .monitoring

  case .stopMonitoring:
    state.phase = .idle

  case .metricsUpdated(let metrics):
    state.cpuUsage = metrics.cpuUsage
    state.memoryUsage = metrics.memoryUsage
    state.memoryUsed = metrics.memoryUsed
    state.memoryTotal = metrics.memoryTotal
    state.diskUsage = metrics.diskUsage
    state.diskUsed = metrics.diskUsed
    state.diskTotal = metrics.diskTotal
    state.batteryLevel = metrics.batteryLevel
    state.networkDownload = metrics.networkDownload
    state.networkUpload = metrics.networkUpload
    state.lastUpdated = Date()

  case .fullUpdate(let metrics, let ioReadRate, let ioWriteRate, let peripheralSnapshot):
    state.cpuUsage = metrics.cpuUsage
    state.memoryUsage = metrics.memoryUsage
    state.memoryUsed = metrics.memoryUsed
    state.memoryTotal = metrics.memoryTotal
    state.diskUsage = metrics.diskUsage
    state.diskUsed = metrics.diskUsed
    state.diskTotal = metrics.diskTotal
    state.batteryLevel = metrics.batteryLevel
    state.networkDownload = metrics.networkDownload
    state.networkUpload = metrics.networkUpload
    state.ioReadRate = ioReadRate
    state.ioWriteRate = ioWriteRate
    state.peripheralSnapshot = peripheralSnapshot
    state.lastUpdated = Date()

  case .ioRatesUpdated(let readRate, let writeRate):
    state.ioReadRate = readRate
    state.ioWriteRate = writeRate

  case .metricsFailed(let error):
    state.phase = .error(error)

  case .showProcessSheet(let type):
    state.showProcessSheet = type

  case .showPeripheralsSheet(let show):
    state.showPeripheralsSheet = show

  case .showDiagnosticsSheet(let show):
    state.showDiagnosticsSheet = show

  case .reset:
    state.phase = .idle
    state.lastUpdated = nil
  }
  return state
}

public func workspaceFileManagerReducer(
  _ state: WorkspaceFileManagerState,
  _ action: WorkspaceFileManagerAction
) -> WorkspaceFileManagerState {
  var state = state

  switch action {
  case .boot:
    state.phase = .loading

  case .openLocation(let location, let pane):
    let targetPane = pane ?? state.activePane
    state.phase = .loading
    if !state.recentLocations.contains(location) {
      state.recentLocations.insert(location, at: 0)
      state.recentLocations = Array(state.recentLocations.prefix(10))
    }
    updateSelectedTab(in: &state, pane: targetPane) { tab in
      tab.locationURL = location
      tab.title = location.lastPathComponent.isEmpty ? location.path : location.lastPathComponent
    }

  case .openCompleted(let pane, let tabID, let location, let items):
    state.phase = .loaded
    updateTab(in: &state, pane: pane, tabID: tabID) { tab in
      tab.locationURL = location
      tab.title = location.lastPathComponent.isEmpty ? location.path : location.lastPathComponent
      tab.items = sortItems(items, by: tab.sort)
      tab.selectedItemIDs = []
    }

  case .openFailed(let message):
    state.phase = .error(message)

  case .refreshVolumes:
    state.phase = .loading

  case .volumesUpdated(let volumes):
    state.mountedVolumes = volumes
    if case .loading = state.phase {
      state.phase = .loaded
    }

  case .setActivePane(let pane):
    state.activePane = pane

  case .toggleDualPane:
    state.isDualPane.toggle()

  case .createTab(let pane, let location):
    let baseLocation = location ?? selectedLocation(in: state, pane: pane)
    let newTab = WorkspaceTabState(locationURL: baseLocation, title: baseLocation.lastPathComponent)
    updatePane(in: &state, pane: pane) { paneState in
      paneState.tabs.append(newTab)
      paneState.selectedTabID = newTab.id
    }

  case .closeTab(let pane, let tabID):
    updatePane(in: &state, pane: pane) { paneState in
      paneState.tabs.removeAll { $0.id == tabID }
      if paneState.tabs.isEmpty {
        let fallback = WorkspaceTabState(locationURL: FileManager.default.homeDirectoryForCurrentUser)
        paneState.tabs = [fallback]
        paneState.selectedTabID = fallback.id
      } else if paneState.selectedTabID == tabID {
        paneState.selectedTabID = paneState.tabs[0].id
      }
    }

  case .selectTab(let pane, let tabID):
    updatePane(in: &state, pane: pane) { paneState in
      if paneState.tabs.contains(where: { $0.id == tabID }) {
        paneState.selectedTabID = tabID
      }
    }

  case .updateSelection(let pane, let tabID, let itemIDs):
    updateTab(in: &state, pane: pane, tabID: tabID) { tab in
      tab.selectedItemIDs = itemIDs
    }

  case .setSort(let pane, let tabID, let sort):
    updateTab(in: &state, pane: pane, tabID: tabID) { tab in
      tab.sort = sort
      tab.items = sortItems(tab.items, by: sort)
    }

  case .setPreview(let url):
    state.previewURL = url

  case .enqueueOperation:
    state.showQueueSheet = true

  case .pauseOperation, .resumeOperation, .cancelOperation:
    break

  case .queueSnapshotUpdated(let queueItems):
    state.queueItems = queueItems

  case .showQueueSheet(let show):
    state.showQueueSheet = show
  }

  return state
}

public func workspaceLauncherReducer(
  _ state: WorkspaceLauncherState,
  _ action: WorkspaceLauncherAction
) -> WorkspaceLauncherState {
  var state = state

  switch action {
  case .loadPinned:
    state.phase = .loading

  case .pinnedLoaded(let items):
    state.phase = .ready
    state.pinnedItems = items.sorted { $0.order < $1.order }

  case .addPinnedFolder(let url):
    if state.pinnedItems.contains(where: { $0.path == url.path }) {
      return state
    }

    state.pinnedItems.append(
      PinnedLaunchItem(
        type: .folder,
        path: url.path,
        title: url.lastPathComponent,
        order: state.pinnedItems.count
      )
    )

  case .addPinnedApp(let path, let title):
    if state.pinnedItems.contains(where: { $0.path == path }) {
      return state
    }

    state.pinnedItems.append(
      PinnedLaunchItem(
        type: .app,
        path: path,
        title: title,
        order: state.pinnedItems.count
      )
    )

  case .removePinned(let id):
    state.pinnedItems.removeAll { $0.id == id }
    state.pinnedItems = state.pinnedItems.enumerated().map { index, item in
      PinnedLaunchItem(
        id: item.id,
        type: item.type,
        path: item.path,
        title: item.title,
        createdAt: item.createdAt,
        order: index
      )
    }

  case .movePinned(let from, let to):
    guard from != to, from >= 0, to >= 0, from < state.pinnedItems.count else {
      break
    }

    var newItems = state.pinnedItems
    let item = newItems.remove(at: from)
    let destination = min(to, newItems.count)
    newItems.insert(item, at: destination)

    state.pinnedItems = newItems.enumerated().map { index, item in
      PinnedLaunchItem(
        id: item.id,
        type: item.type,
        path: item.path,
        title: item.title,
        createdAt: item.createdAt,
        order: index
      )
    }

  case .savePinned:
    if case .idle = state.phase {
      state.phase = .ready
    }

  case .failed(let message):
    state.phase = .error(message)
  }

  return state
}

public func workspaceMediaReducer(
  _ state: WorkspaceMediaState,
  _ action: WorkspaceMediaAction
) -> WorkspaceMediaState {
  var state = state

  switch action {
  case .setRoot(let url):
    state.rootURL = url
    state.phase = .scanning

  case .startScan:
    state.phase = .scanning

  case .scanCompleted(let items):
    state.items = items
    state.phase = .ready

  case .scanFailed(let message):
    state.phase = .error(message)

  case .setKindFilter(let kinds):
    state.selectedKinds = kinds

  case .setMinSize(let size):
    state.minSize = max(0, size)

  case .toggleDuplicatesView(let show):
    state.showDuplicatesView = show
  }

  return state
}

public func workspaceDocumentsReducer(
  _ state: WorkspaceDocumentsState,
  _ action: WorkspaceDocumentsAction
) -> WorkspaceDocumentsState {
  var state = state

  switch action {
  case .setRoot(let url):
    state.rootURL = url
    state.page = 0
    state.phase = .scanning

  case .startScan:
    state.phase = .scanning

  case .scanCompleted(let page):
    state.records = page.records
    state.page = page.page
    state.pageSize = page.pageSize
    state.totalCount = page.totalCount
    state.phase = .ready

  case .scanFailed(let message):
    state.phase = .error(message)

  case .updateQuery(let query):
    state.query = query
    state.page = 0

  case .selectRecord(let id):
    state.selectedRecordID = id

  case .setFavorite, .replaceTags:
    break

  case .loadSavedSearches:
    break

  case .savedSearchesLoaded(let savedSearches):
    state.savedSearches = savedSearches

  case .saveCurrentSearch:
    break

  case .applySavedSearch(let id):
    if let search = state.savedSearches.first(where: { $0.id == id }) {
      state.query = search.query
      state.page = 0
    }

  case .deleteSavedSearch(let id):
    state.savedSearches.removeAll { $0.id == id }
  }

  return state
}

private func updatePane(
  in state: inout WorkspaceFileManagerState,
  pane: WorkspacePane,
  block: (inout WorkspacePaneState) -> Void
) {
  switch pane {
  case .left:
    block(&state.leftPane)
  case .right:
    block(&state.rightPane)
  }
}

private func updateTab(
  in state: inout WorkspaceFileManagerState,
  pane: WorkspacePane,
  tabID: UUID,
  block: (inout WorkspaceTabState) -> Void
) {
  updatePane(in: &state, pane: pane) { paneState in
    if let index = paneState.tabs.firstIndex(where: { $0.id == tabID }) {
      block(&paneState.tabs[index])
    }
  }
}

private func updateSelectedTab(
  in state: inout WorkspaceFileManagerState,
  pane: WorkspacePane,
  block: (inout WorkspaceTabState) -> Void
) {
  updatePane(in: &state, pane: pane) { paneState in
    guard let index = paneState.tabs.firstIndex(where: { $0.id == paneState.selectedTabID }) else {
      return
    }
    block(&paneState.tabs[index])
  }
}

private func selectedLocation(in state: WorkspaceFileManagerState, pane: WorkspacePane) -> URL {
  let paneState = pane == .left ? state.leftPane : state.rightPane
  if let selected = paneState.selectedTab {
    return selected.locationURL
  }
  return FileManager.default.homeDirectoryForCurrentUser
}

private func sortItems(_ items: [WorkspaceItem], by sort: WorkspaceSortDescriptor) -> [WorkspaceItem] {
  items.sorted { lhs, rhs in
    let ascending = sort.order == .ascending
    switch sort.field {
    case .name:
      let compare = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
      return ascending ? compare == .orderedAscending : compare == .orderedDescending
    case .size:
      let l = lhs.size ?? 0
      let r = rhs.size ?? 0
      return ascending ? l < r : l > r
    case .kind:
      let compare = lhs.kind.rawValue.localizedCaseInsensitiveCompare(rhs.kind.rawValue)
      return ascending ? compare == .orderedAscending : compare == .orderedDescending
    case .modifiedAt:
      let l = lhs.modifiedAt ?? .distantPast
      let r = rhs.modifiedAt ?? .distantPast
      return ascending ? l < r : l > r
    }
  }
}
