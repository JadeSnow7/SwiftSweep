import Foundation

/// Scans all package managers concurrently
public actor PackageScanner {
    public static let shared = PackageScanner()
    
    /// Order of providers (used to maintain stable UI ordering)
    private let providerOrder: [String]
    
    /// All registered providers
    private let providers: [any PackageProvider]
    
    public init(providers: [any PackageProvider]? = nil) {
        let defaultProviders: [any PackageProvider] = [
            HomebrewFormulaProvider(),
            HomebrewCaskProvider(),
            NpmProvider(),
            PipProvider(),
            GemProvider()
        ]
        
        self.providers = providers ?? defaultProviders
        self.providerOrder = self.providers.map { $0.id }
    }
    
    /// Scan all providers concurrently
    /// Results are returned in the original provider order for stable UI
    public func scanAll() async -> [PackageScanResult] {
        // Use TaskGroup for concurrent scanning
        let results = await withTaskGroup(of: PackageScanResult.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.scan()
                }
            }
            
            // Collect all results
            var collected: [PackageScanResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        
        // Sort by original provider order for stable UI
        return results.sorted { lhs, rhs in
            let lhsIndex = providerOrder.firstIndex(of: lhs.providerID) ?? Int.max
            let rhsIndex = providerOrder.firstIndex(of: rhs.providerID) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }
    
    /// Scan a single provider by ID
    public func scan(providerID: String) async -> PackageScanResult? {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return nil
        }
        return await provider.scan()
    }
    
    /// Get list of available provider IDs
    public func availableProviderIDs() -> [String] {
        providerOrder
    }
}
