import Foundation
import Logging

/// Manages the lifecycle, registration, and state of plugins.
public final class PluginManager: @unchecked Sendable {
  public static let shared = PluginManager()

  private let logger = Logger(label: "com.swiftsweep.pluginmanager")
  private let defaults = UserDefaults.standard

  // In-memory registry of available plugins
  private var registeredPlugins: [String: any SweepPlugin] = [:]

  // Thread-safe access to plugins
  private let queue = DispatchQueue(
    label: "com.swiftsweep.pluginmanager.queue", attributes: .concurrent)

  private init() {}

  /// Register a plugin implementation.
  /// This is typically called at app startup by the plugin integration layer.
  public func register(_ plugin: any SweepPlugin) {
    queue.async(flags: .barrier) {
      self.registeredPlugins[plugin.id] = plugin
      self.logger.info("Registered plugin: \(plugin.name) (\(plugin.id))")
    }
  }

  /// Get all registered plugins.
  public var allPlugins: [any SweepPlugin] {
    queue.sync {
      Array(registeredPlugins.values).sorted { $0.name < $1.name }
    }
  }

  /// Check if a plugin is enabled.
  public func isPluginEnabled(id: String) -> Bool {
    // Defaults to false (Disabled by default as per safer design)
    return defaults.bool(forKey: "PluginEnabled_\(id)")
  }

  /// Toggle plugin state.
  public func setPluginEnabled(id: String, enabled: Bool) {
    defaults.set(enabled, forKey: "PluginEnabled_\(id)")
    logger.info("Plugin \(id) enabled: \(enabled)")
  }

  /// Get all enabled plugins ready for execution.
  public var enabledPlugins: [any SweepPlugin] {
    allPlugins.filter { isPluginEnabled(id: $0.id) }
  }
}
