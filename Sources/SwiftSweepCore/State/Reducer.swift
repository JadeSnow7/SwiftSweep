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
