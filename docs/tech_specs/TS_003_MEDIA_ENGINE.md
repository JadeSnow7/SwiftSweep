# 项目设计文档：多媒体分析引擎与相似检测

**项目名称**：SwiftSweep - Media Analysis & Deduplication Engine
**作者 / 时间**：JadeSnow7 / 2026-01-02
**项目类型**：多媒体 / 算法优化 / 高性能计算
**适用平台**：macOS

---

## 1. 背景（Background）

用户磁盘空间常被重复或相似的媒体文件（照片、视频）占用。传统的 MD5/SHA256 哈希只能检测**完全一致**的文件，无法识别：
-   仅格式不同（PNG vs JPG）的同一张图。
-   仅分辨率不同（1080p vs 4K）的同一个视频。
-   连拍的相似照片。

此外，视频文件的元数据分析（如编码格式、分辨率）通常需要调用重量级的 FFMpeg 库，如何在不显著增加 App 耗电和体积的前提下实现这一功能是核心挑战。

---

## 2. 目标与非目标（Goals & Non-Goals）

### Goals
-   **感知哈希 (Perceptual Hash)**：实现 pHash 算法，从视觉层面检测相似图片。
-   **局部敏感哈希 (LSH)**：利用 SimHash/LSH 快速在大规模数据集中召回相似项（避免 O(n^2) 两两比对）。
-   **零依赖视频分析**：优先使用 Apple 原生 `AVFoundation`，仅在必要时回退到轻量级解析方案。
-   **高性能预览**：使用 QuickLook 缩略图技术快速展示结果。

### Non-Goals
-   **不做人脸识别**：涉及隐私且模型过大，不属于清理工具范畴。
-   **不支持受损文件修复**：只读分析，不做修改。

---

## 3. 需求与约束（Requirements & Constraints）

### 功能需求
1.  **相似度评分**：给出两张图片的相似度（0.0 - 1.0），默认阈值 0.9。
2.  **大文件筛选**：快速扫描 >1GB 的大文件。
3.  **智能分组**：将相似图片自动归类为一组，推荐保留最佳的一张（如分辨率最高）。

### 非功能需求
-   **速度**：1000 张图片分析需在 10秒 内完成。
-   **内存**：峰值内存占用 < 200MB。

### 约束条件
-   **Sandbox**：只能读取用户授权的目录。
-   **Privacy**：分析过程全本地化，严禁上传任何图片指纹。

---

## 4. 方案调研与对比（Alternatives Considered）🔥

### 相似度算法对比

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **像素逐点对比** | 准确度 100% | 速度极慢，抗噪性差（缩放/旋转即失效）。 | ❌ |
| **直方图 (Histogram)** | 抗旋转，计算快 | 丢失空间信息，颜色分布相同但内容不同的图会被误判。 | ❌ |
| **pHash (DCT变换)** | **抗缩放、压缩、轻微调色；计算复杂度适中。** | **无法处理大幅度裁剪。** | ✅ |
| **CNN Deep Learning** | 语义级相似，最强 | 模型大（几百MB），推理慢，不适合作为辅助功能。 | ❌ |

### 加速比对策略

| 方案 | 优点 | 缺点 | 结论 |
| :--- | :--- | :--- | :--- |
| **两两暴力比对 O(n^2)** | 实现简单 | 1万张图需要 5000万次比对，不可接受。 | ❌ |
| **BK-Tree / LSH** | **查询复杂度接近 O(1) 或 O(log n)。** | **实现复杂，主要用于汉明距离搜索。** | ✅ |

**最终选择**：pHash (指纹提取) + BK-Tree (指纹索引) 方案。

---

## 5. 整体架构设计（Design Overview）

### 流水线架构

```mermaid
flowchart LR
    File[文件输入] --> Resizer[缩略图生成]
    Resizer --> Grayscale[灰度化]
    Grayscale --> DCT[DCT变换]
    DCT --> Hash[pHash生成 (64-bit)]
    Hash --> Store[SQLite 指纹库]
    Store --> Matcher[BK-Tree 匹配]
    Matcher --> Group[相似组]
```

-   **Pre-processing**: 使用 `ImageIO` 读取缩略图（而不是加载原图），大幅降低内存。
-   **Core**: 基于 vDSP (Accelerate.framework) 做矩阵运算（DCT）。
-   **Storage**: SQLite 存储 `(path, pHash)`，便于增量扫描。

---

## 6. 关键设计点（Key Design Decisions）

### 6.1 使用 ImageIO 缩略图
*   **设计**：`CGImageSourceCreateThumbnailAtIndex`。
*   **原因**：直接 `NSImage(contentsOf:)` 会解码整张 4K/8K 图片到内存，瞬间 OOM。缩略图仅需 32x32，极快。

### 6.2 64-bit 整数存储指纹
*   **设计**：将 8x8 的 DCT 结果二值化后压缩为 `UInt64`。
*   **优势**：计算相似度（汉明距离）只需异或如 `(a ^ b).nonzeroBitCount`，CPU 指令级优化。

---

## 7. 并发与线程模型（Concurrency Model）

-   **生产者-消费者**：
    -   1 个文件扫描 Task（生产者）。
    -   N 个指纹计算 Task（消费者），N = CPU 核心数。
    -   1 个结果聚合 Actor。

-   **并行限制**：因为图像处理涉及大量瞬时内存分配，必须严格限制并发数（如 4），否则会导致内存压力告警。

---

## 8. 性能与资源管理（Performance & Resource Management）

### 性能指标
| 步骤 | 耗时 (每张图) | 优化手段 |
|------|--------------|----------|
| I/O 读取 | 2-5ms | 预读取 |
| 缩略图解码 | 10-20ms | ImageIO subsampling |
| pHash 计算 | < 1ms | vDSP 矩阵运算 |

### 资源管理
-   **内存池**：复用 DCT 计算所需的 Buffer，避免反复 malloc/free。
-   **低功耗模式**：当检测到电池供电时，增加 `usleep` 降低 CPU 占用率。

---

## 9. 风险与权衡（Risks & Trade-offs）

-   **误判风险**：pHash 在极简图形（如纯色图、简单线条）上容易碰撞。
    -   *缓解*：对纯色图跳过 pHash，直接用 MD5。
-   **文件修改时间欺骗**：如果文件内容变了但 mtime 没变，缓存指纹失效。
    -   *权衡*：为了性能，默认信赖 mtime。提供“强制重新扫描”选项。

---

## 10. 验证与效果（Validation）

### 测试集
-   Dataset A: 100 对不同分辨率/压缩率的相同图片。
-   Dataset B: 1000 张无关图片（验证误判率）。

### 结果
-   在 Dataset A 上召回率 98%（极度模糊除外）。
-   在 MacBook Air M2 上处理速度达到 200 张/秒。

---

## 11. 可迁移性（macOS → iOS）

-   **Accelerate 框架**：macOS/iOS 通用。
-   **ImageIO**：完全通用。
-   **PhotoKit**：iOS 上应优先使用 PhotoKit 获取资源，而不是文件系统路径。

---

## 12. 后续规划（Future Work）

1.  **AI 语义去重**：引入 Core ML (MobileNet) 识别“内容相似但构图不同”的照片（如连拍时的视角微变）。
2.  **Live Photo 支持**：解析 Live Photo 的视频部分。

---

## 13. 总结（Takeaways）

MediaAnalyzer 证明了通过经典的算法工程（pHash + vDSP），可以在不依赖重型 AI 模型的情况下，解决 90% 的用户痛点（重复图片清理）。**恰当的算法选择**往往比堆积最新技术更有效且更具备工程可行性。
