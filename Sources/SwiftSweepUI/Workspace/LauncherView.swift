import AppInventoryUI
import AppKit
import SwiftUI
import UniformTypeIdentifiers

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

public struct LauncherView: View {
  @EnvironmentObject private var store: AppStore
  @State private var showFolderPicker = false

  private var state: WorkspaceLauncherState {
    store.state.workspaceLauncher
  }

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      pinnedHeader
      Divider()

      ApplicationsView(
        defaults: UserDefaults.standard,
        onUninstallRequested: { app in
          store.dispatch(.navigation(.requestUninstall(app.url)))
        },
        onPinRequested: { app in
          store.dispatch(
            .workspaceLauncher(
              .addPinnedApp(path: app.url.path, title: app.displayName)
            )
          )
          store.dispatch(.workspaceLauncher(.savePinned))
        }
      )
    }
    .onAppear {
      store.dispatch(.workspaceLauncher(.loadPinned))
    }
    .fileImporter(
      isPresented: $showFolderPicker,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      store.dispatch(.workspaceLauncher(.addPinnedFolder(url)))
      store.dispatch(.workspaceLauncher(.savePinned))
    }
  }

  private var pinnedHeader: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Pinned")
          .font(.headline)

        Spacer()

        Button {
          showFolderPicker = true
        } label: {
          Label("Pin Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.bordered)
      }

      if case .error(let message) = state.phase {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(message)
            .font(.caption)
          Spacer()
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(state.pinnedItems) { item in
            pinnedItemCard(item)
          }
        }
      }
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func pinnedItemCard(_ item: PinnedLaunchItem) -> some View {
    let icon = item.type == .app ? "app.fill" : "folder.fill"

    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .foregroundStyle(item.type == .app ? .blue : .orange)
        Text(item.title)
          .lineLimit(1)
          .font(.caption.bold())
      }

      Text(item.path)
        .lineLimit(1)
        .font(.caption2)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Button("Open") {
          NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
        .buttonStyle(.bordered)

        Button("Reveal") {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
          store.dispatch(.workspaceLauncher(.removePinned(item.id)))
          store.dispatch(.workspaceLauncher(.savePinned))
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(10)
    .frame(width: 280, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}
