#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
import SwiftUI

/// Cleanup History View - Shows historical cleanup comparisons
/// Features:
/// - Before/After space comparison
/// - Cleanup events timeline
/// - Rule effectiveness metrics
public struct CleanupHistoryView: View {
  @State private var historyEntries: [CleanupHistoryEntry] = []
  @State private var selectedEntry: CleanupHistoryEntry?

  public init() {}

  public var body: some View {
    NavigationSplitView {
      List(historyEntries, selection: $selectedEntry) { entry in
        HistoryEntryRow(entry: entry)
      }
      .navigationTitle("History")
    } detail: {
      if let entry = selectedEntry {
        HistoryDetailView(entry: entry)
      } else {
        emptyState
      }
    }
    .onAppear { loadMockHistory() }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("Select an entry to view details")
        .foregroundColor(.secondary)
    }
  }

  private func loadMockHistory() {
    let calendar = Calendar.current
    historyEntries = (0..<10).map { i in
      CleanupHistoryEntry(
        id: UUID(),
        date: calendar.date(byAdding: .day, value: -i * 3, to: Date())!,
        ruleTriggered: ["Browser Cache", "Old Downloads", "Developer Cache"].randomElement()!,
        spaceBeforeBytes: Int64.random(in: 100_000_000_000...500_000_000_000),
        spaceAfterBytes: Int64.random(in: 80_000_000_000...450_000_000_000),
        filesDeleted: Int.random(in: 10...500),
        executionTimeMs: Int.random(in: 500...5000)
      )
    }
  }
}

struct CleanupHistoryEntry: Identifiable, Hashable {
  let id: UUID
  let date: Date
  let ruleTriggered: String
  let spaceBeforeBytes: Int64
  let spaceAfterBytes: Int64
  let filesDeleted: Int
  let executionTimeMs: Int

  var spaceSavedBytes: Int64 {
    spaceBeforeBytes - spaceAfterBytes
  }
}

struct HistoryEntryRow: View {
  let entry: CleanupHistoryEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(entry.ruleTriggered)
        .font(.headline)
      HStack {
        Text(entry.date, style: .date)
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Text("-\(formatBytes(entry.spaceSavedBytes))")
          .font(.caption)
          .foregroundColor(.green)
      }
    }
    .padding(.vertical, 4)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct HistoryDetailView: View {
  let entry: CleanupHistoryEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.ruleTriggered)
            .font(.title)
            .fontWeight(.bold)
          Text(entry.date, style: .date)
            .foregroundColor(.secondary)
        }

        // Before/After Comparison
        GroupBox("Space Comparison") {
          HStack(spacing: 32) {
            ComparisonColumn(
              label: "Before",
              value: formatBytes(entry.spaceBeforeBytes),
              color: .orange
            )

            Image(systemName: "arrow.right")
              .font(.title2)
              .foregroundColor(.secondary)

            ComparisonColumn(
              label: "After",
              value: formatBytes(entry.spaceAfterBytes),
              color: .green
            )

            Divider()

            ComparisonColumn(
              label: "Saved",
              value: formatBytes(entry.spaceSavedBytes),
              color: .blue
            )
          }
          .padding()
        }

        // Metrics
        GroupBox("Metrics") {
          HStack(spacing: 32) {
            MetricItem(label: "Files Deleted", value: "\(entry.filesDeleted)")
            MetricItem(label: "Execution Time", value: "\(entry.executionTimeMs)ms")
            MetricItem(
              label: "Avg File Size",
              value: formatBytes(entry.spaceSavedBytes / Int64(max(1, entry.filesDeleted))))
          }
          .padding()
        }

        Spacer()
      }
      .padding()
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct ComparisonColumn: View {
  let label: String
  let value: String
  let color: Color

  var body: some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
      Text(value)
        .font(.title2)
        .fontWeight(.bold)
        .foregroundColor(color)
    }
  }
}

struct MetricItem: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.headline)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  CleanupHistoryView()
    .frame(width: 700, height: 500)
}
