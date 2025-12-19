import SwiftUI
#if canImport(SwiftSweepCore)
import SwiftSweepCore
#endif

// MARK: - InsightsView

/// Displays smart recommendations from the RecommendationEngine
struct InsightsView: View {
  @State private var recommendations: [Recommendation] = []
  @State private var isLoading = false
  @State private var error: String?
  @State private var selectedRecommendation: Recommendation?
  @State private var showActionSheet = false
  @State private var actionInProgress = false
  @State private var actionResult: ActionResult?
  @State private var showBatchCleanup = false

  var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      Divider()

      // Content
      if isLoading {
        loadingView
      } else if let error = error {
        errorView(error)
      } else if recommendations.isEmpty {
        emptyStateView
      } else {
        recommendationsList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      await loadRecommendations()
    }
    .sheet(isPresented: $showActionSheet) {
      if let rec = selectedRecommendation {
        ActionConfirmationSheet(
          recommendation: rec,
          isPresented: $showActionSheet,
          onComplete: { result in
            actionResult = result
            // Refresh after action
            Task { await loadRecommendations() }
          }
        )
      }
    }
    .alert(item: $actionResult) { result in
      Alert(
        title: Text(result.success ? "Success" : "Error"),
        message: Text(result.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .sheet(isPresented: $showBatchCleanup) {
      BatchCleanupSheet(
        recommendations: cleanableRecommendations,
        isPresented: $showBatchCleanup,
        onComplete: { result in
          actionResult = result
          Task { await loadRecommendations() }
        }
      )
    }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Smart Insights")
          .font(.title.bold())
        Text("Personalized recommendations for your Mac")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()

      if let total = totalPotentialSavings {
        VStack(alignment: .trailing) {
          Text(formatBytes(total))
            .font(.title2.bold())
            .foregroundColor(.green)
          Text("potential savings")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.trailing)
      }

      // Clean All button
      if hasCleanableRecommendations {
        Button(action: { showBatchCleanup = true }) {
          Label("Clean All", systemImage: "trash")
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isLoading)
      }

      Button(action: { Task { await loadRecommendations() } }) {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(isLoading)
    }
    .padding()
  }

  private var totalPotentialSavings: Int64? {
    let total = recommendations.compactMap { $0.estimatedReclaimBytes }.reduce(0, +)
    return total > 0 ? total : nil
  }

  private var hasCleanableRecommendations: Bool {
    recommendations.contains { rec in
      rec.actions.contains { $0.type == .cleanupTrash || $0.type == .cleanupDelete }
    }
  }

  private var cleanableRecommendations: [Recommendation] {
    recommendations.filter { rec in
      rec.actions.contains { $0.type == .cleanupTrash || $0.type == .cleanupDelete }
    }
  }

  // MARK: - Loading View

  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
      Text("Analyzing your system...")
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Error View

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.orange)
      Text("Error")
        .font(.headline)
      Text(message)
        .foregroundColor(.secondary)
      Button("Try Again") {
        Task { await loadRecommendations() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundColor(.green)
      Text("All Good!")
        .font(.title2.bold())
      Text("No recommendations at this time.\nYour system is in great shape.")
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Recommendations List

  private var recommendationsList: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(recommendations) { recommendation in
          RecommendationCard(
            recommendation: recommendation,
            onAction: {
              selectedRecommendation = recommendation
              showActionSheet = true
            }
          )
        }
      }
      .padding()
    }
  }

  // MARK: - Data Loading

  private func loadRecommendations() async {
    isLoading = true
    error = nil

    do {
      let results = try await RecommendationEngine.shared.evaluateWithSystemContext()
      await MainActor.run {
        self.recommendations = results
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.error = error.localizedDescription
        self.isLoading = false
      }
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.0f MB", mb)
  }
}

// MARK: - Action Result

struct ActionResult: Identifiable {
  let id = UUID()
  let success: Bool
  let message: String
}

// MARK: - Action Confirmation Sheet

struct ActionConfirmationSheet: View {
  let recommendation: Recommendation
  @Binding var isPresented: Bool
  let onComplete: (ActionResult) -> Void

