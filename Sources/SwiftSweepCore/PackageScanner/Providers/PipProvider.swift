import Foundation

/// Provider for pip (Python) packages
public struct PipProvider: PackageProvider, Sendable {
    public let id = "pip"
    public let displayName = "pip (Python)"
    public let iconName = "cube.box.fill"
    
    private let runner: ProcessRunner
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    public func scan() async -> PackageScanResult {
        let start = Date()
        
        // Find python3 executable
        guard let pythonURL = ToolLocator.find("python3") else {
            return .notInstalled(providerID: id, displayName: displayName)
        }
        
        // Run: python3 -m pip list --format=json
        let result = await runner.run(
            executable: pythonURL.path,
            arguments: ["-m", "pip", "list", "--format=json"],
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
        
        // Parse JSON output
        guard let jsonData = result.stdout.isEmpty ? nil : result.stdout else {
            return PackageScanResult(
                providerID: id,
                displayName: displayName,
                status: .ok,
                packages: [],
                scanDuration: duration
            )
        }
        
        do {
            let packages = try parsePipJson(jsonData)
            return PackageScanResult(
                providerID: id,
                displayName: displayName,
                status: .ok,
                packages: packages,
                scanDuration: duration
            )
        } catch {
            return .failed(
                providerID: id,
                displayName: displayName,
                error: "Failed to parse pip output: \(error.localizedDescription)"
            )
        }
    }
    
    /// Parse pip list --format=json output
    /// Format: [{"name": "package", "version": "1.0.0"}, ...]
    private func parsePipJson(_ data: Data) throws -> [Package] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return array.compactMap { dict -> Package? in
            guard let name = dict["name"] as? String,
                  let version = dict["version"] as? String else {
                return nil
            }
            return Package(name: name, version: version, providerID: id)
        }
    }
}
