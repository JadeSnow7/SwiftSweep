import Foundation

/// Global Application Action (State Mutations)
public enum AppAction: Sendable {
  case navigation(NavigationAction)
  case uninstall(UninstallAction)
  case cleanup(CleanupAction)
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
