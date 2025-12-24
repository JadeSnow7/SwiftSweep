import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

/// Hierarchical tree view for disk analysis - shows folders and files in an outline
struct FileTreeView: View {
  let rootNode: FileNode
  @State private var expandedNodes: Set<UUID> = []
  @State private var selectedNode: FileNode?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        FileTreeRow(
          node: rootNode,
          depth: 0,
          expandedNodes: $expandedNodes,
          selectedNode: $selectedNode,
          parentSize: rootNode.size
        )
      }
      .padding()
    }
  }
}

struct FileTreeRow: View {
  let node: FileNode
  let depth: Int
  @Binding var expandedNodes: Set<UUID>
  @Binding var selectedNode: FileNode?
  let parentSize: Int64

  private var isExpanded: Bool {
    expandedNodes.contains(node.id)
  }

  private var percentage: Double {
    guard parentSize > 0 else { return 0 }
    return Double(node.size) / Double(parentSize) * 100
  }

  private var barWidth: CGFloat {
    CGFloat(min(percentage, 100)) * 2  // Max 200pt wide
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Row content
      HStack(spacing: 8) {
        // Indentation
        ForEach(0..<depth, id: \.self) { _ in
          Rectangle()
            .fill(Color.clear)
            .frame(width: 20)
        }

        // Expand/collapse button for directories
        if node.isDirectory {
          Button(action: { toggleExpand() }) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption)
              .foregroundColor(.secondary)
              .frame(width: 16)
          }
          .buttonStyle(.plain)
        } else {
          Rectangle()
            .fill(Color.clear)
            .frame(width: 16)
        }

        // Icon
        Image(systemName: iconForNode(node))
          .foregroundColor(colorForNode(node))
          .frame(width: 16)

        // iCloud status indicator
        if node.iCloudStatus != .local {
          Image(systemName: iCloudIconForStatus(node.iCloudStatus))
            .font(.caption2)
            .foregroundColor(iCloudColorForStatus(node.iCloudStatus))
            .frame(width: 12)
        }

        // Name
        Text(node.name)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundColor(node.iCloudStatus == .cloudOnly ? .secondary : .primary)

        Spacer()

        // Size bar
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 200, height: 16)
            .cornerRadius(2)

          Rectangle()
            .fill(colorForNode(node).opacity(0.6))
            .frame(width: max(2, barWidth), height: 16)
            .cornerRadius(2)
        }

        // Size text
        Text(formatBytes(node.size))
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 70, alignment: .trailing)

        // Percentage
        Text(String(format: "%5.1f%%", percentage))
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 55, alignment: .trailing)

        // Item counts for directories
        if node.isDirectory {
          Text("\(node.fileCount) files")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 70, alignment: .trailing)
        }

        // Reveal in Finder button
        Button(action: { revealInFinder() }) {
          Image(systemName: "folder.badge.gearshape")
            .font(.caption)
        }
        .buttonStyle(.borderless)
      }
      .padding(.vertical, 4)
      .padding(.horizontal, 8)
      .background(
        selectedNode?.id == node.id
          ? Color.accentColor.opacity(0.2)
          : Color.clear
      )
      .contentShape(Rectangle())
      .onTapGesture {
        selectedNode = node
        if node.isDirectory {
          toggleExpand()
        }
      }

      // Children (if expanded) - rely on Core pre-sorted order
      if isExpanded, let children = node.children {
        ForEach(children) { child in
          FileTreeRow(
            node: child,
            depth: depth + 1,
            expandedNodes: $expandedNodes,
            selectedNode: $selectedNode,
            parentSize: node.size
          )
        }
      }
    }
  }

  private func toggleExpand() {
    if isExpanded {
      expandedNodes.remove(node.id)
    } else {
      expandedNodes.insert(node.id)
    }
  }

  private func revealInFinder() {
    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
  }

  private func iconForNode(_ node: FileNode) -> String {
    if node.isDirectory {
      return isExpanded ? "folder.fill" : "folder"
    }
    let ext = (node.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "mov", "avi", "mkv": return "film"
    case "mp3", "wav", "m4a", "flac": return "music.note"
    case "jpg", "jpeg", "png", "gif", "heic": return "photo"
    case "dmg", "iso", "pkg": return "opticaldiscdrive"
    case "zip", "tar", "gz", "rar": return "doc.zipper"
    case "app": return "app"
    case "pdf": return "doc.richtext"
    default: return "doc"
    }
  }

  private func colorForNode(_ node: FileNode) -> Color {
    if node.isDirectory {
      return .blue
    }
    let ext = (node.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "mov", "avi", "mkv": return .purple
    case "mp3", "wav", "m4a", "flac": return .pink
    case "jpg", "jpeg", "png", "gif", "heic": return .orange
    case "dmg", "iso", "pkg": return .red
    case "zip", "tar", "gz", "rar": return .yellow
    case "app": return .green
    default: return .gray
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  private func iCloudIconForStatus(_ status: ICloudStatus) -> String {
    switch status {
    case .local:
      return ""
    case .downloaded:
      return "icloud.and.arrow.down"
    case .cloudOnly:
      return "icloud"
    case .downloading:
      return "icloud.and.arrow.down"
    }
  }

  private func iCloudColorForStatus(_ status: ICloudStatus) -> Color {
    switch status {
    case .local:
      return .clear
    case .downloaded:
      return .green
    case .cloudOnly:
      return .blue
    case .downloading:
      return .orange
    }
  }
}

#Preview {
  let root = FileNode(name: "Home", path: "/Users/test", isDirectory: true)
  let docs = FileNode(name: "Documents", path: "/Users/test/Documents", isDirectory: true)
  docs.addChild(
    FileNode(
      name: "file1.pdf", path: "/Users/test/Documents/file1.pdf", isDirectory: false,
      size: 5_000_000))
  docs.addChild(
    FileNode(
      name: "file2.docx", path: "/Users/test/Documents/file2.docx", isDirectory: false,
      size: 3_000_000))
  root.addChild(docs)
  root.addChild(
    FileNode(name: "movie.mp4", path: "/Users/test/movie.mp4", isDirectory: false, size: 10_000_000)
  )

  return FileTreeView(rootNode: root)
    .frame(width: 800, height: 400)
}
