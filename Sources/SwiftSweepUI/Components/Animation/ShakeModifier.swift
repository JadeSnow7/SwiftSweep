import SwiftUI

// MARK: - Shake Effect

/// Geometry effect for shake animation
public struct ShakeEffect: GeometryEffect {
  var amount: CGFloat = 10
  var shakesPerUnit: CGFloat = 3
  public var animatableData: CGFloat

  public init(amount: CGFloat = 10, shakesPerUnit: CGFloat = 3, animatableData: CGFloat) {
    self.amount = amount
    self.shakesPerUnit = shakesPerUnit
    self.animatableData = animatableData
  }

  public func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(
      CGAffineTransform(
        translationX: amount * sin(animatableData * .pi * shakesPerUnit),
        y: 0
      ))
  }
}

// MARK: - Shake Modifier

public struct ShakeModifier: ViewModifier {
  let trigger: Bool
  let amount: CGFloat

  @State private var shakeValue: CGFloat = 0
  @Environment(\.motionConfig) private var motion

  public init(trigger: Bool, amount: CGFloat = 10) {
    self.trigger = trigger
    self.amount = amount
  }

  public func body(content: Content) -> some View {
    content
      .modifier(ShakeEffect(amount: amount, animatableData: shakeValue))
      .onChange(of: trigger) { newValue in
        guard newValue && !motion.reduceMotion else { return }
        withAnimation(.linear(duration: 0.4)) {
          shakeValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          shakeValue = 0
        }
      }
  }
}

// MARK: - View Extension

extension View {
  /// Applies shake animation when trigger becomes true
  /// - Parameters:
  ///   - trigger: Boolean that triggers shake when becoming true
  ///   - amount: Horizontal shake distance in points
  public func shake(trigger: Bool, amount: CGFloat = 10) -> some View {
    modifier(ShakeModifier(trigger: trigger, amount: amount))
  }
}

// MARK: - Error Indicator

/// Error view with shake animation
public struct ErrorIndicator: View {
  let message: String
  @State private var shouldShake = false

  public init(message: String) {
    self.message = message
  }

  public var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "xmark.circle.fill")
        .foregroundColor(.red)
      Text(message)
        .foregroundColor(.red)
    }
    .shake(trigger: shouldShake)
    .onAppear {
      shouldShake = true
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    ErrorIndicator(message: "Failed to delete file")
  }
  .padding()
}
