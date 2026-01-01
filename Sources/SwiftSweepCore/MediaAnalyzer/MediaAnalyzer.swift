import Foundation

// MARK: - Media Analyzer

/// 媒体分析器主入口
/// 整合扫描、哈希计算、相似度检测
public actor MediaAnalyzer {
  public static let shared = MediaAnalyzer()

  private let scanner = MediaScanner.shared
  private let hasher = PerceptualHasher.shared
  private let detector = SimilarityDetector.shared

  // MARK: - Full Analysis

  /// 执行完整的媒体分析
  public func analyze(
    root: URL,
    onPhase: (@Sendable (AnalysisPhase) -> Void)? = nil,
    onProgress: (@Sendable (Int, Int) -> Void)? = nil
  ) async throws -> MediaAnalysisResult {
    // Phase 1: 扫描
    onPhase?(.scanning)
    let scanResult = await scanner.scan(root: root) { count, url in
      onProgress?(count, 0)
    }

    if Task.isCancelled { throw CancellationError() }

    // Phase 2: 计算 pHash
    onPhase?(.hashing)
    var filesWithHash: [MediaFile] = []
    let total = scanResult.files.count

    for (index, file) in scanResult.files.enumerated() {
      if Task.isCancelled { throw CancellationError() }

      onProgress?(index + 1, total)

      var enrichedFile = file

      // 只对视频和图像计算 pHash
      if file.type == .video {
        if let hash = try? await hasher.hashVideo(url: file.url) {
          enrichedFile = MediaFile(
            url: file.url,
            type: file.type,
            size: file.size,
            duration: file.duration,
            resolution: file.resolution,
            creationDate: file.creationDate,
            modificationDate: file.modificationDate,
            inode: file.inode,
            perceptualHash: hash
          )
        }
      } else if file.type == .image {
        if let hash = try? await hasher.hashImage(url: file.url) {
          enrichedFile = MediaFile(
            url: file.url,
            type: file.type,
            size: file.size,
            duration: file.duration,
            resolution: file.resolution,
            creationDate: file.creationDate,
            modificationDate: file.modificationDate,
            inode: file.inode,
            perceptualHash: hash
          )
        }
      }

      filesWithHash.append(enrichedFile)
    }

    if Task.isCancelled { throw CancellationError() }

    // Phase 3: 检测相似
    onPhase?(.detecting)
    let similarGroups = await detector.detectSimilar(files: filesWithHash)

    return MediaAnalysisResult(
      scanResult: MediaScanResult(files: filesWithHash, scanDuration: scanResult.scanDuration),
      similarGroups: similarGroups
    )
  }

  // MARK: - Quick Scan (No Hash)

  /// 快速扫描（不计算哈希）
  public func quickScan(
    root: URL,
    onProgress: (@Sendable (Int, URL) -> Void)? = nil
  ) async -> MediaScanResult {
    return await scanner.scan(root: root, onProgress: onProgress)
  }

  // MARK: - Analysis Phases

  public enum AnalysisPhase: String, Sendable {
    case scanning = "Scanning files..."
    case hashing = "Computing hashes..."
    case detecting = "Detecting similar..."
  }
}
