import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

/// Plugin Store view for browsing and installing data pack plugins.
public struct PluginStoreView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var catalog: PluginCatalog?
  @State private var installedIds: Set<String> = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var installProgress: [String: Bool] = [:]

  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Text("Plugin Store")
          .font(.title2)
          .fontWeight(.bold)
        Spacer()
        Button(action: refreshCatalog) {
          if isLoading {
            ProgressView()
              .scaleEffect(0.7)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)

        Button(action: { dismiss() }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .font(.title2)
        }
        .buttonStyle(.plain)
      }
      .padding()

      Divider()

      // Content
      if let error = errorMessage {
        errorView(error)
      } else if let catalog = catalog {
        pluginList(catalog.plugins)
      } else {
        loadingView
      }
    }
    .onAppear {
      refreshCatalog()
    }
  }

  // MARK: - Subviews

  private func pluginList(_ plugins: [PluginManifest]) -> some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(plugins) { plugin in
          PluginCard(
            plugin: plugin,
            isInstalled: installedIds.contains(plugin.id),
            isInstalling: installProgress[plugin.id] ?? false,
            onInstall: { installPlugin(plugin) },
            onUninstall: { uninstallPlugin(plugin.id) }
          )
        }
      }
      .padding()
    }
  }

  private var loadingView: some View {
    VStack {
      Spacer()
      ProgressView("Loading plugins...")
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "exclamationmark.triangle")
        .font(.largeTitle)
        .foregroundColor(.orange)
      Text(message)
        .foregroundColor(.secondary)
      Button("Retry") {
        refreshCatalog()
      }
      .buttonStyle(.bordered)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Actions

  private func refreshCatalog() {
    isLoading = true
    errorMessage = nil

    Task {
      do {
        let fetchedCatalog = try await PluginStoreManager.shared.fetchCatalog()
        let installed = await PluginStoreManager.shared.getInstalledPlugins()
        await MainActor.run {
          catalog = fetchedCatalog
          installedIds = Set(installed.map { $0.id })
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func installPlugin(_ plugin: PluginManifest) {
    installProgress[plugin.id] = true

    Task {
      do {
        try await PluginStoreManager.shared.install(manifest: plugin)
        await MainActor.run {
          installedIds.insert(plugin.id)
          installProgress[plugin.id] = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          installProgress[plugin.id] = false
        }
      }
    }
  }

  private func uninstallPlugin(_ pluginId: String) {
    _ = Task {
      do {
        try await PluginStoreManager.shared.uninstall(pluginId: pluginId)
        _ = await MainActor.run {
          installedIds.remove(pluginId)
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

// MARK: - Plugin Card

struct PluginCard: View {
  let plugin: PluginManifest
  let isInstalled: Bool
  let isInstalling: Bool
  let onInstall: () -> Void
  let onUninstall: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Icon
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.accentColor.opacity(0.1))
        .frame(width: 48, height: 48)
        .overlay {
          Image(systemName: "puzzlepiece.extension")
            .font(.title2)
            .foregroundColor(.accentColor)
        }

      // Info
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(plugin.name)
            .font(.headline)
          Text("v\(plugin.version)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        Text(plugin.description)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
        Text("by \(plugin.author)")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Spacer()

      // Action Button
      if isInstalling {
        ProgressView()
          .scaleEffect(0.7)
      } else if isInstalled {
        Button(action: onUninstall) {
          Text("Remove")
        }
        .buttonStyle(.bordered)
        .tint(.red)
      } else {
        Button(action: onInstall) {
          Text("Install")
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(12)
  }
}
