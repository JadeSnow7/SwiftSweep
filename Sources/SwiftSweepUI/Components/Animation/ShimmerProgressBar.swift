import SwiftUI

// MARK: - Shimmer Progress Bar

/// High-performance progress bar with shimmer effect
/// Uses TimelineView + Canvas for optimal rendering
/// Automatically disables shimmer when progress <= 0.01 or reduceMotion is enabled
public struct ShimmerProgressBar: View {
  let progress: Double
  let color: Color
  let height: CGFloat

  @Environment(\.motionConfig) private var motion

  private var isActive: Bool {
    progress > 0.01 && !motion.reduceMotion
  }

  public init(progress: Double, color: Color = .blue, height: CGFloat = 8) {
    self.progress = min(max(progress, 0), 1)
    self.color = color
    self.height = height
  }

  public var body: some View {
    if isActive {
      animatedProgressBar
    } else {
      staticProgressBar
    }
  }

  // MARK: - Animated Version (TimelineView + Canvas)

  private var animatedProgressBar: some View {
    TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
      Canvas { context, size in
        let progressWidth = size.width * progress
        let cornerRadius: CGFloat = height / 2

        // Background track
        context.fill(
          Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius),
          with: .color(.gray.opacity(0.2))
        )

        // Progress fill
        let progressRect = CGRect(x: 0, y: 0, width: progressWidth, height: size.height)
        context.fill(
          Path(roundedRect: progressRect, cornerRadius: cornerRadius),
          with: .color(color)
        )

        // Shimmer overlay
        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(
          dividingBy: 1.5)
        let shimmerWidth: CGFloat = 60
        let shimmerX = (phase / 1.5) * (progressWidth + shimmerWidth) - shimmerWidth

        context.clip(to: Path(roundedRect: progressRect, cornerRadius: cornerRadius))

        let shimmerGradient = Gradient(colors: [
          .clear,
          .white.opacity(0.4),
          .clear,
        ])

        context.fill(
          Path(CGRect(x: shimmerX, y: 0, width: shimmerWidth, height: size.height)),
          with: .linearGradient(
            shimmerGradient,
            startPoint: CGPoint(x: shimmerX, y: 0),
            endPoint: CGPoint(x: shimmerX + shimmerWidth, y: 0)
          )
        )
      }
    }
    .frame(height: height)
  }

  // MARK: - Static Version

  private var staticProgressBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: height / 2)
          .fill(Color.gray.opacity(0.2))

        RoundedRectangle(cornerRadius: height / 2)
          .fill(color)
          .frame(width: geo.size.width * progress)
      }
    }
    .frame(height: height)
  }
}

// MARK: - Indeterminate Progress

/// Indeterminate progress bar with continuous animation
public struct IndeterminateProgressBar: View {
  let color: Color
  let height: CGFloat

  @Environment(\.motionConfig) private var motion

  public init(color: Color = .blue, height: CGFloat = 4) {
    self.color = color
    self.height = height
  }

  public var body: some View {
    GeometryReader { geo in
      if motion.reduceMotion {
        // Static fallback
        RoundedRectangle(cornerRadius: height / 2)
          .fill(color.opacity(0.3))
      } else {
        TimelineView(.animation) { timeline in
          Canvas { context, size in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(
              dividingBy: 1.0)
            let barWidth = size.width * 0.3
            let x = phase * (size.width + barWidth) - barWidth

            // Background
            context.fill(
              Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2),
              with: .color(color.opacity(0.2))
            )

            // Moving bar
            context.fill(
              Path(
                roundedRect: CGRect(x: x, y: 0, width: barWidth, height: size.height),
                cornerRadius: height / 2),
              with: .color(color)
            )
          }
        }
      }
    }
    .frame(height: height)
  }
}

#Preview {
  VStack(spacing: 20) {
    ShimmerProgressBar(progress: 0.7)
    ShimmerProgressBar(progress: 0.3, color: .green)
    ShimmerProgressBar(progress: 0, color: .orange)
    IndeterminateProgressBar()
  }
  .padding()
  .frame(width: 300)
}
