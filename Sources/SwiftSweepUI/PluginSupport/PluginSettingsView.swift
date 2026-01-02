import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

public struct PluginSettingsView: View {
  @State private var plugins: [any SweepPlugin] = []

  public init() {}

  public var body: some View {
    Form {
      // Sys AI Box Integration
      Section(header: Text("Sys AI Box")) {
        SysAIBoxSettingsRow()
      }

      Section(header: Text("Installed Plugins")) {
        if plugins.isEmpty {
          Text("No plugins installed.")
            .foregroundColor(.secondary)
        } else {
          ForEach(plugins, id: \.id) { plugin in
            PluginRow(plugin: plugin)
          }
        }
      }
    }
    .onAppear {
      self.plugins = PluginManager.shared.allPlugins
    }
  }
}

struct PluginRow: View {
  let plugin: any SweepPlugin
  @State private var isEnabled: Bool = false

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(plugin.name)
          .font(.headline)
        Text(plugin.description)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Toggle("", isOn: $isEnabled)
        .onChange(of: isEnabled) { newValue in
          PluginManager.shared.setPluginEnabled(id: plugin.id, enabled: newValue)
        }
    }
    .padding(.vertical, 4)
    .onAppear {
      self.isEnabled = PluginManager.shared.isPluginEnabled(id: plugin.id)
    }
  }
}

// MARK: - Sys AI Box Settings Row

struct SysAIBoxSettingsRow: View {
  @State private var baseURLString: String = ""
  @State private var connectionStatus: ConnectionStatus = .unknown
  @State private var authStatus: AuthStatus = .notPaired
  @State private var isLoading: Bool = false
  @State private var isPairing: Bool = false
  @State private var userCode: String?
  @State private var errorMessage: String?
  @State private var isOffline: Bool = false
  @State private var lastUpdated: Date?

  enum ConnectionStatus {
    case unknown, connected, failed
  }

  enum AuthStatus {
    case notPaired, pairing, paired
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // URL Input
      HStack {
        TextField("Base URL (e.g., https://box.local:8080)", text: $baseURLString)
          .textFieldStyle(.roundedBorder)

        Button(action: testConnection) {
          if isLoading {
            ProgressView()
              .scaleEffect(0.7)
          } else {
            Text("Test")
          }
        }
        .disabled(baseURLString.isEmpty || isLoading || isPairing)
      }

      // Status Row
      HStack {
        statusBadge
        Spacer()
        authBadge
      }

      // Action Buttons
      HStack {
        // Pair Device Button
        if authStatus == .notPaired {
          Button(action: startPairing) {
            if isPairing {
              ProgressView()
                .scaleEffect(0.7)
            } else {
              Label("Pair Device", systemImage: "link")
            }
          }
          .disabled(connectionStatus != .connected || isPairing)
        }

        // Disconnect Button
        if authStatus == .paired {
          Button(action: disconnect) {
            Label("Disconnect", systemImage: "xmark.circle")
          }
          .foregroundColor(.red)
        }

        Spacer()

        // Open Console Button
        Button(action: openConsole) {
          Label("Open Console", systemImage: "arrow.up.right.square")
        }
        .disabled(connectionStatus != .connected)
      }

      // User Code Display (during pairing)
      if let code = userCode, authStatus == .pairing {
        VStack(alignment: .leading, spacing: 8) {
          Text("Enter this code in the Web UI:")
            .font(.caption)
            .foregroundColor(.secondary)
          Text(code)
            .font(.system(.title, design: .monospaced))
            .fontWeight(.bold)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.top, 4)
      }

      // Error Message
      if let error = errorMessage {
        Text(error)
          .font(.caption)
          .foregroundColor(.red)
      }

      // Offline Indicator
      if isOffline, authStatus == .paired {
        HStack(spacing: 4) {
          Image(systemName: "wifi.slash")
            .foregroundColor(.orange)
          Text("Offline")
            .font(.caption)
            .foregroundColor(.orange)
          if let lastUpdated = lastUpdated {
            Text("• Last online: \(lastUpdated.formatted(.relative(presentation: .named)))")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
      }
    }
    .onAppear {
      loadSavedState()
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch connectionStatus {
    case .unknown:
      Text("Not configured")
        .font(.caption)
        .foregroundColor(.secondary)
    case .connected:
      HStack(spacing: 4) {
        Circle()
          .fill(.green)
          .frame(width: 8, height: 8)
        Text("Connected")
          .font(.caption)
          .foregroundColor(.green)
      }
    case .failed:
      HStack(spacing: 4) {
        Circle()
          .fill(.red)
          .frame(width: 8, height: 8)
        Text("Connection failed")
          .font(.caption)
          .foregroundColor(.red)
      }
    }
  }

  @ViewBuilder
  private var authBadge: some View {
    switch authStatus {
    case .notPaired:
      Text("Not paired")
        .font(.caption)
        .foregroundColor(.secondary)
    case .pairing:
      HStack(spacing: 4) {
        ProgressView()
          .scaleEffect(0.6)
        Text("Pairing...")
          .font(.caption)
          .foregroundColor(.orange)
      }
    case .paired:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text("Paired")
          .font(.caption)
          .foregroundColor(.green)
      }
    }
  }

  private func loadSavedState() {
    if let savedURL = SysAIBoxConfigStore.shared.loadBaseURL() {
      baseURLString = savedURL.absoluteString
      connectionStatus = .unknown
    }

    Task {
      let isPaired = await TokenManager.shared.isAuthenticated()
      await MainActor.run {
        authStatus = isPaired ? .paired : .notPaired
      }
    }
  }

  private func testConnection() {
    guard let url = URL(string: baseURLString) else {
      errorMessage = "Invalid URL format"
      connectionStatus = .failed
      return
    }

    isLoading = true
    errorMessage = nil

    Task {
      do {
        try SysAIBoxConfigStore.shared.save(baseURL: url)
        let response = try await SysAIBoxHealthChecker.shared.checkHealth(baseURL: url)
        await MainActor.run {
          connectionStatus = response.isHealthy ? .connected : .failed
          errorMessage = response.isHealthy ? nil : "Server reported unhealthy status"
          isLoading = false
        }
      } catch {
        await MainActor.run {
          connectionStatus = .failed
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func startPairing() {
    guard let url = URL(string: baseURLString) else { return }

    isPairing = true
    authStatus = .pairing
    errorMessage = nil

    Task {
      do {
        let pairingInfo = try await DeviceAuthManager.shared.startPairing(baseURL: url)
        await MainActor.run {
          userCode = pairingInfo.userCode
        }

        let tokens = try await DeviceAuthManager.shared.completePairing(
          pairingInfo: pairingInfo,
          baseURL: url
        ) { status in
          // Status updates handled by completePairing
        }

        try await TokenManager.shared.storeTokens(tokens)

        await MainActor.run {
          authStatus = .paired
          userCode = nil
          isPairing = false
        }
      } catch {
        await MainActor.run {
          authStatus = .notPaired
          userCode = nil
          isPairing = false
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func disconnect() {
    guard let url = URL(string: baseURLString) else { return }

    Task {
      try? await TokenManager.shared.revoke(baseURL: url)
      await MainActor.run {
        authStatus = .notPaired
      }
    }
  }

  private func openConsole() {
    guard let url = URL(string: baseURLString) else { return }
    let consoleURL = SysAIBoxPlugin.consoleURL(baseURL: url)
    #if os(macOS)
      NSWorkspace.shared.open(consoleURL)
    #endif
  }
}
