import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

struct StatusView: View {
    @StateObject private var monitor = StatusMonitorViewModel()
    
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
                    
                    Button(action: { monitor.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(monitor.isLoading)
                }
                .padding(.bottom)
                
                // Metrics Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                    // CPU Card
                    MetricCard(
                        title: "CPU",
                        value: String(format: "%.1f%%", monitor.metrics.cpuUsage),
                        subtitle: "\(ProcessInfo.processInfo.processorCount) cores",
                        icon: "cpu",
                        color: colorForUsage(monitor.metrics.cpuUsage / 100),
                        progress: monitor.metrics.cpuUsage / 100
                    )
                    
                    // Memory Card
                    MetricCard(
                        title: "Memory",
                        value: formatBytes(monitor.metrics.memoryUsed),
                        subtitle: "\(formatBytes(monitor.metrics.memoryTotal)) total",
                        icon: "memorychip",
                        color: colorForUsage(monitor.metrics.memoryUsage),
                        progress: monitor.metrics.memoryUsage
                    )
                    
                    // Disk Card
                    MetricCard(
                        title: "Disk",
                        value: "\(formatBytes(monitor.metrics.diskUsed))",
                        subtitle: "Total: \(formatBytes(monitor.metrics.diskTotal))",
                        icon: "internaldrive",
                        color: colorForUsage(monitor.metrics.diskUsage),
                        progress: monitor.metrics.diskUsage
                    )
                    
                    // Network Card (New!)
                    MetricCard(
                        title: "Network",
                        value: "↓ " + formatSpeed(monitor.metrics.networkDownload),
                        subtitle: "↑ " + formatSpeed(monitor.metrics.networkUpload),
                        icon: "network",
                        color: .blue,
                        progress: 0 // Network doesn't update progress bar
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
}

@MainActor
class StatusMonitorViewModel: ObservableObject {
    @Published var metrics = SystemMonitor.SystemMetrics()
    @Published var isLoading = false
    
    private var timer: Timer?
    
    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        Task {
            do {
                let newMetrics = try await SystemMonitor.shared.getMetrics()
                DispatchQueue.main.async {
                    self.metrics = newMetrics
                }
            } catch {
                print("Failed to fetch metrics: \(error)")
            }
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2)
    }
}