  @State private var dryRun = true
  @State private var isExecuting = false
  @State private var previewPaths: [String] = []

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        VStack(alignment: .leading) {
          Text(recommendation.title)
            .font(.headline)
          if let bytes = recommendation.estimatedReclaimBytes {
            Text("Potential savings: \(formatBytes(bytes))")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
        Spacer()
        Button(action: { isPresented = false }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .font(.title2)
        }
        .buttonStyle(.plain)
      }
      .padding()

      Divider()

      // Preview list
      if !pathsToClean.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Files to be moved to Trash:")
            .font(.subheadline.bold())
            .padding(.horizontal)
            .padding(.top)

          List(pathsToClean.prefix(20), id: \.self) { path in
            HStack {
              Image(systemName: "doc")
                .foregroundColor(.secondary)
              Text((path as NSString).lastPathComponent)
                .lineLimit(1)
              Spacer()
              Text(pathSize(path))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .frame(height: 250)

          if pathsToClean.count > 20 {
            Text("... and \(pathsToClean.count - 20) more items")
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.horizontal)
          }
        }
      } else {
        VStack {
          Image(systemName: "info.circle")
            .font(.largeTitle)
            .foregroundColor(.blue)
          Text("No cleanup action available")
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Divider()

      // Actions
      HStack {
        Toggle("Preview only (dry run)", isOn: $dryRun)
          .toggleStyle(.checkbox)

        Spacer()

        Button("Cancel") {
          isPresented = false
        }
        .keyboardShortcut(.escape)

        Button(action: executeAction) {
          if isExecuting {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Text(dryRun ? "Preview" : "Move to Trash")
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(dryRun ? .blue : .orange)
        .disabled(pathsToClean.isEmpty || isExecuting)
      }
      .padding()
    }
    .frame(width: 500, height: 450)
  }

  private var pathsToClean: [String] {
    for action in recommendation.actions {
      if case .paths(let paths) = action.payload {
        return paths
      }
    }
    return []
  }

  private func pathSize(_ path: String) -> String {
    let size = calculatePathSize(path)
    return size > 0 ? formatBytes(size) : ""
  }

  private func calculatePathSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

    if isDir.boolValue {
      // Directory: recursively calculate size
      guard
        let enumerator = fm.enumerator(
          at: URL(fileURLWithPath: path),
          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
          options: []
        )
      else { return 0 }

      var total: Int64 = 0
      for case let fileURL as URL in enumerator {
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          let isFile = values.isRegularFile, isFile,
          let size = values.fileSize
        {
          total += Int64(size)
        }
      }
      return total
    } else {
      // File: use attributes
      if let attrs = try? fm.attributesOfItem(atPath: path),
        let size = attrs[.size] as? Int64
      {
        return size
      }
      return 0
    }
  }

  private func executeAction() {
    isExecuting = true

    Task {
      do {
        if dryRun {
          // Just show preview
          await MainActor.run {
            isExecuting = false
            onComplete(
              ActionResult(
                success: true,
                message: "Dry run complete. \(pathsToClean.count) items would be moved to Trash."
              ))
            isPresented = false
          }
        } else {
          // Actually move to trash
          var movedCount = 0
          var totalSize: Int64 = 0
          let fm = FileManager.default

          for path in pathsToClean {
            let url = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: path) {
              // Get accurate size before deletion (recursive for directories)
              totalSize += calculatePathSize(path)

              try fm.trashItem(at: url, resultingItemURL: nil)
              movedCount += 1
            }
          }

          let finalMovedCount = movedCount
          let finalTotalSize = totalSize
          await MainActor.run {
            isExecuting = false

            // Log the cleanup action
            ActionLogger.shared.logCleanup(
              ruleId: recommendation.id,
              paths: pathsToClean,
              totalSize: finalTotalSize,
              success: true,
              itemsMoved: finalMovedCount
            )

            onComplete(
              ActionResult(
                success: true,
                message:
                  "Moved \(finalMovedCount) items to Trash (est. \(formatBytes(finalTotalSize))). Empty Trash to free space."
              ))
            isPresented = false
          }
        }
      } catch {
        await MainActor.run {
          isExecuting = false
          onComplete(
            ActionResult(
              success: false,
              message: "Error: \(error.localizedDescription)"
            ))
        }
      }
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    if mb >= 1 {
      return String(format: "%.0f MB", mb)
    }
    let kb = Double(bytes) / 1_000
    return String(format: "%.0f KB", kb)
  }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
  let recommendation: Recommendation
  var onAction: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header row
      HStack(alignment: .top) {
        severityIcon
          .font(.title2)

        VStack(alignment: .leading, spacing: 4) {
          Text(recommendation.title)
            .font(.headline)
          Text(recommendation.summary)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()

        if let bytes = recommendation.estimatedReclaimBytes {
          VStack(alignment: .trailing) {
            Text(formatBytes(bytes))
              .font(.title3.bold())
              .foregroundColor(.blue)
            Text("potential savings")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      // Evidence tags
      if !recommendation.evidence.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(recommendation.evidence.prefix(4), id: \.label) { evidence in
              EvidenceTag(evidence: evidence)
            }
          }
        }
      }

      // Footer with metadata and action button
      HStack {
        Label(recommendation.risk.displayName, systemImage: "shield")
          .font(.caption)
          .foregroundColor(riskColor)

        Label(recommendation.confidence.displayName, systemImage: "checkmark.seal")
          .font(.caption)
          .foregroundColor(.secondary)

        Spacer()

        // Action buttons
        if hasCleanupAction {
          Button(action: { onAction?() }) {
            Label("Clean", systemImage: "trash")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }

        if hasOpenFinderAction {
          Button(action: openInFinder) {
            Label("Show", systemImage: "folder")
          }
          .controlSize(.small)
        }
      }
    }
    .padding()
    .background(cardBackground)
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(borderColor, lineWidth: 1)
    )
  }

