import SwiftUI

// MARK: - Animated Button Style

/// Custom ButtonStyle with press-scale animation
/// Uses configuration.isPressed for accessibility compliance (not DragGesture)
public struct AnimatedButtonStyle: ButtonStyle {
  @Environment(\.motionConfig) private var motion

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !motion.reduceMotion ? 0.95 : 1.0)
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6),
        value: configuration.isPressed
      )
  }
}

// MARK: - Bordered Animated Style

/// Animated button with border and background feedback
public struct AnimatedBorderedButtonStyle: ButtonStyle {
  @Environment(\.motionConfig) private var motion
  let color: Color

  public init(color: Color = .accentColor) {
    self.color = color
  }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(configuration.isPressed ? color.opacity(0.2) : color.opacity(0.1))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(color, lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed && !motion.reduceMotion ? 0.97 : 1.0)
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7),
        value: configuration.isPressed
      )
  }
}

// MARK: - View Extensions

extension View {
  /// Applies animated button style with scale effect
  public func animatedButton() -> some View {
    buttonStyle(AnimatedButtonStyle())
  }

  /// Applies animated bordered button style
  public func animatedBorderedButton(color: Color = .accentColor) -> some View {
    buttonStyle(AnimatedBorderedButtonStyle(color: color))
  }
}
