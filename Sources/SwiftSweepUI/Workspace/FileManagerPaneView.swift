import AppKit
import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct FileManagerPaneView: View {
  let pane: WorkspacePane
  let paneState: WorkspacePaneState
  let isActive: Bool
  let onSelectTab: (UUID) -> Void
  let onCreateTab: () -> Void
  let onCloseTab: (UUID) -> Void
  let onOpenLocation: (URL) -> Void
  let onSelectItems: (UUID, Set<String>) -> Void
  let onSetPreview: (URL?) -> Void
  let onSetSort: (UUID, WorkspaceSortDescriptor) -> Void

  private var selectedTab: WorkspaceTabState? {
    paneState.selectedTab
  }

  var body: some View {
    VStack(spacing: 0) {
      tabBar
      Divider()
      toolbar
      Divider()
      fileList
    }
    .background(isActive ? Color.accentColor.opacity(0.05) : Color.clear)
  }

  private var tabBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(paneState.tabs) { tab in
          HStack(spacing: 6) {
            Button {
              onSelectTab(tab.id)
            } label: {
              Text(tab.title.isEmpty ? tab.locationURL.path : tab.title)
                .lineLimit(1)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tab.id == paneState.selectedTabID ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if paneState.tabs.count > 1 {
              Button {
                onCloseTab(tab.id)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
        }

        Button {
          onCreateTab()
        } label: {
          Image(systemName: "plus")
            .font(.caption)
            .padding(4)
        }
        .buttonStyle(.borderless)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
  }

  private var toolbar: some View {
    HStack {
      Text(selectedTab?.locationURL.path ?? "")
        .font(.caption)
        .lineLimit(1)
      Spacer()

      Menu {
        sortMenuItem(field: .name, title: "Name")
        sortMenuItem(field: .size, title: "Size")
        sortMenuItem(field: .kind, title: "Type")
        sortMenuItem(field: .modifiedAt, title: "Modified")

        Divider()

        if let tab = selectedTab {
          Button(tab.sort.order == .ascending ? "Descending" : "Ascending") {
            onSetSort(
              tab.id,
              WorkspaceSortDescriptor(
                field: tab.sort.field,
                order: tab.sort.order == .ascending ? .descending : .ascending
              )
            )
          }
        }
      } label: {
        Label("Sort", systemImage: "arrow.up.arrow.down")
          .font(.caption)
      }
      .menuStyle(.borderlessButton)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  private var fileList: some View {
    Group {
      if let tab = selectedTab {
        List(
          tab.items,
          selection: Binding(
            get: { tab.selectedItemIDs },
            set: { newSelection in
              onSelectItems(tab.id, newSelection)
              if let firstID = newSelection.first,
                let item = tab.items.first(where: { $0.id == firstID })
              {
                onSetPreview(item.url)
              } else {
                onSetPreview(nil)
              }
            }
          )
        ) { item in
          HStack(spacing: 8) {
            Image(systemName: icon(for: item))
              .foregroundStyle(item.kind == .folder ? .blue : .secondary)
              .frame(width: 18)

            Text(item.url.lastPathComponent)
              .lineLimit(1)

            Spacer()

            if let size = item.size {
              Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture(count: 2) {
            if item.kind == .folder || item.kind == .volume {
              onOpenLocation(item.url)
            } else if item.kind == .app {
              NSWorkspace.shared.open(item.url)
            } else {
              onSetPreview(item.url)
            }
          }
          .contextMenu {
            Button("Reveal in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.kind == .app {
              Button("Open") {
                NSWorkspace.shared.open(item.url)
              }
            }
          }
        }
        .listStyle(.inset)
      } else {
        Text("No tab")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func sortMenuItem(field: WorkspaceSortField, title: String) -> some View {
    Button(title) {
      guard let tab = selectedTab else { return }
      onSetSort(tab.id, WorkspaceSortDescriptor(field: field, order: tab.sort.order))
    }
  }

  private func icon(for item: WorkspaceItem) -> String {
    switch item.kind {
    case .folder, .volume:
      return "folder"
    case .app:
      return "app.fill"
    case .file:
      return "doc"
    }
  }
}
