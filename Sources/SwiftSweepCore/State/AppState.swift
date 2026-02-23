import Foundation

/// Global Application State (Single Source of Truth)
public struct AppState: Equatable, Sendable {
  public var navigation: NavigationState
  public var uninstall: UninstallState
  public var cleanup: CleanupState
  public var insights: InsightsState
  public var status: StatusState
  public var workspaceFileManager: WorkspaceFileManagerState
  public var workspaceLauncher: WorkspaceLauncherState
  public var workspaceMedia: WorkspaceMediaState
  public var workspaceDocuments: WorkspaceDocumentsState

  public init(
    navigation: NavigationState = .init(),
    uninstall: UninstallState = .init(),
    cleanup: CleanupState = .init(),
    insights: InsightsState = .init(),
    status: StatusState = .init(),
    workspaceFileManager: WorkspaceFileManagerState = .init(),
    workspaceLauncher: WorkspaceLauncherState = .init(),
    workspaceMedia: WorkspaceMediaState = .init(),
    workspaceDocuments: WorkspaceDocumentsState = .init()
  ) {
    self.navigation = navigation
    self.uninstall = uninstall
    self.cleanup = cleanup
    self.insights = insights
    self.status = status
    self.workspaceFileManager = workspaceFileManager
    self.workspaceLauncher = workspaceLauncher
    self.workspaceMedia = workspaceMedia
    self.workspaceDocuments = workspaceDocuments
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

/// State for Insights Feature
public struct InsightsState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  public var phase: Phase = .idle
  public var recommendations: [Recommendation] = []
  public var selectedRecommendation: Recommendation?
  public var selectedCategory: RuleCategory?
  public var isCacheHit: Bool = false
  public var cacheAge: TimeInterval?
  public var actionInProgress: Bool = false
  public var actionResult: ActionResult?

  public init() {}
}

/// State for Status/System Monitor Feature
public struct StatusState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case monitoring
    case error(String)
  }

  public var phase: Phase = .idle
  public var cpuUsage: Double = 0
  public var memoryUsage: Double = 0
  public var memoryUsed: Int64 = 0
  public var memoryTotal: Int64 = 0
  public var diskUsage: Double = 0
  public var diskUsed: Int64 = 0
  public var diskTotal: Int64 = 0
  public var batteryLevel: Double = 0
  public var networkDownload: Double = 0
  public var networkUpload: Double = 0
  public var ioReadRate: Double = 0
  public var ioWriteRate: Double = 0
  public var peripheralSnapshot: PeripheralSnapshot = PeripheralSnapshot(
    displays: [], inputDevices: [], collectedAt: Date())
  public var lastUpdated: Date?
  public var showProcessSheet: ProcessMetricType?
  public var showPeripheralsSheet: Bool = false
  public var showDiagnosticsSheet: Bool = false

  public init() {}
}

// MARK: - Workspace State

public struct WorkspaceTabState: Equatable, Sendable, Identifiable {
  public let id: UUID
  public var locationURL: URL
  public var title: String
  public var items: [WorkspaceItem]
  public var selectedItemIDs: Set<String>
  public var sort: WorkspaceSortDescriptor

  public init(
    id: UUID = UUID(),
    locationURL: URL,
    title: String? = nil,
    items: [WorkspaceItem] = [],
    selectedItemIDs: Set<String> = [],
    sort: WorkspaceSortDescriptor = .init()
  ) {
    self.id = id
    self.locationURL = locationURL
    self.title = title ?? locationURL.lastPathComponent
    self.items = items
    self.selectedItemIDs = selectedItemIDs
    self.sort = sort
  }
}

public struct WorkspacePaneState: Equatable, Sendable {
  public var tabs: [WorkspaceTabState]
  public var selectedTabID: UUID

  public init(tabs: [WorkspaceTabState], selectedTabID: UUID) {
    self.tabs = tabs
    self.selectedTabID = selectedTabID
  }

  public var selectedTabIndex: Int {
    tabs.firstIndex(where: { $0.id == selectedTabID }) ?? 0
  }

  public var selectedTab: WorkspaceTabState? {
    guard !tabs.isEmpty else { return nil }
    return tabs[selectedTabIndex]
  }
}

public struct WorkspaceFileManagerState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
  }

  public var phase: Phase
  public var isDualPane: Bool
  public var activePane: WorkspacePane
  public var leftPane: WorkspacePaneState
  public var rightPane: WorkspacePaneState
  public var favorites: [URL]
  public var recentLocations: [URL]
  public var mountedVolumes: [URL]
  public var queueItems: [FileOperationProgress]
  public var showQueueSheet: Bool
  public var previewURL: URL?

  public init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let leftTab = WorkspaceTabState(locationURL: home, title: home.lastPathComponent)
    let rightTab = WorkspaceTabState(locationURL: home, title: home.lastPathComponent)

    self.phase = .idle
    self.isDualPane = true
    self.activePane = .left
    self.leftPane = WorkspacePaneState(tabs: [leftTab], selectedTabID: leftTab.id)
    self.rightPane = WorkspacePaneState(tabs: [rightTab], selectedTabID: rightTab.id)
    self.favorites = [home]
    self.recentLocations = []
    self.mountedVolumes = []
    self.queueItems = []
    self.showQueueSheet = false
    self.previewURL = nil
  }
}

public struct WorkspaceLauncherState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case error(String)
  }

  public var phase: Phase = .idle
  public var pinnedItems: [PinnedLaunchItem] = []

  public init() {}
}

public struct WorkspaceMediaState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case error(String)
  }

  public var phase: Phase = .idle
  public var rootURL: URL?
  public var items: [MediaLibraryItem] = []
  public var selectedKinds: Set<WorkspaceMediaKind> = []
  public var minSize: Int64 = 0
  public var showDuplicatesView: Bool = false

  public init() {}
}

public struct WorkspaceDocumentsState: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case error(String)
  }

  public var phase: Phase = .idle
  public var rootURL: URL?
  public var query: DocumentQuery = .init()
  public var records: [DocumentRecord] = []
  public var savedSearches: [WorkspaceSavedSearch] = []
  public var selectedRecordID: String?
  public var page: Int = 0
  public var pageSize: Int = 200
  public var totalCount: Int = 0

  public init() {}
}

/// Process metric type for sheet display
public enum ProcessMetricType: String, Equatable, Sendable {
  case cpu
  case memory
}

/// Action result for insights
public struct ActionResult: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let success: Bool
  public let message: String
  public let freedBytes: Int64?

  public init(id: UUID = UUID(), success: Bool, message: String, freedBytes: Int64? = nil) {
    self.id = id
    self.success = success
    self.message = message
    self.freedBytes = freedBytes
  }
}
