import Foundation

/// Unified effects handler that routes actions to specific effect handlers
@MainActor
public func appEffects(_ action: AppAction, _ store: AppStore) async {
  switch action {
  case .cleanup:
    await cleanupEffects(action, store)

  case .uninstall:
    await uninstallEffects(action, store)

  case .insights:
    await insightsEffects(action, store)

  case .status:
    await statusEffects(action, store)

  case .workspaceFileManager:
    await workspaceFileManagerEffects(action, store)

  case .workspaceLauncher:
    await workspaceLauncherEffects(action, store)

  case .workspaceMedia:
    await workspaceMediaEffects(action, store)

  case .workspaceDocuments:
    await workspaceDocumentsEffects(action, store)

  case .navigation:
    // Navigation actions don't have side effects
    break
  }
}
