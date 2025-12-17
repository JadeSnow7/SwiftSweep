import SwiftUI
import AppKit

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
                        Text("(\(String(format: "%.1f%%", Double(hovered.size) / Double(currentNode.size) * 100)))")
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

// MARK: - Treemap Layout (Squarified Algorithm)

struct TreemapLayout: View {
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
        indices: [Int],
        nodes: [FileNode],
        rowSize: Int64,
        totalSize: Int64,
        remaining: CGRect,
        isHorizontal: Bool
    ) -> CGFloat {
        let rowFraction = CGFloat(rowSize) / CGFloat(totalSize)
        let rowLength = isHorizontal ? remaining.width * rowFraction : remaining.height * rowFraction
        let otherLength = isHorizontal ? remaining.height : remaining.width
        
        var worst: CGFloat = 0
        for i in indices {
            let nodeFraction = CGFloat(nodes[i].size) / CGFloat(rowSize)
            let nodeLength = otherLength * nodeFraction
            let aspect = max(rowLength / nodeLength, nodeLength / rowLength)
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
    
    private var fillColor: Color {
        if node.isDirectory {
            return .blue.opacity(0.3)
        }
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "avi", "mkv", "wmv": return .purple.opacity(0.4)
        case "mp3", "wav", "m4a", "flac", "aac": return .pink.opacity(0.4)
        case "jpg", "jpeg", "png", "gif", "heic", "raw": return .orange.opacity(0.4)
        case "dmg", "iso", "pkg": return .red.opacity(0.4)
        case "zip", "tar", "gz", "rar", "7z": return .yellow.opacity(0.4)
        case "app": return .green.opacity(0.4)
        case "pdf", "doc", "docx": return .cyan.opacity(0.4)
        default: return .gray.opacity(0.3)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(isHovered ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isHovered ? 2 : 1)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .onHover(perform: onHover)
                .onTapGesture(perform: onTap)
            
            if rect.width > 60 && rect.height > 30 {
                Text(node.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .padding(4)
                    .foregroundColor(.primary)
                    .frame(width: rect.width - 8, alignment: .leading)
                    .position(x: rect.minX + (rect.width / 2), y: rect.minY + 12)
            }
        }
    }
}

