import Foundation

/// Provider for Homebrew formula packages
public struct HomebrewFormulaProvider: PackageProvider, Sendable {
    public let id = "homebrew_formula"
    public let displayName = "Homebrew Formulae"
    public let iconName = "mug.fill"
    
    private let runner: ProcessRunner
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    public func scan() async -> PackageScanResult {
        let start = Date()
        
        // Find brew executable
        guard let brewURL = ToolLocator.find("brew") else {
            return .notInstalled(providerID: id, displayName: displayName)
        }
        
        // Run: brew list --formula --versions
        let result = await runner.run(
            executable: brewURL.path,
            arguments: ["list", "--formula", "--versions"],
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
        
        // Parse output: each line is "name version [version...]"
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let packages = parseBrewOutput(stdout)
        
        return PackageScanResult(
            providerID: id,
            displayName: displayName,
            status: .ok,
            packages: packages,
            scanDuration: duration
        )
    }
    
    /// Parse brew list --versions output
    /// Format: "name version [version...]" (one per line)
    private func parseBrewOutput(_ output: String) -> [Package] {
        output
            .split(separator: "\n")
            .compactMap { line -> Package? in
                let parts = line.split(separator: " ")
                guard parts.count >= 2 else { return nil }
                let name = String(parts[0])
                // Take the first (latest) version
                let version = String(parts[1])
                return Package(name: name, version: version, providerID: id)
            }
    }
}

/// Provider for Homebrew cask packages
public struct HomebrewCaskProvider: PackageProvider, Sendable {
    public let id = "homebrew_cask"
    public let displayName = "Homebrew Casks"
    public let iconName = "macwindow"
    
    private let runner: ProcessRunner
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    public func scan() async -> PackageScanResult {
        let start = Date()
        
        // Find brew executable
        guard let brewURL = ToolLocator.find("brew") else {
            return .notInstalled(providerID: id, displayName: displayName)
        }
        
        // Run: brew list --cask --versions
        let result = await runner.run(
            executable: brewURL.path,
            arguments: ["list", "--cask", "--versions"],
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
        
        // Parse output: each line is "name version"
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let packages = parseBrewCaskOutput(stdout)
        
        return PackageScanResult(
            providerID: id,
            displayName: displayName,
            status: .ok,
            packages: packages,
            scanDuration: duration
        )
    }
    
    private func parseBrewCaskOutput(_ output: String) -> [Package] {
        output
            .split(separator: "\n")
            .compactMap { line -> Package? in
                let parts = line.split(separator: " ")
                guard parts.count >= 2 else { return nil }
                let name = String(parts[0])
                let version = String(parts[1])
                return Package(name: name, version: version, providerID: id)
            }
    }
}
