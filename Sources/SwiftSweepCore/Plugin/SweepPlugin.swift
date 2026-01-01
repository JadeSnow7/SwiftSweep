import Foundation

/// Protocol defining the interface for SwiftSweep plugins.
/// Plugins are identifiable, versioned modules that provide specific analysis capabilities.
public protocol SweepPlugin: Sendable {
  /// Unique identifier for the plugin (e.g., "com.swiftsweep.capcut").
  var id: String { get }

  /// Display name of the plugin.
  var name: String { get }

  /// Brief description of what the plugin does.
  var description: String { get }

  /// Semantic version of the plugin.
  var version: String { get }

  /// Minimum compatible version of the main app.
  var minAppVersion: String { get }

  /// Perform analysis on the given context.
  /// - Parameter context: verifiable context providing safe resources.
  /// - Returns: A list of Recommendations based on the analysis.
  func analyze(context: PluginContext) async throws -> [Recommendation]
}
