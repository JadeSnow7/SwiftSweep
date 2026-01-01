import AVFoundation
import Foundation

// MARK: - Media Scanner

/// 媒体文件扫描器
/// 支持安全作用域书签访问用户选择的目录
public actor MediaScanner {
  public static let shared = MediaScanner()

  // MARK: - File Extensions

  /// 支持的视频格式
  public static let videoExtensions: Set<String> = [
    "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "3gp", "ts",
  ]

  /// 支持的图片格式
  public static let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif", "raw",
  ]

  /// 支持的音频格式
  public static let audioExtensions: Set<String> = [
    "mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg", "wma",
  ]

  // MARK: - Bookmark Storage

  private let bookmarkKey = "MediaScanner.SecurityScopedBookmarks"

  /// 加载已保存的书签
  public func loadSavedBookmarks() -> [URL] {
    guard let bookmarksData = UserDefaults.standard.dictionary(forKey: bookmarkKey) else {
      return []
    }

    var urls: [URL] = []
    for (_, value) in bookmarksData {
      guard let data = value as? Data else { continue }
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        urls.append(url)
      }
    }
    return urls
  }

  /// 保存安全作用域书签
  public func saveBookmark(for url: URL) throws {
    let bookmark = try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
    bookmarks[url.path] = bookmark
    UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
  }

  /// 移除书签
  public func removeBookmark(for url: URL) {
    var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
    bookmarks.removeValue(forKey: url.path)
    UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
  }

  // MARK: - Scanning

  /// 扫描目录中的媒体文件
  public func scan(
    root: URL,
    includeSubdirectories: Bool = true,
    onProgress: (@Sendable (Int, URL) -> Void)? = nil
  ) async -> MediaScanResult {
    let start = mach_absolute_time()

    // 尝试恢复安全作用域访问
    let hasAccess = root.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        root.stopAccessingSecurityScopedResource()
      }
    }

    var files: [MediaFile] = []
    var scannedCount = 0

    let fm = FileManager.default
    let resourceKeys: Set<URLResourceKey> = [
      .fileSizeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .isDirectoryKey,
      .isRegularFileKey,
      .fileResourceIdentifierKey,
    ]

    guard
      let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: Array(resourceKeys),
        options: includeSubdirectories
          ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
      )
    else {
      return MediaScanResult(files: [], scanDuration: 0)
    }

    for case let fileURL as URL in enumerator {
      if Task.isCancelled { break }

      guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
        values.isRegularFile == true
      else { continue }

      let ext = fileURL.pathExtension.lowercased()
      let mediaType: MediaType?

      if Self.videoExtensions.contains(ext) {
        mediaType = .video
      } else if Self.imageExtensions.contains(ext) {
        mediaType = .image
      } else if Self.audioExtensions.contains(ext) {
        mediaType = .audio
      } else {
        mediaType = nil
      }

      guard let type = mediaType else { continue }

      scannedCount += 1
      onProgress?(scannedCount, fileURL)

      // 获取 inode
      var inode: UInt64 = 0
      if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
        let inodeNum = attrs[.systemFileNumber] as? UInt64
      {
        inode = inodeNum
      }

      let file = MediaFile(
        url: fileURL,
        type: type,
        size: Int64(values.fileSize ?? 0),
        duration: nil,  // 延迟加载
        resolution: nil,  // 延迟加载
        creationDate: values.creationDate,
        modificationDate: values.contentModificationDate,
        inode: inode
      )

      files.append(file)
    }

    let end = mach_absolute_time()
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let duration = Double((end - start) * UInt64(info.numer) / UInt64(info.denom)) / 1_000_000_000

    // 记录性能指标
    await PerformanceMonitor.shared.record(
      OperationMetrics(
        operationName: "media.scan",
        startTicks: start,
        endTicks: end,
        durationNanos: (end - start) * UInt64(info.numer) / UInt64(info.denom),
        itemsProcessed: files.count,
        bytesProcessed: files.reduce(0) { $0 + $1.size },
        outcome: Task.isCancelled ? .cancelled : .success
      )
    )

    return MediaScanResult(files: files, scanDuration: duration)
  }

  // MARK: - Video Metadata Loading

  /// 加载视频元数据（时长、分辨率）
  public func loadVideoMetadata(for file: MediaFile) async -> MediaFile {
    guard file.type == .video else { return file }

    let asset = AVAsset(url: file.url)

    var duration: Double?
    var resolution: CGSize?

    // 加载时长
    if let durationCMTime = try? await asset.load(.duration) {
      duration = durationCMTime.seconds
    }

    // 加载分辨率
    if let tracks = try? await asset.loadTracks(withMediaType: .video),
      let track = tracks.first,
      let size = try? await track.load(.naturalSize),
      let transform = try? await track.load(.preferredTransform)
    {
      // 应用 transform 归一化方向
      let transformedSize = size.applying(transform)
      resolution = CGSize(
        width: abs(transformedSize.width),
        height: abs(transformedSize.height)
      )
    }

    return MediaFile(
      url: file.url,
      type: file.type,
      size: file.size,
      duration: duration,
      resolution: resolution,
      creationDate: file.creationDate,
      modificationDate: file.modificationDate,
      inode: file.inode,
      perceptualHash: file.perceptualHash
    )
  }
}
