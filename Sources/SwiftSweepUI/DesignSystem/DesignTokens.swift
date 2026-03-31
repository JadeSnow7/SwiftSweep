import SwiftUI

// MARK: - Spacing

enum Spacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 20
  static let xxl: CGFloat = 24
}

// MARK: - Corner Radius

enum Radius {
  static let sm: CGFloat = 8
  static let md: CGFloat = 10
  static let lg: CGFloat = 12
}

// MARK: - Color tokens

extension Color {
  /// Standard card / panel background (respects dark mode)
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
  /// 12 % primary-color tint — selected / active state borders
  static let borderPrimary = Color.primary.opacity(0.12)
  /// 8 % gray tint — default card border
  static let borderSubtle = Color.gray.opacity(0.15)
  /// 5 % primary tint — hover / subtle fill
  static let subtleFill = Color.primary.opacity(0.05)
}
