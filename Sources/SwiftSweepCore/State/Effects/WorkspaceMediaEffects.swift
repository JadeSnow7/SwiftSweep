import Foundation

@MainActor
public func workspaceMediaEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .workspaceMedia(let mediaAction) = action else { return }

  switch mediaAction {
  case .setRoot, .startScan:
    guard let root = store.state.workspaceMedia.rootURL else {
      store.dispatch(.workspaceMedia(.scanFailed("Please select a folder first.")))
      return
    }

    let items = await WorkspaceMediaService.shared.scanLibrary(root: root)
    store.dispatch(.workspaceMedia(.scanCompleted(items)))

  case .scanCompleted,
    .scanFailed,
    .setKindFilter,
    .setMinSize,
    .toggleDuplicatesView:
    break
  }
}
