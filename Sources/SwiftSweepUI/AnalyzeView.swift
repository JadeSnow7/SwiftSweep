import SwiftUI
import SwiftSweepCore

struct AnalyzeView: View {
    @StateObject private var viewModel = AnalyzeViewModel()
    @State private var targetPath: String = NSHomeDirectory()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Disk Analyzer")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Find large files and folders")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            
            // Path selector
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                TextField("Path to analyze", text: $targetPath)
                    .textFieldStyle(.plain)
                
                Button("Browse...") {
                    selectFolder()
                }
                .buttonStyle(.borderless)
                
                if viewModel.isAnalyzing {
                    Button(action: { viewModel.cancel() }) {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { viewModel.analyze(path: targetPath) }) {
                        Label("Analyze", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Divider()
                .padding(.top)
            
            if viewModel.isAnalyzing {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Analyzing \(viewModel.scannedFiles) files...")
                        .foregroundColor(.secondary)
                    Text("\(formatBytes(viewModel.totalSize)) scanned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.topFiles.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "chart.pie")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a folder and click Analyze")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Results
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary
                        HStack(spacing: 20) {
                            SummaryCard(title: "Total Size", value: formatBytes(viewModel.totalSize), icon: "internaldrive.fill", color: .blue)
                            SummaryCard(title: "Files", value: "\(viewModel.fileCount)", icon: "doc.fill", color: .green)
                            SummaryCard(title: "Folders", value: "\(viewModel.dirCount)", icon: "folder.fill", color: .orange)
                        }
                        .padding()
                        
                        // Top files
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Largest Files")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(Array(viewModel.topFiles.enumerated()), id: \.offset) { index, file in
                                LargeFileRow(index: index + 1, path: file.path, size: file.size, basePath: targetPath)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                targetPath = url.path
            }
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct LargeFileRow: View {
    let index: Int
    let path: String
    let size: Int64
    let basePath: String
    
    var relativePath: String {
        path.replacingOccurrences(of: basePath + "/", with: "")
    }
    
    var body: some View {
        HStack {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Image(systemName: iconForFile(path))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .fontWeight(.medium)
                Text(relativePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(formatBytes(size))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Button(action: { revealInFinder() }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
    
    func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg", "iso": return "opticaldiscdrive"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "app": return "app"
        default: return "doc"
        }
    }
    
    func revealInFinder() {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb > 1024 {
            return String(format: "%.2f GB", mb / 1024)
        } else if mb > 1 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
    }
}

@MainActor
class AnalyzeViewModel: ObservableObject {
    @Published var topFiles: [(path: String, size: Int64)] = []
    @Published var totalSize: Int64 = 0
    @Published var fileCount: Int = 0
    @Published var dirCount: Int = 0
    @Published var scannedFiles: Int = 0
    @Published var isAnalyzing = false
    @Published var currentPath: String = ""
    
    private var analyzeTask: Task<Void, Never>?
    
    // 跳过的系统目录 (避免权限问题和无限循环)
    private let skipDirs = [
        ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        "node_modules", ".git", "Library/Caches", ".npm", ".gradle"
    ]
    
    func analyze(path: String) {
        // 取消之前的任务
        analyzeTask?.cancel()
        
        isAnalyzing = true
        scannedFiles = 0
        topFiles = []
        totalSize = 0
        fileCount = 0
        dirCount = 0
        currentPath = path
        
        analyzeTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.performAnalysis(path: path)
        }
    }
    
    func cancel() {
        analyzeTask?.cancel()
        Task { @MainActor in
            isAnalyzing = false
        }
    }
    
    private func performAnalysis(path: String) async {
        let fileManager = FileManager.default
        var allFiles: [(path: String, size: Int64)] = []
        var localFileCount = 0
        var localDirCount = 0
        var localTotalSize: Int64 = 0
        var lastUIUpdate = Date()
        
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            await MainActor.run { self.isAnalyzing = false }
            return
        }
        
        // 使用 while 循环而非 for-in 以避免 Swift 6 警告
        while let fileURL = enumerator.nextObject() as? URL {
            // 检查取消
            if Task.isCancelled { break }
            
            // 跳过系统目录
            let pathStr = fileURL.path
            if skipDirs.contains(where: { pathStr.contains($0) }) {
                enumerator.skipDescendants()
                continue
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey])
                
                if resourceValues.isDirectory == true {
                    localDirCount += 1
                } else if resourceValues.isRegularFile == true {
                    localFileCount += 1
                    let size = Int64(resourceValues.fileSize ?? 0)
                    localTotalSize += size
                    
                    // 只保存大于1MB的文件用于排序
                    if size > 1_000_000 {
                        allFiles.append((pathStr, size))
                    }
                }
            } catch {
                continue
            }
            
            // 每0.3秒更新一次UI
            if Date().timeIntervalSince(lastUIUpdate) > 0.3 {
                lastUIUpdate = Date()
                let countSnapshot = localFileCount
                let dirSnapshot = localDirCount
                let sizeSnapshot = localTotalSize
                
                await MainActor.run {
                    self.scannedFiles = countSnapshot
                    self.fileCount = countSnapshot
                    self.dirCount = dirSnapshot
                    self.totalSize = sizeSnapshot
                }
            }
        }
        
        // 最终排序
        let sorted = allFiles.sorted { $0.size > $1.size }.prefix(20)
        
        await MainActor.run {
            self.topFiles = Array(sorted)
            self.fileCount = localFileCount
            self.dirCount = localDirCount
            self.totalSize = localTotalSize
            self.isAnalyzing = false
        }
    }
}

