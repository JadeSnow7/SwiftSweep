import SwiftSweepCore
import SwiftUI

// MARK: - Media Analyzer View

/// 媒体文件分析视图
/// 展示相似/重复媒体文件，支持一键清理
public struct MediaAnalyzerView: View {
  @State private var isScanning = false
  @State private var scanProgress: Double = 0
  @State private var currentPhase: MediaAnalyzer.AnalysisPhase = .scanning
  @State private var result: MediaAnalysisResult?
  @State private var selectedDirectory: URL?
  @State private var showDirectoryPicker = false
  @State private var expandedGroups: Set<UUID> = []
  @State private var selectedForDeletion: Set<UUID> = []

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      Divider()

      // Content
      if isScanning {
        scanningView
      } else if let result = result {
        resultsView(result)
      } else {
        emptyStateView
      }
    }
    .frame(minWidth: 600, minHeight: 400)
    .fileImporter(
      isPresented: $showDirectoryPicker,
      allowedContentTypes: [.folder],
      onCompletion: handleDirectorySelection
    )
  }

  // MARK: - Header

  private var headerView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Media Analyzer")
          .font(.title2.bold())

        if let dir = selectedDirectory {
          Text(dir.path)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      HStack(spacing: 12) {
        Button("Select Folder") {
          showDirectoryPicker = true
        }
        .disabled(isScanning)

        if selectedDirectory != nil {
          Button(action: startScan) {
            Label("Scan", systemImage: "magnifyingglass")
          }
          .buttonStyle(.borderedProminent)
          .disabled(isScanning)
        }
      }
    }
    .padding()
  }

  // MARK: - Scanning View

  private var scanningView: some View {
    VStack(spacing: 16) {
      Spacer()

      ProgressView()
        .scaleEffect(1.5)

      Text(currentPhase.rawValue)
        .font(.headline)

      ProgressView(value: scanProgress)
        .frame(width: 200)

      Button("Cancel") {
        // Cancel would require Task cancellation
        isScanning = false
      }

      Spacer()
    }
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Spacer()

      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 64))
        .foregroundColor(.secondary)

      Text("Select a folder to analyze")
        .font(.headline)
        .foregroundColor(.secondary)

      Text("Find similar and duplicate photos/videos")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Button("Select Folder") {
        showDirectoryPicker = true
      }
      .buttonStyle(.borderedProminent)

      Spacer()
    }
  }

  // MARK: - Results View

  private func resultsView(_ result: MediaAnalysisResult) -> some View {
    VStack(spacing: 0) {
      // Summary bar
      summaryBar(result)

      Divider()

      // Groups list
      if result.similarGroups.isEmpty {
        noSimilarFilesView
      } else {
        List {
          ForEach(result.similarGroups) { group in
            SimilarGroupRow(
              group: group,
              isExpanded: expandedGroups.contains(group.id),
              selectedForDeletion: $selectedForDeletion
            ) {
              toggleExpanded(group.id)
            }
          }
        }
      }
    }
  }

  private func summaryBar(_ result: MediaAnalysisResult) -> some View {
    HStack {
      StatBadge(
        value: "\(result.scanResult.files.count)",
        label: "Files",
        icon: "doc.fill"
      )

      StatBadge(
        value: formatSize(result.scanResult.totalSize),
        label: "Total Size",
        icon: "internaldrive"
      )

      StatBadge(
        value: "\(result.similarGroups.count)",
        label: "Similar Groups",
        icon: "square.stack.3d.up.fill"
      )

      StatBadge(
        value: formatSize(result.totalReclaimableSize),
        label: "Reclaimable",
        icon: "trash.fill",
        tint: .green
      )

      Spacer()

      if !selectedForDeletion.isEmpty {
        Button(action: deleteSelected) {
          Label("Delete \(selectedForDeletion.count) files", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
  }

  private var noSimilarFilesView: some View {
    VStack(spacing: 16) {
      Spacer()

      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48))
        .foregroundColor(.green)

      Text("No similar files found")
        .font(.headline)

      Text("Your media library is well organized!")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Spacer()
    }
  }

  // MARK: - Actions

  private func handleDirectorySelection(_ result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      selectedDirectory = url
      // Save bookmark for future access
      Task {
        try? await MediaScanner.shared.saveBookmark(for: url)
      }
    case .failure:
      break
    }
  }

  private func startScan() {
    guard let directory = selectedDirectory else { return }

    isScanning = true
    scanProgress = 0
    result = nil

    Task {
      do {
        let analysisResult = try await MediaAnalyzer.shared.analyze(
          root: directory,
          onPhase: { phase in
            Task { @MainActor in
              currentPhase = phase
            }
          },
          onProgress: { current, total in
            Task { @MainActor in
              if total > 0 {
                scanProgress = Double(current) / Double(total)
              }
            }
          }
        )

        await MainActor.run {
          result = analysisResult
          isScanning = false
        }
      } catch {
        await MainActor.run {
          isScanning = false
        }
      }
    }
  }

  private func toggleExpanded(_ id: UUID) {
    if expandedGroups.contains(id) {
      expandedGroups.remove(id)
    } else {
      expandedGroups.insert(id)
    }
  }

  private func deleteSelected() {
    // TODO: Implement deletion
  }

  // MARK: - Helpers

  private func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

// MARK: - Similar Group Row

struct SimilarGroupRow: View {
  let group: SimilarGroup
  let isExpanded: Bool
  @Binding var selectedForDeletion: Set<UUID>
  let onToggle: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header
      HStack {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)

        // Thumbnail placeholder
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.secondary.opacity(0.2))
          .frame(width: 40, height: 40)
          .overlay {
            Image(systemName: group.representative.type == .video ? "video.fill" : "photo.fill")
              .foregroundColor(.secondary)
          }

        VStack(alignment: .leading, spacing: 2) {
          Text("\(group.duplicates.count + 1) similar files")
            .font(.headline)

          Text("Save \(formatSize(group.reclaimableSize))")
            .font(.caption)
            .foregroundColor(.green)
        }

        Spacer()

        Text(formatSize(group.totalSize))
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: onToggle)

      // Expanded content
      if isExpanded {
        VStack(spacing: 4) {
          // Representative (keep)
          FileRow(file: group.representative, isKeep: true, isSelected: false, onToggle: {})

          // Duplicates (can delete)
          ForEach(group.duplicates) { file in
            FileRow(
              file: file,
              isKeep: false,
              isSelected: selectedForDeletion.contains(file.id)
            ) {
              if selectedForDeletion.contains(file.id) {
                selectedForDeletion.remove(file.id)
              } else {
                selectedForDeletion.insert(file.id)
              }
            }
          }
        }
        .padding(.leading, 48)
      }
    }
    .padding(.vertical, 4)
  }

  private func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

// MARK: - File Row

struct FileRow: View {
  let file: MediaFile
  let isKeep: Bool
  let isSelected: Bool
  let onToggle: () -> Void

  var body: some View {
    HStack {
      if isKeep {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
      } else {
        Button(action: onToggle) {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(isSelected ? .red : .secondary)
        }
        .buttonStyle(.plain)
      }

      Text(file.url.lastPathComponent)
        .lineLimit(1)

      Spacer()

      if let duration = file.duration {
        Text(formatDuration(duration))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Text(formatSize(file.size))
        .font(.caption)
        .foregroundColor(.secondary)

      if isKeep {
        Text("Keep")
          .font(.caption.bold())
          .foregroundColor(.green)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.green.opacity(0.1))
          .cornerRadius(4)
      }
    }
    .padding(.vertical, 2)
  }

  private func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, secs)
  }
}

// MARK: - Stat Badge

struct StatBadge: View {
  let value: String
  let label: String
  let icon: String
  var tint: Color = .primary

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(tint)

      VStack(alignment: .leading, spacing: 0) {
        Text(value)
          .font(.headline)
          .foregroundColor(tint)

        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }
}

#Preview {
  MediaAnalyzerView()
}
