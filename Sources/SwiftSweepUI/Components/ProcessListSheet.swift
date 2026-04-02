import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

// MARK: - Metric Type

public enum ProcessListMetricType: String, Identifiable, CaseIterable {
  case cpu = "CPU"
  case memory = "Memory"
  case network = "Network"
  case io = "I/O"

  public var id: String { rawValue }

  static let primaryCases: [ProcessListMetricType] = [.cpu, .memory]

  var titleKey: String {
    switch self {
    case .cpu: return "process.list.title.cpu"
    case .memory: return "process.list.title.memory"
    case .network: return "process.list.title.network"
    case .io: return "process.list.title.io"
    }
  }

  var summaryKey: String {
    switch self {
    case .cpu: return "process.summary.cpu"
    case .memory: return "process.summary.memory"
    case .network: return "process.summary.network"
    case .io: return "process.summary.io"
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

// MARK: - Provider

protocol ProcessDataProviding: Sendable {
  func getProcesses(sortBy: ProcessSortKey, limit: Int) async -> [SystemProcessInfo]
  func killProcess(_ pid: pid_t) throws
}

struct LiveProcessDataProvider: ProcessDataProviding {
  func getProcesses(sortBy: ProcessSortKey, limit: Int) async -> [SystemProcessInfo] {
    await ProcessMonitor.shared.getProcesses(sortBy: sortBy, limit: limit)
  }

  func killProcess(_ pid: pid_t) throws {
    try ProcessMonitor.shared.killProcess(pid)
  }
}

// MARK: - View Model

@MainActor
final class ProcessMonitorViewModel: ObservableObject {
  @Published var processes: [SystemProcessInfo] = []
  @Published var isLoading = false
  @Published var sortKey: ProcessSortKey
  @Published var selectedMetric: ProcessListMetricType
  @Published var selectedProcess: SystemProcessInfo?

  @Published var error: Error?
  @Published var showedErrorAlert = false
  @Published var processToKill: SystemProcessInfo?
  @Published var showConfirmAlert = false

  let availableSortKeys: [ProcessSortKey] = [.cpu, .memory, .name]

  private let provider: any ProcessDataProviding
  private let limit: Int
  private var timer: Timer?
  private var processHistory: [pid_t: [ProcessSnapshot]] = [:]
  private let maxHistoryCount = 5

  init(
    initialMetric: ProcessListMetricType,
    provider: any ProcessDataProviding = LiveProcessDataProvider(),
    limit: Int = 30
  ) {
    self.selectedMetric = initialMetric
    self.sortKey = initialMetric.sortKey
    self.provider = provider
    self.limit = limit
  }

  var titleKey: String {
    selectedMetric.titleKey
  }

  var summaryKey: String {
    selectedMetric.summaryKey
  }

  func selectMetric(_ metric: ProcessListMetricType) {
    guard selectedMetric != metric else { return }
    selectedMetric = metric
    sortKey = metric.sortKey
    refresh()
  }

  func updateSortKey(_ sortKey: ProcessSortKey) {
    guard self.sortKey != sortKey else { return }
    self.sortKey = sortKey
    refresh()
  }

  func selectProcess(_ process: SystemProcessInfo) {
    selectedProcess = process
  }

  func clearSelection() {
    selectedProcess = nil
  }

  func refreshForTesting() async {
    await runRefresh()
  }

  func refresh() {
    Task {
      await runRefresh()
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

  func confirmKill(_ process: SystemProcessInfo) {
    processToKill = process
    showConfirmAlert = true
  }

  func executeKill() {
    guard let process = processToKill else { return }

    Task {
      do {
        try provider.killProcess(process.id)
        try? await Task.sleep(nanoseconds: 200_000_000)
        await runRefresh()
      } catch {
        self.error = error
        self.showedErrorAlert = true
      }

      self.processToKill = nil
    }
  }

  func getHistory(for pid: pid_t) -> [ProcessSnapshot] {
    processHistory[pid] ?? []
  }

  private func runRefresh() async {
    if processes.isEmpty {
      isLoading = true
    }

    let result = await provider.getProcesses(sortBy: sortKey, limit: limit)
    processes = result
    isLoading = false

    for process in result {
      updateHistory(for: process)
    }

    guard let current = selectedProcess else { return }
    selectedProcess = result.first(where: { $0.id == current.id })
  }

  private func updateHistory(for process: SystemProcessInfo) {
    let snapshot = ProcessSnapshot(from: process)
    var history = processHistory[process.id] ?? []
    history.append(snapshot)

    if history.count > maxHistoryCount {
      history.removeFirst(history.count - maxHistoryCount)
    }

    processHistory[process.id] = history
  }
}

// MARK: - Main View

struct ProcessMonitorView: View {
  @Binding var selection: ContentView.NavigationItem?
  @Binding var selectedMetric: ProcessListMetricType
  @StateObject private var viewModel: ProcessMonitorViewModel

  init(
    selection: Binding<ContentView.NavigationItem?>,
    selectedMetric: Binding<ProcessListMetricType>
  ) {
    _selection = selection
    _selectedMetric = selectedMetric
    _viewModel = StateObject(
      wrappedValue: ProcessMonitorViewModel(initialMetric: selectedMetric.wrappedValue)
    )
  }

  public var body: some View {
    HStack(spacing: Spacing.xl) {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header
        content
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      ProcessInspectorPane(
        process: viewModel.selectedProcess,
        history: inspectorHistory,
        onKill: {
          guard let process = viewModel.selectedProcess else { return }
          viewModel.confirmKill(process)
        },
        onClearSelection: {
          viewModel.clearSelection()
        }
      )
      .frame(width: 360)
    }
    .padding()
    .navigationTitle("process.monitor.title".localized)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button(action: { selection = .status }) {
          Label("process.monitor.back".localized, systemImage: "chevron.left")
        }
      }
    }
    .onAppear {
      viewModel.startAutoRefresh()
    }
    .onDisappear {
      viewModel.stopAutoRefresh()
    }
    .onChange(of: selectedMetric) { newValue in
      viewModel.selectMetric(newValue)
    }
    .onChange(of: viewModel.selectedMetric) { newValue in
      if selectedMetric != newValue {
        selectedMetric = newValue
      }
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
  }

  private var inspectorHistory: [ProcessSnapshot] {
    guard let process = viewModel.selectedProcess else { return [] }
    return viewModel.getHistory(for: process.id)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: Spacing.lg) {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("process.monitor.title".localized)
          .font(.title2.weight(.semibold))
        Text(LocalizedStringKey(viewModel.summaryKey))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Picker("", selection: Binding(
        get: { viewModel.selectedMetric },
        set: { metric in
          selectedMetric = metric
        }
      )) {
        ForEach(ProcessListMetricType.primaryCases) { metric in
          Text(metric.rawValue).tag(metric)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 220)

      Spacer()

      Button(action: { viewModel.refresh() }) {
        Label(L10n.Common.refresh.localized, systemImage: "arrow.clockwise")
      }
    }
    .cardStyle()
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      loadingView
    } else if viewModel.processes.isEmpty {
      emptyView
    } else {
      processTable
    }
  }

  private var loadingView: some View {
    VStack {
      Spacer()
      ProgressView()
      Text("process.loading")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .cardStyle()
  }

  private var emptyView: some View {
    VStack(spacing: Spacing.md) {
      Spacer()
      Image(systemName: "tray")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("process.empty")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .cardStyle()
  }

  private var processTable: some View {
    VStack(spacing: 0) {
      processTableHeader
      Divider()

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(viewModel.processes) { process in
            ProcessTableRow(
              process: process,
              highlightedMetric: viewModel.selectedMetric,
              isSelected: viewModel.selectedProcess?.id == process.id
            )
            .contentShape(Rectangle())
            .onTapGesture {
              viewModel.selectProcess(process)
            }

            Divider()
          }
        }
      }
    }
    .cardStyle()
  }

  private var processTableHeader: some View {
    HStack(spacing: 12) {
      sortButton("process.column.name", key: .name, enabled: true)
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

      Text("process.column.pid")
        .frame(width: 70, alignment: .trailing)

      sortButton("process.column.cpu", key: .cpu, enabled: true)
        .frame(width: 88, alignment: .trailing)

      sortButton("process.column.memory", key: .memory, enabled: true)
        .frame(width: 110, alignment: .trailing)

      Text("process.column.user")
        .frame(width: 120, alignment: .leading)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
  }

  @ViewBuilder
  private func sortButton(_ titleKey: String, key: ProcessSortKey, enabled: Bool) -> some View {
    if enabled {
      Button(action: { viewModel.updateSortKey(key) }) {
        HStack(spacing: 4) {
          Text(LocalizedStringKey(titleKey))
          if viewModel.sortKey == key {
            Image(systemName: "arrow.down")
              .font(.system(size: 10, weight: .semibold))
          }
        }
      }
      .buttonStyle(.plain)
    } else {
      Text(LocalizedStringKey(titleKey))
    }
  }
}

// MARK: - Table Row

private struct ProcessTableRow: View {
  let process: SystemProcessInfo
  let highlightedMetric: ProcessListMetricType
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(process.name)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

      Text("\(process.id)")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 70, alignment: .trailing)

      Text(String(format: "%.1f%%", process.cpuUsage))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(highlightedMetric == .cpu ? cpuColor(process.cpuUsage) : .primary)
        .frame(width: 88, alignment: .trailing)

      Text(formatBytes(process.memoryUsage))
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(highlightedMetric == .memory ? memoryColor(process.memoryUsage) : .primary)
        .frame(width: 110, alignment: .trailing)

      Text(process.user)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 120, alignment: .leading)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.vertical, Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: Radius.md)
        .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
    )
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, 2)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    if mb < 1 {
      return String(format: "%.0f KB", Double(bytes) / 1024)
    }
    if mb > 1024 {
      return String(format: "%.1f GB", mb / 1024)
    }
    return String(format: "%.1f MB", mb)
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
}

// MARK: - Inspector

private struct ProcessInspectorPane: View {
  let process: SystemProcessInfo?
  let history: [ProcessSnapshot]
  let onKill: () -> Void
  let onClearSelection: () -> Void

  var body: some View {
    Group {
      if let process {
        ProcessDetailDrawer(
          process: process,
          history: history,
          onKill: onKill,
          onClose: onClearSelection,
          showsCloseButton: true,
          embedded: true
        )
      } else {
        VStack(alignment: .leading, spacing: Spacing.md) {
          Image(systemName: "sidebar.right")
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
          Text("process.details.empty.title".localized)
            .font(.headline)
          Text("process.details.empty.body".localized)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.lg)
        .cardStyle()
      }
    }
  }
}

#Preview {
  ProcessMonitorView(
    selection: .constant(.processMonitor),
    selectedMetric: .constant(.cpu)
  )
}
