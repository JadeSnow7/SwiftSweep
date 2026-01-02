import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct SettingsView: View {
  @AppStorage("autoCleanOnLaunch") private var autoCleanOnLaunch = false
  @AppStorage("showHiddenFiles") private var showHiddenFiles = false
  @AppStorage("defaultCleanCategory") private var defaultCleanCategory = "all"
  @AppStorage("allowAppleAppUninstall") private var allowAppleAppUninstall = false
  @ObservedObject private var languageManager = LanguageManager.shared
  @StateObject private var helperViewModel = HelperStatusViewModel()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Header
        VStack(alignment: .leading) {
          Text("Settings")
            .font(.largeTitle)
            .fontWeight(.bold)
          Text("Configure SwiftSweep preferences")
            .foregroundColor(.secondary)
        }
        .padding()

        // General Settings
        SettingsSection(title: "General", icon: "gear") {
          Picker("Language", selection: $languageManager.currentLanguage) {
            Text("English").tag("en")
            Text("中文").tag("zh-Hans")
          }
          .pickerStyle(.menu)

          Text("Language changes require restart to fully apply")
            .font(.caption)
            .foregroundColor(.secondary)

          Toggle("Auto-scan on launch", isOn: $autoCleanOnLaunch)
          Toggle("Show hidden files in analyzer", isOn: $showHiddenFiles)
        }

        // Cleanup Settings
        SettingsSection(title: "Cleanup", icon: "sparkles") {
          Picker("Default category", selection: $defaultCleanCategory) {
            Text("All").tag("all")
            Text("Cache").tag("cache")
            Text("Logs").tag("logs")
            Text("Browser").tag("browser")
          }
          .pickerStyle(.menu)
        }

        // Uninstall Settings
        SettingsSection(title: "Uninstall", icon: "trash") {
          Toggle(isOn: $allowAppleAppUninstall) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Allow Apple App Uninstall")
              Text(
                "Enable uninstalling iMovie, GarageBand, and other Apple apps from /Applications"
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }

          if allowAppleAppUninstall {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
              Text("Apple apps can be reinstalled from the App Store")
                .font(.caption)
                .foregroundColor(.orange)
            }
          }
        }

        // Insights Rules
        SettingsSection(title: "Insights Rules", icon: "lightbulb") {
          InsightsRulesConfigView()
        }

        // About
        SettingsSection(title: "About", icon: "info.circle") {
          HStack {
            Text("Version")
            Spacer()
            Text("0.1.0")
              .foregroundColor(.secondary)
          }

          HStack {
            Text("Build")
            Spacer()
            Text("Development")
              .foregroundColor(.secondary)
          }

          Link(destination: URL(string: "https://github.com/JadeSnow7/SwiftSweep")!) {
            HStack {
              Text("GitHub Repository")
              Spacer()
              Image(systemName: "arrow.up.right.square")
            }
          }
        }

        // Plugins
        SettingsSection(title: "Plugins", icon: "powerplug") {
          PluginSettingsView()
        }

        // Privileged Helper
        SettingsSection(title: "Privileged Helper", icon: "lock.shield") {
          HStack {
            VStack(alignment: .leading) {
              Text("Helper Status")
              Text("Required for system optimization and uninstallation")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            helperStatusBadge
          }

          if helperViewModel.status == .requiresApproval {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
              Text("Please approve SwiftSweep Helper in System Settings > Login Items")
                .font(.caption)
                .foregroundColor(.orange)
            }

            Button(action: openLoginItems) {
              Label("Open Login Items", systemImage: "gear")
            }
            .buttonStyle(.bordered)
          }

          HStack(spacing: 12) {
            Button(action: { Task { await helperViewModel.registerHelper() } }) {
              Label("Install Helper", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .disabled(helperViewModel.status == .enabled || helperViewModel.isLoading)

            if helperViewModel.isLoading {
              ProgressView()
                .scaleEffect(0.7)
            }

            if helperViewModel.status == .enabled {
              Button(action: { Task { await helperViewModel.unregisterHelper() } }) {
                Label("Remove", systemImage: "minus.circle")
              }
              .buttonStyle(.bordered)
              .tint(.red)
            }
          }

          if let error = helperViewModel.errorMessage {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
              Text(error)
                .font(.caption)
                .foregroundColor(.red)
            }
          }
        }

        Spacer()
      }
    }
    .onAppear {
      helperViewModel.checkStatus()
    }
  }

  @ViewBuilder
  var helperStatusBadge: some View {
    switch helperViewModel.status {
    case .enabled:
      Text("Enabled")
        .foregroundColor(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    case .requiresApproval:
      Text("Needs Approval")
        .foregroundColor(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    case .notRegistered, .notFound:
      Text("Not Installed")
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
  }

  private func openLoginItems() {
    // Open System Settings > Login Items
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }
}

@MainActor
class HelperStatusViewModel: ObservableObject {
  @Published var status: HelperClientStatus = .notRegistered
  @Published var isLoading = false
  @Published var errorMessage: String?

  enum HelperClientStatus {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
  }

  func checkStatus() {
    if #available(macOS 13.0, *) {
      let clientStatus = HelperClient.shared.checkStatus()
      switch clientStatus {
      case .notRegistered: status = .notRegistered
      case .enabled: status = .enabled
      case .requiresApproval: status = .requiresApproval
      case .notFound: status = .notFound
      }
    } else {
      status = .notFound
    }
  }

  func registerHelper() async {
    guard #available(macOS 13.0, *) else { return }
    isLoading = true
    errorMessage = nil

    do {
      try await HelperClient.shared.registerHelper()
      checkStatus()
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  func unregisterHelper() async {
    guard #available(macOS 13.0, *) else { return }
    isLoading = true

    do {
      try await HelperClient.shared.unregisterHelper()
      checkStatus()
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }
}

struct SettingsSection<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: icon)
          .foregroundColor(.accentColor)
        Text(title)
          .font(.headline)
      }
      .padding(.horizontal)

      VStack(alignment: .leading, spacing: 16) {
        content
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(10)
      .padding(.horizontal)
    }
  }
}

