import Foundation

/// Provider for Ruby gem packages
public struct GemProvider: PackageProvider, Sendable {
    public let id = "gem"
    public let displayName = "Ruby Gems"
    public let iconName = "diamond.fill"
    
    private let runner: ProcessRunner
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    public func scan() async -> PackageScanResult {
        let start = Date()
        
        // Find gem executable
        guard let gemURL = ToolLocator.find("gem") else {
            return .notInstalled(providerID: id, displayName: displayName)
        }
        
        // Run: gem list --local
        let result = await runner.run(
            executable: gemURL.path,
            arguments: ["list", "--local"],
            environment: ToolLocator.packageFinderEnvironment
        )
        
        let duration = Date().timeIntervalSince(start)
        
        // Check for errors
        guard result.reason == .exit, let exitCode = result.exitCode, exitCode == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            return .failed(
                providerID: id,
                displayName: displayName,
                error: stderr.isEmpty ? "Command failed with exit code \(result.exitCode ?? -1)" : stderr
            )
        }
        
        // Parse output
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let packages = parseGemOutput(stdout)
        
        return PackageScanResult(
            providerID: id,
            displayName: displayName,
            status: .ok,
            packages: packages,
            scanDuration: duration
        )
    }
    
    /// Parse gem list --local output
    /// Format: "gemname (v1, v2, ...)" - one per line, or "gemname (v1)"
    private func parseGemOutput(_ output: String) -> [Package] {
        output
            .split(separator: "\n")
            .compactMap { line -> Package? in
                // Match pattern: name (version, version, ...)
                // Example: "rake (13.0.6, 13.0.3)"
                let lineStr = String(line)
                guard let parenStart = lineStr.firstIndex(of: "("),
                      let parenEnd = lineStr.lastIndex(of: ")") else {
                    return nil
                }
                
                let name = String(lineStr[..<parenStart]).trimmingCharacters(in: .whitespaces)
                let versionsStr = String(lineStr[lineStr.index(after: parenStart)..<parenEnd])
                
                // Take the first (latest) version
                let versions = versionsStr.split(separator: ",").map { 
                    String($0).trimmingCharacters(in: .whitespaces) 
                }
                guard let firstVersion = versions.first, !name.isEmpty else {
                    return nil
                }
                
                return Package(name: name, version: firstVersion, providerID: id)
            }
    }
}
