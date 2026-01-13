import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Metric Type

/// 指标类型枚举
public enum ProcessMetricType: String, Identifiable, CaseIterable {
  case cpu = "CPU"
  case memory = "Memory"
  case network = "Network"
  case io = "I/O"

  public var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .cpu: return "process.list.title.cpu"
    case .memory: return "process.list.title.memory"
    case .network: return "process.list.title.network"
    case .io: return "process.list.title.io"
    }
  }

  var icon: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .network: return "network"
    case .io: return "arrow.up.arrow.down.circle"
    }
  }

  var sortKey: ProcessSortKey {
    switch self {
    case .cpu: return .cpu
    case .memory: return .memory
    case .network: return .network
    case .io: return .io
    }
  }
}

// MARK: - Process List Sheet

/// 进程列表弹窗 - 显示系统进程的资源使用情况
public struct ProcessListSheet: View {
  let metricType: ProcessMetricType

  @StateObject private var viewModel = ProcessListViewModel()
  @Environment(\.dismiss) private var dismiss
  @State private var selectedProcess: SystemProcessInfo?  // For detail drawer

  public init(metricType: ProcessMetricType) {
    self.metricType = metricType
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Header
      header

      Divider()

      // Process Table
      if viewModel.isLoading {
        loadingView
      } else if viewModel.processes.isEmpty {
        emptyView
      } else {
        processTable
      }
    }
    .frame(minWidth: 650, minHeight: 400)
    .frame(maxWidth: 900, maxHeight: 600)
    .onAppear {
      viewModel.load(sortBy: metricType.sortKey)
      viewModel.startAutoRefresh()
    }
    .onDisappear {
      viewModel.stopAutoRefresh()
    }
    .alert(isPresented: $viewModel.showConfirmAlert) {
      Alert(
        title: Text("Force Quit Process?"),
        message: Text(
          "Are you sure you want to quit '\(viewModel.processToKill?.name ?? "")' (PID: \(viewModel.processToKill?.id ?? 0))? Unsaved data may be lost."
        ),
        primaryButton: .destructive(Text("Force Quit")) {
          viewModel.executeKill()
        },
        secondaryButton: .cancel()
      )
    }
    .alert(isPresented: $viewModel.showedErrorAlert) {
      Alert(
        title: Text("Failed to Quit Process"),
        message: Text(viewModel.error?.localizedDescription ?? "Unknown error"),
        dismissButton: .default(Text("OK"))
      )
    }
    .overlay(alignment: .trailing) {
      // Detail Drawer Overlay
      if let process = selectedProcess {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .onTapGesture {
            selectedProcess = nil
          }

        ProcessDetailDrawer(
          process: process,
          history: viewModel.getHistory(for: process.id),
          onKill: {
            viewModel.confirmKill(process)
            selectedProcess = nil
          },
          onClose: {
            selectedProcess = nil
          }
        )
        .transition(.move(edge: .trailing))
        .zIndex(1)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: selectedProcess != nil)
  }

  // MARK: - Subviews

