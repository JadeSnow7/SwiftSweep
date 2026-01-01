import AVFoundation
import Accelerate
import CoreGraphics
import Foundation

// MARK: - Perceptual Hasher

/// 感知哈希算法（pHash）
/// 用于检测视觉相似的图片/视频
public struct PerceptualHasher {
  public static let shared = PerceptualHasher()

  /// 相似度阈值：汉明距离 <= 10 认为相似
  public static let similarityThreshold = 10

  private let cache = pHashCache.shared

  // MARK: - Video Hash

  /// 计算视频的感知哈希（采样关键帧）
  public func hashVideo(url: URL, sampleCount: Int = 5) async throws -> UInt64 {
    let fm = FileManager.default
    let attrs = try fm.attributesOfItem(atPath: url.path)
    let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
    let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast

    // 检查缓存
    if let cached = await cache.get(path: url.path, inode: inode, mtime: mtime) {
      return cached
    }

    // 计算哈希
    let hash = try await computeVideoHash(url: url, sampleCount: sampleCount)

    // 存入缓存
    await cache.set(path: url.path, inode: inode, mtime: mtime, hash: hash)

    return hash
  }

  private func computeVideoHash(url: URL, sampleCount: Int) async throws -> UInt64 {
    let asset = AVAsset(url: url)
    let duration = try await asset.load(.duration).seconds

    guard duration > 0 else { return 0 }

    // 获取 track 和 transform 用于归一化方向
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else { return 0 }
    _ = try await track.load(.preferredTransform)  // Ensure transform is available

    // 均匀采样帧
    var hashes: [UInt64] = []
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true  // 应用方向归一化
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

    for i in 0..<sampleCount {
      let time = CMTime(
        seconds: duration * Double(i + 1) / Double(sampleCount + 1),
        preferredTimescale: 600
      )

      do {
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let frameHash = hashImage(cgImage)
        hashes.append(frameHash)
      } catch {
        continue
      }
    }

    // 合并多帧哈希（异或组合）
    return combineHashes(hashes)
  }

  // MARK: - Image Hash

  /// 计算图像的感知哈希 (DCT-based pHash)
  public func hashImage(_ image: CGImage) -> UInt64 {
    // 1. 缩放到 32x32 灰度
    guard let grayscale = resizeToGrayscale(image, size: 32) else {
      return 0
    }

    // 2. 应用 DCT 变换
    let dct = applyDCT(grayscale)

    // 3. 取左上 8x8 低频分量（跳过 DC 分量）
    var lowFreq: [Float] = []
    for y in 0..<8 {
      for x in 0..<8 {
        if x == 0 && y == 0 { continue }  // 跳过 DC
        lowFreq.append(dct[y * 32 + x])
      }
    }

    // 4. 计算中位数
    let sorted = lowFreq.sorted()
    let median = sorted[sorted.count / 2]

    // 5. 生成 64-bit 哈希
    var hash: UInt64 = 0
    var bitIndex = 0
    for y in 0..<8 {
      for x in 0..<8 {
        if x == 0 && y == 0 { continue }
        if dct[y * 32 + x] > median {
          hash |= (1 << bitIndex)
        }
        bitIndex += 1
        if bitIndex >= 64 { break }
      }
      if bitIndex >= 64 { break }
    }

    return hash
  }

  /// 从 URL 加载并计算图像哈希
  public func hashImage(url: URL) async throws -> UInt64 {
    let fm = FileManager.default
    let attrs = try fm.attributesOfItem(atPath: url.path)
    let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
    let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast

    // 检查缓存
    if let cached = await cache.get(path: url.path, inode: inode, mtime: mtime) {
      return cached
    }

    // 加载图像
    guard let dataProvider = CGDataProvider(url: url as CFURL),
      let cgImage = CGImage(
        pngDataProviderSource: dataProvider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
        ?? CGImage(
          jpegDataProviderSource: dataProvider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
    else {
      throw HashError.imageLoadFailed
    }

    let hash = hashImage(cgImage)

    // 存入缓存
    await cache.set(path: url.path, inode: inode, mtime: mtime, hash: hash)

    return hash
  }

  // MARK: - Similarity

  /// 计算汉明距离（相似度）
  public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    return (a ^ b).nonzeroBitCount
  }

  /// 判断是否相似
  public static func isSimilar(_ a: UInt64, _ b: UInt64, threshold: Int = similarityThreshold)
    -> Bool
  {
    return hammingDistance(a, b) <= threshold
  }

  // MARK: - Private Helpers

  private func resizeToGrayscale(_ image: CGImage, size: Int) -> [Float]? {
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixels = [UInt8](repeating: 0, count: size * size)

    guard
      let context = CGContext(
        data: &pixels,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else {
      return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    return pixels.map { Float($0) }
  }

  private func applyDCT(_ input: [Float]) -> [Float] {
    let n = 32
    var output = [Float](repeating: 0, count: n * n)

    // 简化的 2D DCT（实际生产中可用 vDSP 优化）
    for u in 0..<n {
      for v in 0..<n {
        var sum: Float = 0
        for x in 0..<n {
          for y in 0..<n {
            let cosX = cos(Float.pi * Float(2 * x + 1) * Float(u) / Float(2 * n))
            let cosY = cos(Float.pi * Float(2 * y + 1) * Float(v) / Float(2 * n))
            sum += input[y * n + x] * cosX * cosY
          }
        }

        let cu: Float = u == 0 ? 1 / sqrt(2) : 1
        let cv: Float = v == 0 ? 1 / sqrt(2) : 1
        output[u * n + v] = 0.25 * cu * cv * sum
      }
    }

    return output
  }

  private func combineHashes(_ hashes: [UInt64]) -> UInt64 {
    guard !hashes.isEmpty else { return 0 }
    return hashes.reduce(0) { $0 ^ $1 }
  }

  // MARK: - Errors

  public enum HashError: Error {
    case imageLoadFailed
    case videoProcessingFailed
  }
}
