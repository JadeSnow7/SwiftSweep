import SwiftUI

// MARK: - Hover Card

/// Card container with hover shadow and scale effect
public struct HoverCard<Content: View>: View {
  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  let cornerRadius: CGFloat
  @ViewBuilder let content: () -> Content

  public init(cornerRadius: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
    self.cornerRadius = cornerRadius
    self.content = content
  }

  public var body: some View {
    content()
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color(nsColor: .controlBackgroundColor))
          .shadow(
            color: .black.opacity(isHovered ? 0.15 : 0.05),
            radius: isHovered ? 12 : 4,
            y: isHovered ? 6 : 2
          )
      )
      .scaleEffect(isHovered && !motion.reduceMotion ? 1.02 : 1.0)
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
        value: isHovered
      )
      .onHover { isHovered = $0 }
  }
}

// MARK: - Hover Highlight

/// Simple hover highlight modifier for list items
public struct HoverHighlightModifier: ViewModifier {
  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  let cornerRadius: CGFloat
  let highlightColor: Color

  public init(cornerRadius: CGFloat = 8, highlightColor: Color = .accentColor) {
    self.cornerRadius = cornerRadius
    self.highlightColor = highlightColor
  }

  public func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(highlightColor.opacity(isHovered ? 0.1 : 0))
      )
      .animation(
        motion.reduceMotion ? nil : .easeInOut(duration: 0.15),
        value: isHovered
      )
      .onHover { isHovered = $0 }
  }
}

extension View {
  /// Applies hover highlight effect
  public func hoverHighlight(
    cornerRadius: CGFloat = 8,
    color: Color = .accentColor
  ) -> some View {
    modifier(HoverHighlightModifier(cornerRadius: cornerRadius, highlightColor: color))
  }
}

#Preview {
  VStack(spacing: 20) {
    HoverCard {
      VStack(alignment: .leading) {
        Text("Hover Card")
          .font(.headline)
        Text("Hover to see the effect")
          .foregroundColor(.secondary)
      }
      .padding()
    }

    Text("Hover Highlight Item")
      .padding()
      .hoverHighlight()
  }
  .padding()
}
