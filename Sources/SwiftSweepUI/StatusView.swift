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
  @StateObject private var monitor = StatusMonitorViewModel()
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

          Button(action: { monitor.refresh() }) {
            Image(systemName: "arrow.clockwise")
              .font(.title3)
          }
          .help(L10n.Common.refresh.localized)
          .animatedButton()
          .disabled(monitor.isLoading)
        }
        .padding(.bottom)

        // Metrics Cards
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
          // CPU Card - Clickable
          MetricCard(
            title: "CPU",
            value: String(format: "%.1f%%", monitor.metrics.cpuUsage),
            subtitle: "Load avg · \(ProcessInfo.processInfo.processorCount) cores",
            icon: "cpu",
            color: colorForUsage(monitor.metrics.cpuUsage / 100),
            progress: monitor.metrics.cpuUsage / 100
          )
          .onTapGesture { showProcessSheet = .cpu }
          .help("Click to view process CPU usage")

          // Memory Card - Clickable
          MetricCard(
            title: "Memory",
            value: formatBytes(monitor.metrics.memoryUsed),
            subtitle: "\(formatBytes(monitor.metrics.memoryTotal)) total",
            icon: "memorychip",
            color: colorForUsage(monitor.metrics.memoryUsage),
            progress: monitor.metrics.memoryUsage
          )
          .onTapGesture { showProcessSheet = .memory }
          .help("Click to view process memory usage")

          // Disk Card
          MetricCard(
            title: "Disk",
            value: "\(formatBytes(monitor.metrics.diskUsed))",
            subtitle: "Total: \(formatBytes(monitor.metrics.diskTotal))",
            icon: "internaldrive",
            color: colorForUsage(monitor.metrics.diskUsage),
            progress: monitor.metrics.diskUsage
          )
          .onTapGesture { selection = .analyze }
          .help("Click to open Disk Analyzer")

          // Network Card (New!)
          MetricCard(
            title: "Network",
            value: "↓ " + formatSpeed(monitor.metrics.networkDownload),
            subtitle: "↑ " + formatSpeed(monitor.metrics.networkUpload),
            icon: "network",
            color: .blue,
            progress: 0  // Network doesn't update progress bar
          )

          // Battery Card (if available)
          if monitor.metrics.batteryLevel > 0 {
            MetricCard(
              title: "Battery",
              value: String(format: "%.0f%%", monitor.metrics.batteryLevel),
              subtitle: "Power Source",
              icon: "battery.100",
              color: colorForBattery(monitor.metrics.batteryLevel / 100),
              progress: monitor.metrics.batteryLevel / 100
            )
          }

          // Disk I/O Card (uses IOAnalyzer if tracing)
          MetricCard(
            title: "Disk I/O",
            value: "↓ " + formatSpeed(monitor.ioReadRate),
            subtitle: "↑ " + formatSpeed(monitor.ioWriteRate),
            icon: "arrow.up.arrow.down.circle",
            color: ioColor(monitor.ioReadRate + monitor.ioWriteRate),
            progress: 0
          )
          .onTapGesture { selection = .ioAnalyzer }
          .help("Click to open I/O Analyzer")

          MetricCard(
            title: L10n.Status.peripherals.localized,
            value: "\(monitor.peripheralSnapshot.displays.count) \(L10n.Status.displays.localized)",
            subtitle:
              "\(monitor.peripheralSnapshot.inputDevices.count) \(L10n.Status.inputDevices.localized)",
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
      monitor.startMonitoring()
    }
    .onDisappear {
      monitor.stopMonitoring()
    }
    .sheet(item: $showProcessSheet) { metricType in
      ProcessListSheet(metricType: metricType)
    }
    .sheet(isPresented: $showPeripheralsSheet) {
      PeripheralsSheet(snapshot: monitor.peripheralSnapshot)
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

@MainActor
class StatusMonitorViewModel: ObservableObject {
  @Published var metrics = SystemMonitor.SystemMetrics()
  @Published var peripheralSnapshot = PeripheralSnapshot()
  @Published var isLoading = false
  @Published var ioReadRate: Double = 0  // MB/s
  @Published var ioWriteRate: Double = 0  // MB/s

  private let metricsProvider: any StatusMetricsProviding
  private let peripheralProvider: any PeripheralSnapshotProviding
  private var timer: Timer?
  private var lastIOSlice: IOTimeSlice?
  private var isRefreshing = false

  init(
    metricsProvider: any StatusMetricsProviding = LiveStatusMetricsProvider(),
    peripheralProvider: any PeripheralSnapshotProviding = LivePeripheralSnapshotProvider()
  ) {
    self.metricsProvider = metricsProvider
    self.peripheralProvider = peripheralProvider
  }

  func startMonitoring() {
    refresh(includePeripherals: true)
    // Start IO tracing for this session (self mode, won't throw)
    Task {
      try? await IOAnalyzer.shared.startAnalysis { [weak self] slice in
        Task { @MainActor [weak self] in
          self?.ioReadRate = slice.readThroughput / (1024 * 1024)  // bytes -> MB
          self?.ioWriteRate = slice.writeThroughput / (1024 * 1024)
        }
      }
    }
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refresh(includePeripherals: false)
      }
    }
  }

  func stopMonitoring() {
    timer?.invalidate()
    timer = nil
    Task {
      await IOAnalyzer.shared.stopAnalysis()
    }
  }

  func refresh(includePeripherals: Bool = true) {
    Task {
      await performRefresh(includePeripherals: includePeripherals)
    }
  }

  func refreshForTesting(includePeripherals: Bool = true) async {
    await performRefresh(includePeripherals: includePeripherals)
  }

  private func performRefresh(includePeripherals: Bool) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    isLoading = true
    defer {
      isRefreshing = false
      isLoading = false
    }

    do {
      let newMetrics = try await metricsProvider.getMetrics()
      self.metrics = newMetrics
    } catch {
      print("Failed to fetch metrics: \(error)")
    }

    if includePeripherals {
      peripheralSnapshot = await peripheralProvider.getSnapshot()
    }
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
