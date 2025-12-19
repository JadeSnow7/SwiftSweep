import Foundation

// MARK: - GitRepoScanner

/// Scans directories for Git repositories
public actor GitRepoScanner {
    public static let shared = GitRepoScanner()
    
    private let runner: ProcessRunner
    private let fileManager = FileManager.default
    
    /// Default directories to scan
    public static let defaultScanRoots: [String] = [
        "Developer",
        "Projects",
        "Code",
        "Dev",
        "Workspace",
        "repos"
    ]
    
    /// Maximum depth to traverse
    public static let defaultMaxDepth = 4
    
    /// Concurrency limit for status checks
    private let statusConcurrencyLimit = 6
    
    public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
        self.runner = runner
    }
    
    // MARK: - Public API
    
    /// Scan for Git repositories in default directories
    public func scan() async -> GitRepoScanResult {
        let home = NSHomeDirectory()
        let roots = Self.defaultScanRoots.map { home + "/" + $0 }
        return await scan(roots: roots, maxDepth: Self.defaultMaxDepth)
    }
    
    /// Scan for Git repositories in specified directories
    public func scan(roots: [String], maxDepth: Int) async -> GitRepoScanResult {
        let start = Date()
        var repos: [GitRepo] = []
        var scannedPaths: [String] = []
        
        for root in roots {
            guard fileManager.fileExists(atPath: root) else { continue }
            scannedPaths.append(root)
            
            let found = await scanDirectory(root, currentDepth: 0, maxDepth: maxDepth)
            repos.append(contentsOf: found)
        }
        
        let duration = Date().timeIntervalSince(start)
        return GitRepoScanResult(repos: repos, scanDuration: duration, scannedPaths: scannedPaths)
    }
    
    /// Get status for a single repository (dirty/clean)
    public func getStatus(for repo: GitRepo) async -> Bool? {
        guard let gitURL = findGit() else { return nil }
        
        // git -C <path> status --porcelain=v1 -uno
        let result = await runner.run(
            executable: gitURL.path,
            arguments: ["-C", repo.path, "status", "--porcelain=v1", "-uno"],
            environment: ToolLocator.packageFinderEnvironment
        )
        
        guard result.reason == .exit, result.exitCode == 0 else { return nil }
        
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Get status for multiple repos with concurrency limit
    public func getStatuses(for repos: [GitRepo]) async -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        await withTaskGroup(of: (String, Bool?).self) { group in
            var pending = 0
            var index = 0
            
            while index < repos.count || pending > 0 {
                // Add tasks up to limit
                while pending < statusConcurrencyLimit && index < repos.count {
                    let repo = repos[index]
                    group.addTask {
                        let isDirty = await self.getStatus(for: repo)
                        return (repo.id, isDirty)
                    }
                    pending += 1
                    index += 1
                }
                
                // Wait for one to complete
                if let (id, isDirty) = await group.next() {
                    if let dirty = isDirty {
                        results[id] = dirty
                    }
                    pending -= 1
                }
            }
        }
        
        return results
    }
    
    // MARK: - Private
    
    private func scanDirectory(_ path: String, currentDepth: Int, maxDepth: Int) async -> [GitRepo] {
        guard currentDepth < maxDepth else { return [] }
        
        var repos: [GitRepo] = []
        
        // Check if this directory is a git repo
        let gitPath = path + "/.git"
        if fileManager.fileExists(atPath: gitPath) {
            // Found a repo - resolve gitDir and stop recursion here
            let gitDir = await resolveGitDir(repoPath: path, gitPath: gitPath)
            let name = URL(fileURLWithPath: path).lastPathComponent
            let repo = GitRepo(name: name, path: path, gitDir: gitDir)
            return [repo]  // Don't recurse into git repos
        }
        
        // Not a repo - scan children
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }
        
        for item in contents {
            // Skip hidden directories (except we already check .git above)
            if item.hasPrefix(".") { continue }
            
            let itemPath = path + "/" + item
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            // Recurse
            let found = await scanDirectory(itemPath, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            repos.append(contentsOf: found)
        }
        
        return repos
    }
    
    /// Resolve the actual .git directory (handles worktrees and submodules)
    private func resolveGitDir(repoPath: String, gitPath: String) async -> String {
        var isDir: ObjCBool = false
        
        // Check if .git is a directory or file
        if fileManager.fileExists(atPath: gitPath, isDirectory: &isDir) {
            if isDir.boolValue {
                // Normal repo - .git is the directory
                return gitPath
            } else {
                // Worktree/submodule - .git is a file containing "gitdir: <path>"
                if let content = try? String(contentsOfFile: gitPath, encoding: .utf8) {
                    let lines = content.split(separator: "\n")
                    for line in lines {
                        let lineStr = String(line).trimmingCharacters(in: .whitespaces)
                        if lineStr.hasPrefix("gitdir:") {
                            var gitdir = String(lineStr.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            // Handle relative paths
                            if !gitdir.hasPrefix("/") {
                                gitdir = repoPath + "/" + gitdir
                            }
                            // Normalize
                            return URL(fileURLWithPath: gitdir).standardized.path
                        }
                    }
                }
            }
        }
        
        // Fallback: use git rev-parse
        if let gitURL = findGit() {
            let result = await runner.run(
                executable: gitURL.path,
                arguments: ["-C", repoPath, "rev-parse", "--git-dir"],
                environment: ToolLocator.packageFinderEnvironment
            )
            
            if result.reason == .exit, result.exitCode == 0 {
                let output = String(data: result.stdout, encoding: .utf8) ?? ""
                var resolvedPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !resolvedPath.hasPrefix("/") {
                    resolvedPath = repoPath + "/" + resolvedPath
                }
                return URL(fileURLWithPath: resolvedPath).standardized.path
            }
        }
        
        return gitPath
    }
    
    private func findGit() -> URL? {
        ToolLocator.find("git")
    }
}
