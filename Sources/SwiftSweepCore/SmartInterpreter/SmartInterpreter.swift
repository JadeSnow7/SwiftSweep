import Foundation

/// Smart Interpreter - Converts technical evidence into user-friendly explanations.
/// This demonstrates "Explainable AI" principles for the AI Coding interview.
public struct SmartInterpreter: Sendable {
  public static let shared = SmartInterpreter()

  private init() {}

  /// Generate a user-friendly explanation for a recommendation.
  /// - Parameter recommendation: The recommendation to explain.
  /// - Returns: A human-readable explanation string.
  public func explain(recommendation: Recommendation) -> String {
    var explanations: [String] = []

    for evidence in recommendation.evidence {
      if let explanation = explainEvidence(evidence) {
        explanations.append(explanation)
      }
    }

    if explanations.isEmpty {
      return "This recommendation is based on our analysis of your system."
    }

    let combined = explanations.joined(separator: " ")
    return combined
  }

  /// Generate a detailed explanation with reasoning steps.
  /// - Parameter recommendation: The recommendation to explain.
  /// - Returns: A structured explanation with evidence breakdown.
  public func explainDetailed(recommendation: Recommendation) -> ExplanationResult {
    var steps: [ExplanationStep] = []

    for (index, evidence) in recommendation.evidence.enumerated() {
      let stepExplanation = explainEvidence(evidence) ?? "Evidence: \(evidence.label)"
      steps.append(
        ExplanationStep(
          order: index + 1,
          evidenceKind: evidence.kind.rawValue,
          label: evidence.label,
          value: evidence.value,
          explanation: stepExplanation
        ))
    }

    return ExplanationResult(
      summary: explain(recommendation: recommendation),
      steps: steps,
      confidence: recommendation.confidence.displayName,
      risk: recommendation.risk.displayName
    )
  }

  // MARK: - Private Helpers

  private func explainEvidence(_ evidence: Evidence) -> String? {
    switch evidence.kind {
    case .path:
      return explainPathEvidence(evidence)
    case .metric:
      return explainMetricEvidence(evidence)
    case .metadata:
      return explainMetadataEvidence(evidence)
    case .aggregate:
      return explainAggregateEvidence(evidence)
    }
  }

  private func explainPathEvidence(_ evidence: Evidence) -> String {
    let path = evidence.value
    let filename = (path as NSString).lastPathComponent

    if path.contains("Cache") || path.contains("cache") {
      return "Found cache data at '\(filename)' which can be safely removed to free up space."
    } else if path.contains("Downloads") {
      return "Located file '\(filename)' in your Downloads folder that may no longer be needed."
    } else if path.contains("Trash") {
      return "Your Trash contains files that are ready to be permanently deleted."
    } else {
      return "Identified '\(filename)' as a candidate for cleanup."
    }
  }

  private func explainMetricEvidence(_ evidence: Evidence) -> String {
    let label = evidence.label.lowercased()
    let value = evidence.value

    if label.contains("disk") || label.contains("storage") {
      return "Your disk usage is at \(value), which is above the recommended threshold."
    } else if label.contains("size") {
      return "This item occupies \(value) of storage space."
    } else if label.contains("age") || label.contains("days") {
      return "This item is \(value) old and hasn't been accessed recently."
    } else {
      return "\(evidence.label): \(value)"
    }
  }

  private func explainMetadataEvidence(_ evidence: Evidence) -> String {
    let label = evidence.label.lowercased()
    let value = evidence.value

    if label.contains("last") && (label.contains("used") || label.contains("accessed")) {
      return "This item was last accessed on \(value)."
    } else if label.contains("created") {
      return "This item was created on \(value)."
    } else {
      return "\(evidence.label): \(value)"
    }
  }

  private func explainAggregateEvidence(_ evidence: Evidence) -> String {
    let label = evidence.label.lowercased()
    let value = evidence.value

    if label.contains("count") {
      return "Found \(value) items matching this criteria."
    } else if label.contains("total") {
      return "Total impact: \(value)"
    } else {
      return "\(evidence.label): \(value)"
    }
  }
}

// MARK: - Supporting Types

/// Result of a detailed explanation
public struct ExplanationResult: Sendable {
  public let summary: String
  public let steps: [ExplanationStep]
  public let confidence: String
  public let risk: String
}

/// A single step in the explanation chain
public struct ExplanationStep: Identifiable, Sendable {
  public let id = UUID()
  public let order: Int
  public let evidenceKind: String
  public let label: String
  public let value: String
  public let explanation: String
}
