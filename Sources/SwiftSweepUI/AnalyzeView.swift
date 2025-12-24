import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct AnalyzeView: View {
  @StateObject private var viewModel = AnalyzeViewModel()
  @State private var targetPath: String = NSHomeDirectory()
  @State private var viewMode: ViewMode = .treemap
  @State private var showLocalSizeOnly: Bool = false  // 是否仅显示本地文件体积
  @AppStorage("showHiddenFiles") private var showHiddenFiles = false

  enum ViewMode: String, CaseIterable {
    case treemap = "Treemap"
    case tree = "Tree"
    case files = "Largest Files"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        VStack(alignment: .leading) {
          Text("Disk Analyzer")
            .font(.largeTitle)
            .fontWeight(.bold)
          Text("Visualize disk usage like WizTree")
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
          Button(action: {
            viewModel.analyze(path: targetPath, includeHiddenFiles: showHiddenFiles)
          }) {
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
          Text("Scanning \(viewModel.scannedFiles) items...")
            .foregroundColor(.secondary)
          Text("\(formatBytes(viewModel.totalSize)) found")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else if let rootNode = viewModel.rootNode {
        // View mode picker and options
        HStack {
          Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
              Text(mode.rawValue).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 300)

          // iCloud size toggle (only show if there are cloud-only files)
          if rootNode.cloudOnlyCount > 0 {
            Toggle(isOn: $showLocalSizeOnly) {
              Label("Local Only", systemImage: "internaldrive")
            }
            .toggleStyle(.button)
            .controlSize(.small)
          }

          Spacer()

          // Summary stats
          HStack(spacing: 16) {
            // 根据切换显示本地体积或总体积
            if showLocalSizeOnly {
              Label("\(formatBytes(rootNode.localSize))", systemImage: "internaldrive.fill")
                .foregroundColor(.primary)
            } else {
              Label("\(formatBytes(viewModel.totalSize))", systemImage: "internaldrive.fill")
            }

            Label("\(viewModel.fileCount) files", systemImage: "doc.fill")
            Label("\(viewModel.dirCount) folders", systemImage: "folder.fill")

            // 显示云端文件数量
            if rootNode.cloudOnlyCount > 0 {
              Label("\(rootNode.cloudOnlyCount) in iCloud", systemImage: "icloud")
                .foregroundColor(.blue)
            }
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        // Content based on view mode
        switch viewMode {
        case .treemap:
          TreemapView(rootNode: rootNode)
        case .tree:
          FileTreeView(rootNode: rootNode, showLocalSizeOnly: showLocalSizeOnly)
        case .files:
          LargestFilesView(files: viewModel.topFiles, basePath: targetPath)
        }
      } else {
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
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Largest Files View (Original functionality)

struct LargestFilesView: View {
  let files: [(path: String, size: Int64)]
  let basePath: String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(files.enumerated()), id: \.offset) { index, file in
          LargeFileRow(index: index + 1, path: file.path, size: file.size, basePath: basePath)
        }
      }
      .padding()
    }
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
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - ViewModel

@MainActor
class AnalyzeViewModel: ObservableObject {
  @Published var topFiles: [(path: String, size: Int64)] = []
  @Published var totalSize: Int64 = 0
  @Published var fileCount: Int = 0
  @Published var dirCount: Int = 0
  @Published var scannedFiles: Int = 0
  @Published var isAnalyzing = false
  @Published var rootNode: FileNode?

  private var analyzeTask: Task<Void, Never>?
  private let engine = AnalyzerEngine.shared

  func analyze(path: String, includeHiddenFiles: Bool = false) {
    analyzeTask?.cancel()

    isAnalyzing = true
    scannedFiles = 0
    topFiles = []
    totalSize = 0
    fileCount = 0
    dirCount = 0
    rootNode = nil

    analyzeTask = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self = self else { return }

      let result = try? await self.engine.analyze(
        path: path, includeHiddenFiles: includeHiddenFiles
      ) { scanned, size in
        Task { @MainActor in
          self.scannedFiles = scanned
          self.totalSize = size
        }
      }

      if let result = result {
        await MainActor.run {
          self.topFiles = result.topFiles.map { ($0.path, $0.size) }
          self.totalSize = result.totalSize
          self.fileCount = result.fileCount
          self.dirCount = result.dirCount
          self.rootNode = result.rootNode
          self.isAnalyzing = false
        }
      } else {
        await MainActor.run {
          self.isAnalyzing = false
        }
      }
    }
  }

  func cancel() {
    analyzeTask?.cancel()
    isAnalyzing = false
  }
}
