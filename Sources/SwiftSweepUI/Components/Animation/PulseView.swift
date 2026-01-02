import SwiftUI

// MARK: - Pulse View

/// Pulsing animation for scanning/loading states
public struct PulseView: View {
  let icon: String
  let color: Color

  @State private var isPulsing = false
  @Environment(\.motionConfig) private var motion

  public init(icon: String = "magnifyingglass", color: Color = .blue) {
    self.icon = icon
    self.color = color
  }

  public var body: some View {
    ZStack {
      // Pulse rings (only when motion allowed)
      if !motion.reduceMotion {
        ForEach(0..<3, id: \.self) { i in
          Circle()
            .stroke(color.opacity(0.3), lineWidth: 2)
            .scaleEffect(isPulsing ? 2 : 1)
            .opacity(isPulsing ? 0 : 1)
            .animation(
              .easeOut(duration: 1.5)
                .repeatForever(autoreverses: false)
                .delay(Double(i) * 0.5),
              value: isPulsing
            )
        }
      }

      // Center icon
      Image(systemName: icon)
        .font(.title)
        .foregroundColor(color)
    }
    .frame(width: 60, height: 60)
    .onAppear {
      if !motion.reduceMotion {
        isPulsing = true
      }
    }
  }
}

// MARK: - Scanning Indicator

/// Full scanning indicator with pulse and label
public struct ScanningIndicator: View {
  let message: String

  @Environment(\.motionConfig) private var motion

  public init(message: String = "Scanning...") {
    self.message = message
  }

  public var body: some View {
    VStack(spacing: 16) {
      PulseView()

      Text(message)
        .font(.headline)
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  VStack(spacing: 40) {
    PulseView()
    PulseView(icon: "folder", color: .orange)
    ScanningIndicator(message: "Analyzing files...")
  }
  .padding()
}
