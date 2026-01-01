import SwiftUI

// MARK: - I/O Analyzer View

/// I/O 性能分析视图
/// 实时展示吞吐量、热点路径、优化建议
public struct IOAnalyzerView: View {
  @State private var isTracing = false
  @State private var timeSlices: [IOTimeSlice] = []
  @State private var topPaths: [IOPathStats] = []
  @State private var optimizations: [IOOptimization] = []
  @State private var bufferStats: IOEventBuffer.BufferStats?
  @State private var currentReadSpeed: Double = 0
  @State private var currentWriteSpeed: Double = 0
  @State private var peakReadSpeed: Double = 0
  @State private var peakWriteSpeed: Double = 0

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      Divider()

      // Content
      ScrollView {
        VStack(spacing: 16) {
          // Speed Cards
          speedCardsRow

          // Charts
          HStack(spacing: 16) {
            throughputChart
            latencyChart
          }
          .frame(height: 200)

          // Bottom row
          HStack(alignment: .top, spacing: 16) {
            topPathsView
            optimizationsView
          }
        }
        .padding()
      }
    }
    .frame(minWidth: 800, minHeight: 600)
    .onDisappear {
      Task {
        await IOAnalyzer.shared.stopAnalysis()
      }
    }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("I/O Performance Analyzer")
          .font(.title2.bold())

        HStack(spacing: 8) {
          if isTracing {
            HStack(spacing: 4) {
              Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay {
                  Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 2)
                    .scaleEffect(1.5)
                    .opacity(0.6)
                }
              Text("Recording")
                .font(.caption.bold())
                .foregroundColor(.red)
            }
          } else {
            Text("Ready to analyze")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      // Buffer stats
      if isTracing, let stats = bufferStats {
        HStack(spacing: 20) {
          StatPill(value: "\(stats.count)", label: "Events", color: .blue)
          StatPill(value: "\(Int(stats.sampleRate * 100))%", label: "Sample", color: .green)
          StatPill(
            value: String(format: "%.1f%%", stats.dropRate * 100), label: "Drop",
            color: stats.dropRate > 0.1 ? .red : .orange)
        }
        .padding(.horizontal)
      }

      Spacer()

      Button(action: {
        isTracing.toggle()
        if isTracing {
          startTracing()
        } else {
          stopTracing()
        }
      }) {
        HStack {
          Image(systemName: isTracing ? "stop.fill" : "record.circle")
          Text(isTracing ? "Stop" : "Start")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .tint(isTracing ? .red : .green)
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
  }

  // MARK: - Speed Cards

  private var speedCardsRow: some View {
    HStack(spacing: 16) {
      SpeedCard(
        title: "Read Speed",
        currentValue: currentReadSpeed,
        peakValue: peakReadSpeed,
        icon: "arrow.down.circle.fill",
        color: .blue
      )

      SpeedCard(
        title: "Write Speed",
        currentValue: currentWriteSpeed,
        peakValue: peakWriteSpeed,
        icon: "arrow.up.circle.fill",
        color: .orange
      )

      SpeedCard(
        title: "Total I/O",
        currentValue: currentReadSpeed + currentWriteSpeed,
        peakValue: peakReadSpeed + peakWriteSpeed,
        icon: "arrow.up.arrow.down.circle.fill",
        color: .purple
      )

      // Events per second
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "bolt.circle.fill")
            .foregroundColor(.yellow)
            .font(.title2)
          Text("Operations")
            .font(.subheadline.bold())
        }

        if let last = timeSlices.last {
          Text("\(last.readOps + last.writeOps)")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
          Text("ops/sec")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text("--")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundColor(.secondary)
          Text("ops/sec")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(12)
    }
  }

  // MARK: - Throughput Chart

  private var throughputChart: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Throughput")
          .font(.headline)
        Spacer()
        if let last = timeSlices.last {
          HStack(spacing: 12) {
            Label(formatSpeed(last.readThroughput), systemImage: "arrow.down")
              .font(.caption.monospacedDigit())
              .foregroundColor(.blue)
            Label(formatSpeed(last.writeThroughput), systemImage: "arrow.up")
              .font(.caption.monospacedDigit())
              .foregroundColor(.orange)
          }
        }
      }

      GeometryReader { geo in
        ZStack {
          // Background grid
          Path { path in
            for i in 0..<5 {
              let y = geo.size.height * CGFloat(i) / 4
              path.move(to: CGPoint(x: 0, y: y))
              path.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
          }
          .stroke(Color.secondary.opacity(0.15), lineWidth: 1)

          if timeSlices.isEmpty {
            // Animated placeholder
            emptyChartAnimation(in: geo.size)
          } else {
            // Read area (blue)
            throughputArea(
              data: timeSlices.map { $0.readThroughput },
              in: geo.size,
              color: .blue
            )

            // Write area (orange)
            throughputArea(
              data: timeSlices.map { $0.writeThroughput },
              in: geo.size,
              color: .orange
            )

            // Read line
            throughputLine(
              data: timeSlices.map { $0.readThroughput },
              in: geo.size,
              color: .blue
            )

            // Write line
            throughputLine(
              data: timeSlices.map { $0.writeThroughput },
              in: geo.size,
              color: .orange
            )
          }
        }
      }

      // Legend
      HStack {
        LegendItem(color: .blue, label: "Read")
        LegendItem(color: .orange, label: "Write")
        Spacer()
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(12)
  }

  private func throughputArea(data: [Double], in size: CGSize, color: Color) -> some View {
    let maxValue = max(data.max() ?? 1, 1024 * 1024)  // At least 1MB for scale

    return Path { path in
      guard data.count > 1 else { return }

      path.move(to: CGPoint(x: 0, y: size.height))

      for (index, value) in data.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(data.count - 1)
        let y = size.height * (1 - CGFloat(min(value / maxValue, 1.0)))
        path.addLine(to: CGPoint(x: x, y: y))
      }

      path.addLine(to: CGPoint(x: size.width, y: size.height))
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

  private func throughputLine(data: [Double], in size: CGSize, color: Color) -> some View {
    let maxValue = max(data.max() ?? 1, 1024 * 1024)

    return Path { path in
      guard data.count > 1 else { return }

      for (index, value) in data.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(data.count - 1)
        let y = size.height * (1 - CGFloat(min(value / maxValue, 1.0)))

        if index == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
    }
    .stroke(color, lineWidth: 2)
  }

  private func emptyChartAnimation(in size: CGSize) -> some View {
    VStack {
      Spacer()
      if isTracing {
        HStack(spacing: 4) {
          ProgressView()
            .scaleEffect(0.7)
          Text("Collecting data...")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      } else {
        Text("Start tracing to see data")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Latency Chart

  private var latencyChart: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Latency (P99)")
          .font(.headline)
        Spacer()
        if let last = timeSlices.last {
          Text(formatLatency(last.p99LatencyNanos))
            .font(.caption.monospacedDigit().bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(latencyColor(last.p99LatencyNanos).opacity(0.2))
            .cornerRadius(4)
        }
      }

      GeometryReader { geo in
        if timeSlices.isEmpty {
          emptyChartAnimation(in: geo.size)
        } else {
          HStack(spacing: 1) {
            ForEach(timeSlices.suffix(60)) { slice in
              VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                  .fill(
                    LinearGradient(
                      colors: [
                        latencyColor(slice.p99LatencyNanos),
                        latencyColor(slice.p99LatencyNanos).opacity(0.5),
                      ],
                      startPoint: .top,
                      endPoint: .bottom
                    )
                  )
                  .frame(height: latencyBarHeight(slice.p99LatencyNanos, in: geo.size.height))
              }
            }
          }
        }
      }

      // Legend
      HStack {
        LegendItem(color: .green, label: "< 1ms")
        LegendItem(color: .yellow, label: "1-10ms")
        LegendItem(color: .red, label: "> 10ms")
        Spacer()
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(12)
  }

  private func latencyColor(_ nanos: UInt64) -> Color {
    let ms = Double(nanos) / 1_000_000
    if ms < 1 { return .green }
    if ms < 10 { return .yellow }
    return .red
  }

  private func latencyBarHeight(_ nanos: UInt64, in maxHeight: CGFloat) -> CGFloat {
    let ms = Double(nanos) / 1_000_000
    let capped = min(ms, 100)
    return max(maxHeight * CGFloat(capped / 100), 4)  // Minimum 4px height
  }

  // MARK: - Top Paths View

  private var topPathsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Hot Paths")
          .font(.headline)
        Spacer()
        if !topPaths.isEmpty {
          Text("\(topPaths.count) paths")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      if topPaths.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "folder.badge.questionmark")
            .font(.title)
            .foregroundColor(.secondary.opacity(0.5))
          Text(isTracing ? "Analyzing..." : "No data yet")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
      } else {
        ScrollView {
          VStack(spacing: 6) {
            ForEach(Array(topPaths.prefix(8).enumerated()), id: \.element.id) { index, path in
              HStack {
                Text("\(index + 1)")
                  .font(.caption.bold())
                  .foregroundColor(.secondary)
                  .frame(width: 20)

                Image(systemName: "folder.fill")
                  .foregroundColor(.blue.opacity(0.7))
                  .font(.caption)

                Text(path.path)
                  .font(.caption.monospaced())
                  .lineLimit(1)
                  .truncationMode(.middle)

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                  Text(formatSize(path.totalBytes))
                    .font(.caption.monospacedDigit().bold())
                  Text("\(path.operationCount) ops")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.secondary.opacity(0.08))
              .cornerRadius(6)
            }
          }
        }
      }
    }
    .frame(minWidth: 300)
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(12)
  }

  // MARK: - Optimizations View

  private var optimizationsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Suggestions")
          .font(.headline)
        Spacer()
        if !optimizations.isEmpty {
          Text("\(optimizations.count) issues")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(4)
        }
      }

      if optimizations.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .font(.title)
            .foregroundColor(.green.opacity(0.5))
          Text("No issues detected")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
      } else {
        ScrollView {
          VStack(spacing: 8) {
            ForEach(optimizations) { opt in
              HStack(alignment: .top, spacing: 10) {
                Circle()
                  .fill(severityColor(opt.severity))
                  .frame(width: 10, height: 10)
                  .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                  Text(opt.suggestion)
                    .font(.caption)
                    .lineLimit(2)

                  HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                      .font(.caption2)
                    Text(opt.estimatedImprovement)
                      .font(.caption2.bold())
                  }
                  .foregroundColor(.green)
                }
              }
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(severityColor(opt.severity).opacity(0.1))
              .cornerRadius(8)
            }
          }
        }
      }
    }
    .frame(minWidth: 300)
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(12)
  }

  // MARK: - Actions

  private func startTracing() {
    // Reset data
    timeSlices.removeAll()
    topPaths.removeAll()
    optimizations.removeAll()
    currentReadSpeed = 0
    currentWriteSpeed = 0
    peakReadSpeed = 0
    peakWriteSpeed = 0

    Task {
      await IOAnalyzer.shared.startAnalysis(aggregationInterval: 1.0) { slice in
        Task { @MainActor in
          timeSlices.append(slice)
          if timeSlices.count > 120 {
            timeSlices.removeFirst(timeSlices.count - 120)
          }

          // Update current speeds
          currentReadSpeed = slice.readThroughput
          currentWriteSpeed = slice.writeThroughput

          // Track peaks
          if slice.readThroughput > peakReadSpeed {
            peakReadSpeed = slice.readThroughput
          }
          if slice.writeThroughput > peakWriteSpeed {
            peakWriteSpeed = slice.writeThroughput
          }
        }
      }

      // Periodic stats update
      while isTracing {
        let paths = await IOAnalyzer.shared.getTopPaths()
        let result = await IOAnalyzer.shared.getAnalysisResult()
        let stats = await IOAnalyzer.shared.getBufferStats()

        await MainActor.run {
          topPaths = paths
          optimizations = result.optimizations
          bufferStats = stats
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
      }
    }
  }

  private func stopTracing() {
    Task {
      await IOAnalyzer.shared.stopAnalysis()
    }
  }

  // MARK: - Helpers

  private func severityColor(_ severity: IOOptimization.Severity) -> Color {
    switch severity {
    case .high: return .red
    case .medium: return .yellow
    case .low: return .green
    }
  }

  private func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1024 {
      return String(format: "%.0f B/s", bytesPerSec)
    } else if bytesPerSec < 1024 * 1024 {
      return String(format: "%.1f KB/s", bytesPerSec / 1024)
    } else {
      return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
    }
  }

  private func formatLatency(_ nanos: UInt64) -> String {
    let ms = Double(nanos) / 1_000_000
    if ms < 1 {
      return String(format: "%.2fms", ms)
    }
    return String(format: "%.1fms", ms)
  }

  private func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

// MARK: - Supporting Views

struct SpeedCard: View {
  let title: String
  let currentValue: Double
  let peakValue: Double
  let icon: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.title2)
        Text(title)
          .font(.subheadline.bold())
      }

      Text(formatSpeed(currentValue))
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundColor(.primary)

      HStack {
        Text("Peak:")
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(formatSpeed(peakValue))
          .font(.caption2.bold())
          .foregroundColor(color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(12)
  }

  private func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1024 {
      return String(format: "%.0f B/s", bytesPerSec)
    } else if bytesPerSec < 1024 * 1024 {
      return String(format: "%.1f KB/s", bytesPerSec / 1024)
    } else {
      return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
    }
  }
}

struct StatPill: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundColor(color)
      Text(label)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}

struct LegendItem: View {
  let color: Color
  let label: String

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(label)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  IOAnalyzerView()
}
