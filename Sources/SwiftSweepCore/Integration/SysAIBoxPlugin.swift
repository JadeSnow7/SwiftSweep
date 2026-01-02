import Foundation

/// Sys AI Box Plugin - Thin attachment layer for Web UI integration.
/// v1 provides settings, health check, and "Open Console" functionality.
/// Full server/container management is handled by the Web UI.
public struct SysAIBoxPlugin: SweepPlugin {
  public let id = "com.swiftsweep.sysaibox"
  public let name = "Sys AI Box"
  public let description = "Remote server and container management via Sys AI Box Web UI"
  public let version = "0.1.0"
  public let minAppVersion = "1.0.0"

  public init() {}

  /// v1: Analysis is handled by Web UI; no local recommendations.
  public func analyze(context: PluginContext) async throws -> [Recommendation] {
    // Future: Could fetch remote risk recommendations from Sys AI Box API
    return []
  }

  /// Get the console URL for opening in browser.
  public static func consoleURL(baseURL: URL) -> URL {
    return baseURL.appendingPathComponent("console")
  }
}
