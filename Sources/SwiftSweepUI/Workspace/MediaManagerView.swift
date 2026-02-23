import SwiftUI
import UniformTypeIdentifiers

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

public struct MediaManagerView: View {
  public enum Tab: String, CaseIterable {
    case library = "Library"
    case duplicates = "Duplicates"
  }

  @EnvironmentObject private var store: AppStore
  @State private var selectedTab: Tab
  @State private var showFolderPicker = false

  private var state: WorkspaceMediaState {
    store.state.workspaceMedia
  }

  public init(initialTab: Tab = .library) {
    _selectedTab = State(initialValue: initialTab)
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      Picker("", selection: $selectedTab) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 12)
      .padding(.top, 8)

      if selectedTab == .library {
        libraryView
      } else {
        MediaAnalyzerView()
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Media Manager")
          .font(.title3.bold())

        if let root = state.rootURL {
          Text(root.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Text("No folder selected")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button {
        showFolderPicker = true
      } label: {
        Label("Select Folder", systemImage: "folder")
      }

      Button {
        store.dispatch(.workspaceMedia(.startScan))
      } label: {
        Label("Scan", systemImage: "magnifyingglass")
      }
      .buttonStyle(.borderedProminent)
      .disabled(state.rootURL == nil)
    }
    .padding(12)
    .fileImporter(
      isPresented: $showFolderPicker,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      store.dispatch(.workspaceMedia(.setRoot(url)))
    }
  }

  private var libraryView: some View {
    VStack(spacing: 8) {
      filterBar

      if case .scanning = state.phase {
        ProgressView("Scanning media files...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if case .error(let message) = state.phase {
        VStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(message)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(filteredItems) { item in
          HStack(spacing: 10) {
            Image(systemName: icon(for: item.kind))
              .frame(width: 18)
              .foregroundStyle(item.kind == .video ? .purple : item.kind == .audio ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
              Text(URL(fileURLWithPath: item.path).lastPathComponent)
                .lineLimit(1)
              Text(item.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .listStyle(.inset)
      }
    }
    .padding(8)
  }

  private var filterBar: some View {
    HStack(spacing: 16) {
      HStack(spacing: 8) {
        ForEach(WorkspaceMediaKind.allCases, id: \.self) { kind in
          let isSelected = state.selectedKinds.isEmpty || state.selectedKinds.contains(kind)
          Button {
            var next = state.selectedKinds
            if isSelected {
              next.remove(kind)
            } else {
              next.insert(kind)
            }
            store.dispatch(.workspaceMedia(.setKindFilter(next)))
          } label: {
            Label(kind.rawValue.capitalized, systemImage: icon(for: kind))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
        }
      }

      Spacer()

      HStack(spacing: 8) {
        Text("Min Size")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(
          value: Binding(
            get: { Double(state.minSize) / 1_000_000 },
            set: { store.dispatch(.workspaceMedia(.setMinSize(Int64($0 * 1_000_000)))) }
          ),
          in: 0...2_000,
          step: 50
        )
        .frame(width: 220)
        Text("\(Int(Double(state.minSize) / 1_000_000)) MB")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
  }

  private var filteredItems: [MediaLibraryItem] {
    state.items.filter { item in
      let kindPass = state.selectedKinds.isEmpty || state.selectedKinds.contains(item.kind)
      let sizePass = item.size >= state.minSize
      return kindPass && sizePass
    }
    .sorted {
      let l = $0.modifiedAt ?? .distantPast
      let r = $1.modifiedAt ?? .distantPast
      return l > r
    }
  }

  private func icon(for kind: WorkspaceMediaKind) -> String {
    switch kind {
    case .image:
      return "photo"
    case .video:
      return "video"
    case .audio:
      return "waveform"
    }
  }
}
