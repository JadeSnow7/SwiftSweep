import Foundation

#if canImport(SwiftSweepCore)
  // Internal file, no need to import self
#endif

/// Analyzes the potential impact of removing a package
public actor ImpactAnalyzer {
  public static let shared = ImpactAnalyzer()

  private let graphService = DependencyGraphService.shared

  public init() {}

  /// Analyze impact of removing a package
  public func analyzeRemoval(packageId: String) async throws -> RemovalImpact {
    guard
      let node = try await graphService.getAllNodes().first(where: {
        $0.identity.canonicalKey == packageId
      })
    else {
      throw IngestionError(phase: "analyze", message: "Package not found", recoverable: false)
    }

    // Get base graph removal impact
    let graphImpact = try await graphService.simulateRemoval(of: node)

    // Enhance with warnings
    var warnings = graphImpact.warnings

    // 1. Check for system/critical packages
    if isCriticalPackage(node) {
      warnings.append("⚠️ This appears to be a critical system-related package.")
    }

    // 2. Check for cross-ecosystem implications
    // Example: removing a python version used by pip
    if node.identity.ecosystemId == "homebrew_formula" && node.identity.name.contains("python") {
      warnings.append("⚠️ Removing Python may break pip packages installed in global site-packages.")
    }

    if node.identity.ecosystemId == "homebrew_formula" && node.identity.name.contains("node") {
      warnings.append("⚠️ Removing Node.js will break all globally installed npm packages.")
    }

    // 3. Check for high dependent count (indirect impact)
    if graphImpact.totalAffected > 20 {
      warnings.append("⚠️ Removing this will break \(graphImpact.totalAffected) other packages.")
    }

    return RemovalImpact(
      directDependents: graphImpact.directDependents,
      totalAffected: graphImpact.totalAffected,
      isSafeToRemove: graphImpact.isSafeToRemove && warnings.isEmpty,
      warnings: warnings
    )
  }

  private func isCriticalPackage(_ node: PackageNode) -> Bool {
    let criticalNames = [
      "openssl", "glib", "pkg-config", "readline", "sqlite", "xz", "automake", "autoconf",
    ]
    return criticalNames.contains(node.identity.name)
  }
}
