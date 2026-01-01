import Foundation

// MARK: - Media Types

/// 媒体文件类型
public enum MediaType: String, Sendable, CaseIterable {
  case video
  case image
  case audio
}

/// 媒体文件信息
public struct MediaFile: Identifiable, Sendable {
  public let id: UUID
  public let url: URL
  public let type: MediaType
  public let size: Int64
  public let duration: Double?  // 视频时长（秒）
  public let resolution: CGSize?  // 分辨率
  public let creationDate: Date?
  public let modificationDate: Date?
  public let inode: UInt64  // 用于缓存失效
  public var perceptualHash: UInt64?  // pHash（延迟计算）

  public init(
    url: URL,
    type: MediaType,
    size: Int64,
    duration: Double? = nil,
    resolution: CGSize? = nil,
    creationDate: Date? = nil,
    modificationDate: Date? = nil,
    inode: UInt64 = 0,
    perceptualHash: UInt64? = nil
  ) {
    self.id = UUID()
    self.url = url
    self.type = type
    self.size = size
    self.duration = duration
    self.resolution = resolution
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.inode = inode
    self.perceptualHash = perceptualHash
  }
}

// MARK: - Similar Group

/// 相似媒体分组
public struct SimilarGroup: Identifiable, Sendable {
  public let id: UUID
  public let representative: MediaFile  // 保留的代表文件（通常最大）
  public let duplicates: [MediaFile]  // 可删除的重复文件
  public let totalSize: Int64
  public let reclaimableSize: Int64  // 可回收空间

  public init(representative: MediaFile, duplicates: [MediaFile]) {
    self.id = UUID()
    self.representative = representative
    self.duplicates = duplicates
    self.totalSize = representative.size + duplicates.reduce(0) { $0 + $1.size }
    self.reclaimableSize = duplicates.reduce(0) { $0 + $1.size }
  }
}

// MARK: - Scan Result

/// 媒体扫描结果
public struct MediaScanResult: Sendable {
  public let files: [MediaFile]
  public let totalSize: Int64
  public let videoCount: Int
  public let imageCount: Int
  public let audioCount: Int
  public let scanDuration: TimeInterval

  public init(
    files: [MediaFile],
    scanDuration: TimeInterval
  ) {
    self.files = files
    self.totalSize = files.reduce(0) { $0 + $1.size }
    self.videoCount = files.filter { $0.type == .video }.count
    self.imageCount = files.filter { $0.type == .image }.count
    self.audioCount = files.filter { $0.type == .audio }.count
    self.scanDuration = scanDuration
  }
}

// MARK: - Analysis Result

/// 媒体分析结果
public struct MediaAnalysisResult: Sendable {
  public let scanResult: MediaScanResult
  public let similarGroups: [SimilarGroup]
  public let totalReclaimableSize: Int64

  public init(scanResult: MediaScanResult, similarGroups: [SimilarGroup]) {
    self.scanResult = scanResult
    self.similarGroups = similarGroups
    self.totalReclaimableSize = similarGroups.reduce(0) { $0 + $1.reclaimableSize }
  }
}
