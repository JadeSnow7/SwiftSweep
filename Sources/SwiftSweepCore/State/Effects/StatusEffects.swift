import Foundation

// Track monitoring task to allow cancellation
private var monitoringTask: Task<Void, Never>?

@MainActor
public func statusEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .status(let statusAction) = action else { return }

  switch statusAction {
  case .startMonitoring:
    await runStatusMonitoringEffect(store)

  case .stopMonitoring:
    // Cancel the monitoring task
    monitoringTask?.cancel()
    monitoringTask = nil
    // Stop IO analysis
    await IOAnalyzer.shared.stopAnalysis()

  // State-only actions don't trigger effects
  case .metricsUpdated, .fullUpdate, .ioRatesUpdated, .metricsFailed, .showProcessSheet,
    .showPeripheralsSheet, .showDiagnosticsSheet, .reset:
    break
  }
}

// MARK: - Monitoring Effect

@MainActor
private func runStatusMonitoringEffect(_ store: AppStore) async {
  // Cancel any existing monitoring task
  monitoringTask?.cancel()

  // Start IO analysis with callback for rate updates
  Task {
    try? await IOAnalyzer.shared.startAnalysis { slice in
      Task { @MainActor in
        let readRate = slice.readThroughput / (1024 * 1024)  // bytes -> MB/s
        let writeRate = slice.writeThroughput / (1024 * 1024)
        store.dispatch(.status(.ioRatesUpdated(readRate: readRate, writeRate: writeRate)))
      }
    }
  }

  // Fetch peripherals once at start
  let initialPeripherals = await PeripheralInspector.shared.getSnapshot()

  // Create monitoring task
  monitoringTask = Task {
    var updateCount = 0
    while !Task.isCancelled && store.state.status.phase == .monitoring {
      do {
        let metrics = try await SystemMonitor.shared.getMetrics()

        // Every 5th update (10 seconds), also fetch peripherals
        let peripherals: PeripheralSnapshot
        if updateCount % 5 == 0 {
          peripherals = await PeripheralInspector.shared.getSnapshot()
        } else {
          peripherals = updateCount == 0 ? initialPeripherals : store.state.status.peripheralSnapshot
        }

        // Get current IO rates from state (updated by callback)
        let ioReadRate = store.state.status.ioReadRate
        let ioWriteRate = store.state.status.ioWriteRate

        // Dispatch update with all data
        await MainActor.run {
          store.dispatch(
            .status(
              .fullUpdate(
                metrics: metrics,
                ioReadRate: ioReadRate,
                ioWriteRate: ioWriteRate,
                peripheralSnapshot: peripherals
              )
            )
          )
        }

        updateCount += 1

        // Wait 2 seconds before next update
        try await Task.sleep(nanoseconds: 2_000_000_000)
      } catch is CancellationError {
        break
      } catch {
        await MainActor.run {
          store.dispatch(.status(.metricsFailed(error.localizedDescription)))
        }
        break
      }
    }
  }
}