  private var header: some View {
    VStack(spacing: 12) {
      HStack {
        HStack(spacing: 8) {
          Image(systemName: metricType.icon)
            .font(.title2)
            .foregroundColor(.accentColor)

          // 使用 LocalizedStringKey 确保动态字符串能被本地化
          Text(LocalizedStringKey(metricType.titleKey))
            .font(.headline)
        }

        Spacer()

        Button(action: { dismiss() }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .font(.system(size: 20))
        }
        .buttonStyle(.borderless)
      }

      // 第二行放控制控件，避免拥挤
      HStack {
        Text("Sort by")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("", selection: $viewModel.sortKey) {
          ForEach(ProcessSortKey.allCases, id: \.self) { key in
            Text(key.rawValue).tag(key)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
        .onChange(of: viewModel.sortKey) { newValue in
          viewModel.load(sortBy: newValue)
        }

        Spacer()

        Button(action: { viewModel.load(sortBy: viewModel.sortKey) }) {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }
    }
    .padding()
  }

  private var loadingView: some View {
    VStack {
      Spacer()
      ProgressView()
        .progressViewStyle(.circular)
      Text("process.loading")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 8)
      Spacer()
    }
  }

  private var emptyView: some View {
    VStack {
      Spacer()
      Image(systemName: "tray")
        .font(.largeTitle)
        .foregroundColor(.secondary)
      Text("process.empty")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 8)
      Spacer()
    }
  }

  private var processTable: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        // Table Header
        tableHeader

        Divider()

        // Process Rows
        ForEach(viewModel.processes) { process in
          ProcessRow(process: process, metricType: metricType) {
            viewModel.confirmKill(process)
          }
          .contentShape(Rectangle())
          .onTapGesture {
            selectedProcess = process
          }
          Divider()
        }
      }
    }
  }

  private var tableHeader: some View {
    HStack(spacing: 12) {
      Text("process.column.name")
        .frame(maxWidth: .infinity, alignment: .leading)  // 自适应宽度

      Text("process.column.pid")
        .frame(width: 60, alignment: .trailing)

      Text("process.column.user")
        .frame(width: 80, alignment: .leading)

      Text("process.column.cpu")
        .frame(width: 70, alignment: .trailing)

      Text("process.column.memory")
        .frame(width: 80, alignment: .trailing)

      Text("process.column.network")
        .frame(width: 120, alignment: .trailing)

      Text("process.column.io")
        .frame(width: 120, alignment: .trailing)
    }
    .font(.caption)
    .foregroundColor(.secondary)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor))
  }

}

// MARK: - Process Row

struct ProcessRow: View {
  let process: SystemProcessInfo
  let metricType: ProcessMetricType
  let onKill: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 12) {
      // Process Name
      HStack(spacing: 6) {
        Image(systemName: "terminal")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(process.name)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)  // 自适应宽度

      // PID
      Text("\(process.id)")
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 60, alignment: .trailing)

      // User
      Text(process.user)
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 80, alignment: .leading)
        .lineLimit(1)

      // CPU
      HStack(spacing: 4) {
        Text(String(format: "%.1f%%", process.cpuUsage))
          .font(.system(.body, design: .monospaced))
          .foregroundColor(metricType == .cpu ? cpuColor(process.cpuUsage) : .primary)
      }
      .frame(width: 70, alignment: .trailing)

      // Memory
      Text(formatBytes(process.memoryUsage))
        .font(.system(.body, design: .monospaced))
        .foregroundColor(metricType == .memory ? memoryColor(process.memoryUsage) : .primary)
        .frame(width: 80, alignment: .trailing)

      // Network
      Text(formatNetwork(process.networkBytesIn, process.networkBytesOut))
        .font(.system(.body, design: .monospaced))
        .foregroundColor(metricType == .network ? .accentColor : .primary)
        .lineLimit(1)
        .frame(width: 120, alignment: .trailing)

      // Disk I/O (show rates, not cumulative totals)
      Text(formatDiskIORate(process.diskReadRate, process.diskWriteRate))
        .font(.system(.body, design: .monospaced))
        .foregroundColor(metricType == .io ? .accentColor : .primary)
        .lineLimit(1)
        .frame(width: 120, alignment: .trailing)

      // Kill Button (Hover only)
      if isHovered {
        Button(action: onKill) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .frame(width: 20, alignment: .center)
      } else {
        Spacer()
          .frame(width: 20)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(isHovered ? Color(nsColor: .selectedControlColor).opacity(0.1) : Color.clear)
    .onHover { isHovered = $0 }
  }

  private func cpuColor(_ usage: Double) -> Color {
    if usage > 80 { return .red }
    if usage > 50 { return .orange }
    if usage > 20 { return .yellow }
    return .green
  }

  private func memoryColor(_ bytes: Int64) -> Color {
    let mb = Double(bytes) / (1024 * 1024)
    if mb > 1000 { return .red }
    if mb > 500 { return .orange }
    if mb > 100 { return .yellow }
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

  private func formatNetwork(_ bytesIn: Int64, _ bytesOut: Int64) -> String {
    let inbound = formatCompactBytes(bytesIn)
    let outbound = formatCompactBytes(bytesOut)
    return "Rx \(inbound) / Tx \(outbound)"
  }

  private func formatDiskIO(_ readBytes: Int64, _ writeBytes: Int64) -> String {
    let readText = formatCompactBytes(readBytes)
    let writeText = formatCompactBytes(writeBytes)
    return "R \(readText) / W \(writeText)"
  }

  private func formatDiskIORate(_ readRate: Double, _ writeRate: Double) -> String {
    // Show "–" when no I/O activity
    if readRate < 1 && writeRate < 1 {
      return "–"
    }
    let readText = formatSpeed(readRate)
    let writeText = formatSpeed(writeRate)
    return "↓\(readText) ↑\(writeText)"
  }

  private func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1 {
      return "0"
    }
    let kb = bytesPerSec / 1024
    if kb < 1 {
      return String(format: "%.0fB/s", bytesPerSec)
    }
    let mb = kb / 1024
    if mb < 1 {
      return String(format: "%.0fK/s", kb)
    }
    let gb = mb / 1024
    if gb < 1 {
      return String(format: "%.1fM/s", mb)
    }
    return String(format: "%.1fG/s", gb)
  }

  private func formatCompactBytes(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024
    if kb < 1 {
      return "0K"
    }
    let mb = kb / 1024
    if mb < 1 {
      return String(format: "%.0fK", kb)
    }
    let gb = mb / 1024
    if gb < 1 {
      return String(format: "%.1fM", mb)
    }
    return String(format: "%.1fG", gb)
  }
}

