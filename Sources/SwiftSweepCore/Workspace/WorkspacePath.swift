import Foundation

enum WorkspacePath {
  static func canonicalize(_ path: String) -> String {
    URL(fileURLWithPath: path)
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .path
  }

  static func canonicalize(url: URL) -> String {
    canonicalize(url.path)
  }

  static func displayPath(for canonicalItemPath: String, under root: URL) -> String {
    let canonicalRootPath = canonicalize(url: root)
    let preferredRootPath = root.standardizedFileURL.path

    guard
      canonicalItemPath == canonicalRootPath
        || canonicalItemPath.hasPrefix(canonicalRootPath + "/")
    else {
      return URL(fileURLWithPath: canonicalItemPath).standardizedFileURL.path
    }

    if canonicalItemPath == canonicalRootPath {
      return preferredRootPath
    }

    let suffix = String(canonicalItemPath.dropFirst(canonicalRootPath.count))
    let relative = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return (preferredRootPath as NSString).appendingPathComponent(relative)
  }
}
