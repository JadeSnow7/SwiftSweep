import Foundation

/// Provider for npm global packages
public struct NpmProvider: PackageProvider, Sendable {
    public let id = "npm"
    public let displayName = "npm Global"
    public let iconName = "shippingbox.fill"
    
    private let runner: ProcessRunner
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    public func scan() async -> PackageScanResult {
        let start = Date()
        
        // Find npm executable
        guard let npmURL = ToolLocator.find("npm") else {
            return .notInstalled(providerID: id, displayName: displayName)
        }
        
        // Run: npm ls -g --depth=0 --json
        let result = await runner.run(
            executable: npmURL.path,
            arguments: ["ls", "-g", "--depth=0", "--json"],
            environment: ToolLocator.packageFinderEnvironment
        )
        
        let duration = Date().timeIntervalSince(start)
        
        // npm may return non-zero exit code but still have valid JSON output
        // (e.g., when there are peer dependency warnings)
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
        
        // Try to parse JSON even if exit code is non-zero
        guard let jsonData = stdout.data(using: .utf8) else {
            return .failed(providerID: id, displayName: displayName, error: "No output from npm")
        }
        
        do {
            let packages = try parseNpmJson(jsonData)
            
            // Success - add warning if there was stderr or non-zero exit
            var warning: String? = nil
            if result.exitCode != 0 && !stderr.isEmpty {
                warning = "npm reported warnings: \(stderr.prefix(200))"
            }
            
            return PackageScanResult(
                providerID: id,
                displayName: displayName,
                status: .ok,
                packages: packages,
                scanDuration: duration,
                warning: warning
            )
        } catch {
            // JSON parsing failed - this is a real error
            return .failed(
                providerID: id,
                displayName: displayName,
                error: "Failed to parse npm output: \(error.localizedDescription)"
            )
        }
    }
    
    /// Parse npm ls --json output
    /// Format: {"dependencies": {"package-name": {"version": "1.0.0"}, ...}}
    private func parseNpmJson(_ data: Data) throws -> [Package] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: Any] else {
            return []
        }
        
        return dependencies.compactMap { (name, value) -> Package? in
            guard let info = value as? [String: Any],
                  let version = info["version"] as? String else {
                return nil
            }
            return Package(name: name, version: version, providerID: id)
        }
    }
}
