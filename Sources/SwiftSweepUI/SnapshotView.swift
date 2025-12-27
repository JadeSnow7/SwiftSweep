import SwiftUI
import UniformTypeIdentifiers

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct SnapshotView: View {
  @StateObject private var viewModel = SnapshotViewModel()
  @State private var showingExportSheet = false
  @State private var showingImportSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack {
        Text("Time Machine")
          .font(.largeTitle)
          .fontWeight(.bold)

        Spacer()

        Button(action: { Task { await viewModel.captureCurrent() } }) {
          Label("Capture Current", systemImage: "camera")
        }

        Button(action: { showingExportSheet = true }) {
          Label("Export...", systemImage: "square.and.arrow.up")
        }
        .disabled(viewModel.currentSnapshot == nil)

        Button(action: { showingImportSheet = true }) {
          Label("Import Baseline...", systemImage: "square.and.arrow.down")
        }
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor))

      Divider()

      // Content
      HStack(spacing: 0) {
        // Left: Current State
        VStack {
          Text("Current State")
            .font(.headline)
            .padding(.top)

          if let snapshot = viewModel.currentSnapshot {
            SnapshotSummaryView(snapshot: snapshot)
          } else {
            ContentUnavailableView(
              "No Snapshot", systemImage: "camera",
              description: Text("Capture current state to begin"))
          }
        }
        .frame(maxWidth: .infinity)

        Divider()

        // Right: Baseline / Diff
        VStack {
          if let diff = viewModel.diff {
            Text("Comparison vs Baseline")
              .font(.headline)
              .padding(.top)

            DiffView(diff: diff)
          } else if let baseline = viewModel.baselineSnapshot {
            Text("Baseline: \(baseline.timestamp.formatted())")
              .font(.headline)
              .padding(.top)

            SnapshotSummaryView(snapshot: baseline)
          } else {
            Text("Baseline")
              .font(.headline)
              .padding(.top)

            ContentUnavailableView(
              "No Baseline", systemImage: "doc.badge.clock",
              description: Text("Import a snapshot to compare"))
          }
        }
        .frame(maxWidth: .infinity)
      }
    }
    .fileExporter(
      isPresented: $showingExportSheet,
      document: SnapshotDocument(snapshot: viewModel.currentSnapshot),
      contentType: .json,
      defaultFilename:
        "swiftsweep-snapshot-\(Date().formatted(date: .numeric, time: .omitted)).json"
    ) { result in
      if case .failure(let error) = result {
        print("Export failed: \(error)")
      }
    }
    .fileImporter(
      isPresented: $showingImportSheet,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first {
        Task { await viewModel.importBaseline(from: url) }
      }
    }
  }
}

// MARK: - Subviews

struct SnapshotSummaryView: View {
  let snapshot: PackageSnapshot

  var body: some View {
    List {
      Section("Metadata") {
        LabeledContent("Timestamp", value: snapshot.timestamp.formatted())
        LabeledContent("Machine", value: snapshot.context.hostname)
        LabeledContent("OS", value: snapshot.context.os)
      }

      Section("Packages") {
        LabeledContent("Requested", value: "\(snapshot.manifest.requested.count)")
        LabeledContent("Transitive", value: "\(snapshot.manifest.transitive.count)")
        LabeledContent(
          "Total",
          value: "\(snapshot.manifest.requested.count + snapshot.manifest.transitive.count)")
      }
    }
    .listStyle(.inset)
  }
}

struct DiffView: View {
  let diff: SnapshotDiff

  var body: some View {
    List {
      if !diff.added.isEmpty {
        Section(header: Text("Added (\(diff.added.count))").foregroundColor(.green)) {
          ForEach(diff.added) { pkg in
            HStack {
              Text(pkg.displayName)
              Spacer()
              Text(pkg.version).foregroundStyle(.secondary)
            }
          }
        }
      }

      if !diff.removed.isEmpty {
        Section(header: Text("Removed (\(diff.removed.count))").foregroundColor(.red)) {
          ForEach(diff.removed) { pkg in
            HStack {
              Text(pkg.displayName)
              Spacer()
              Text(pkg.version).foregroundStyle(.secondary)
            }
          }
        }
      }

      if !diff.changed.isEmpty {
        Section(header: Text("Changed (\(diff.changed.count))").foregroundColor(.orange)) {
          ForEach(diff.changed, id: \.new.id) { change in
            VStack(alignment: .leading) {
              Text(change.new.displayName)
              HStack {
                Text(change.old.version).strikethrough().foregroundStyle(.red)
                Image(systemName: "arrow.right").font(.caption)
                Text(change.new.version).foregroundStyle(.green)
              }
              .font(.caption)
            }
          }
        }
      }

      if diff.added.isEmpty && diff.removed.isEmpty && diff.changed.isEmpty {
        Text("Snapshots are identical")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding()
      }
    }
    .listStyle(.inset)
  }
}

// MARK: - ViewModel

@MainActor
class SnapshotViewModel: ObservableObject {
  @Published var currentSnapshot: PackageSnapshot?
  @Published var baselineSnapshot: PackageSnapshot?

  var diff: SnapshotDiff? {
    guard let current = currentSnapshot, let baseline = baselineSnapshot else { return nil }
    return SnapshotService.shared.compareSnapshot(current: current, baseline: baseline)
  }

  func captureCurrent() async {
    do {
      self.currentSnapshot = try await SnapshotService.shared.exportSnapshot()
    } catch {
      print("Failed to capture snapshot: \(error)")
    }
  }

  func importBaseline(from url: URL) async {
    do {
      // Security scoped resource access
      guard url.startAccessingSecurityScopedResource() else { return }
      defer { url.stopAccessingSecurityScopedResource() }

      self.baselineSnapshot = try SnapshotService.shared.importFromFile(url: url)
    } catch {
      print("Failed to import snapshot: \(error)")
    }
  }
}

// MARK: - File Export

struct SnapshotDocument: FileDocument {
  static var readableContentTypes: [UTType] = [.json]

  var snapshot: PackageSnapshot?

  init(snapshot: PackageSnapshot?) {
    self.snapshot = snapshot
  }

  init(configuration: ReadConfiguration) throws {
    let data = try configuration.file.regularFileContents
    if let data = data {
      self.snapshot = try JSONDecoder().decode(PackageSnapshot.self, from: data)
    }
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601

    let data = try encoder.encode(snapshot)
    return FileWrapper(regularFileWithContents: data)
  }
}
