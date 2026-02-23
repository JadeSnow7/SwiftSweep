import Foundation

public actor WorkspaceMediaService {
  public static let shared = WorkspaceMediaService()

  private let scanner: MediaScanner

  public init(scanner: MediaScanner = .shared) {
    self.scanner = scanner
  }

  public func scanLibrary(root: URL) async -> [MediaLibraryItem] {
    let result = await scanner.scan(root: root, includeSubdirectories: true)

    return result.files.map { file in
      let kind: WorkspaceMediaKind
      switch file.type {
      case .image:
        kind = .image
      case .video:
        kind = .video
      case .audio:
        kind = .audio
      }

      let canonicalPath = WorkspacePath.canonicalize(url: file.url)
      let displayPath = WorkspacePath.displayPath(for: canonicalPath, under: root)

      return MediaLibraryItem(
        id: canonicalPath,
        path: displayPath,
        kind: kind,
        size: file.size,
        modifiedAt: file.modificationDate,
        createdAt: file.creationDate
      )
    }
  }
}
