import SwiftUI

// MARK: - Wave Progress Bar

/// Animated wave-fill progress indicator
/// Uses TimelineView for smooth wave animation
public struct WaveProgressBar: View {
  let progress: Double
  let color: Color

  @Environment(\.motionConfig) private var motion

  public init(progress: Double, color: Color = .blue) {
    self.progress = min(max(progress, 0), 1)
    self.color = color
  }

  public var body: some View {
    GeometryReader { geo in
      ZStack {
        // Background
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.gray.opacity(0.1))

        if motion.reduceMotion {
          staticFill(size: geo.size)
        } else {
          animatedWave(size: geo.size)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }

  private func staticFill(size: CGSize) -> some View {
    VStack {
      Spacer()
      Rectangle()
        .fill(color.opacity(0.6))
        .frame(height: size.height * progress)
    }
  }

  private func animatedWave(size: CGSize) -> some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
        let waveY = size.height * (1 - progress)

        // Wave 1
        var path1 = Path()
        path1.move(to: CGPoint(x: 0, y: waveY))

        for x in stride(from: 0, through: size.width, by: 2) {
          let relativeX = x / size.width
          let y = waveY + sin((relativeX * 4 * CGFloat.pi) + phase * CGFloat.pi) * 6
          path1.addLine(to: CGPoint(x: x, y: y))
        }

        path1.addLine(to: CGPoint(x: size.width, y: size.height))
        path1.addLine(to: CGPoint(x: 0, y: size.height))
        path1.closeSubpath()

        context.fill(path1, with: .color(color.opacity(0.7)))

        // Wave 2 (slightly offset)
        var path2 = Path()
        path2.move(to: CGPoint(x: 0, y: waveY + 5))

        for x in stride(from: 0, through: size.width, by: 2) {
          let relativeX = x / size.width
          let y = waveY + 5 + sin((relativeX * 3 * CGFloat.pi) + phase * CGFloat.pi * 1.3) * 4
          path2.addLine(to: CGPoint(x: x, y: y))
        }

        path2.addLine(to: CGPoint(x: size.width, y: size.height))
        path2.addLine(to: CGPoint(x: 0, y: size.height))
        path2.closeSubpath()

        context.fill(path2, with: .color(color.opacity(0.4)))
      }
    }
  }
}

// MARK: - Wave Container

/// Container with wave fill indicator
public struct WaveContainer<Content: View>: View {
  let progress: Double
  let color: Color
  @ViewBuilder let content: () -> Content

  public init(progress: Double, color: Color = .blue, @ViewBuilder content: @escaping () -> Content)
  {
    self.progress = progress
    self.color = color
    self.content = content
  }

  public var body: some View {
    ZStack {
      WaveProgressBar(progress: progress, color: color)
      content()
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    WaveProgressBar(progress: 0.6)
      .frame(width: 100, height: 150)

    WaveProgressBar(progress: 0.3, color: .green)
      .frame(width: 80, height: 120)

    WaveContainer(progress: 0.75, color: .orange) {
      VStack {
        Text("75%")
          .font(.title.bold())
        Text("Storage")
          .font(.caption)
      }
    }
    .frame(width: 120, height: 160)
  }
  .padding()
}
