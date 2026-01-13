import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Process Detail Drawer

/// 进程详情抽屉 - 显示进程的历史数据和快捷操作
struct ProcessDetailDrawer: View {
  let process: SystemProcessInfo
  let history: [ProcessSnapshot]  // 最近 5 次采样
  let onKill: () -> Void
  let onClose: () -> Void

  @Environment(\.motionConfig) private var motion

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(process.name)
            .font(.headline)
          Text("PID: \(process.id) • User: \(process.user)")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        Button(action: onClose) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
      }

      Divider()

      // Metrics Grid
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        MetricTile(
          title: "CPU",
          value: String(format: "%.1f%%", process.cpuUsage),
          icon: "cpu",
          color: cpuColor(process.cpuUsage)
        )

        MetricTile(
          title: "Memory",
          value: formatBytes(process.memoryUsage),
          icon: "memorychip",
          color: .blue
        )

        MetricTile(
          title: "Disk Read",
          value: formatSpeed(process.diskReadRate),
          icon: "arrow.down.circle",
          color: .green
        )

        MetricTile(
          title: "Disk Write",
          value: formatSpeed(process.diskWriteRate),
          icon: "arrow.up.circle",
          color: .orange
        )
      }

      // Sparkline Chart
      if !history.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("CPU History (Last 5 samples)")
            .font(.caption)
            .foregroundColor(.secondary)

          SparklineChart(
            data: history.map { $0.cpuUsage },
            color: .accentColor,
            height: 60
          )
        }
      }

      Divider()

      // Quick Actions
      HStack(spacing: 12) {
        Button(action: onKill) {
          Label("Force Quit", systemImage: "xmark.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)

        Button(action: {
          // TODO: Implement pause (SIGSTOP)
        }) {
          Label("Pause", systemImage: "pause.circle")
        }
        .buttonStyle(.bordered)
        .disabled(true)  // Placeholder

        Button(action: {
          // TODO: Implement resource limit
        }) {
          Label("Limit", systemImage: "gauge")
        }
        .buttonStyle(.bordered)
        .disabled(true)  // Placeholder
      }
    }
    .padding()
    .frame(width: 400)
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(12)
    .shadow(radius: 10)
  }

  private func cpuColor(_ usage: Double) -> Color {
    if usage > 80 { return .red }
    if usage > 50 { return .orange }
    if usage > 20 { return .yellow }
    return .green
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    if mb < 1 {
      let kb = Double(bytes) / 1024
      return String(format: "%.0f KB", kb)
    }
    if mb > 1024 {
      let gb = mb / 1024
      return String(format: "%.1f GB", gb)
    }
    return String(format: "%.1f MB", mb)
  }

  private func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1 {
      return "0 B/s"
    }
    let kb = bytesPerSec / 1024
    if kb < 1 {
      return String(format: "%.0f B/s", bytesPerSec)
    }
    let mb = kb / 1024
    if mb < 1 {
      return String(format: "%.0f KB/s", kb)
    }
    return String(format: "%.1f MB/s", mb)
  }
}

// MARK: - Metric Tile

struct MetricTile: View {
  let title: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(color)
        .font(.title3)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundColor(.secondary)
        Text(value)
          .font(.body)
          .fontWeight(.semibold)
      }

      Spacer()
    }
    .padding(10)
    .background(Color(nsColor: .textBackgroundColor))
    .cornerRadius(8)
  }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
  let data: [Double]
  let color: Color
  let height: CGFloat

  var body: some View {
    GeometryReader { geometry in
      let maxValue = data.max() ?? 1
      let points = data.enumerated().map { index, value in
        let x = CGFloat(index) / CGFloat(max(data.count - 1, 1)) * geometry.size.width
        let y = geometry.size.height - (CGFloat(value) / CGFloat(maxValue) * geometry.size.height)
        return CGPoint(x: x, y: y)
      }

      Path { path in
        guard !points.isEmpty else { return }
        path.move(to: points[0])
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
      }
      .stroke(color, lineWidth: 2)

      // Fill area under curve
      Path { path in
        guard !points.isEmpty else { return }
        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
        path.addLine(to: points[0])
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: points.last!.x, y: geometry.size.height))
        path.closeSubpath()
      }
      .fill(
        LinearGradient(
          colors: [color.opacity(0.3), color.opacity(0.05)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }
    .frame(height: height)
  }
}

// MARK: - Process Snapshot

/// 进程快照 - 用于历史记录
public struct ProcessSnapshot: Identifiable {
  public let id = UUID()
  public let timestamp: Date
  public let cpuUsage: Double
  public let memoryUsage: Int64
  public let diskReadRate: Double
  public let diskWriteRate: Double

  public init(
    timestamp: Date = Date(),
    cpuUsage: Double,
    memoryUsage: Int64,
    diskReadRate: Double,
    diskWriteRate: Double
  ) {
    self.timestamp = timestamp
    self.cpuUsage = cpuUsage
    self.memoryUsage = memoryUsage
    self.diskReadRate = diskReadRate
    self.diskWriteRate = diskWriteRate
  }

  public init(from process: SystemProcessInfo) {
    self.timestamp = Date()
    self.cpuUsage = process.cpuUsage
    self.memoryUsage = process.memoryUsage
    self.diskReadRate = process.diskReadRate
    self.diskWriteRate = process.diskWriteRate
  }
}
