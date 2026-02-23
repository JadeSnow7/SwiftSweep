import Foundation

@MainActor
public func workspaceDocumentsEffects(_ action: AppAction, _ store: AppStore) async {
  guard case .workspaceDocuments(let documentsAction) = action else { return }

  switch documentsAction {
  case .setRoot, .startScan, .updateQuery, .applySavedSearch:
    await runDocumentScan(store)

  case .setFavorite(let path, let isFavorite):
    do {
      try await DocumentCatalogService.shared.setFavorite(path: path, isFavorite: isFavorite)
    } catch {
      store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
      return
    }
    await runDocumentScan(store)

  case .replaceTags(let path, let tags):
    do {
      try await DocumentCatalogService.shared.replaceTags(path: path, tags: tags)
    } catch {
      store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
      return
    }
    await runDocumentScan(store)

  case .loadSavedSearches:
    do {
      let saved = try await DocumentCatalogService.shared.loadSavedSearches()
      store.dispatch(.workspaceDocuments(.savedSearchesLoaded(saved)))
    } catch {
      store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
    }

  case .saveCurrentSearch(let name):
    let query = store.state.workspaceDocuments.query
    do {
      try await DocumentCatalogService.shared.saveSearch(name: name, query: query)
      let saved = try await DocumentCatalogService.shared.loadSavedSearches()
      store.dispatch(.workspaceDocuments(.savedSearchesLoaded(saved)))
    } catch {
      store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
    }

  case .deleteSavedSearch(let id):
    do {
      try await DocumentCatalogService.shared.deleteSearch(id: id)
      let saved = try await DocumentCatalogService.shared.loadSavedSearches()
      store.dispatch(.workspaceDocuments(.savedSearchesLoaded(saved)))
    } catch {
      store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
    }

  case .scanCompleted,
    .scanFailed,
    .selectRecord,
    .savedSearchesLoaded:
    break
  }
}

@MainActor
private func runDocumentScan(_ store: AppStore) async {
  guard let root = store.state.workspaceDocuments.rootURL else {
    store.dispatch(.workspaceDocuments(.scanFailed("Please select a folder first.")))
    return
  }

  do {
    let state = store.state.workspaceDocuments
    let page = try await DocumentCatalogService.shared.scan(
      root: root,
      query: state.query,
      page: state.page,
      pageSize: state.pageSize
    )
    store.dispatch(.workspaceDocuments(.scanCompleted(page)))
  } catch {
    store.dispatch(.workspaceDocuments(.scanFailed(error.localizedDescription)))
  }
}
