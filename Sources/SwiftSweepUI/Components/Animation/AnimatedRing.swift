import SwiftUI

// MARK: - Animated Ring

/// Circular progress indicator with smooth fill animation
public struct AnimatedRing: View {
  let progress: Double
  let color: Color
  let lineWidth: CGFloat

  @State private var animatedProgress: Double = 0
  @Environment(\.motionConfig) private var motion

  public init(progress: Double, color: Color = .blue, lineWidth: CGFloat = 12) {
    self.progress = min(max(progress, 0), 1)
    self.color = color
    self.lineWidth = lineWidth
  }

  public var body: some View {
    ZStack {
      // Background track
      Circle()
        .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

      // Progress arc
      Circle()
        .trim(from: 0, to: animatedProgress)
        .stroke(
          color,
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(
          motion.reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7),
          value: animatedProgress
        )

      // Percentage text with numeric transition (macOS 14+)
      percentageText
    }
    .onAppear {
      animatedProgress = motion.reduceMotion ? progress : 0
      if !motion.reduceMotion {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          animatedProgress = progress
        }
      }
    }
    .onChange(of: progress) { newValue in
      animatedProgress = newValue
    }
  }

  @ViewBuilder
  private var percentageText: some View {
    if #available(macOS 14.0, *) {
      Text("\(Int(animatedProgress * 100))%")
        .font(.title2.bold())
        .contentTransition(.numericText())
    } else {
      Text("\(Int(animatedProgress * 100))%")
        .font(.title2.bold())
    }
  }
}

// MARK: - Mini Ring

/// Compact ring for inline use
public struct MiniRing: View {
  let progress: Double
  let color: Color

  public init(progress: Double, color: Color = .blue) {
    self.progress = progress
    self.color = color
  }

  public var body: some View {
    AnimatedRing(progress: progress, color: color, lineWidth: 4)
      .frame(width: 24, height: 24)
  }
}

#Preview {
  HStack(spacing: 40) {
    AnimatedRing(progress: 0.75)
      .frame(width: 100, height: 100)

    AnimatedRing(progress: 0.45, color: .orange)
      .frame(width: 80, height: 80)

    MiniRing(progress: 0.6, color: .green)
  }
  .padding()
}
