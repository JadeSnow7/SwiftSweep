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

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      Divider()

      // Content
      HSplitView {
        // Left: Charts
        VStack(spacing: 16) {
          throughputChart
          latencyChart
        }
        .frame(minWidth: 400)
        .padding()

        Divider()

        // Right: Stats & Suggestions
        VStack(spacing: 16) {
          topPathsView
          optimizationsView
        }
        .frame(minWidth: 300)
        .padding()
      }
    }
    .frame(minWidth: 800, minHeight: 500)
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

        if isTracing {
          HStack(spacing: 4) {
            Circle()
              .fill(Color.red)
              .frame(width: 8, height: 8)
            Text("Recording")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      // Buffer stats
      if let stats = bufferStats {
        HStack(spacing: 16) {
          StatLabel(label: "Events", value: "\(stats.count)")
          StatLabel(label: "Sample Rate", value: "\(Int(stats.sampleRate * 100))%")
          StatLabel(label: "Drop Rate", value: String(format: "%.1f%%", stats.dropRate * 100))
        }
      }

      Spacer()

      Toggle(isOn: $isTracing) {
        Label(isTracing ? "Stop" : "Start", systemImage: isTracing ? "stop.fill" : "record.circle")
      }
      .toggleStyle(.button)
      .buttonStyle(.borderedProminent)
      .tint(isTracing ? .red : .green)
      .onChange(of: isTracing) { newValue in
        if newValue {
          startTracing()
        } else {
          stopTracing()
        }
      }
    }
    .padding()
  }

  // MARK: - Throughput Chart

  private var throughputChart: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Throughput")
        .font(.headline)

      if timeSlices.isEmpty {
        emptyChartPlaceholder
      } else {
        GeometryReader { geo in
          ZStack {
            // Grid lines
            ForEach(0..<5) { i in
              Path { path in
                let y = geo.size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geo.size.width, y: y))
              }
              .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }

            // Read line (blue)
            throughputLine(
              data: timeSlices.map { $0.readThroughput },
              in: geo.size,
              color: .blue
            )

            // Write line (orange)
            throughputLine(
              data: timeSlices.map { $0.writeThroughput },
              in: geo.size,
              color: .orange
            )
          }
        }
        .frame(height: 120)

        // Legend
        HStack {
          LegendItem(color: .blue, label: "Read")
          LegendItem(color: .orange, label: "Write")
          Spacer()
          if let last = timeSlices.last {
            Text(
              "R: \(formatThroughput(last.readThroughput)) W: \(formatThroughput(last.writeThroughput))"
            )
            .font(.caption.monospacedDigit())
          }
        }
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  private func throughputLine(data: [Double], in size: CGSize, color: Color) -> some View {
    let maxValue = max(data.max() ?? 1, 1)

    return Path { path in
      guard data.count > 1 else { return }

      for (index, value) in data.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(data.count - 1)
        let y = size.height * (1 - CGFloat(value / maxValue))

        if index == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
    }
    .stroke(color, lineWidth: 2)
  }

  // MARK: - Latency Chart

  private var latencyChart: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Latency")
        .font(.headline)

      if timeSlices.isEmpty {
        emptyChartPlaceholder
      } else {
        GeometryReader { geo in
          ZStack {
            // Bars
            HStack(spacing: 2) {
              ForEach(timeSlices.suffix(60)) { slice in
                VStack(spacing: 0) {
                  Spacer()

                  // P99 bar
                  Rectangle()
                    .fill(latencyColor(slice.p99LatencyNanos))
                    .frame(height: latencyBarHeight(slice.p99LatencyNanos, in: geo.size.height))
                }
              }
            }
          }
        }
        .frame(height: 80)

        // Legend
        HStack {
          LegendItem(color: .green, label: "< 1ms")
          LegendItem(color: .yellow, label: "1-10ms")
          LegendItem(color: .red, label: "> 10ms")
          Spacer()
          if let last = timeSlices.last {
            Text("P99: \(formatLatency(last.p99LatencyNanos))")
              .font(.caption.monospacedDigit())
          }
        }
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  private func latencyColor(_ nanos: UInt64) -> Color {
    let ms = Double(nanos) / 1_000_000
    if ms < 1 { return .green }
    if ms < 10 { return .yellow }
    return .red
  }

  private func latencyBarHeight(_ nanos: UInt64, in maxHeight: CGFloat) -> CGFloat {
    let ms = Double(nanos) / 1_000_000
    let capped = min(ms, 100)  // Cap at 100ms
    return maxHeight * CGFloat(capped / 100)
  }

  // MARK: - Top Paths View

  private var topPathsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Hot Paths")
        .font(.headline)

      if topPaths.isEmpty {
        Text("No data yet")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding()
      } else {
        ScrollView {
          VStack(spacing: 4) {
            ForEach(topPaths.prefix(10)) { path in
              HStack {
                Text(path.path)
                  .font(.caption.monospaced())
                  .lineLimit(1)

                Spacer()

                Text(formatSize(path.totalBytes))
                  .font(.caption.monospacedDigit())
                  .foregroundColor(.secondary)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(4)
            }
          }
        }
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  // MARK: - Optimizations View

  private var optimizationsView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Suggestions")
        .font(.headline)

      if optimizations.isEmpty {
        Text("No issues detected")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding()
      } else {
        ScrollView {
          VStack(spacing: 8) {
            ForEach(optimizations) { opt in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Circle()
                    .fill(severityColor(opt.severity))
                    .frame(width: 8, height: 8)

                  Text(opt.suggestion)
                    .font(.caption)
                    .lineLimit(2)
                }

                Text(opt.estimatedImprovement)
                  .font(.caption2)
                  .foregroundColor(.green)
              }
              .padding(8)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(4)
            }
          }
        }
      }
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  // MARK: - Helpers

  private var emptyChartPlaceholder: some View {
    Text("Start tracing to see data")
      .font(.caption)
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, minHeight: 100)
  }

  private func severityColor(_ severity: IOOptimization.Severity) -> Color {
    switch severity {
    case .high: return .red
    case .medium: return .yellow
    case .low: return .green
    }
  }

  private func startTracing() {
    Task {
      await IOAnalyzer.shared.startAnalysis(aggregationInterval: 1.0) { slice in
        Task { @MainActor in
          timeSlices.append(slice)
          if timeSlices.count > 300 {
            timeSlices.removeFirst(timeSlices.count - 300)
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

        try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
      }
    }
  }

  private func stopTracing() {
    Task {
      await IOAnalyzer.shared.stopAnalysis()
    }
  }

  private func formatThroughput(_ bytesPerSec: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .file) + "/s"
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

struct StatLabel: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 0) {
      Text(value)
        .font(.caption.monospacedDigit().bold())
      Text(label)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
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