  private var hasCleanupAction: Bool {
    recommendation.actions.contains { $0.type == .cleanupTrash || $0.type == .cleanupDelete }
  }

  private var hasOpenFinderAction: Bool {
    recommendation.actions.contains { $0.type == .openFinder }
  }

  private func openInFinder() {
    for action in recommendation.actions {
      if action.type == .openFinder, case .paths(let paths) = action.payload,
        let first = paths.first
      {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: first)
        break
      }
    }
  }

  private var severityIcon: some View {
    Group {
      switch recommendation.severity {
      case .critical:
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.red)
      case .warning:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
      case .info:
        Image(systemName: "info.circle.fill")
          .foregroundColor(.blue)
      }
    }
  }

  private var cardBackground: some View {
    Group {
      switch recommendation.severity {
      case .critical:
        Color.red.opacity(0.05)
      case .warning:
        Color.orange.opacity(0.05)
      case .info:
        Color.blue.opacity(0.05)
      }
    }
  }

  private var borderColor: Color {
    switch recommendation.severity {
    case .critical: return .red.opacity(0.3)
    case .warning: return .orange.opacity(0.3)
    case .info: return .blue.opacity(0.2)
    }
  }

  private var riskColor: Color {
    switch recommendation.risk {
    case .low: return .green
    case .medium: return .orange
    case .high: return .red
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 {
      return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.0f MB", mb)
  }
}

// MARK: - Evidence Tag

struct EvidenceTag: View {
  let evidence: Evidence

  var body: some View {
    HStack(spacing: 4) {
      evidenceIcon
        .font(.caption)
      Text("\(evidence.label): \(evidence.value)")
        .font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(6)
  }

  private var evidenceIcon: some View {
    Group {
      switch evidence.kind {
      case .path:
        Image(systemName: "folder")
      case .metric:
        Image(systemName: "chart.bar")
      case .metadata:
        Image(systemName: "info.circle")
      case .aggregate:
        Image(systemName: "sum")
      }
    }
  }
}

// MARK: - Batch Cleanup Sheet

struct BatchCleanupSheet: View {
  let recommendations: [Recommendation]
  @Binding var isPresented: Bool
  let onComplete: (ActionResult) -> Void

  @State private var isExecuting = false
  @State private var progress: Double = 0
  @State private var currentItem = ""

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Clean All Recommendations")
          .font(.headline)
        Spacer()
        Button(action: { isPresented = false }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .font(.title2)
        }
        .buttonStyle(.plain)
      }
      .padding()

      Divider()

      // Summary
      VStack(alignment: .leading, spacing: 12) {
        Text("\(recommendations.count) recommendations with cleanable items")
          .font(.subheadline)

        let totalSize = recommendations.compactMap { $0.estimatedReclaimBytes }.reduce(0, +)
        Text("Potential savings: \(formatBytes(totalSize))")
          .font(.title2.bold())
          .foregroundColor(.green)

        // List of recommendations
        List(recommendations, id: \.id) { rec in
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text(rec.title)
            Spacer()
            if let size = rec.estimatedReclaimBytes {
              Text(formatBytes(size))
                .foregroundColor(.secondary)
            }
          }
        }
        .frame(height: 200)

        if isExecuting {
          VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
            Text(currentItem)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }
      }
      .padding()

      Divider()

      // Actions
      HStack {
        Spacer()
        Button("Cancel") { isPresented = false }
          .keyboardShortcut(.escape)

        Button(action: executeCleanup) {
          if isExecuting {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Text("Clean All")
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isExecuting)
      }
      .padding()
    }
    .frame(width: 500, height: 450)
  }

  private func executeCleanup() {
    isExecuting = true
    progress = 0

    Task {
      var totalMoved = 0
      var totalFreed: Int64 = 0
      let fm = FileManager.default

      // Collect all paths
      var allPaths: [String] = []
      for rec in recommendations {
        for action in rec.actions {
          if action.type == .cleanupTrash || action.type == .cleanupDelete,
            case .paths(let paths) = action.payload
          {
            allPaths.append(contentsOf: paths)
          }
        }
      }

      let total = allPaths.count
      for (index, path) in allPaths.enumerated() {
        await MainActor.run {
          currentItem = (path as NSString).lastPathComponent
          progress = Double(index) / Double(max(total, 1))
        }

        if fm.fileExists(atPath: path) {
          do {
            if let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64
            {
              totalFreed += size
            }
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            totalMoved += 1
          } catch {
            // Skip failed items
          }
        }
      }

      let finalTotalMoved = totalMoved
      let finalTotalFreed = totalFreed
      await MainActor.run {
        isExecuting = false
        onComplete(
          ActionResult(
            success: true,
            message:
              "Moved \(finalTotalMoved) items to Trash. Freed \(formatBytes(finalTotalFreed))."
          ))
        isPresented = false
      }
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(bytes) / 1_000_000
    return String(format: "%.0f MB", mb)
  }
}

#Preview {
  InsightsView()
    .frame(width: 800, height: 600)
}
