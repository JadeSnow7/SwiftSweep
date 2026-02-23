import Foundation

/// Global Application Action (State Mutations)
public enum AppAction: Sendable {
  case navigation(NavigationAction)
  case uninstall(UninstallAction)
  case cleanup(CleanupAction)
  case insights(InsightsAction)
  case status(StatusAction)
  case workspaceFileManager(WorkspaceFileManagerAction)
  case workspaceLauncher(WorkspaceLauncherAction)
  case workspaceMedia(WorkspaceMediaAction)
  case workspaceDocuments(WorkspaceDocumentsAction)
}

/// Actions for Navigation
public enum NavigationAction: Sendable {
  case requestUninstall(URL?)  // Request to navigate to UninstallView with optional app URL
  case clearUninstallRequest
}

/// Actions for Uninstall Feature
public enum UninstallAction: Sendable {
  case startScan
  case scanCompleted([UninstallEngine.InstalledApp])
  case selectApp(UUID)  // Selects app and loads residuals
  case setPendingSelection(URL)  // Set pending selection for after scan completes
  case loadResidualsCompleted([UninstallEngine.ResidualFile])
  case prepareUninstall(UninstallEngine.InstalledApp)  // Trigger plan creation
  case planCreated(DeletionPlan)
  case cancelUninstall  // Cancel plan
  case confirmUninstall  // User confirmed plan
  case startDelete
  case deleteCompleted(Result<DeletionResult, Error>)
  case reset
}

/// Actions for Cleanup Feature
public enum CleanupAction: Sendable {
  case startScan
  case scanCompleted([CleanupEngine.CleanupItem])
  case scanFailed(String)
  case toggleItem(UUID)
  case selectAll
  case deselectAll
  case confirmClean  // Show confirmation sheet
  case cancelClean  // Dismiss confirmation
  case startClean
  case cleanCompleted(CleanupResult)
  case reset
}

/// Actions for Insights Feature
public enum InsightsAction: Sendable {
  case startEvaluation(forceRefresh: Bool)
  case evaluationCompleted([Recommendation], isCacheHit: Bool, cacheAge: TimeInterval?)
  case evaluationFailed(String)
  case selectRecommendation(Recommendation?)
  case selectCategory(RuleCategory?)
  case executeAction(Recommendation, dryRun: Bool)
  case actionCompleted(ActionResult)
  case actionFailed(String)
  case reset
}

/// Actions for Status/System Monitor Feature
public enum StatusAction: Sendable {
  case startMonitoring
  case stopMonitoring
  case metricsUpdated(SystemMonitor.SystemMetrics)
  case fullUpdate(
    metrics: SystemMonitor.SystemMetrics,
    ioReadRate: Double,
    ioWriteRate: Double,
    peripheralSnapshot: PeripheralSnapshot
  )
  case ioRatesUpdated(readRate: Double, writeRate: Double)
  case metricsFailed(String)
  case showProcessSheet(ProcessMetricType?)
  case showPeripheralsSheet(Bool)
  case showDiagnosticsSheet(Bool)
  case reset
}

/// Actions for Workspace File Manager
public enum WorkspaceFileManagerAction: Sendable {
  case boot
  case openLocation(URL, pane: WorkspacePane?)
  case openCompleted(pane: WorkspacePane, tabID: UUID, location: URL, items: [WorkspaceItem])
  case openFailed(String)
  case refreshVolumes
  case volumesUpdated([URL])
  case setActivePane(WorkspacePane)
  case toggleDualPane
  case createTab(pane: WorkspacePane, location: URL?)
  case closeTab(pane: WorkspacePane, tabID: UUID)
  case selectTab(pane: WorkspacePane, tabID: UUID)
  case updateSelection(pane: WorkspacePane, tabID: UUID, itemIDs: Set<String>)
  case setSort(pane: WorkspacePane, tabID: UUID, sort: WorkspaceSortDescriptor)
  case setPreview(URL?)
  case enqueueOperation(
    type: FileOperationType,
    sources: [URL],
    destination: URL?,
    conflictPolicy: FileConflictPolicy?
  )
  case pauseOperation(UUID)
  case resumeOperation(UUID)
  case cancelOperation(UUID)
  case queueSnapshotUpdated([FileOperationProgress])
  case showQueueSheet(Bool)
}

/// Actions for Workspace Launcher
public enum WorkspaceLauncherAction: Sendable {
  case loadPinned
  case pinnedLoaded([PinnedLaunchItem])
  case addPinnedFolder(URL)
  case addPinnedApp(path: String, title: String)
  case removePinned(UUID)
  case movePinned(from: Int, to: Int)
  case savePinned
  case failed(String)
}

/// Actions for Workspace Media
public enum WorkspaceMediaAction: Sendable {
  case setRoot(URL)
  case startScan
  case scanCompleted([MediaLibraryItem])
  case scanFailed(String)
  case setKindFilter(Set<WorkspaceMediaKind>)
  case setMinSize(Int64)
  case toggleDuplicatesView(Bool)
}

/// Actions for Workspace Documents
public enum WorkspaceDocumentsAction: Sendable {
  case setRoot(URL)
  case startScan
  case scanCompleted(DocumentCatalogPage)
  case scanFailed(String)
  case updateQuery(DocumentQuery)
  case selectRecord(String?)
  case setFavorite(path: String, isFavorite: Bool)
  case replaceTags(path: String, tags: [String])
  case loadSavedSearches
  case savedSearchesLoaded([WorkspaceSavedSearch])
  case saveCurrentSearch(name: String)
  case applySavedSearch(UUID)
  case deleteSavedSearch(UUID)
}
