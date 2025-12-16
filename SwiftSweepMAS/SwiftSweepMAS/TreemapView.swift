import SwiftUI

/// WizTree-style treemap visualization for disk usage.
/// Pure UI (no filesystem access) so it's safe for MAS sandbox.
struct TreemapView: View {
    let rootNode: FileNode
    @State private var currentNode: FileNode
    @State private var navigationPath: [FileNode] = []
    @State private var hoveredNode: FileNode?
    
    /// Limits the number of rectangles rendered at once for performance.
    private let maxVisibleNodes = 500
    
    init(rootNode: FileNode) {
        self.rootNode = rootNode
        self._currentNode = State(initialValue: rootNode)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(
                path: navigationPath,
                current: currentNode,
                onNavigate: { node in
                    navigateTo(node)
                }
            )
            
            GeometryReader { geometry in
                let children = (currentNode.children ?? [])
                let visible = Array(children.prefix(maxVisibleNodes))
                
                if !visible.isEmpty {
                    TreemapLayout(
                        nodes: visible,
                        totalSize: max(currentNode.size, 1),
                        frame: geometry.size,
                        hoveredNode: $hoveredNode,
                        onTap: { node in
                            if node.isDirectory, (node.children?.isEmpty == false) {
                                drillDown(to: node)
                            }
                        }
                    )
                    .overlay(alignment: .topLeading) {
                        if children.count > visible.count {
                            Text("Showing top \(visible.count) items")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(6)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(8)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Empty folder")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            if let hovered = hoveredNode {
                HStack(spacing: 8) {
                    Image(systemName: hovered.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundColor(colorForNode(hovered))
                    Text(hovered.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(SizeFormatter.shared.format(hovered.size))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    if currentNode.size > 0 {
                        Text("(\(String(format: "%.1f%%", Double(hovered.size) / Double(currentNode.size) * 100)))")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
        case "mp4", "mov", "avi", "mkv", "wmv":
            return .purple
        case "mp3", "wav", "m4a", "flac", "aac":
            return .pink
        case "jpg", "jpeg", "png", "gif", "heic", "raw":
            return .orange
        case "dmg", "iso", "pkg":
            return .red
        case "zip", "tar", "gz", "rar", "7z":
            return .yellow
        case "app":
            return .green
        case "pdf", "doc", "docx":
            return .cyan
        default:
            return .gray
        }
    }
}

// MARK: - Breadcrumb Bar

private struct BreadcrumbBar: View {
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
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Treemap Layout (Squarified Algorithm)

private struct TreemapLayout: View {
    let nodes: [FileNode]
    let totalSize: Int64
    let frame: CGSize
    let hoveredNode: Binding<FileNode?>
    let onTap: (FileNode) -> Void
    
    var body: some View {
        let rects = calculateSquarifiedLayout(nodes: nodes, bounds: CGRect(origin: .zero, size: frame))
        
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(nodes, rects)), id: \.0.id) { node, rect in
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
    }
    
    /// Squarified treemap layout algorithm.
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
            
            let rowFraction = CGFloat(rowSize) / CGFloat(total)
            let rowLength = isHorizontal ? remaining.width * rowFraction : remaining.height * rowFraction
            
            var offset: CGFloat = 0
            for i in row {
                let nodeFraction = CGFloat(nodes[i].size) / CGFloat(max(rowSize, 1))
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
        indices: [Int],
        nodes: [FileNode],
        rowSize: Int64,
        totalSize: Int64,
        remaining: CGRect,
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
            let h = max(nodeLength, 1)
            let aspect = max(w / h, h / w)
            worst = max(worst, aspect)
        }
        
        return worst
    }
}

// MARK: - Treemap Cell

private struct TreemapCell: View {
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
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "wav", "m4a", "flac":
            return .pink
        case "jpg", "jpeg", "png", "gif", "heic":
            return .orange
        case "dmg", "iso", "pkg":
            return .red
        case "zip", "tar", "gz", "rar", "7z":
            return .yellow
        case "app":
            return .green
        default:
            return .gray
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
                                Text(SizeFormatter.shared.format(node.size))
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
            .border(Color.white.opacity(0.25), width: 0.5)
            .position(x: rect.midX, y: rect.midY)
            .onHover { isHovering in
                onHover(isHovering)
            }
            .onTapGesture {
                onTap()
            }
    }
}

