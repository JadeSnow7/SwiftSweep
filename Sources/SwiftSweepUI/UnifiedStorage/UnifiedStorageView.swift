#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
import SwiftUI

/// Unified Storage Analyzer View
/// Combines Disk Analyzer + Media Analyzer into a single experience.
/// Provides unified filtering, statistics, and cleanup actions.
public struct UnifiedStorageView: View {
  @State private var selectedTab: AnalysisTab = .overview
  @State private var filterText: String = ""
  @State private var sizeThreshold: Int64 = 100_000_000  // 100 MB default
  @State private var storageStats: StorageStats = StorageStats()

  enum AnalysisTab: String, CaseIterable {
    case overview = "Overview"
    case diskAnalyzer = "Disk"
    case mediaAnalyzer = "Media"
    case duplicates = "Duplicates"

    var icon: String {
      switch self {
      case .overview: return "square.grid.2x2"
      case .diskAnalyzer: return "internaldrive"
      case .mediaAnalyzer: return "photo.stack"
      case .duplicates: return "doc.on.doc"
      }
    }
  }

  public init() {}

  public var body: some View {
    NavigationSplitView {
      // Sidebar with tabs
      List(selection: $selectedTab) {
        ForEach(AnalysisTab.allCases, id: \.self) { tab in
          Label(tab.rawValue, systemImage: tab.icon)
            .tag(tab)
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Storage")
    } detail: {
      VStack(spacing: 0) {
        // Unified filter bar
        filterBar

        Divider()

        // Content based on selected tab
        switch selectedTab {
        case .overview:
          overviewContent
        case .diskAnalyzer:
          AnalyzeView()
        case .mediaAnalyzer:
          MediaAnalyzerView()
        case .duplicates:
          duplicatesContent
        }
      }
    }
    .onAppear { loadStorageStats() }
  }

  // MARK: - Filter Bar

  private var filterBar: some View {
    HStack(spacing: 16) {
      // Search
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
        TextField("Filter by name or path...", text: $filterText)
          .textFieldStyle(.plain)
      }
      .padding(8)
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(8)
      .frame(maxWidth: 300)

      // Size threshold
      HStack {
        Text("Min Size:")
          .foregroundColor(.secondary)
        Picker("", selection: $sizeThreshold) {
          Text("10 MB").tag(Int64(10_000_000))
          Text("100 MB").tag(Int64(100_000_000))
          Text("500 MB").tag(Int64(500_000_000))
          Text("1 GB").tag(Int64(1_000_000_000))
        }
        .pickerStyle(.menu)
        .frame(width: 100)
      }

      Spacer()

      // Quick stats
      HStack(spacing: 16) {
        UnifiedStatPill(label: "Used", value: formatBytes(storageStats.usedSpace), color: .blue)
        UnifiedStatPill(
          label: "Reclaimable", value: formatBytes(storageStats.reclaimable), color: .orange)
      }
    }
    .padding()
  }

  // MARK: - Overview Content

  private var overviewContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Storage breakdown
        GroupBox("Storage Breakdown") {
          HStack(spacing: 32) {
            StorageRingChart(
              used: storageStats.usedSpace,
              total: storageStats.totalSpace
            )
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 8) {
              CategoryRow(name: "Applications", size: storageStats.appsSpace, color: .blue)
              CategoryRow(name: "Documents", size: storageStats.documentsSpace, color: .green)
              CategoryRow(name: "Media", size: storageStats.mediaSpace, color: .purple)
              CategoryRow(name: "Cache", size: storageStats.cacheSpace, color: .orange)
              CategoryRow(name: "Other", size: storageStats.otherSpace, color: .gray)
            }
          }
          .padding()
        }

        // Quick Actions
        GroupBox("Quick Actions") {
          HStack(spacing: 16) {
            QuickActionButton(
              title: "Scan Disk",
              icon: "magnifyingglass",
              color: .blue
            ) {
              selectedTab = .diskAnalyzer
            }

            QuickActionButton(
              title: "Find Duplicates",
              icon: "doc.on.doc",
              color: .orange
            ) {
              selectedTab = .duplicates
            }

            QuickActionButton(
              title: "Analyze Media",
              icon: "photo.stack",
              color: .purple
            ) {
              selectedTab = .mediaAnalyzer
            }
          }
          .padding()
        }

        Spacer()
      }
      .padding()
    }
  }

  // MARK: - Duplicates Content

  private var duplicatesContent: some View {
    VStack {
      Spacer()
      Image(systemName: "doc.on.doc")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("Duplicate Detection")
        .font(.headline)
      Text("Combines Media Analyzer's pHash with file hash comparison")
        .font(.caption)
        .foregroundColor(.secondary)
      Button("Start Scan") {
        // Would trigger unified duplicate scan
      }
      .buttonStyle(.borderedProminent)
      .padding()
      Spacer()
    }
  }

  // MARK: - Helpers

  private func loadStorageStats() {
    // Mock data for demo
    storageStats = StorageStats(
      totalSpace: 500_000_000_000,
      usedSpace: 350_000_000_000,
      reclaimable: 25_000_000_000,
      appsSpace: 80_000_000_000,
      documentsSpace: 120_000_000_000,
      mediaSpace: 100_000_000_000,
      cacheSpace: 30_000_000_000,
      otherSpace: 20_000_000_000
    )
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

// MARK: - Supporting Types

struct StorageStats {
  var totalSpace: Int64 = 0
  var usedSpace: Int64 = 0
  var reclaimable: Int64 = 0
  var appsSpace: Int64 = 0
  var documentsSpace: Int64 = 0
  var mediaSpace: Int64 = 0
  var cacheSpace: Int64 = 0
  var otherSpace: Int64 = 0
}

struct UnifiedStatPill: View {
  let label: String
  let value: String
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
      Text(value)
        .font(.caption)
        .fontWeight(.semibold)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(color.opacity(0.1))
    .cornerRadius(12)
  }
}

struct CategoryRow: View {
  let name: String
  let size: Int64
  let color: Color

  var body: some View {
    HStack {
      Circle()
        .fill(color)
        .frame(width: 10, height: 10)
      Text(name)
        .font(.caption)
      Spacer()
      Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

struct QuickActionButton: View {
  let title: String
  let icon: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack {
        Image(systemName: icon)
          .font(.title2)
          .foregroundColor(color)
        Text(title)
          .font(.caption)
      }
      .frame(width: 100, height: 80)
      .background(color.opacity(0.1))
      .cornerRadius(12)
    }
    .buttonStyle(.plain)
  }
}

struct StorageRingChart: View {
  let used: Int64
  let total: Int64

  var usedPercent: Double {
    guard total > 0 else { return 0 }
    return Double(used) / Double(total)
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.gray.opacity(0.2), lineWidth: 12)

      Circle()
        .trim(from: 0, to: usedPercent)
        .stroke(
          usedPercent > 0.9 ? Color.red : Color.blue,
          style: StrokeStyle(lineWidth: 12, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))

      VStack(spacing: 2) {
        Text("\(Int(usedPercent * 100))%")
          .font(.title2)
          .fontWeight(.bold)
        Text("Used")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}

#Preview {
  UnifiedStorageView()
    .frame(width: 900, height: 600)
}
