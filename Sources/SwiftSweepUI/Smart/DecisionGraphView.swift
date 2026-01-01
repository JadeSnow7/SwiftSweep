#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
import SwiftUI

/// Decision Graph View - Visualizes explanation evidence as a tree/graph.
/// Demonstrates "White-box AI" principles for the AI Coding interview.
public struct DecisionGraphView: View {
  let recommendation: Recommendation
  let explanation: ExplanationResult

  public init(recommendation: Recommendation) {
    self.recommendation = recommendation
    self.explanation = SmartInterpreter.shared.explainDetailed(recommendation: recommendation)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        Image(systemName: "brain.head.profile")
          .font(.title2)
          .foregroundColor(.accentColor)
        Text("AI Decision Explanation")
          .font(.headline)
        Spacer()
        confidenceBadge
      }

      Divider()

      // Summary
      Text(explanation.summary)
        .font(.body)
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)

      // Evidence Tree
      Text("Evidence Chain")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(explanation.steps) { step in
            EvidenceStepRow(step: step, isLast: step.order == explanation.steps.count)
          }
        }
      }

      Spacer()
    }
    .padding()
  }

  private var confidenceBadge: some View {
    HStack(spacing: 8) {
      Text(explanation.confidence)
        .font(.caption)
        .foregroundColor(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(4)

      Text(explanation.risk)
        .font(.caption)
        .foregroundColor(riskColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(riskColor.opacity(0.1))
        .cornerRadius(4)
    }
  }

  private var riskColor: Color {
    if explanation.risk.lowercased().contains("high") {
      return .red
    } else if explanation.risk.lowercased().contains("medium") {
      return .orange
    } else {
      return .green
    }
  }
}

struct EvidenceStepRow: View {
  let step: ExplanationStep
  let isLast: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Tree connector
      VStack(spacing: 0) {
        Circle()
          .fill(kindColor)
          .frame(width: 12, height: 12)
        if !isLast {
          Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
        }
      }

      // Content
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Step \(step.order)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)

          Text(step.evidenceKind.uppercased())
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(kindColor)
            .cornerRadius(4)
        }

        Text(step.explanation)
          .font(.body)

        HStack {
          Text(step.label)
            .font(.caption)
            .foregroundColor(.secondary)
          Text("→")
            .foregroundColor(.secondary)
          Text(step.value)
            .font(.caption)
            .foregroundColor(.accentColor)
        }
      }
      .padding(.bottom, 16)
    }
  }

  private var kindColor: Color {
    switch step.evidenceKind {
    case "path": return .blue
    case "metric": return .orange
    case "metadata": return .purple
    case "aggregate": return .green
    default: return .gray
    }
  }
}

#Preview {
  let mockRecommendation = Recommendation(
    id: "demo",
    title: "Clean Browser Cache",
    summary: "Your browser cache is using 2.3 GB of space",
    severity: .warning,
    risk: .low,
    confidence: .high,
    estimatedReclaimBytes: 2_300_000_000,
    evidence: [
      Evidence(kind: .path, label: "Cache Location", value: "~/Library/Caches/com.google.Chrome"),
      Evidence(kind: .metric, label: "Cache Size", value: "2.3 GB"),
      Evidence(kind: .metadata, label: "Last Accessed", value: "2024-01-15"),
      Evidence(kind: .aggregate, label: "File Count", value: "1,234 files"),
    ]
  )

  return DecisionGraphView(recommendation: mockRecommendation)
    .frame(width: 500, height: 500)
}
