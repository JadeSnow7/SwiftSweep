import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Metric Type

/// 指标类型枚举
public enum ProcessMetricType: String, Identifiable, CaseIterable {
  case cpu = "CPU"
  case memory = "Memory"

  public var id: String { rawValue }

  var icon: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    }
  }

  var sortKey: ProcessSortKey {
    switch self {
    case .cpu: return .cpu
    case .memory: return .memory
    }
  }
}

// MARK: - Process List Sheet

/// 进程列表弹窗 - 显示系统进程的资源使用情况
public struct ProcessListSheet: View {
  let metricType: ProcessMetricType

  @StateObject private var viewModel = ProcessListViewModel()
  @Environment(\.dismiss) private var dismiss

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
    .frame(minWidth: 500, minHeight: 400)
    .frame(maxWidth: 700, maxHeight: 600)
    .onAppear {
      viewModel.load(sortBy: metricType.sortKey)
      viewModel.startAutoRefresh()
    }
    .onDisappear {
      viewModel.stopAutoRefresh()
    }
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
          Text(LocalizedStringKey("process.list.title.\(metricType.rawValue.lowercased())"))
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
          ProcessRow(process: process, metricType: metricType)
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
}

// MARK: - View Model

@MainActor
class ProcessListViewModel: ObservableObject {
  @Published var processes: [SystemProcessInfo] = []
  @Published var isLoading = false
  @Published var sortKey: ProcessSortKey = .cpu

  private var timer: Timer?

  func load(sortBy: ProcessSortKey) {
    self.sortKey = sortBy
    refresh()
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
    }
  }
}

// MARK: - Preview

#Preview {
  ProcessListSheet(metricType: .cpu)
}
