import Foundation

@MainActor
public func statusEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .status(let statusAction) = action else { return }

  switch statusAction {
  case .startMonitoring:
    await runStatusMonitoringEffect(store)

  case .stopMonitoring:
    // Stop monitoring is handled by state change
    break

  // State-only actions don't trigger effects
  case .metricsUpdated, .metricsFailed, .showProcessSheet, .showPeripheralsSheet,
    .showDiagnosticsSheet, .reset:
    break
  }
}

// MARK: - Monitoring Effect

@MainActor
private func runStatusMonitoringEffect(_ store: AppStore) async {
  // Continuous monitoring loop
  while store.state.status.phase == .monitoring {
    do {
      let metrics = try await SystemMonitor.shared.getMetrics()
      store.dispatch(.status(.metricsUpdated(metrics)))

      // Wait 2 seconds before next update
      try await Task.sleep(nanoseconds: 2_000_000_000)
    } catch {
      store.dispatch(.status(.metricsFailed(error.localizedDescription)))
      break
    }
  }
}
