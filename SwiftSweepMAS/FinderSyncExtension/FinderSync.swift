import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    
    private var lastKnownVersion: Int = 0
    private var lastReloadTime: Date = .distantPast
    private let minReloadInterval: TimeInterval = 1.0  // Debounce: 1 second
    
    override init() {
        super.init()
        
        // Initial load
        reloadIfVersionChanged()
        
        // Listen for distributed notification (accelerator)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onDirectoriesNotification),
            name: NSNotification.Name(DirectorySyncConstants.syncNotificationName),
            object: nil
        )
        
        NSLog("SwiftSweep FinderSync initialized")
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: - Menu
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Debounced version check on every menu request
        reloadIfVersionChanged()
        
        let menu = NSMenu(title: "SwiftSweep")
        
        let analyzeItem = NSMenuItem(
            title: "Analyze Folder Size",
            action: #selector(analyzeFolderSize(_:)),
            keyEquivalent: ""
        )
        analyzeItem.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: nil)
        menu.addItem(analyzeItem)
        
        let largestItem = NSMenuItem(
            title: "Show Largest Items",
            action: #selector(showLargestItems(_:)),
            keyEquivalent: ""
        )
        largestItem.image = NSImage(systemSymbolName: "list.number", accessibilityDescription: nil)
        menu.addItem(largestItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let openItem = NSMenuItem(
            title: "Open in SwiftSweep",
            action: #selector(openInSwiftSweep(_:)),
            keyEquivalent: ""
        )
        openItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
        menu.addItem(openItem)
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc func analyzeFolderSize(_ sender: AnyObject?) {
        guard let targetURLs = FIFinderSyncController.default().selectedItemURLs(),
              let url = targetURLs.first else { return }
        
        Task {
            await AnalyzeMenuHandler.shared.analyzeFolderSize(url: url)
        }
    }
    
    @objc func showLargestItems(_ sender: AnyObject?) {
        guard let targetURLs = FIFinderSyncController.default().selectedItemURLs(),
              let url = targetURLs.first else { return }
        
        Task {
            await AnalyzeMenuHandler.shared.showLargestItems(url: url)
        }
    }
    
    @objc func openInSwiftSweep(_ sender: AnyObject?) {
        guard let targetURLs = FIFinderSyncController.default().selectedItemURLs(),
              let url = targetURLs.first else { return }
        
        ResultPresenter.openInHostApp(path: url.path)
    }
    
    // MARK: - Sync Logic
    
    @objc private func onDirectoriesNotification() {
        // Notification triggers version check, not direct reload
        reloadIfVersionChanged()
    }
    
    private func reloadIfVersionChanged() {
        // Debounce: skip if called too recently
        guard Date().timeIntervalSince(lastReloadTime) >= minReloadInterval else { return }
        
        let currentVersion = DirectorySyncConstants.userDefaults.integer(forKey: DirectorySyncConstants.versionKey)
        
        // Only reload if version actually changed
        guard currentVersion != lastKnownVersion else { return }
        
        lastKnownVersion = currentVersion
        lastReloadTime = Date()
        
        let urls = BookmarkManager.shared.resolveAuthorizedDirectories()
        FIFinderSyncController.default().directoryURLs = Set(urls)
        
        NSLog("SwiftSweep: Reloaded \(urls.count) authorized directories (version \(currentVersion))")
    }
}
