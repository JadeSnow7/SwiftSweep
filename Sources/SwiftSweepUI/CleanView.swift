import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct CleanView: View {
  @StateObject private var viewModel = CleanupViewModel()
  @State private var showingConfirmation = false
  @State private var cleanupResult: CleanupResult?
  @State private var showingResult = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("System Cleanup")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text("Remove junk files, caches, and temporary data to free up disk space.")
          .foregroundColor(.secondary)

        // Scan Control
        if !viewModel.isScanning && !viewModel.scanComplete {
          Button(action: {
            Task { await viewModel.startScan() }
          }) {
            Label("Start Scan", systemImage: "magnifyingglass")
              .frame(maxWidth: .infinity)
              .padding()
          }
          .controlSize(.large)
          .buttonStyle(.borderedProminent)
          .padding(.top)
        }

        // Scanning Progress
        if viewModel.isScanning {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              PulseView(icon: "magnifyingglass", color: .blue)
                .frame(width: 40, height: 40)
              Text("Scanning system...")
                .font(.headline)
            }

            Text("Found \(viewModel.items.count) items...")
              .font(.caption)
              .foregroundColor(.secondary)

            IndeterminateProgressBar(color: .blue, height: 4)
              .padding(.top, 4)
          }
          .padding()
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(10)
        }

        // Results
        if viewModel.scanComplete {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title)
              VStack(alignment: .leading) {
                Text("Scan Complete")
                  .font(.headline)
                Text("Found \(viewModel.formattedTotalSize)")
                  .foregroundColor(.secondary)
              }
              Spacer()
            }
            .padding()

            Divider()

            if viewModel.items.isEmpty {
              HStack {
                Spacer()
                VStack(spacing: 10) {
                  Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                  Text("Your system is clean!")
                    .foregroundColor(.secondary)
                }
                Spacer()
              }
              .padding(.vertical, 40)
            } else {
              List {
                ForEach($viewModel.items) { $item in
                  CleanupItemRow(item: $item)
                    .padding(.vertical, 4)
                }
              }
              .listStyle(.plain)
              .frame(minHeight: 300)
            }

            Divider()

            // Action Buttons
            HStack {
              Button("Scan Again") {
                viewModel.reset()
              }
              .keyboardShortcut("r", modifiers: .command)

              Spacer()

              if !viewModel.items.isEmpty {
                Button(action: {
                  showingConfirmation = true
                }) {
                  Label("Clean Selected", systemImage: "trash")
                    .padding(.horizontal)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.selectedSize == 0)
              }
            }
            .padding()
          }
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(10)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.gray.opacity(0.2), lineWidth: 1)
          )
        }

        Spacer()
      }
      .padding()
    }
    .sheet(isPresented: $showingConfirmation) {
      CleanupConfirmationSheet(
        items: viewModel.items.filter { $0.isSelected },
        onConfirm: {
          showingConfirmation = false
          Task {
            let result = await viewModel.cleanSelected()
            cleanupResult = result
            showingResult = true
          }
        },
        onCancel: {
          showingConfirmation = false
        }
      )
    }
    .alert("Cleanup Result", isPresented: $showingResult) {
      Button("OK") {
        cleanupResult = nil
        Task { await viewModel.startScan() }  // Rescan
      }
    } message: {
      if let result = cleanupResult {
        Text(
          "\(result.successCount) items deleted\n\(result.failedCount) failed\nFreed: \(result.formattedFreedSpace)"
        )
      }
    }
  }
}

// MARK: - Cleanup Result

struct CleanupResult {
  let successCount: Int
  let failedCount: Int
  let freedBytes: Int64

  var formattedFreedSpace: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: freedBytes)
  }
}

// MARK: - Confirmation Sheet

struct CleanupConfirmationSheet: View {
  let items: [CleanupEngine.CleanupItem]
  let onConfirm: () -> Void
  let onCancel: () -> Void

  private var totalSize: Int64 {
    items.reduce(0) { $0 + $1.size }
  }

