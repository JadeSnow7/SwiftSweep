import Foundation

/// Global Application State (Single Source of Truth)
public struct AppState: Equatable, Sendable {
  public var navigation: NavigationState
  public var uninstall: UninstallState
  public var cleanup: CleanupState

  public init(
    navigation: NavigationState = .init(),
    uninstall: UninstallState = .init(),
    cleanup: CleanupState = .init()
  ) {
    self.navigation = navigation
    self.uninstall = uninstall
    self.cleanup = cleanup
  }
}

/// State for Navigation (replaces NavigationState singleton)
public struct NavigationState: Equatable, Sendable {
  /// Pending uninstall request from outside the UninstallView (e.g., deep link or Applications tab)
  public var pendingUninstallURL: URL?

  public init(pendingUninstallURL: URL? = nil) {
    self.pendingUninstallURL = pendingUninstallURL
  }
}

/// State for Uninstall Feature
public struct UninstallState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case scanning
    case scanned
    case deleting
    case done
    case error(String)
  }

  public var phase: Phase = .idle
  public var apps: [UninstallEngine.InstalledApp] = []
  public var selectedAppID: UUID?
  public var residuals: [UninstallEngine.ResidualFile] = []
  public var deletionPlan: DeletionPlan?
  public var deletionResult: DeletionResult?

  /// URL to select once scan is complete (preselection support)
  public var pendingSelectionURL: URL?

  // Derived helper
  public var selectedApp: UninstallEngine.InstalledApp? {
    guard let id = selectedAppID else { return nil }
    return apps.first { $0.id == id }
  }

  public init() {}
}

/// State for Cleanup Feature
public struct CleanupState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case scanning
    case scanned
    case cleaning
    case completed
    case error(String)
  }

  public var phase: Phase = .idle
  public var items: [CleanupEngine.CleanupItem] = []
  public var cleanResult: CleanupResult?

  // Computed properties
  public var totalSize: Int64 {
    items.reduce(0) { $0 + $1.size }
  }

  public var selectedSize: Int64 {
    items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
  }

  public var selectedItems: [CleanupEngine.CleanupItem] {
    items.filter { $0.isSelected }
  }

  public init() {}
}

/// Result of cleanup operation
public struct CleanupResult: Equatable, Sendable {
  public let successCount: Int
  public let failedCount: Int
  public let freedBytes: Int64

  public init(successCount: Int, failedCount: Int, freedBytes: Int64) {
    self.successCount = successCount
    self.failedCount = failedCount
    self.freedBytes = freedBytes
  }
}
