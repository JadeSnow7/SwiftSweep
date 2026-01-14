import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Git Repo Cleanup View

/// Git 仓库清理视图 - 扫描并清理构建产物和冗余文件
struct GitRepoCleanupView: View {
  @StateObject private var viewModel = GitRepoCleanupViewModel()
  @Environment(\.dismiss) private var dismiss

  let repoPath: String

  var body: some View {
    VStack(spacing: 0) {
      // Header
      header

      Divider()

      // Content
      if viewModel.isScanning {
        scanningView
      } else if viewModel.cleanupItems.isEmpty {
        emptyView
      } else {
        cleanupList
      }

      Divider()

      // Footer with actions
      footer
    }
    .frame(minWidth: 700, minHeight: 500)
    .onAppear {
      viewModel.scan(repoPath: repoPath)
    }
    .alert("Cleanup Complete", isPresented: $viewModel.showSuccessAlert) {
      Button("OK") { dismiss() }
    } message: {
      Text("Successfully cleaned \(formatBytes(viewModel.cleanedSize))")
    }
    .alert("Error", isPresented: $viewModel.showErrorAlert) {
      Button("OK") {}
    } message: {
      if let error = viewModel.error {
        Text(error.localizedDescription)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "trash.circle")
          .font(.title)
          .foregroundColor(.accentColor)

        VStack(alignment: .leading) {
          Text("Git Repository Cleanup")
            .font(.headline)
          Text(repoPath)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer()

        Button(action: { dismiss() }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
      }

      if !viewModel.cleanupItems.isEmpty {
        HStack(spacing: 16) {
          Label(
            "\(viewModel.cleanupItems.count) items",
            systemImage: "doc.on.doc"
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Label(
            formatBytes(viewModel.totalSize),
            systemImage: "externaldrive"
          )
          .font(.caption)
          .foregroundColor(.orange)
        }
      }
    }
    .padding()
  }

  private var scanningView: some View {
    VStack(spacing: 16) {
      Spacer()
      ProgressView()
        .scaleEffect(1.5)
      Text("Scanning repository...")
        .font(.headline)
      Text("Looking for build artifacts and redundant files")
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
  }

  private var emptyView: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "checkmark.circle")
        .font(.system(size: 60))
        .foregroundColor(.green)
      Text("Repository is clean!")
        .font(.headline)
      Text("No build artifacts or redundant files found")
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
  }

  private var cleanupList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        // Group by type
        ForEach(groupedItems, id: \.type) { group in
          Section {
            ForEach(group.items) { item in
              CleanupItemRow(
                item: item,
                isSelected: viewModel.selectedItems.contains(item.id)
              ) {
                viewModel.toggleSelection(item.id)
              }
              Divider()
            }
          } header: {
            HStack {
              Image(systemName: iconForType(group.type))
                .foregroundColor(colorForType(group.type))
              Text(group.type.rawValue)
                .font(.headline)
              Spacer()
              Text("\(group.items.count) items • \(formatBytes(group.totalSize))")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
          }
        }
      }
    }
  }

  private var footer: some View {
    HStack {
      Button(action: { viewModel.selectAll() }) {
        Text("Select All")
      }
      .buttonStyle(.borderless)

      Button(action: { viewModel.deselectAll() }) {
        Text("Deselect All")
      }
      .buttonStyle(.borderless)

      Spacer()

      if viewModel.isCleaning {
        ProgressView()
          .scaleEffect(0.8)
        Text("Cleaning...")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Button(action: { viewModel.runGitGC(repoPath: repoPath) }) {
        Label("Run Git GC", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)
      .disabled(viewModel.isCleaning)

      Button(action: { viewModel.clean() }) {
        Label("Clean Selected", systemImage: "trash")
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.selectedItems.isEmpty || viewModel.isCleaning)
    }
    .padding()
  }

  private var groupedItems:
    [(
      type: GitRepoCleaner.CleanupItem.CleanupType, items: [GitRepoCleaner.CleanupItem],
      totalSize: Int64
    )]
  {
    let groups = Dictionary(grouping: viewModel.cleanupItems) { $0.type }
    return groups.map { type, items in
      let totalSize = items.reduce(0) { $0 + $1.size }
      return (type, items, totalSize)
    }.sorted { $0.totalSize > $1.totalSize }
  }

  private func iconForType(_ type: GitRepoCleaner.CleanupItem.CleanupType) -> String {
    switch type {
    case .buildArtifact: return "hammer.circle"
    case .redundantFile: return "doc.badge.minus"
    case .gitObject: return "arrow.triangle.branch"
    }
  }

  private func colorForType(_ type: GitRepoCleaner.CleanupItem.CleanupType) -> Color {
    switch type {
    case .buildArtifact: return .orange
    case .redundantFile: return .red
    case .gitObject: return .blue
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Cleanup Item Row

struct CleanupItemRow: View {
  let item: GitRepoCleaner.CleanupItem
  let isSelected: Bool
  let onToggle: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Toggle(
        "",
        isOn: Binding(
          get: { isSelected },
          set: { _ in onToggle() }
        )
      )
      .toggleStyle(.checkbox)
      .labelsHidden()

      Image(systemName: "doc.fill")
        .foregroundColor(.secondary)
        .font(.caption)

      VStack(alignment: .leading, spacing: 2) {
        Text(URL(fileURLWithPath: item.path).lastPathComponent)
          .font(.body)
        Text(item.path)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Text(formatBytes(item.size))
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .onTapGesture {
      onToggle()
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - View Model

@MainActor
class GitRepoCleanupViewModel: ObservableObject {
  @Published var cleanupItems: [GitRepoCleaner.CleanupItem] = []
  @Published var selectedItems: Set<UUID> = []
  @Published var isScanning = false
  @Published var isCleaning = false
  @Published var totalSize: Int64 = 0
  @Published var cleanedSize: Int64 = 0

  @Published var showSuccessAlert = false
  @Published var showErrorAlert = false
  @Published var error: Error?

  func scan(repoPath: String) {
    isScanning = true

    Task {
      let result = await GitRepoCleaner.shared.scan(repoPath: repoPath)

      await MainActor.run {
        self.cleanupItems = result.items
        self.totalSize = result.totalSize
        // Auto-select all items
        self.selectedItems = Set(result.items.map { $0.id })
        self.isScanning = false
      }
    }
  }

  func clean() {
    let itemsToClean = cleanupItems.filter { selectedItems.contains($0.id) }
    guard !itemsToClean.isEmpty else { return }

    isCleaning = true

    Task {
      do {
        let cleaned = try await GitRepoCleaner.shared.clean(items: itemsToClean)

        await MainActor.run {
          self.cleanedSize = cleaned
          self.cleanupItems.removeAll { selectedItems.contains($0.id) }
          self.selectedItems.removeAll()
          self.totalSize -= cleaned
          self.isCleaning = false
          self.showSuccessAlert = true
        }
      } catch {
        await MainActor.run {
          self.error = error
          self.isCleaning = false
          self.showErrorAlert = true
        }
      }
    }
  }

  func runGitGC(repoPath: String) {
    isCleaning = true

    Task {
      let result = await GitRepoCleaner.shared.runGitGC(repoPath: repoPath, aggressive: false)

      await MainActor.run {
        self.isCleaning = false
        if result.success {
          // Rescan after GC
          self.scan(repoPath: repoPath)
        } else {
          self.error = NSError(
            domain: "GitGC", code: 1, userInfo: [NSLocalizedDescriptionKey: result.message])
          self.showErrorAlert = true
        }
      }
    }
  }

  func toggleSelection(_ id: UUID) {
    if selectedItems.contains(id) {
      selectedItems.remove(id)
    } else {
      selectedItems.insert(id)
    }
  }

  func selectAll() {
    selectedItems = Set(cleanupItems.map { $0.id })
  }

  func deselectAll() {
    selectedItems.removeAll()
  }
}

// MARK: - Preview

#Preview {
  GitRepoCleanupView(repoPath: "/Users/example/project")
}
