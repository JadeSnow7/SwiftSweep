import SwiftUI

// MARK: - Confetti Piece

struct ConfettiPiece: Identifiable {
  let id = UUID()
  let x: CGFloat
  let initialY: CGFloat
  let rotation: Double
  let color: Color
  let size: CGFloat
  let velocity: CGFloat
}

// MARK: - Confetti View

/// Celebration effect with falling confetti particles
/// Uses TimelineView + Canvas for optimal performance
public struct ConfettiView: View {
  @State private var pieces: [ConfettiPiece] = []
  @State private var startTime: Date?
  @Environment(\.motionConfig) private var motion

  private let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
  private let duration: Double = 2.5

  public init() {}

  public var body: some View {
    if motion.reduceMotion {
      // Static fallback - just show some colored dots
      staticConfetti
    } else {
      animatedConfetti
    }
  }

  private var animatedConfetti: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        guard let start = startTime else { return }
        let elapsed = timeline.date.timeIntervalSince(start)
        let progress = min(elapsed / duration, 1.0)

        for piece in pieces {
          let y = piece.initialY + progress * piece.velocity
          let rotation = piece.rotation + progress * 360 * 2
          let opacity = 1.0 - (progress * 0.8)

          guard y < size.height + 50 else { continue }

          context.opacity = opacity

          var transform = CGAffineTransform.identity
          transform = transform.translatedBy(x: piece.x, y: y)
          transform = transform.rotated(by: rotation * .pi / 180)

          context.transform = transform

          // Draw confetti piece (rectangle or circle)
          let rect = CGRect(
            x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size * 0.4)
          context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(piece.color))

          context.transform = .identity
        }
      }
    }
    .onAppear { spawnConfetti() }
  }

  private var staticConfetti: some View {
    ZStack {
      ForEach(0..<15, id: \.self) { i in
        Circle()
          .fill(colors[i % colors.count])
          .frame(width: 8, height: 8)
          .offset(
            x: CGFloat.random(in: -100...100),
            y: CGFloat.random(in: -50...50)
          )
      }
    }
  }

  private func spawnConfetti() {
    startTime = Date()
    pieces = (0..<60).map { _ in
      ConfettiPiece(
        x: CGFloat.random(in: 0...400),
        initialY: CGFloat.random(in: -80 ...- 20),
        rotation: Double.random(in: 0...360),
        color: colors.randomElement()!,
        size: CGFloat.random(in: 8...14),
        velocity: CGFloat.random(in: 300...500)
      )
    }
  }
}

// MARK: - Celebration View

/// Complete celebration overlay
public struct CelebrationView: View {
  let title: String
  let subtitle: String?

  @State private var showContent = false
  @Environment(\.motionConfig) private var motion

  public init(title: String = "🎉 Congratulations!", subtitle: String? = nil) {
    self.title = title
    self.subtitle = subtitle
  }

  public var body: some View {
    ZStack {
      ConfettiView()

      VStack(spacing: 12) {
        SuccessCheckmark(size: 80)

        Text(title)
          .font(.title.bold())
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : 20)

        if let subtitle {
          Text(subtitle)
            .font(.headline)
            .foregroundColor(.secondary)
            .opacity(showContent ? 1 : 0)
        }
      }
      .animation(motion.reduceMotion ? nil : .spring().delay(0.3), value: showContent)
    }
    .onAppear { showContent = true }
  }
}

#Preview {
  VStack {
    ConfettiView()
      .frame(width: 400, height: 300)

    CelebrationView(title: "Cleanup Complete!", subtitle: "Freed 2.5 GB")
      .frame(width: 400, height: 300)
  }
}
