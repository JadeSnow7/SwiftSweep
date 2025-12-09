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
                
                Button(action: { Task { await viewModel.analyze(path: targetPath) }}) {
                    Label("Analyze", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)
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
                        .padding(.top)
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
    
    func analyze(path: String) async {
        isAnalyzing = true
        scannedFiles = 0
        topFiles = []
        totalSize = 0
        fileCount = 0
        dirCount = 0
        
        let fileManager = FileManager.default
        var allFiles: [(path: String, size: Int64)] = []
        
        if let enumerator = fileManager.enumerator(atPath: path) {
            for case let file as String in enumerator {
                let fullPath = path + "/" + file
                
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        dirCount += 1
                    } else {
                        fileCount += 1
                        scannedFiles += 1
                        
                        if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                            let size = attrs[.size] as? Int64 ?? 0
                            totalSize += size
                            allFiles.append((fullPath, size))
                        }
                    }
                }
            }
        }
        
        topFiles = Array(allFiles.sorted { $0.size > $1.size }.prefix(20))
        isAnalyzing = false
    }
}
