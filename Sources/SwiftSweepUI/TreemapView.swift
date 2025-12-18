import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

/// Treemap visualization for disk usage - shows rectangles sized by file/folder size
struct TreemapView: View {
  let rootNode: FileNode
  @State private var currentNode: FileNode
  @State private var navigationPath: [FileNode] = []
  @State private var hoveredNode: FileNode?

  init(rootNode: FileNode) {
    self.rootNode = rootNode
    self._currentNode = State(initialValue: rootNode)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Breadcrumb navigation
      BreadcrumbBar(
        path: navigationPath,
        current: currentNode,
        onNavigate: { node in
          navigateTo(node)
        }
      )

      // Treemap content
      GeometryReader { geometry in
        if let children = currentNode.children, !children.isEmpty {
          TreemapLayout(
            nodes: children,
            totalSize: currentNode.size,
            frame: geometry.size,
            hoveredNode: $hoveredNode,
            onTap: { node in
              if node.isDirectory && node.children?.isEmpty == false {
                drillDown(to: node)
              }
            }
          )
        } else {
          VStack {
            Image(systemName: "folder")
              .font(.system(size: 48))
              .foregroundColor(.secondary)
            Text("Empty folder")
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }

      // Info bar
      if let hovered = hoveredNode {
        HStack {
          Image(systemName: hovered.isDirectory ? "folder.fill" : "doc.fill")
            .foregroundColor(colorForNode(hovered))
          Text(hovered.name)
            .fontWeight(.medium)
          Spacer()
          Text(formatBytes(hovered.size))
            .foregroundColor(.secondary)
          if currentNode.size > 0 {
            Text(
              "(\(String(format: "%.1f%%", Double(hovered.size) / Double(currentNode.size) * 100)))"
            )
            .foregroundColor(.secondary)
          }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
      }
    }
  }

  private func drillDown(to node: FileNode) {
    navigationPath.append(currentNode)
    currentNode = node
  }

  private func navigateTo(_ node: FileNode) {
    if let index = navigationPath.firstIndex(where: { $0.id == node.id }) {
      navigationPath = Array(navigationPath.prefix(index))
      currentNode = node
    } else if node.id == rootNode.id {
      navigationPath = []
      currentNode = rootNode
    }
  }

  private func colorForNode(_ node: FileNode) -> Color {
    if node.isDirectory {
      return .blue
    }
    let ext = (node.name as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "mov", "avi", "mkv", "wmv": return .purple
    case "mp3", "wav", "m4a", "flac", "aac": return .pink
    case "jpg", "jpeg", "png", "gif", "heic", "raw": return .orange
    case "dmg", "iso", "pkg": return .red
    case "zip", "tar", "gz", "rar", "7z": return .yellow
    case "app": return .green
    case "pdf", "doc", "docx": return .cyan
    default: return .gray
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Breadcrumb Bar

struct BreadcrumbBar: View {
  let path: [FileNode]
  let current: FileNode
  let onNavigate: (FileNode) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(path) { node in
          Button(action: { onNavigate(node) }) {
            Text(node.name)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)

          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Text(current.name)
          .fontWeight(.medium)
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }
}

// MARK: - Treemap Layout (Squarified Algorithm with Caching)

struct TreemapLayout: View {
  let nodes: [FileNode]
  let totalSize: Int64
  let frame: CGSize
  let hoveredNode: Binding<FileNode?>
  let onTap: (FileNode) -> Void

  // TopN limit to prevent too many rectangles
  private let maxNodes = 50

  // Cached layout to avoid recalculation on every render
  @State private var cachedRects: [CGRect] = []
  @State private var cachedNodes: [FileNode] = []
  @State private var cacheKey: String = ""

  private var displayNodes: [FileNode] {
    guard nodes.count > maxNodes else { return nodes }

    // TopN + Others: show top N-1 items + one "Others" aggregated node
    let sorted = nodes.sorted { $0.size > $1.size }
    let topN = Array(sorted.prefix(maxNodes - 1))
    let othersSize = sorted.dropFirst(maxNodes - 1).reduce(0) { $0 + $1.size }

    if othersSize > 0 {
      let othersNode = FileNode(
        name: "(\(nodes.count - maxNodes + 1) others)", path: "", isDirectory: true,
        size: othersSize)
      return topN + [othersNode]
    }
    return topN
  }

  private var currentCacheKey: String {
    let nodeIds = displayNodes.map { "\($0.id):\($0.size)" }.joined(separator: ",")
    return "\(Int(frame.width))x\(Int(frame.height))|\(nodeIds)"
  }

  var body: some View {
    let nodesToDisplay = displayNodes
    let rects = getOrCalculateRects(for: nodesToDisplay)

    ZStack(alignment: .topLeading) {
      ForEach(Array(zip(nodesToDisplay, rects)), id: \.0.id) { node, rect in
        TreemapCell(
          node: node,
          rect: rect,
          isHovered: hoveredNode.wrappedValue?.id == node.id,
          onHover: { isHovering in
            hoveredNode.wrappedValue = isHovering ? node : nil
          },
          onTap: { onTap(node) }
        )
      }
    }
    .onChange(of: frame) { _ in
      // Invalidate cache when frame changes
      cacheKey = ""
    }
  }

  private func getOrCalculateRects(for nodes: [FileNode]) -> [CGRect] {
    let newKey = currentCacheKey
    if cacheKey == newKey && cachedRects.count == nodes.count {
      return cachedRects
    }

    // Recalculate
    let rects = calculateSquarifiedLayout(nodes: nodes, bounds: CGRect(origin: .zero, size: frame))

    // Update cache (in next run loop to avoid modifying state during render)
    DispatchQueue.main.async {
      self.cachedRects = rects
      self.cachedNodes = nodes
      self.cacheKey = newKey
    }

    return rects
  }

  /// Squarified treemap layout algorithm
  private func calculateSquarifiedLayout(nodes: [FileNode], bounds: CGRect) -> [CGRect] {
    guard !nodes.isEmpty, bounds.width > 0, bounds.height > 0 else {
      return nodes.map { _ in .zero }
    }

    let total = nodes.reduce(Int64(0)) { $0 + $1.size }
    guard total > 0 else {
      return nodes.map { _ in .zero }
    }

    var rects: [CGRect] = Array(repeating: .zero, count: nodes.count)
    var remaining = bounds
    var index = 0

    while index < nodes.count {
      let isHorizontal = remaining.width >= remaining.height
      var row: [Int] = []
      var rowSize: Int64 = 0
      var bestAspect = CGFloat.infinity

      // Greedily add nodes to row while aspect ratio improves
      for i in index..<nodes.count {
        let testRow = row + [i]
        let testSize = rowSize + nodes[i].size
        let aspect = calculateWorstAspect(
          indices: testRow,
          nodes: nodes,
          rowSize: testSize,
          totalSize: total,
          remaining: remaining,
          isHorizontal: isHorizontal
        )

        if aspect <= bestAspect {
          row = testRow
          rowSize = testSize
          bestAspect = aspect
        } else {
          break
        }
      }

      // Layout the row
      let rowFraction = CGFloat(rowSize) / CGFloat(total)
      let rowLength = isHorizontal ? remaining.width * rowFraction : remaining.height * rowFraction

      var offset: CGFloat = 0
      for i in row {
        let nodeFraction = CGFloat(nodes[i].size) / CGFloat(rowSize)
        let nodeLength = (isHorizontal ? remaining.height : remaining.width) * nodeFraction

        if isHorizontal {
          rects[i] = CGRect(
            x: remaining.minX,
            y: remaining.minY + offset,
            width: rowLength,
            height: nodeLength
          )
        } else {
          rects[i] = CGRect(
            x: remaining.minX + offset,
            y: remaining.minY,
            width: nodeLength,
            height: rowLength
          )
        }
        offset += nodeLength
      }

      // Update remaining area
      if isHorizontal {
        remaining = CGRect(
          x: remaining.minX + rowLength,
          y: remaining.minY,
          width: remaining.width - rowLength,
          height: remaining.height
        )
      } else {
        remaining = CGRect(
          x: remaining.minX,
          y: remaining.minY + rowLength,
          width: remaining.width,
          height: remaining.height - rowLength
        )
      }

      index += row.count
    }

    return rects
  }

  private func calculateWorstAspect(
    indices: [Int], nodes: [FileNode], rowSize: Int64, totalSize: Int64, remaining: CGRect,
    isHorizontal: Bool
  ) -> CGFloat {
    guard rowSize > 0 else { return .infinity }

    let rowFraction = CGFloat(rowSize) / CGFloat(totalSize)
    let rowLength = isHorizontal ? remaining.width * rowFraction : remaining.height * rowFraction
    let crossLength = isHorizontal ? remaining.height : remaining.width

    var worst: CGFloat = 0
    for i in indices {
      let nodeFraction = CGFloat(nodes[i].size) / CGFloat(rowSize)
      let nodeLength = crossLength * nodeFraction

      let w = rowLength
      let h = nodeLength
      let aspect = max(w / h, h / w)
      worst = max(worst, aspect)
    }

    return worst
  }
}

// MARK: - Treemap Cell

struct TreemapCell: View {
  let node: FileNode
  let rect: CGRect
  let isHovered: Bool
  let onHover: (Bool) -> Void
  let onTap: () -> Void

  private var color: Color {
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

  var body: some View {
    Rectangle()
      .fill(color.opacity(isHovered ? 0.9 : 0.7))
      .frame(width: max(0, rect.width - 1), height: max(0, rect.height - 1))
      .overlay(
        Group {
          if rect.width > 60 && rect.height > 30 {
            VStack(alignment: .leading, spacing: 2) {
              Text(node.name)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
              if rect.height > 45 {
                Text(formatBytes(node.size))
                  .font(.caption2)
                  .opacity(0.8)
              }
            }
            .foregroundColor(.white)
            .padding(4)
          }
        },
        alignment: .topLeading
      )
      .border(Color.white.opacity(0.3), width: 0.5)
      .position(x: rect.midX, y: rect.midY)
      .onHover { isHovering in
        onHover(isHovering)
      }
      .onTapGesture {
        onTap()
      }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

#Preview {
  // Create sample data for preview
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

  return TreemapView(rootNode: root)
    .frame(width: 600, height: 400)
}
