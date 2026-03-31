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
  @State private var pathInput: String = ""

  private var state: WorkspaceFileManagerState {
    store.state.workspaceFileManager
  }

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      // Path bar — stays in content so layout is unambiguous
      HStack {
        TextField("Path", text: $pathInput)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            let url = URL(fileURLWithPath: pathInput)
            mode = .browser
            store.dispatch(.workspaceFileManager(.openLocation(url, pane: state.activePane)))
          }
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.sm)
      .onAppear { pathInput = activeTab?.locationURL.path ?? "" }
      .onChange(of: activeTab?.locationURL.path) { newPath in
        pathInput = newPath ?? ""
      }

      Divider()

      Picker("", selection: $mode) {
        ForEach(Mode.allCases, id: \.self) { m in
          Text(m.rawValue).tag(m)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.sm)

      if case .error(let message) = state.phase {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(message)
            .font(.caption)
            .lineLimit(1)
          Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
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
    .navigationTitle("File Manager")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          if mode == .browser, let location = activeTab?.locationURL {
            store.dispatch(.workspaceFileManager(.openLocation(location, pane: state.activePane)))
          }
          store.dispatch(.workspaceFileManager(.refreshVolumes))
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button {
          mode = .browser
          store.dispatch(.workspaceFileManager(.toggleDualPane))
        } label: {
          Label(state.isDualPane ? "Single Pane" : "Dual Pane", systemImage: "rectangle.split.2x1")
        }

        Button {
          mode = .browser
          store.dispatch(.workspaceFileManager(.createTab(pane: state.activePane, location: nil)))
        } label: {
          Label("New Tab", systemImage: "plus.rectangle.on.rectangle")
        }

        Divider()

        Button { performTransfer(type: .copy) } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }

        Button { performTransfer(type: .move) } label: {
          Label("Move", systemImage: "arrow.right.doc.on.clipboard")
        }

        Button { performRename() } label: {
          Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) { performTrash() } label: {
          Label("Trash", systemImage: "trash")
        }
      }

      ToolbarItem(placement: .automatic) {
        Button {
          store.dispatch(.workspaceFileManager(.showQueueSheet(true)))
        } label: {
          Label("Queue", systemImage: "list.bullet.rectangle")
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
        onPause: { id in store.dispatch(.workspaceFileManager(.pauseOperation(id))) },
        onResume: { id in store.dispatch(.workspaceFileManager(.resumeOperation(id))) },
        onCancel: { id in store.dispatch(.workspaceFileManager(.cancelOperation(id))) }
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
