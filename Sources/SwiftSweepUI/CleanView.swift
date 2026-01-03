import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct CleanView: View {
  @EnvironmentObject var store: AppStore
  @State private var showingConfirmation = false
  @State private var showingResult = false

  var state: CleanupState { store.state.cleanup }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("System Cleanup")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text("Remove junk files, caches, and temporary data to free up disk space.")
          .foregroundColor(.secondary)

        // Scan Control
        if state.phase == .idle {
          Button(action: {
            store.dispatch(.cleanup(.startScan))
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
        if state.phase == .scanning {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              PulseView(icon: "magnifyingglass", color: .blue)
                .frame(width: 40, height: 40)
              Text("Scanning system...")
                .font(.headline)
            }

            Text("Found \(state.items.count) items...")
              .font(.caption)
              .foregroundColor(.secondary)

            IndeterminateProgressBar(color: .blue, height: 4)
              .padding(.top, 4)
          }
          .padding()
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(10)
        }

        // Error State
        if case .error(let message) = state.phase {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title)
              Text("Scan Failed")
                .font(.headline)
            }
            Text(message)
              .foregroundColor(.secondary)
            Button("Try Again") {
              store.dispatch(.cleanup(.startScan))
            }
            .buttonStyle(.borderedProminent)
          }
          .padding()
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(10)
        }

        // Results
        if state.phase == .scanned || state.phase == .completed {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title)
              VStack(alignment: .leading) {
                Text("Scan Complete")
                  .font(.headline)
                Text("Found \(formattedSize(state.totalSize))")
                  .foregroundColor(.secondary)
              }
              Spacer()
            }
            .padding()

            Divider()

            if state.items.isEmpty {
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
                ForEach(state.items) { item in
                  CleanupItemRowStore(itemID: item.id)
                }
              }
              .listStyle(.plain)
              .frame(minHeight: 300)
            }

            Divider()

            // Action Buttons
            HStack {
              Button("Scan Again") {
                store.dispatch(.cleanup(.reset))
                store.dispatch(.cleanup(.startScan))
              }
              .keyboardShortcut("r", modifiers: .command)

              Spacer()

              if !state.items.isEmpty {
                Button(action: {
                  showingConfirmation = true
                }) {
                  Label("Clean Selected", systemImage: "trash")
                    .padding(.horizontal)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(state.selectedSize == 0)
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
      CleanupConfirmationSheetStore(
        onConfirm: {
          showingConfirmation = false
          store.dispatch(.cleanup(.startClean))
        },
        onCancel: {
          showingConfirmation = false
        }
      )
    }
    .alert("Cleanup Result", isPresented: $showingResult) {
      Button("OK") {
        store.dispatch(.cleanup(.startScan))  // Rescan
      }
    } message: {
      if let result = state.cleanResult {
        Text(
          "\(result.successCount) items deleted\n\(result.failedCount) failed\nFreed: \(formattedSize(result.freedBytes))"
        )
      }
    }
    .onChange(of: state.phase) { newPhase in
      if case .completed = newPhase {
        showingResult = true
      }
    }
  }

  private func formattedSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

// MARK: - Store-connected Item Row

struct CleanupItemRowStore: View {
  @EnvironmentObject var store: AppStore
  let itemID: UUID

  var item: CleanupEngine.CleanupItem? {
    store.state.cleanup.items.first { $0.id == itemID }
  }

  var body: some View {
    if let item = item {
      HStack {
        Toggle(
          "",
          isOn: Binding(
            get: { item.isSelected },
            set: { _ in store.dispatch(.cleanup(.toggleItem(itemID))) }
          )
        )
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
      .padding(.vertical, 4)
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

// MARK: - Confirmation Sheet (Store-connected)

struct CleanupConfirmationSheetStore: View {
  @EnvironmentObject var store: AppStore
  let onConfirm: () -> Void
  let onCancel: () -> Void

  var items: [CleanupEngine.CleanupItem] {
    store.state.cleanup.selectedItems
  }

  var totalSize: Int64 {
    store.state.cleanup.selectedSize
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
          Text("\(items.count) items • \(formattedSize(totalSize))")
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

      // Items preview
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

  private func formattedSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1024 / 1024
    if mb > 1024 {
      return String(format: "%.2f GB", mb / 1024)
    }
    return String(format: "%.1f MB", mb)
  }
}
