import SwiftUI

// MARK: - Slide In Modifier

/// Animates list items sliding in from the right with staggered delay
/// Uses task(id:) to properly handle List cell reuse
public struct SlideInModifier<ID: Hashable>: ViewModifier {
  let id: ID
  let index: Int
  let maxDelay: Double

  @State private var appeared = false
  @Environment(\.motionConfig) private var motion

  public init(id: ID, index: Int, maxDelay: Double = 0.5) {
    self.id = id
    self.index = index
    self.maxDelay = maxDelay
  }

  public func body(content: Content) -> some View {
    content
      .offset(x: appeared || motion.reduceMotion ? 0 : 50)
      .opacity(appeared || motion.reduceMotion ? 1 : 0)
      .animation(
        motion.reduceMotion
          ? nil
          : .spring(response: 0.4, dampingFraction: 0.7)
            .delay(min(Double(index) * 0.05, maxDelay)),
        value: appeared
      )
      .task(id: id) {
        // Reset and trigger animation when id changes (cell reuse)
        appeared = false
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        appeared = true
      }
      .onDisappear { appeared = false }
  }
}

// MARK: - Fade In Modifier

/// Simple fade-in animation without horizontal offset
public struct FadeInModifier<ID: Hashable>: ViewModifier {
  let id: ID
  let index: Int

  @State private var appeared = false
  @Environment(\.motionConfig) private var motion

  public init(id: ID, index: Int) {
    self.id = id
    self.index = index
  }

  public func body(content: Content) -> some View {
    content
      .opacity(appeared || motion.reduceMotion ? 1 : 0)
      .scaleEffect(appeared || motion.reduceMotion ? 1 : 0.95)
      .animation(
        motion.reduceMotion
          ? nil
          : .easeOut(duration: 0.25)
            .delay(Double(index) * 0.03),
        value: appeared
      )
      .task(id: id) {
        appeared = false
        try? await Task.sleep(nanoseconds: 10_000_000)
        appeared = true
      }
  }
}

// MARK: - View Extensions

extension View {
  /// Applies slide-in animation from right with staggered delay
  /// - Parameters:
  ///   - id: Unique identifier for this item (for cell reuse handling)
  ///   - index: Position in list for stagger calculation
  public func slideIn<ID: Hashable>(id: ID, index: Int) -> some View {
    modifier(SlideInModifier(id: id, index: index))
  }

  /// Applies fade-in animation with staggered delay
  public func fadeIn<ID: Hashable>(id: ID, index: Int) -> some View {
    modifier(FadeInModifier(id: id, index: index))
  }
}
