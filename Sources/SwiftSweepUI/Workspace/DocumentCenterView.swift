import AppKit
import SwiftUI
import UniformTypeIdentifiers

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

public struct DocumentCenterView: View {
  @EnvironmentObject private var store: AppStore

  @State private var showFolderPicker = false
  @State private var searchText = ""
  @State private var favoritesOnly = false
  @State private var showSaveSearchSheet = false
  @State private var saveSearchName = ""

  private var state: WorkspaceDocumentsState {
    store.state.workspaceDocuments
  }

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      HSplitView {
        savedSearchPanel
          .frame(minWidth: 220, maxWidth: 300)

        documentsPanel
          .frame(minWidth: 460)

        if let selectedURL {
          WorkspaceQuickLookPreview(url: selectedURL)
            .frame(minWidth: 260, maxWidth: 420)
        }
      }
    }
    .onAppear {
      searchText = state.query.text
      favoritesOnly = state.query.favoritesOnly
      store.dispatch(.workspaceDocuments(.loadSavedSearches))
    }
    .fileImporter(
      isPresented: $showFolderPicker,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      store.dispatch(.workspaceDocuments(.setRoot(url)))
    }
    .sheet(isPresented: $showSaveSearchSheet) {
      saveSearchSheet
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Document Center")
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
        store.dispatch(.workspaceDocuments(.startScan))
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(state.rootURL == nil)

      Button {
        showSaveSearchSheet = true
      } label: {
        Label("Save Smart Folder", systemImage: "bookmark")
      }
      .disabled(state.rootURL == nil)
    }
    .padding(12)
  }

  private var savedSearchPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Smart Folders")
          .font(.headline)
        Spacer()
        Button {
          store.dispatch(.workspaceDocuments(.loadSavedSearches))
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
      }

      List(state.savedSearches, id: \.id) { search in
        HStack {
          Button {
            store.dispatch(.workspaceDocuments(.applySavedSearch(search.id)))
            store.dispatch(.workspaceDocuments(.startScan))
            searchText = search.query.text
            favoritesOnly = search.query.favoritesOnly
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(search.name)
                .lineLimit(1)
              Text(search.query.text.isEmpty ? "All documents" : search.query.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .buttonStyle(.plain)

          Spacer()

          Button(role: .destructive) {
            store.dispatch(.workspaceDocuments(.deleteSavedSearch(search.id)))
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
        }
      }
      .listStyle(.inset)

      Spacer()
    }
    .padding(8)
  }

  private var documentsPanel: some View {
    VStack(spacing: 8) {
      filterBar

      if case .scanning = state.phase {
        ProgressView("Scanning documents...")
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
        List(
          state.records,
          selection: Binding(
            get: { state.selectedRecordID },
            set: { store.dispatch(.workspaceDocuments(.selectRecord($0))) }
          )
        ) { record in
          HStack(spacing: 8) {
            Image(systemName: "doc.text")
              .frame(width: 18)
              .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
              Text(record.name)
                .lineLimit(1)
              HStack(spacing: 6) {
                Text(record.fileExtension.uppercased())
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                if !record.tags.isEmpty {
                  Text(record.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }
            }

            Spacer()

            Button {
              store.dispatch(
                .workspaceDocuments(
                  .setFavorite(path: record.path, isFavorite: !record.isFavorite)
                )
              )
            } label: {
              Image(systemName: record.isFavorite ? "star.fill" : "star")
                .foregroundStyle(record.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
          }
          .contextMenu {
            Button("Reveal in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)])
            }
            Button("Toggle Favorite") {
              store.dispatch(
                .workspaceDocuments(
                  .setFavorite(path: record.path, isFavorite: !record.isFavorite)
                )
              )
            }
            Button("Tag: important") {
              var tags = record.tags
              if tags.contains("important") {
                tags.removeAll { $0 == "important" }
              } else {
                tags.append("important")
              }
              store.dispatch(.workspaceDocuments(.replaceTags(path: record.path, tags: tags)))
            }
          }
        }
        .listStyle(.inset)
      }

      HStack {
        Text("\(state.totalCount) documents")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 8)
    }
    .padding(8)
  }

  private var filterBar: some View {
    HStack(spacing: 10) {
      TextField("Search name/path", text: $searchText)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          applyQueryChanges()
        }

      Toggle("Favorites", isOn: $favoritesOnly)
        .toggleStyle(.checkbox)
        .onChange(of: favoritesOnly) { _ in
          applyQueryChanges()
        }

      Button("Apply") {
        applyQueryChanges()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 8)
  }

  private var selectedURL: URL? {
    guard let id = state.selectedRecordID,
      let record = state.records.first(where: { $0.id == id })
    else {
      return nil
    }

    return URL(fileURLWithPath: record.path)
  }

  private var saveSearchSheet: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $saveSearchName)
      }
      .navigationTitle("Save Smart Folder")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            showSaveSearchSheet = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let trimmed = saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            store.dispatch(.workspaceDocuments(.saveCurrentSearch(name: trimmed)))
            saveSearchName = ""
            showSaveSearchSheet = false
          }
        }
      }
    }
    .frame(minWidth: 420, minHeight: 180)
  }

  private func applyQueryChanges() {
    var query = state.query
    query.text = searchText
    query.favoritesOnly = favoritesOnly
    store.dispatch(.workspaceDocuments(.updateQuery(query)))
    store.dispatch(.workspaceDocuments(.startScan))
  }
}
