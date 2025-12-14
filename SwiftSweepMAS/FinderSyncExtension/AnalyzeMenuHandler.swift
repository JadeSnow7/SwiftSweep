import Foundation

/// Handles analysis operations triggered from Finder menu
actor AnalyzeMenuHandler {
    static let shared = AnalyzeMenuHandler()
    
    private init() {}
    
    /// Analyze folder size and show quick result
    func analyzeFolderSize(url: URL) async {
        do {
            let summary = try await performQuickAnalysis(url: url)
            await ResultPresenter.showResult(summary, for: url.path)
        } catch {
            NSLog("SwiftSweep: Analysis failed - \(error.localizedDescription)")
            ResultPresenter.openInHostApp(path: url.path)
        }
    }
    
    /// Show largest items in folder
    func showLargestItems(url: URL) async {
        // For this action, always open Host App for detailed view
        ResultPresenter.openInHostApp(path: url.path)
    }
    
    // MARK: - Private
    
    private func performQuickAnalysis(url: URL) async throws -> AnalyzerEngine.QuickSummary {
        // Step 1: Try direct access first (common case for registered directories)
        if FileManager.default.isReadableFile(atPath: url.path) {
            return try await AnalyzerEngine.shared.quickSummary(path: url.path)
        }
        
        // Step 2: Try security-scoped access
        guard let bookmarkData = BookmarkManager.shared.getBookmark(for: url) else {
            throw AnalyzerError.accessDenied("Directory not authorized")
        }
        
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        )
        
        // Start access only when actually analyzing
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            throw AnalyzerError.accessDenied("Cannot access directory")
        }
        
        // ALWAYS stop when done
        defer { resolvedURL.stopAccessingSecurityScopedResource() }
        
        return try await AnalyzerEngine.shared.quickSummary(path: resolvedURL.path)
    }
}
