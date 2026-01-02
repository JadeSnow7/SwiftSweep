import SwiftUI

// MARK: - Sidebar Row with Hover Effect

/// Custom sidebar row with hover animation effect
public struct SidebarRow<Content: View>: View {
  let content: Content

  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
      )
      .scaleEffect(isHovered && !motion.reduceMotion ? 1.02 : 1.0)
      .animation(
        motion.reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
        value: isHovered
      )
      .onHover { isHovered = $0 }
  }
}

// MARK: - Animated Navigation Link

/// NavigationLink with hover animation for sidebar
public struct AnimatedNavigationLink<Value: Hashable>: View {
  let value: Value
  let title: String
  let icon: String

  @State private var isHovered = false
  @Environment(\.motionConfig) private var motion

  public init(value: Value, title: String, icon: String) {
    self.value = value
    self.title = title
    self.icon = icon
  }

  public var body: some View {
    NavigationLink(value: value) {
      Label(title, systemImage: icon)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .shadow(
          color: isHovered ? Color.accentColor.opacity(0.1) : Color.clear,
          radius: isHovered ? 4 : 0,
          y: isHovered ? 2 : 0
        )
    )
    .scaleEffect(isHovered && !motion.reduceMotion ? 1.01 : 1.0)
    .animation(
      motion.reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8),
      value: isHovered
    )
    .onHover { isHovered = $0 }
  }
}

// MARK: - Responsive Layout Utilities

/// Size class for responsive layout
public enum ResponsiveSizeClass {
  case compact  // < 600px
  case regular  // 600-900px
  case expanded  // > 900px

  public static func from(width: CGFloat) -> ResponsiveSizeClass {
    if width < 600 { return .compact }
    if width < 900 { return .regular }
    return .expanded
  }
}

/// Environment key for size class
private struct ResponsiveSizeClassKey: EnvironmentKey {
  static let defaultValue: ResponsiveSizeClass = .regular
}

extension EnvironmentValues {
  public var responsiveSizeClass: ResponsiveSizeClass {
    get { self[ResponsiveSizeClassKey.self] }
    set { self[ResponsiveSizeClassKey.self] = newValue }
  }
}

/// Modifier to automatically update size class based on view width
public struct ResponsiveModifier: ViewModifier {
  @State private var sizeClass: ResponsiveSizeClass = .regular

  public func body(content: Content) -> some View {
    GeometryReader { geo in
      content
        .environment(\.responsiveSizeClass, ResponsiveSizeClass.from(width: geo.size.width))
        .onAppear {
          sizeClass = ResponsiveSizeClass.from(width: geo.size.width)
        }
        .onChange(of: geo.size.width) { newWidth in
          sizeClass = ResponsiveSizeClass.from(width: newWidth)
        }
    }
  }
}

extension View {
  /// Enables responsive size class environment values
  public func responsive() -> some View {
    modifier(ResponsiveModifier())
  }
}

// MARK: - Adaptive Grid

/// Grid that adapts column count based on available width
public struct AdaptiveGrid<Content: View>: View {
  let minItemWidth: CGFloat
  let spacing: CGFloat
  @ViewBuilder let content: () -> Content

  @Environment(\.responsiveSizeClass) private var sizeClass

  public init(
    minItemWidth: CGFloat = 200, spacing: CGFloat = 16,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.minItemWidth = minItemWidth
    self.spacing = spacing
    self.content = content
  }

  public var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: minItemWidth), spacing: spacing)],
      spacing: spacing
    ) {
      content()
    }
  }
}

// MARK: - Responsive Stack

/// Stack that switches between horizontal and vertical based on size class
public struct ResponsiveStack<Content: View>: View {
  let horizontalAlignment: HorizontalAlignment
  let verticalAlignment: VerticalAlignment
  let spacing: CGFloat
  @ViewBuilder let content: () -> Content

  @Environment(\.responsiveSizeClass) private var sizeClass

  public init(
    horizontalAlignment: HorizontalAlignment = .center,
    verticalAlignment: VerticalAlignment = .center,
    spacing: CGFloat = 16,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.horizontalAlignment = horizontalAlignment
    self.verticalAlignment = verticalAlignment
    self.spacing = spacing
    self.content = content
  }

  public var body: some View {
    Group {
      if sizeClass == .compact {
        VStack(alignment: horizontalAlignment, spacing: spacing) {
          content()
        }
      } else {
        HStack(alignment: verticalAlignment, spacing: spacing) {
          content()
        }
      }
    }
  }
}

// MARK: - Sidebar Width Preference

/// Preference key for sidebar width
public struct SidebarWidthKey: PreferenceKey {
  public static var defaultValue: CGFloat = 250
  public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

#Preview {
  VStack(spacing: 20) {
    AnimatedNavigationLink(value: "test", title: "Test Item", icon: "star")
    AnimatedNavigationLink(value: "test2", title: "Another Item", icon: "heart")
  }
  .padding()
  .withMotionConfig()
}
