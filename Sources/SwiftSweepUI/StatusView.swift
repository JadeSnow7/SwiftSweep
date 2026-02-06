import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

protocol StatusMetricsProviding: Sendable {
  func getMetrics() async throws -> SystemMonitor.SystemMetrics
}

struct LiveStatusMetricsProvider: StatusMetricsProviding {
  func getMetrics() async throws -> SystemMonitor.SystemMetrics {
    try await SystemMonitor.shared.getMetrics()
  }
}

protocol PeripheralSnapshotProviding: Sendable {
  func getSnapshot() async -> PeripheralSnapshot
}

struct LivePeripheralSnapshotProvider: PeripheralSnapshotProviding {
  func getSnapshot() async -> PeripheralSnapshot {
    await PeripheralInspector.shared.getSnapshot()
  }
}

struct StatusView: View {
  @Binding var selection: ContentView.NavigationItem?
  @EnvironmentObject var store: AppStore
  @State private var showProcessSheet: ProcessMetricType?
  @State private var showPeripheralsSheet = false
  @State private var showDiagnosticsSheet = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // Header
        HStack {
          VStack(alignment: .leading) {
            Text("System Status")
              .font(.largeTitle)
              .fontWeight(.bold)
            Text("Real-time monitoring")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }

          Spacer()

          Button(action: { showDiagnosticsSheet = true }) {
            HStack(spacing: 4) {
              Image(systemName: "stethoscope")
              Text(L10n.Status.appleDiagnostics.localized)
            }
            .font(.subheadline)
          }
          .animatedButton()

          Button(action: { store.dispatch(.status(.startMonitoring)) }) {
            Image(systemName: "arrow.clockwise")
              .font(.title3)
          }
          .help(L10n.Common.refresh.localized)
          .animatedButton()
          .disabled(store.state.status.phase == .monitoring)
        }
        .padding(.bottom)

        // Metrics Cards
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
          // CPU Card - Clickable
          MetricCard(
            title: "CPU",
            value: String(format: "%.1f%%", store.state.status.cpuUsage),
            subtitle: "Load avg · \(ProcessInfo.processInfo.processorCount) cores",
            icon: "cpu",
            color: colorForUsage(store.state.status.cpuUsage / 100),
            progress: store.state.status.cpuUsage / 100
          )
          .onTapGesture { showProcessSheet = .cpu }
          .help("Click to view process CPU usage")

          // Memory Card - Clickable
          MetricCard(
            title: "Memory",
            value: formatBytes(store.state.status.memoryUsed),
            subtitle: "\(formatBytes(store.state.status.memoryTotal)) total",
            icon: "memorychip",
            color: colorForUsage(store.state.status.memoryUsage),
            progress: store.state.status.memoryUsage
          )
          .onTapGesture { showProcessSheet = .memory }
          .help("Click to view process memory usage")

          // Disk Card
          MetricCard(
            title: "Disk",
            value: "\(formatBytes(store.state.status.diskUsed))",
            subtitle: "Total: \(formatBytes(store.state.status.diskTotal))",
            icon: "internaldrive",
            color: colorForUsage(store.state.status.diskUsage),
            progress: store.state.status.diskUsage
          )
          .onTapGesture { selection = .analyze }
          .help("Click to open Disk Analyzer")

          // Network Card (New!)
          MetricCard(
            title: "Network",
            value: "↓ " + formatSpeed(store.state.status.networkDownload),
            subtitle: "↑ " + formatSpeed(store.state.status.networkUpload),
            icon: "network",
            color: .blue,
            progress: 0  // Network doesn't update progress bar
          )

          // Battery Card (if available)
          if store.state.status.batteryLevel > 0 {
            MetricCard(
              title: "Battery",
              value: String(format: "%.0f%%", store.state.status.batteryLevel),
              subtitle: "Power Source",
              icon: "battery.100",
              color: colorForBattery(store.state.status.batteryLevel / 100),
              progress: store.state.status.batteryLevel / 100
            )
          }

          // Disk I/O Card (uses IOAnalyzer if tracing)
          MetricCard(
            title: "Disk I/O",
            value: "↓ " + formatSpeed(store.state.status.ioReadRate),
            subtitle: "↑ " + formatSpeed(store.state.status.ioWriteRate),
            icon: "arrow.up.arrow.down.circle",
            color: ioColor(store.state.status.ioReadRate + store.state.status.ioWriteRate),
            progress: 0
          )
          .onTapGesture { selection = .ioAnalyzer }
          .help("Click to open I/O Analyzer")

          MetricCard(
            title: L10n.Status.peripherals.localized,
            value: "\(store.state.status.peripheralSnapshot.displays.count) \(L10n.Status.displays.localized)",
            subtitle:
              "\(store.state.status.peripheralSnapshot.inputDevices.count) \(L10n.Status.inputDevices.localized)",
            icon: "keyboard",
            color: .purple,
            progress: 0
          )
          .onTapGesture { showPeripheralsSheet = true }
          .help("Click to view connected peripherals")
        }

        Spacer()
      }
      .padding()
    }
    .onAppear {
      store.dispatch(.status(.startMonitoring))
    }
    .onDisappear {
      store.dispatch(.status(.stopMonitoring))
    }
    .sheet(item: $showProcessSheet) { metricType in
      ProcessListSheet(metricType: metricType)
    }
    .sheet(isPresented: $showPeripheralsSheet) {
      PeripheralsSheet(snapshot: store.state.status.peripheralSnapshot)
    }
    .sheet(isPresented: $showDiagnosticsSheet) {
      DiagnosticsGuideSheet(guide: DiagnosticsGuideService.shared.getGuide())
    }
  }

  func colorForUsage(_ usage: Double) -> Color {
    if usage > 0.9 { return .red }
    if usage > 0.7 { return .orange }
    if usage > 0.5 { return .yellow }
    return .green
  }

  func colorForBattery(_ level: Double) -> Color {
    if level < 0.2 { return .red }
    if level < 0.5 { return .orange }
    return .green
  }

  func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / (1024 * 1024 * 1024)
    return String(format: "%.1f GB", gb)
  }

  func formatSpeed(_ mbps: Double) -> String {
    if mbps < 0.1 { return "0 KB/s" }
    if mbps < 1.0 { return String(format: "%.1f KB/s", mbps * 1024) }
    return String(format: "%.1f MB/s", mbps)
  }

  func ioColor(_ totalMBps: Double) -> Color {
    if totalMBps > 50 { return .red }
    if totalMBps > 20 { return .orange }
    if totalMBps > 5 { return .yellow }
    return .green
  }
}

struct MetricCard: View {
  let title: String
  let value: String
  let subtitle: String
  let icon: String
  let color: Color
  let progress: Double

  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .foregroundColor(color)
          .font(.title2)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(value)
            .fontWeight(.semibold)
            .font(.body)
          if !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()

      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)

      if progress > 0 {
        ProgressView(value: min(progress, 1.0))
          .tint(color)
      }
    }
    .padding()
    .frame(height: 110)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .controlBackgroundColor))
        .shadow(
          color: .black.opacity(isHovered ? 0.12 : 0.05),
          radius: isHovered ? 8 : 2,
          y: isHovered ? 4 : 1
        )
    )
    .scaleEffect(isHovered && !motion.reduceMotion ? 1.02 : 1.0)
    .animation(motion.reduceMotion ? nil : .spring(response: 0.3), value: isHovered)
    .onHover { isHovered = $0 }
  }
}
