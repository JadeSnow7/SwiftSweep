import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - UninstallView

struct UninstallView: View {
  @EnvironmentObject var store: AppStore
  @State private var searchText = ""
  @State private var showErrorAlert = false
  @State private var errorMessage = ""
  var preselectedAppURL: URL?

  init(preselectedAppURL: URL? = nil) {
    self.preselectedAppURL = preselectedAppURL
  }

  // Maps to store state
  var state: UninstallState { store.state.uninstall }

  var filteredApps: [UninstallEngine.InstalledApp] {
    if searchText.isEmpty {
      return state.apps
    }
    return state.apps.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.bundleID.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        VStack(alignment: .leading) {
          Text("App Uninstaller")
            .font(.largeTitle)
            .fontWeight(.bold)
          HStack(spacing: 8) {
            Text("Remove apps and their residual files")
              .foregroundColor(.secondary)

            if state.phase == .scanning {
              ProgressView()
                .scaleEffect(0.6)
            }
          }
        }
        Spacer()

        Button(action: {
          store.dispatch(.uninstall(.startScan))
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(state.phase == .scanning)
      }
      .padding()

      // Search
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
        TextField("Search apps...", text: $searchText)
          .textFieldStyle(.plain)
      }
      .padding(8)
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(8)
      .padding(.horizontal)

      Divider()
        .padding(.top)

      if state.apps.isEmpty && state.phase != .scanning {
        EmptyStateView()
      } else {
        // App List
        List(
          filteredApps,
          selection: Binding(
            get: { state.selectedApp },
            set: { app in
              if let id = app?.id {
                store.dispatch(.uninstall(.selectApp(id)))
              } else {
                // Handle deselection if needed, though List usually handles selection binding by ID
              }
            }
          )
        ) { app in
          AppRow(app: app, isSelected: state.selectedAppID == app.id)
            .tag(app)
            .onTapGesture {
              store.dispatch(.uninstall(.selectApp(app.id)))
            }
        }
        .listStyle(.inset)
      }

      // Detail Panel
      if let selected = state.selectedApp {
        Divider()
        AppDetailPanel(app: selected, residuals: state.residuals)
      }
    }
    .sheet(
      isPresented: Binding(
        get: { state.deletionPlan != nil },
        set: { if !$0 { store.dispatch(.uninstall(.cancelUninstall)) } }
      )
    ) {
      if let plan = state.deletionPlan {
        UninstallConfirmationSheet(plan: plan)
      }
    }
    .onAppear {
      // Set pending selection before scan starts
      if let url = preselectedAppURL {
        // Set pending selection in state so it's applied after scan
        store.dispatch(.uninstall(.setPendingSelection(url)))
      }

      if state.apps.isEmpty {
        store.dispatch(.uninstall(.startScan))
      } else if let url = preselectedAppURL {
        // Scan already done, try immediate selection
        if let app = state.apps.first(where: { $0.path == url.path }) {
          store.dispatch(.uninstall(.selectApp(app.id)))
        }
      }
    }
    .onChange(of: state.phase) { newPhase in
      if case .error(let msg) = newPhase {
        errorMessage = msg
        showErrorAlert = true
      }
    }
    .alert("Uninstall Error", isPresented: $showErrorAlert) {
      Button("OK") {
        store.dispatch(.uninstall(.reset))
      }
    } message: {
      Text(errorMessage)
    }
  }
}

// MARK: - Subviews

struct EmptyStateView: View {
  @EnvironmentObject var store: AppStore

