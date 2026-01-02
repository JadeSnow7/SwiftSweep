import SwiftUI

// MARK: - Checkmark Shape

struct CheckmarkShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.5))
    path.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.7))
    path.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.3))
    return path
  }
}

// MARK: - Success Checkmark

/// Animated success indicator with scale + checkmark draw
public struct SuccessCheckmark: View {
  let size: CGFloat
  let color: Color

  @State private var scale: CGFloat = 0
  @State private var trimEnd: CGFloat = 0
  @Environment(\.motionConfig) private var motion

  public init(size: CGFloat = 60, color: Color = .green) {
    self.size = size
    self.color = color
  }

  public var body: some View {
    ZStack {
      Circle()
        .fill(color)
        .scaleEffect(motion.reduceMotion ? 1 : scale)

      CheckmarkShape()
        .trim(from: 0, to: motion.reduceMotion ? 1 : trimEnd)
        .stroke(
          Color.white, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round, lineJoin: .round)
        )
        .frame(width: size * 0.5, height: size * 0.5)
    }
    .frame(width: size, height: size)
    .onAppear {
      guard !motion.reduceMotion else {
        scale = 1
        trimEnd = 1
        return
      }
      withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
        scale = 1
      }
      withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
        trimEnd = 1
      }
    }
  }
}

// MARK: - Success View

/// Complete success state with checkmark and message
public struct SuccessView: View {
  let title: String
  let subtitle: String?

  public init(title: String = "Success!", subtitle: String? = nil) {
    self.title = title
    self.subtitle = subtitle
  }

  public var body: some View {
    VStack(spacing: 16) {
      SuccessCheckmark()

      Text(title)
        .font(.title2.bold())

      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
  }
}

#Preview {
  VStack(spacing: 40) {
    SuccessCheckmark()
    SuccessCheckmark(size: 40, color: .blue)
    SuccessView(title: "Cleanup Complete", subtitle: "Freed 2.5 GB of space")
  }
  .padding()
}