// MARK: - Insights Rules Configuration View

struct InsightsRulesConfigView: View {
  @State private var enabledRules: Set<String> = RuleSettings.shared.enabledRuleIDs
  @State private var oldDownloadsDays: Double = Double(
    RuleSettings.shared.threshold(forRule: "old_downloads", key: "days"))
  @State private var unusedAppsDays: Double = Double(
    RuleSettings.shared.threshold(forRule: "unused_apps", key: "days"))

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Rule toggles by category
      ForEach(RuleCategory.allCases, id: \.self) { category in
        VStack(alignment: .leading, spacing: 8) {
          Label(category.rawValue, systemImage: category.icon)
            .font(.subheadline.bold())
            .foregroundColor(.secondary)

          ForEach(RuleSettings.rules(in: category), id: \.self) { ruleID in
            ruleToggle(for: ruleID)
          }
        }
      }

      Divider()

      // Threshold sliders
      VStack(alignment: .leading, spacing: 12) {
        Text("Thresholds")
          .font(.subheadline.bold())
          .foregroundColor(.secondary)

        // Old Downloads threshold
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Old Downloads Age")
            Spacer()
            Text("\(Int(oldDownloadsDays)) days")
              .foregroundColor(.secondary)
          }
          Slider(value: $oldDownloadsDays, in: 7...90, step: 1)
            .onChange(of: oldDownloadsDays) { newValue in
              RuleSettings.shared.setThreshold(
                forRule: "old_downloads", key: "days", value: Int(newValue))
            }
        }

        // Unused Apps threshold
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Unused Apps Age")
            Spacer()
            Text("\(Int(unusedAppsDays)) days")
              .foregroundColor(.secondary)
          }
          Slider(value: $unusedAppsDays, in: 30...365, step: 1)
            .onChange(of: unusedAppsDays) { newValue in
              RuleSettings.shared.setThreshold(
                forRule: "unused_apps", key: "days", value: Int(newValue))
            }
        }
      }

      // Reset button
      Button("Reset to Defaults") {
        RuleSettings.shared.resetToDefaults()
        enabledRules = RuleSettings.shared.enabledRuleIDs
        oldDownloadsDays = 30
        unusedAppsDays = 90
      }
      .foregroundColor(.red)
    }
  }

  private func ruleToggle(for ruleID: String) -> some View {
    Toggle(
      isOn: Binding(
        get: { enabledRules.contains(ruleID) },
        set: { enabled in
          if enabled {
            enabledRules.insert(ruleID)
          } else {
            enabledRules.remove(ruleID)
          }
          RuleSettings.shared.setRuleEnabled(ruleID, enabled: enabled)
        }
      )
    ) {
      VStack(alignment: .leading, spacing: 2) {
        Text(RuleSettings.displayName(for: ruleID))
        Text(RuleSettings.description(for: ruleID))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}

#Preview {
  SettingsView()
}