  var body: some View {
    VStack {
      Spacer()
      Image(systemName: "app.badge.checkmark")
        .font(.system(size: 48))
        .foregroundColor(.secondary)
      Text("No apps scanned yet")
        .foregroundColor(.secondary)
      Button("Scan Applications") {
        store.dispatch(.uninstall(.startScan))
      }
      .buttonStyle(.borderedProminent)
      .padding(.top)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

struct AppRow: View {
  let app: UninstallEngine.InstalledApp
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
        .resizable()
        .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(app.name.replacingOccurrences(of: ".app", with: ""))
          .fontWeight(.medium)
        Text(app.bundleID)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if app.size > 0 {
        Text(formatBytes(app.size))
          .font(.callout)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }

  // Helper to format bytes
  func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct AppDetailPanel: View {
  let app: UninstallEngine.InstalledApp
  let residuals: [UninstallEngine.ResidualFile]
  @EnvironmentObject var store: AppStore

  var totalSize: Int64 {
    app.size + residuals.reduce(0) { $0 + $1.size }
  }

  // Check if Helper is "available" - simplified for this refactor
  // In real app, we check actual HelperClient status.
  var isHelperAvailable: Bool {
    if #available(macOS 13.0, *) {
      return true  // Assuming helper is available or we prompt
    }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading) {
          Text(app.name.replacingOccurrences(of: ".app", with: ""))
            .font(.headline)
          Text("Total: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
            .foregroundColor(.secondary)
        }

        Spacer()

        Button(action: {
          store.dispatch(.uninstall(.prepareUninstall(app)))
        }) {
          Label("Uninstall", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!isHelperAvailable)
      }

      if !residuals.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ResidualBadge(label: "App", size: app.size, color: .blue)

            // Simplified grouping for badge display
            let grouped = Dictionary(grouping: residuals, by: { $0.type })
            ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
              let size = grouped[type]?.reduce(0) { $0 + $1.size } ?? 0
              ResidualBadge(label: type.rawValue, size: size, color: colorForType(type))
            }
          }
        }
      }

      if !isHelperAvailable {
        Text("⚠️ requires macOS 13+")
          .font(.caption)
          .foregroundColor(.orange)
      }
    }
    .padding()
    .background(Color(nsColor: .controlBackgroundColor))
  }

  func colorForType(_ type: UninstallEngine.ResidualType) -> Color {
    switch type {
    case .cache: return .orange
    case .preferences: return .purple
    case .appSupport: return .green
    case .launchAgent: return .red
    case .container: return .cyan
    case .other: return .gray
    }
  }
}

struct ResidualBadge: View {
  let label: String
  let size: Int64
  let color: Color

  var body: some View {
    VStack(spacing: 2) {
      Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        .font(.caption)
        .fontWeight(.semibold)
      Text(label)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(color.opacity(0.15))
    .cornerRadius(8)
  }
}

struct UninstallConfirmationSheet: View {
  let plan: DeletionPlan
  @EnvironmentObject var store: AppStore

  // Local state derived from global state
  var isDeleting: Bool { store.state.uninstall.phase == .deleting }
  var result: DeletionResult? { store.state.uninstall.deletionResult }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 12) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: plan.app.path))
          .resizable()
          .frame(width: 44, height: 44)
          .cornerRadius(8)

        VStack(alignment: .leading, spacing: 4) {
          Text("Confirm Uninstall")
            .font(.headline)
          Text(plan.app.name)
            .foregroundColor(.secondary)
          Text(
            "Space: \(ByteCountFormatter.string(fromByteCount: plan.totalSize, countStyle: .file))"
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
        Spacer()
      }
      .padding()

      Divider()

      // File List
      List {
        ForEach(plan.items) { item in
          HStack {
            Text(item.path)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
              .foregroundColor(.secondary)
          }
        }
      }
      .listStyle(.bordered)
      .frame(height: 250)
      .padding()

      if isDeleting {
        HStack {
          ProgressView()
          Text("Deleting...")
        }
        .padding()
      } else if let res = result {
        HStack {
          Image(
            systemName: res.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundColor(res.isComplete ? .green : .orange)

          if res.isComplete {
            Text("Uninstall Complete!")
          } else {
            Text("Partial success. Failed: \(res.failureCount)")
          }
        }
        .padding()
      }

      Divider()

      // Actions
      HStack {
        if result == nil || !result!.isComplete {
          Button("Cancel") {
            store.dispatch(.uninstall(.cancelUninstall))
          }
          .keyboardShortcut(.escape)
          .disabled(isDeleting)
        }

        Spacer()

        if result == nil {
          Button("Confirm Uninstall") {
            store.dispatch(.uninstall(.startDelete))
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .disabled(isDeleting)
        } else {
          Button("Done") {
            store.dispatch(.uninstall(.cancelUninstall))
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding()
    }
    .frame(width: 500, height: 500)
  }
}
