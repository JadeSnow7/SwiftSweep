import SwiftUI

struct AnalysisResultView: View {
    let path: String
    
    @State private var result: AnalyzerEngine.AnalysisResult?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var progress: (count: Int, size: Int64) = (0, 0)
    
    var body: some View {
        VStack {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing...")
                        .font(.headline)
                    Text("\(progress.count) items scanned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Analysis Failed")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .foregroundColor(.secondary)
                }
            } else if let result = result {
                ResultContentView(result: result, path: path)
            }
        }
        .padding()
        .navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
        .task {
            await performAnalysis()
        }
    }
    
    private func performAnalysis() async {
        isLoading = true
        error = nil
        
        do {
            // Try direct access first
            if FileManager.default.isReadableFile(atPath: path) {
                result = try await AnalyzerEngine.shared.analyze(path: path) { count, size in
                    progress = (count, size)
                }
            } else {
                // Need security-scoped access
                guard let bookmarkData = BookmarkManager.shared.getBookmark(for: URL(fileURLWithPath: path)) else {
                    throw AnalyzerError.accessDenied("Please authorize this directory first.")
                }
                
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    bookmarkDataIsStale: &isStale
                )
                
                guard url.startAccessingSecurityScopedResource() else {
                    throw AnalyzerError.accessDenied("Cannot access this directory.")
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                result = try await AnalyzerEngine.shared.analyze(path: url.path) { count, size in
                    progress = (count, size)
                }
            }
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

struct ResultContentView: View {
    let result: AnalyzerEngine.AnalysisResult
    let path: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary card
                HStack(spacing: 32) {
                    StatCard(title: "Total Size", value: SizeFormatter.shared.format(result.totalSize), icon: "externaldrive")
                    StatCard(title: "Files", value: "\(result.fileCount)", icon: "doc")
                    StatCard(title: "Folders", value: "\(result.dirCount)", icon: "folder")
                }
                
                // Partial result warning
                if result.wasLimited {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Result may be partial due to size limits.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                if let rootNode = result.rootNode,
                   let children = rootNode.children,
                   !children.isEmpty {
                    GroupBox("Folder Tree") {
                        FileTreeView(nodes: children, totalSize: rootNode.size)
                    }
                }
                
                // Largest files
                GroupBox("Largest Files") {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(result.topFiles.prefix(10)) { file in
                            HStack {
                                Image(systemName: iconForFile(file.path))
                                    .foregroundColor(.secondary)
                                
                                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(SizeFormatter.shared.format(file.size))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func iconForFile(_ path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "app": return "app"
        case "dmg", "iso": return "opticaldisc"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "m4a": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

struct FileTreeView: View {
    let nodes: [FileNode]
    let totalSize: Int64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                FileTreeNodeView(node: node, totalSize: totalSize, depth: 0)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FileTreeNodeView: View {
    let node: FileNode
    let totalSize: Int64
    let depth: Int
    
    @State private var isExpanded = false
    
    var body: some View {
        if node.isDirectory,
           let children = node.children,
           !children.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(children) { child in
                        FileTreeNodeView(node: child, totalSize: totalSize, depth: depth + 1)
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 4)
            } label: {
                FileTreeRow(node: node, totalSize: totalSize)
            }
            .padding(.leading, CGFloat(depth) * 12)
        } else {
            FileTreeRow(node: node, totalSize: totalSize)
                .padding(.leading, CGFloat(depth) * 12)
        }
    }
}

struct FileTreeRow: View {
    let node: FileNode
    let totalSize: Int64
    
    private var percent: Double {
        guard totalSize > 0 else { return 0 }
        return Double(node.size) / Double(totalSize)
    }
    
    private var percentString: String {
        String(format: "%.1f%%", percent * 100)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(node.isDirectory ? .blue : .secondary)
                .frame(width: 16)
            
            Text(node.name)
                .lineLimit(1)
            
            Spacer()
            
            ProgressView(value: percent)
                .frame(width: 80)
            
            Text(SizeFormatter.shared.format(node.size))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)
            
            Text(percentString)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}