// MARK: - View Model

@MainActor
class ProcessListViewModel: ObservableObject {
  @Published var processes: [SystemProcessInfo] = []
  @Published var isLoading = false
  @Published var sortKey: ProcessSortKey = .cpu

  @Published var error: Error?
  @Published var showedErrorAlert = false

  @Published var processToKill: SystemProcessInfo?
  @Published var showConfirmAlert = false

  private var timer: Timer?

  // Process history: PID -> [最近 5 次快照]
  private var processHistory: [pid_t: [ProcessSnapshot]] = [:]
  private let maxHistoryCount = 5

  func load(sortBy: ProcessSortKey) {
    self.sortKey = sortBy
    refresh()
  }

  func confirmKill(_ process: SystemProcessInfo) {
    processToKill = process
    showConfirmAlert = true
  }

  func executeKill() {
    guard let process = processToKill else { return }

    Task {
      do {
        try ProcessMonitor.shared.killProcess(process.id)
        // 成功后延迟稍许刷新
        try? await Task.sleep(nanoseconds: 200_000_000)
        refresh()
      } catch {
        await MainActor.run {
          self.error = error
          self.showedErrorAlert = true
        }
      }

      await MainActor.run {
        self.processToKill = nil
      }
    }
  }

  func startAutoRefresh() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refresh()
      }
    }
  }

  func stopAutoRefresh() {
    timer?.invalidate()
    timer = nil
  }

  private func refresh() {
    // 只有第一次加载显示 loading，后续静默刷新
    if processes.isEmpty {
      isLoading = true
    }

    Task {
      let result = await ProcessMonitor.shared.getProcesses(sortBy: sortKey, limit: 30)
      self.processes = result
      self.isLoading = false

      // Update history for each process
      for process in result {
        updateHistory(for: process)
      }
    }
  }

  func getHistory(for pid: pid_t) -> [ProcessSnapshot] {
    return processHistory[pid] ?? []
  }

  private func updateHistory(for process: SystemProcessInfo) {
    let snapshot = ProcessSnapshot(from: process)
    var history = processHistory[process.id] ?? []
    history.append(snapshot)

    // Keep only last N snapshots
    if history.count > maxHistoryCount {
      history.removeFirst(history.count - maxHistoryCount)
    }

    processHistory[process.id] = history
  }
}

// MARK: - Preview

#Preview {
  ProcessListSheet(metricType: .cpu)
}
