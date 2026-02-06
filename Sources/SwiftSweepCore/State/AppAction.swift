import Foundation

/// Global Application Action (State Mutations)
public enum AppAction: Sendable {
  case navigation(NavigationAction)
  case uninstall(UninstallAction)
  case cleanup(CleanupAction)
  case insights(InsightsAction)
  case status(StatusAction)
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