  private var formattedSize: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: totalSize)
  }

  var body: some View {
    VStack(spacing: 16) {
      // Header
      HStack {
        Image(systemName: "trash.fill")
          .font(.title)
          .foregroundColor(.red)
        VStack(alignment: .leading) {
          Text("Confirm Deletion")
            .font(.headline)
          Text("\(items.count) items • \(formattedSize)")
            .foregroundColor(.secondary)
        }
        Spacer()
      }

      Divider()

      // Warning
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
        Text("This action is permanent and cannot be undone.")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(8)
      .background(Color.orange.opacity(0.1))
      .cornerRadius(4)

      // Items preview (Top 10)
      VStack(alignment: .leading, spacing: 4) {
        Text("Items to delete:")
          .font(.caption)
          .foregroundColor(.secondary)

        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(items.prefix(10), id: \.path) { item in
              HStack {
                Text(item.name)
                  .font(.caption)
                Spacer()
                Text(formatBytes(item.size))
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            if items.count > 10 {
              Text("... and \(items.count - 10) more")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .frame(maxHeight: 150)
      }
      .padding(8)
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(4)

      Divider()

      // Actions
      HStack {
        Button("Cancel", role: .cancel) {
          onCancel()
        }
        .keyboardShortcut(.escape)

        Spacer()

        Button(role: .destructive) {
          onConfirm()
        } label: {
          Label("Delete Permanently", systemImage: "trash.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
      }
    }
    .padding()
    .frame(width: 450)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

struct CleanupItemRow: View {
  @Binding var item: CleanupEngine.CleanupItem

  var body: some View {
    HStack {
      Toggle("", isOn: $item.isSelected)
        .labelsHidden()

      Image(systemName: iconForCategory(item.category))
        .foregroundColor(.blue)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.name)
          .fontWeight(.medium)
        Text(item.path)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Text(formatBytes(item.size))
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
        .font(.monospacedDigit(.body)())
    }
  }

  func iconForCategory(_ category: CleanupEngine.CleanupCategory) -> String {
    switch category {
    case .userCache, .systemCache: return "folder.fill"
    case .logs: return "doc.text.fill"
    case .trash: return "trash.fill"
    case .browserCache: return "globe"
    case .developerTools: return "hammer.fill"
    case .applications: return "app.fill"
    case .other: return "doc.fill"
    }
  }

  func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1024 / 1024
    if mb > 1024 {
      return String(format: "%.2f GB", mb / 1024)
    }
    return String(format: "%.1f MB", mb)
  }
}

@MainActor
class CleanupViewModel: ObservableObject {
  @Published var items: [CleanupEngine.CleanupItem] = []
  @Published var isScanning = false
  @Published var scanComplete = false

  var selectedSize: Int64 {
    items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
  }

  var formattedTotalSize: String {
    let bytes = items.reduce(0) { $0 + $1.size }
    let mb = Double(bytes) / 1024 / 1024
    if mb > 1024 {
      return String(format: "%.2f GB", mb / 1024)
    }
    return String(format: "%.1f MB", mb)
  }

  func startScan() async {
    isScanning = true
    scanComplete = false
    items = []

    do {
      // Artificial delay for better UX if scan is too fast
      try? await Task.sleep(nanoseconds: 500_000_000)

      let foundItems = try await CleanupEngine.shared.scanForCleanableItems()

      withAnimation {
        self.items = foundItems
        self.isScanning = false
        self.scanComplete = true
      }
    } catch {
      print("Scan failed: \(error)")
      self.isScanning = false
      self.scanComplete = true
    }
  }

  func cleanSelected() async -> CleanupResult {
    let selectedItems = items.filter { $0.isSelected }
    guard !selectedItems.isEmpty else {
      return CleanupResult(successCount: 0, failedCount: 0, freedBytes: 0)
    }

    var successCount = 0
    var failedCount = 0
    var freedBytes: Int64 = 0
    let fm = FileManager.default

    for item in selectedItems {
      do {
        try fm.removeItem(atPath: item.path)
        successCount += 1
        freedBytes += item.size
      } catch {
        failedCount += 1
        print("Failed to delete \(item.path): \(error)")
      }
    }

    return CleanupResult(
      successCount: successCount, failedCount: failedCount, freedBytes: freedBytes)
  }

  func reset() {
    items = []
    scanComplete = false
    isScanning = false
  }
}
