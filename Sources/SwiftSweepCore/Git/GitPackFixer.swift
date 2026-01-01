import Foundation

/// Utility to fix Git repository corruption caused by AppleDouble files in pack folder
public struct GitPackFixer {

  /// Scans the git repository for `._*` files in `.git/objects/pack/` and removes them.
  /// - Parameter gitDir: The URL to the `.git` directory
  /// - Returns: A summary of removed files
  public static func fixPackIndex(gitDir: URL) throws -> [String] {
    let packDir = gitDir.appendingPathComponent("objects/pack")
    let fm = FileManager.default
    var removedFiles: [String] = []

    guard fm.fileExists(atPath: packDir.path) else {
      return []
    }

    let contents = try fm.contentsOfDirectory(at: packDir, includingPropertiesForKeys: nil)

    for file in contents {
      if file.lastPathComponent.hasPrefix("._") {
        try fm.removeItem(at: file)
        removedFiles.append(file.lastPathComponent)
      }
    }

    return removedFiles
  }
}
