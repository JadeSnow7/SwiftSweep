import SwiftUI

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

public struct FileManagerView: View {
  private enum Mode: String, CaseIterable {
    case browser = "Browser"
    case spaceAnalysis = "Space Analysis"
  }

  @EnvironmentObject private var store: AppStore
  @State private var mode: Mode = .browser

  private var state: WorkspaceFileManagerState {
    store.state.workspaceFileManager
  }

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      FileManagerToolbar(
        currentLocation: activeTab?.locationURL,
        isDualPane: state.isDualPane,
        onToggleDualPane: {
          store.dispatch(.workspaceFileManager(.toggleDualPane))
        },
        onGoToPath: { url in
          mode = .browser
          store.dispatch(.workspaceFileManager(.openLocation(url, pane: state.activePane)))
        },
        onRefresh: {
          if mode == .spaceAnalysis {
            return
          }

          if let location = activeTab?.locationURL {
            store.dispatch(.workspaceFileManager(.openLocation(location, pane: state.activePane)))
          }
          store.dispatch(.workspaceFileManager(.refreshVolumes))
        },
        onShowQueue: {
          store.dispatch(.workspaceFileManager(.showQueueSheet(true)))
        },
        onNewTab: {
          mode = .browser
          store.dispatch(.workspaceFileManager(.createTab(pane: state.activePane, location: nil)))
        },
        onCopy: {
          performTransfer(type: .copy)
        },
        onMove: {
          performTransfer(type: .move)
        },
        onRename: {
          performRename()
        },
        onTrash: {
          performTrash()
        }
      )

      Divider()

      Picker("", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)

      if case .error(let message) = state.phase {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(message)
            .font(.caption)
            .lineLimit(1)
          Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        Divider()
      }

      if mode == .spaceAnalysis {
        AnalyzeView()
      } else {
        HSplitView {
          FileManagerSidebar(
            favorites: state.favorites,
            recentLocations: state.recentLocations,
            mountedVolumes: state.mountedVolumes,
            onOpen: { url in
              store.dispatch(.workspaceFileManager(.openLocation(url, pane: state.activePane)))
            }
          )
          .frame(minWidth: 180, maxWidth: 260)

          paneColumn(.left)
            .frame(minWidth: 320)

          if state.isDualPane {
            paneColumn(.right)
              .frame(minWidth: 320)
          }

          if let previewURL = state.previewURL {
            WorkspaceQuickLookPreview(url: previewURL)
              .frame(minWidth: 220, maxWidth: 360)
          }
        }
      }
    }
    .onAppear {
      store.dispatch(.workspaceFileManager(.boot))
    }
    .sheet(
      isPresented: Binding(
        get: { state.showQueueSheet },
        set: { store.dispatch(.workspaceFileManager(.showQueueSheet($0))) }
      )
    ) {
      FileOperationQueueSheet(
        items: state.queueItems,
        onPause: { id in
          store.dispatch(.workspaceFileManager(.pauseOperation(id)))
        },
        onResume: { id in
          store.dispatch(.workspaceFileManager(.resumeOperation(id)))
        },
        onCancel: { id in
          store.dispatch(.workspaceFileManager(.cancelOperation(id)))
        }
      )
    }
  }

  private func paneColumn(_ pane: WorkspacePane) -> some View {
    let paneState = pane == .left ? state.leftPane : state.rightPane

    return FileManagerPaneView(
      pane: pane,
      paneState: paneState,
      isActive: state.activePane == pane,
      onSelectTab: { tabID in
        store.dispatch(.workspaceFileManager(.setActivePane(pane)))
        store.dispatch(.workspaceFileManager(.selectTab(pane: pane, tabID: tabID)))
      },
      onCreateTab: {
        store.dispatch(.workspaceFileManager(.setActivePane(pane)))
        store.dispatch(.workspaceFileManager(.createTab(pane: pane, location: nil)))
      },
      onCloseTab: { tabID in
        store.dispatch(.workspaceFileManager(.closeTab(pane: pane, tabID: tabID)))
      },
      onOpenLocation: { url in
        store.dispatch(.workspaceFileManager(.setActivePane(pane)))
        store.dispatch(.workspaceFileManager(.openLocation(url, pane: pane)))
      },
      onSelectItems: { tabID, selectedIDs in
        store.dispatch(.workspaceFileManager(.setActivePane(pane)))
        store.dispatch(
          .workspaceFileManager(
            .updateSelection(pane: pane, tabID: tabID, itemIDs: selectedIDs)
          )
        )
      },
      onSetPreview: { url in
        store.dispatch(.workspaceFileManager(.setPreview(url)))
      },
      onSetSort: { tabID, sort in
        store.dispatch(.workspaceFileManager(.setSort(pane: pane, tabID: tabID, sort: sort)))
      }
    )
    .contentShape(Rectangle())
    .onTapGesture {
      store.dispatch(.workspaceFileManager(.setActivePane(pane)))
    }
  }

  private var activeTab: WorkspaceTabState? {
    switch state.activePane {
    case .left:
      return state.leftPane.selectedTab
    case .right:
      return state.rightPane.selectedTab
    }
  }

  private var inactiveTabLocation: URL? {
    if !state.isDualPane {
      return activeTab?.locationURL
    }

    switch state.activePane {
    case .left:
      return state.rightPane.selectedTab?.locationURL
    case .right:
      return state.leftPane.selectedTab?.locationURL
    }
  }

  private var selectedSourceURLs: [URL] {
    guard let tab = activeTab else { return [] }
    let selected = tab.items.filter { tab.selectedItemIDs.contains($0.id) }
    return selected.map(\.url)
  }

  private func performTransfer(type: FileOperationType) {
    let sources = selectedSourceURLs
    guard !sources.isEmpty else { return }

    store.dispatch(
      .workspaceFileManager(
        .enqueueOperation(
          type: type,
          sources: sources,
          destination: inactiveTabLocation,
          conflictPolicy: .keepBoth
        )
      )
    )
  }

  private func performRename() {
    guard let source = selectedSourceURLs.first else { return }

    let ext = source.pathExtension
    let stem = source.deletingPathExtension().lastPathComponent
    let name = ext.isEmpty ? "\(stem)-renamed" : "\(stem)-renamed.\(ext)"
    let destination = source.deletingLastPathComponent().appendingPathComponent(name)

    store.dispatch(
      .workspaceFileManager(
        .enqueueOperation(
          type: .rename,
          sources: [source],
          destination: destination,
          conflictPolicy: .keepBoth
        )
      )
    )
  }

  private func performTrash() {
    let sources = selectedSourceURLs
    guard !sources.isEmpty else { return }

    store.dispatch(
      .workspaceFileManager(
        .enqueueOperation(
          type: .trash,
          sources: sources,
          destination: nil,
          conflictPolicy: .keepBoth
        )
      )
    )
  }
}
