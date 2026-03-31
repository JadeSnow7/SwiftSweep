import SwiftUI

// MARK: - Card style

struct CardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(Spacing.lg)
      .background(Color.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg)
          .stroke(Color.borderSubtle, lineWidth: 1)
      )
  }
}

extension View {
  /// Applies the standard SwiftSweep card appearance.
  func cardStyle() -> some View {
    modifier(CardModifier())
  }
}
