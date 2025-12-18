import Foundation

// MARK: - RecommendationRule Protocol

/// Protocol for pluggable recommendation rules.
/// Each rule evaluates the context and returns zero or more recommendations.
public protocol RecommendationRule: Sendable {
    /// Unique identifier for the rule (used for caching, logging, feature flags)
    var id: String { get }
    
    /// Human-readable name for the rule
    var displayName: String { get }
    
    /// Capabilities/permissions this rule requires
    var capabilities: [RuleCapability] { get }
    
    /// Evaluates the context and returns recommendations.
    /// - Parameter context: Aggregated data for rule evaluation
    /// - Returns: Array of recommendations (may be empty)
    func evaluate(context: RecommendationContext) async throws -> [Recommendation]
}

// MARK: - RuleCapability

/// Capabilities or data sources a rule needs.
public enum RuleCapability: String, Sendable, CaseIterable {
    case systemMetrics = "systemMetrics"       // Needs SystemMonitor data
    case cleanupItems = "cleanupItems"         // Needs CleanupEngine scan
    case downloadsAccess = "downloadsAccess"   // Needs access to ~/Downloads
    case installedApps = "installedApps"       // Needs app inventory
    case spotlightQuery = "spotlightQuery"     // Needs NSMetadataQuery
    case helperRequired = "helperRequired"     // Needs privileged helper for actions
}

// MARK: - Default Implementation

public extension RecommendationRule {
    /// Default: no special capabilities required
    var capabilities: [RuleCapability] { [] }
}
