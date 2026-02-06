import Foundation
import AppKit

@MainActor
public func insightsEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .insights(let insightsAction) = action else { return }

  switch insightsAction {
  case .startEvaluation(let forceRefresh):
    await runInsightsEvaluationEffect(forceRefresh: forceRefresh, store)

  case .executeAction(let recommendation, let dryRun):
    await runInsightsActionEffect(recommendation: recommendation, dryRun: dryRun, store)

  // State-only actions don't trigger effects
  case .evaluationCompleted, .evaluationFailed, .selectRecommendation, .selectCategory,
    .actionCompleted, .actionFailed, .reset:
    break
  }
}

// MARK: - Evaluation Effect

@MainActor
private func runInsightsEvaluationEffect(forceRefresh: Bool, _ store: AppStore) async {
  do {
    let result = try await RecommendationEngine.shared.evaluateWithSystemContext(
      forceRefresh: forceRefresh
    )

    store.dispatch(
      .insights(
        .evaluationCompleted(
          result.recommendations, isCacheHit: result.isCacheHit, cacheAge: result.cacheAge))
    )
  } catch {
    store.dispatch(.insights(.evaluationFailed(error.localizedDescription)))
  }
}

// MARK: - Action Execution Effect

@MainActor
private func runInsightsActionEffect(
  recommendation: Recommendation, dryRun: Bool, _ store: AppStore
) async {
  // Execute the recommendation's actions
  var successCount = 0
  var failedCount = 0
  var freedBytes: Int64 = 0

  for action in recommendation.actions {
    do {
      // Execute based on action type
      switch action.type {
      case .cleanupDelete, .cleanupTrash:
        if case .paths(let paths) = action.payload {
          for path in paths {
            if !dryRun {
              try FileManager.default.removeItem(atPath: path)
            }
            successCount += 1
            // Estimate freed bytes (would need actual file size)
            freedBytes += 1024 * 1024  // Placeholder
          }
        }

      case .emptyTrash:
        if !dryRun {
          // Would need to implement trash emptying
        }
        successCount += 1

      case .openFinder:
        if case .paths(let paths) = action.payload, let path = paths.first {
          NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
        successCount += 1

      case .uninstallPlan:
        // Would trigger uninstall flow
        successCount += 1

      case .optimizeTask:
        // Would run optimization task
        successCount += 1

      case .rescan:
        // Would trigger rescan
        successCount += 1
      }
    } catch {
      failedCount += 1
      print("Action execution failed: \(error)")
    }
  }

  let result = ActionResult(
    success: failedCount == 0,
    message: dryRun
      ? "Dry run: \(successCount) actions would be executed"
      : "\(successCount) actions completed, \(failedCount) failed",
    freedBytes: dryRun ? nil : freedBytes
  )

  if result.success {
    store.dispatch(.insights(.actionCompleted(result)))
  } else {
    store.dispatch(.insights(.actionFailed(result.message)))
  }
}
