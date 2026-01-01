import Foundation

// MARK: - Similarity Detector

/// 相似度检测器，使用 LSH 加速
public actor SimilarityDetector {
  public static let shared = SimilarityDetector()

  // MARK: - LSH Configuration

  /// LSH 配置
  public struct LSHConfig: Sendable {
    /// 将 64-bit 分成的 band 数量
    public let bands: Int
    /// 每个 band 的 bit 数
    public let rowsPerBand: Int
    /// 汉明距离阈值
    public let threshold: Int

    public static let `default` = LSHConfig(bands: 4, rowsPerBand: 16, threshold: 10)

    /// bands=4, rows=16: 汉明距离<=10 的捕获率约 85%
    /// 如需更高捕获率，可增加 bands 但会增加候选对数量
  }

  // MARK: - Detection

  /// 检测相似媒体文件
  public func detectSimilar(
    files: [MediaFile],
    config: LSHConfig = .default,
    onProgress: (@Sendable (Int, Int) -> Void)? = nil
  ) async -> [SimilarGroup] {
    // 过滤已有 hash 的文件
    let hashedFiles = files.filter { $0.perceptualHash != nil }
    guard hashedFiles.count >= 2 else { return [] }

    // 使用 LSH 生成候选对
    let candidates = generateCandidates(files: hashedFiles, config: config)

    // 精确验证候选对
    var unionFind = UnionFind(count: hashedFiles.count)

    var verified = 0
    for (i, j) in candidates {
      guard let hash1 = hashedFiles[i].perceptualHash,
        let hash2 = hashedFiles[j].perceptualHash
      else { continue }

      if PerceptualHasher.isSimilar(hash1, hash2, threshold: config.threshold) {
        unionFind.union(i, j)
      }

      verified += 1
      if verified % 100 == 0 {
        onProgress?(verified, candidates.count)
      }
    }

    // 聚合成组
    var groups: [Int: [Int]] = [:]
    for i in 0..<hashedFiles.count {
      let root = unionFind.find(i)
      groups[root, default: []].append(i)
    }

    // 转换为 SimilarGroup（只保留有多于1个成员的组）
    var result: [SimilarGroup] = []
    for (_, indices) in groups where indices.count > 1 {
      let groupFiles = indices.map { hashedFiles[$0] }

      // 选择最大的文件作为代表
      let sorted = groupFiles.sorted { $0.size > $1.size }
      let representative = sorted[0]
      let duplicates = Array(sorted.dropFirst())

      result.append(SimilarGroup(representative: representative, duplicates: duplicates))
    }

    // 按可回收空间排序
    return result.sorted { $0.reclaimableSize > $1.reclaimableSize }
  }

  // MARK: - LSH Candidate Generation

  private func generateCandidates(
    files: [MediaFile],
    config: LSHConfig
  ) -> [(Int, Int)] {
    var buckets: [Int: [String: [Int]]] = [:]  // band -> hash -> indices

    // 将每个文件分配到各个 band 的桶中
    for (index, file) in files.enumerated() {
      guard let hash = file.perceptualHash else { continue }

      for band in 0..<config.bands {
        let bandHash = extractBand(hash: hash, band: band, rowsPerBand: config.rowsPerBand)
        let bandKey = String(bandHash, radix: 16)

        if buckets[band] == nil {
          buckets[band] = [:]
        }
        buckets[band]![bandKey, default: []].append(index)
      }
    }

    // 收集候选对（同一桶内的所有对）
    var candidateSet = Set<CandidatePair>()

    for (_, bandBuckets) in buckets {
      for (_, indices) in bandBuckets where indices.count > 1 {
        for i in 0..<indices.count {
          for j in (i + 1)..<indices.count {
            let pair = CandidatePair(min(indices[i], indices[j]), max(indices[i], indices[j]))
            candidateSet.insert(pair)
          }
        }
      }
    }

    return candidateSet.map { ($0.a, $0.b) }
  }

  private func extractBand(hash: UInt64, band: Int, rowsPerBand: Int) -> UInt64 {
    let shift = band * rowsPerBand
    let mask: UInt64 = (1 << rowsPerBand) - 1
    return (hash >> shift) & mask
  }

  // MARK: - Helper Types

  private struct CandidatePair: Hashable {
    let a: Int
    let b: Int

    init(_ a: Int, _ b: Int) {
      self.a = a
      self.b = b
    }
  }
}

// MARK: - Union Find

/// 并查集，用于聚合相似文件
private struct UnionFind {
  private var parent: [Int]
  private var rank: [Int]

  init(count: Int) {
    parent = Array(0..<count)
    rank = Array(repeating: 0, count: count)
  }

  mutating func find(_ x: Int) -> Int {
    if parent[x] != x {
      parent[x] = find(parent[x])  // 路径压缩
    }
    return parent[x]
  }

  mutating func union(_ x: Int, _ y: Int) {
    let rootX = find(x)
    let rootY = find(y)

    if rootX == rootY { return }

    // 按秩合并
    if rank[rootX] < rank[rootY] {
      parent[rootX] = rootY
    } else if rank[rootX] > rank[rootY] {
      parent[rootY] = rootX
    } else {
      parent[rootY] = rootX
      rank[rootX] += 1
    }
  }
}
