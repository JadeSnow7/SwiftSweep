#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif
import SwiftUI

public struct PluginSettingsView: View {
  @State private var plugins: [any SweepPlugin] = []

  public init() {}

  public var body: some View {
    Form {
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
