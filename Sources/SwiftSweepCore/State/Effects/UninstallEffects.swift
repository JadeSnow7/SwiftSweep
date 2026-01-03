import Foundation

@MainActor
public func uninstallEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .uninstall(let uninstallAction) = action else { return }

  switch uninstallAction {
  case .startScan:
    await runScanEffect(store)

  case .selectApp(let appID):
    await runLoadResidualsEffect(appID, store)

  case .prepareUninstall(let app):
    await runCreatePlanEffect(app, store)

  case .startDelete:
    await runDeleteEffect(store)

  // Simple state updates don't trigger effects
  case .scanCompleted, .loadResidualsCompleted, .planCreated, .confirmUninstall, .cancelUninstall,
    .deleteCompleted, .reset, .setPendingSelection:
    break
  }
}

// MARK: - Scheduler Helper

private let scheduler = ConcurrentScheduler.shared

// MARK: - Scan Effect

@MainActor
private func runScanEffect(_ store: AppStore) async {
  // 1. Load from cache (SWR) - Synchronous call
  let cached = UninstallCacheStore.shared.loadCachedApps()
  if !cached.isEmpty {
    let installed = cached.map { $0.toInstalledApp() }
    store.dispatch(.uninstall(.scanCompleted(installed)))
  }

  // 2. Scan fresh using ConcurrentScheduler
  do {
    let freshApps = try await scheduler.schedule(priority: .normal) {
      try await UninstallEngine.shared.scanInstalledApps(includeSizes: true)
    }

    // Update Cache (Synchronous wrapper around async queue)
    let cachedApps = freshApps.map { CachedAppInfo(from: $0) }
    UninstallCacheStore.shared.saveApps(cachedApps)
    UninstallCacheStore.shared.cleanup()

    // Update Store
    store.dispatch(.uninstall(.scanCompleted(freshApps)))
  } catch {
    print("Scan error: \(error)")
  }
}

// MARK: - Load Residuals Effect

@MainActor
private func runLoadResidualsEffect(_ appID: UUID, _ store: AppStore) async {
  // Need to find the app in the current state
  guard let app = store.state.uninstall.apps.first(where: { $0.id == appID }) else { return }

  // Capture requestedID to prevent race conditions
  let requestedAppID = appID

  // 1. Cache
  let cachedResiduals = UninstallCacheStore.shared.loadResiduals(for: app.path)
  if !cachedResiduals.isEmpty {
    let residuals = cachedResiduals.map { $0.toResidualFile() }
    // Only dispatch if selection hasn't changed
    if store.state.uninstall.selectedAppID == requestedAppID {
      store.dispatch(.uninstall(.loadResidualsCompleted(residuals)))
    }
  }

  // 2. Fresh Scan using ConcurrentScheduler
  do {
    let residuals = try await scheduler.schedule(priority: .high) {
      try UninstallEngine.shared.findResidualFiles(for: app)
    }

    // Update Cache
    let cached = residuals.map { CachedResidualInfo(from: $0, appPath: app.path) }
    UninstallCacheStore.shared.saveResiduals(cached, for: app.path)

    // Only dispatch if selection hasn't changed (race condition guard)
    if store.state.uninstall.selectedAppID == requestedAppID {
      store.dispatch(.uninstall(.loadResidualsCompleted(residuals)))
    }
  } catch {
    print("Residuals error: \(error)")
  }
}

// MARK: - Create Plan Effect

@MainActor
private func runCreatePlanEffect(_ app: UninstallEngine.InstalledApp, _ store: AppStore) async {
  // Reconstruct App with residuals
  var appWithResiduals = app
  appWithResiduals.residualFiles = store.state.uninstall.residuals

  do {
    let plan = try await UninstallEngine.shared.createDeletionPlan(for: appWithResiduals)
    store.dispatch(.uninstall(.planCreated(plan)))
  } catch {
    store.dispatch(.uninstall(.deleteCompleted(.failure(error))))
  }
}

// MARK: - Delete Effect

@MainActor
private func runDeleteEffect(_ store: AppStore) async {
  // Use the plan already in state
  guard let plan = store.state.uninstall.deletionPlan else { return }

  do {
    if #available(macOS 13.0, *) {
      let result = try await UninstallEngine.shared.executeDeletionPlan(plan) { _, _ in
        // Progress updates: dispatch(.uninstall(.progress...)) if needed
      }
      store.dispatch(.uninstall(.deleteCompleted(.success(result))))
    } else {
      // Construct a proper Error
      let error = NSError(
        domain: "SwiftSweep", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires macOS 13"])
      store.dispatch(.uninstall(.deleteCompleted(.failure(error))))
    }
  } catch {
    store.dispatch(.uninstall(.deleteCompleted(.failure(error))))
  }
}
