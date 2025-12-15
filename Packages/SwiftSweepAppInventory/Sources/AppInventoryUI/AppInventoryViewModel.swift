import SwiftUI
import AppKit
import Combine
import AppInventoryLogic

/// State machine for the App Inventory.
public enum InventoryState: Equatable {
    case idle
    case loadingBaseline
    case baselineReady
    case baselineUnavailableOrEmpty
    case authorizedReady
    case deepScanning(current: Int, total: Int)
    case error(String)
    
    public static func == (lhs: InventoryState, rhs: InventoryState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loadingBaseline, .loadingBaseline),
             (.baselineReady, .baselineReady),
             (.baselineUnavailableOrEmpty, .baselineUnavailableOrEmpty),
             (.authorizedReady, .authorizedReady):
            return true
        case let (.deepScanning(c1, t1), .deepScanning(c2, t2)):
            return c1 == c2 && t1 == t2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// ViewModel for App Inventory, shared between MAS and Main.
@MainActor
public final class AppInventoryViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var state: InventoryState = .idle
    @Published public var apps: [AppItem] = []
    @Published public var categories: [AppCategory] = []
    @Published public var assignments: [String: UUID] = [:]
    @Published public var searchText: String = ""
    @Published public var selectedFilter: FilterType = .all
    @Published public var isAuthorized: Bool = false
    
    // MARK: - Filter Types
    
    public enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case large = "Large Apps"
        case unused = "Unused"
        case recentlyUpdated = "Recently Updated"
        case uncategorized = "Uncategorized"
        
        public var id: String { rawValue }
    }
    
    // MARK: - Dependencies
    
    private let inventoryProvider: InventoryProvider
    private let organizationStore: OrganizationStore
    private let cacheStore: CacheStore
    private var deepScanner: DeepScanner?
    
    // Bookmark storage
    private let defaults: UserDefaults
    private let bookmarkKey = "appInventory.applicationsBookmark"
    
    // MARK: - Initialization
    
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.inventoryProvider = InventoryProvider()
        self.organizationStore = OrganizationStore(defaults: defaults)
        self.cacheStore = CacheStore(defaults: defaults)
        
        loadOrganizationData()
        checkAuthorization()
    }
    
    // MARK: - Public Methods
    
    /// Load the app list (Baseline: Spotlight + FS Fallback).
    public func loadApps() async {
        state = .loadingBaseline
        
        let fetchedApps = await inventoryProvider.fetchApps()
        
        if fetchedApps.isEmpty {
            state = .baselineUnavailableOrEmpty
        } else {
            apps = fetchedApps
            state = isAuthorized ? .authorizedReady : .baselineReady
        }
    }
    
    /// Authorizes access to /Applications and stores bookmark.
    public func authorize(url: URL) -> Bool {
        // Validate path
        let standardized = url.standardizedFileURL.path
        guard standardized == "/Applications" else {
            return false
        }
        
        // Create and store bookmark
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmarkData, forKey: bookmarkKey)
            isAuthorized = true
            if !apps.isEmpty {
                state = .authorizedReady
            }
            return true
        } catch {
            return false
        }
    }
    
    /// Start deep scanning all apps.
    public func startDeepScan() async {
        guard let directoryURL = resolveBookmark() else { return }
        
        do {
            _ = directoryURL.startAccessingSecurityScopedResource()
            defer { directoryURL.stopAccessingSecurityScopedResource() }
            
            // If apps is empty (Spotlight failed), list apps from directory first
            if apps.isEmpty {
                let fm = FileManager.default
                guard let contents = try? fm.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.contentModificationDateKey, .localizedNameKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    state = .error("Failed to list /Applications directory")
                    return
                }
                
                apps = contents.compactMap { url -> AppItem? in
                    guard url.pathExtension == "app" else { return nil }
                    
                    let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                        ?? url.deletingPathExtension().lastPathComponent
                    let contentModified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let bundle = Bundle(url: url)
                    let bundleID = bundle?.bundleIdentifier
                    let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
                    
                    let id = bundleID ?? url.path
                    
                    return AppItem(
                        id: id,
                        url: url,
                        displayName: displayName,
                        version: version,
                        estimatedSizeBytes: nil,
                        lastUsedDate: nil,
                        contentModifiedDate: contentModified,
                        source: .filesystem
                    )
                }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            
            deepScanner = DeepScanner(cacheStore: cacheStore)
            state = .deepScanning(current: 0, total: apps.count)
            
            // Use scanApps with the existing apps array for ID consistency
            let sizes = try await deepScanner?.scanApps(apps) { [weak self] current, total in
                Task { @MainActor in
                    self?.state = .deepScanning(current: current, total: total)
                }
            }
            
            // Update apps with accurate sizes
            if let sizes = sizes {
                for (index, app) in apps.enumerated() {
                    if let size = sizes[app.id] {
                        apps[index].accurateSizeBytes = size
                    }
                }
            }
            
            state = .authorizedReady
        } catch {
            state = .error("Deep scan failed: \(error.localizedDescription)")
        }
    }
    
    /// Cancel ongoing deep scan.
    public func cancelDeepScan() async {
        await deepScanner?.cancel()
        state = .authorizedReady
    }
    
    // MARK: - Organization
    
    public func addCategory(name: String) {
        let newCategory = AppCategory(name: name, order: categories.count)
        categories.append(newCategory)
        organizationStore.saveCategories(categories)
    }
    
    public func renameCategory(_ id: UUID, to name: String) {
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = name
            organizationStore.saveCategories(categories)
        }
    }
    
    public func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        // Normalize order values
        for (index, _) in categories.enumerated() {
            categories[index].order = index
        }
        organizationStore.saveCategories(categories)
        organizationStore.saveAssignments(assignments)
    }
    
    public func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        // Update order values
        for (index, _) in categories.enumerated() {
            categories[index].order = index
        }
        organizationStore.saveCategories(categories)
    }
    
    public func assignApp(_ appID: String, to categoryID: UUID?) {
        if let categoryID = categoryID {
            assignments[appID] = categoryID
        } else {
            assignments.removeValue(forKey: appID)
        }
        organizationStore.saveAssignments(assignments)
    }
    
    // MARK: - Data Availability
    
    /// Returns true if any apps have lastUsedDate, meaning Unused filter can work.
    public var hasLastUsedData: Bool {
        apps.contains { $0.lastUsedDate != nil }
    }
    
    // MARK: - Filtering
    
    public var filteredApps: [AppItem] {
        var result = apps
        
        // Apply search
        if !searchText.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply smart filter
        switch selectedFilter {
        case .all:
            break
        case .large:
            result = SmartFilters.largeApps(result)
        case .unused:
            result = SmartFilters.unusedApps(result)
        case .recentlyUpdated:
            result = SmartFilters.recentlyUpdated(result)
        case .uncategorized:
            result = SmartFilters.uncategorized(result, assignments: assignments)
        }
        
        return result
    }
    
    // MARK: - Private Helpers
    
    private func loadOrganizationData() {
        categories = organizationStore.loadCategories()
        assignments = organizationStore.loadAssignments()
    }
    
    private func checkAuthorization() {
        isAuthorized = resolveBookmark() != nil
    }
    
    private func resolveBookmark() -> URL? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else { return nil }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark is stale, user needs to re-authorize
                isAuthorized = false
                return nil
            }
            
            return url
        } catch {
            isAuthorized = false
            return nil
        }
    }
}
