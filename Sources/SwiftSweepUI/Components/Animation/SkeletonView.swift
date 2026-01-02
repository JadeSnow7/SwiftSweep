import Combine
import SwiftUI

// MARK: - Skeleton Controller

/// Centralized shimmer phase controller to avoid multiple animation sources
public final class SkeletonController: ObservableObject {
  @Published private(set) var phase: CGFloat = 0
  private var displayLink: CVDisplayLink?
  private var isRunning = false

  public static let shared = SkeletonController()

  private init() {}

  public func start() {
    guard !isRunning else { return }
    isRunning = true

    // Use Timer for simplicity (CVDisplayLink is more complex)
    Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] timer in
      guard let self, self.isRunning else {
        timer.invalidate()
        return
      }
      DispatchQueue.main.async {
        self.phase += 0.05
        if self.phase > 1 { self.phase = 0 }
      }
    }
  }

  public func stop() {
    isRunning = false
    phase = 0
  }
}

// MARK: - Skeleton View

/// Skeleton loading placeholder with shimmer effect
public struct SkeletonView: View {
  let cornerRadius: CGFloat

  @ObservedObject private var controller = SkeletonController.shared
  @Environment(\.motionConfig) private var motion

  public init(cornerRadius: CGFloat = 8) {
    self.cornerRadius = cornerRadius
  }

  public var body: some View {
    GeometryReader { geo in
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.gray.opacity(0.2))
        .overlay(
          Group {
            if !motion.reduceMotion {
              shimmerOverlay(width: geo.size.width)
            }
          }
        )
        .mask(RoundedRectangle(cornerRadius: cornerRadius))
    }
    .onAppear { controller.start() }
  }

  private func shimmerOverlay(width: CGFloat) -> some View {
    LinearGradient(
      colors: [.clear, .white.opacity(0.4), .clear],
      startPoint: .leading, endPoint: .trailing
    )
    .frame(width: 100)
    .offset(x: (controller.phase * (width + 200)) - 100)
  }
}

// MARK: - Skeleton Text

/// Text-shaped skeleton placeholder
public struct SkeletonText: View {
  let lines: Int
  let lastLineWidth: CGFloat

  public init(lines: Int = 3, lastLineWidth: CGFloat = 0.6) {
    self.lines = lines
    self.lastLineWidth = lastLineWidth
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(0..<lines, id: \.self) { index in
        SkeletonView()
          .frame(height: 16)
          .frame(
            maxWidth: index == lines - 1 ? .infinity : .infinity,
            alignment: .leading
          )
          .scaleEffect(
            x: index == lines - 1 ? lastLineWidth : 1,
            y: 1,
            anchor: .leading
          )
      }
    }
  }
}

// MARK: - Skeleton Card

/// Card-shaped skeleton placeholder
public struct SkeletonCard: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SkeletonView()
        .frame(height: 120)

      SkeletonText(lines: 2)
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
  }
}

#Preview {
  VStack(spacing: 20) {
    SkeletonView()
      .frame(width: 200, height: 40)

    SkeletonText()
      .frame(width: 300)

    SkeletonCard()
      .frame(width: 250)
  }
  .padding()
}
