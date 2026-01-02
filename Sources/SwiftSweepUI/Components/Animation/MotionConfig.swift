import SwiftUI

// MARK: - Motion Configuration

/// Global motion configuration for accessibility and performance
/// Centralizes reduceMotion handling and animation timing
public struct MotionConfig {
  public let reduceMotion: Bool
  public let durationFactor: Double

  public var standardDuration: Double { 0.3 * durationFactor }
  public var springResponse: Double { reduceMotion ? 0 : 0.4 }
  public var springDamping: Double { 0.7 }

  public init(reduceMotion: Bool, durationFactor: Double = 1.0) {
    self.reduceMotion = reduceMotion
    self.durationFactor = reduceMotion ? 0 : durationFactor
  }

  public static func from(environment: EnvironmentValues) -> MotionConfig {
    MotionConfig(
      reduceMotion: environment.accessibilityReduceMotion,
      durationFactor: environment.accessibilityReduceMotion ? 0 : 1
    )
  }
}

// MARK: - Environment Key

private struct MotionConfigKey: EnvironmentKey {
  static let defaultValue = MotionConfig(reduceMotion: false, durationFactor: 1)
}

extension EnvironmentValues {
  public var motionConfig: MotionConfig {
    get { self[MotionConfigKey.self] }
    set { self[MotionConfigKey.self] = newValue }
  }
}

// MARK: - Modifier

/// Automatically injects MotionConfig based on system accessibility settings
public struct MotionConfigModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public func body(content: Content) -> some View {
    content.environment(
      \.motionConfig,
      MotionConfig(
        reduceMotion: reduceMotion,
        durationFactor: reduceMotion ? 0 : 1
      ))
  }
}

extension View {
  /// Applies global motion configuration based on accessibility settings
  public func withMotionConfig() -> some View {
    modifier(MotionConfigModifier())
  }
}
