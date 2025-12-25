import Foundation

// MARK: - EcosystemDescriptor

/// 生态系统描述协议 (支持插件扩展)
public protocol EcosystemDescriptor: Sendable {
  static var identifier: String { get }
  static var displayName: String { get }
  static var iconName: String { get }
}

// MARK: - Built-in Ecosystems

public struct HomebrewFormulaEcosystem: EcosystemDescriptor {
  public static let identifier = "homebrew_formula"
  public static let displayName = "Homebrew"
  public static let iconName = "mug"
}

public struct HomebrewCaskEcosystem: EcosystemDescriptor {
  public static let identifier = "homebrew_cask"
  public static let displayName = "Homebrew Cask"
  public static let iconName = "macwindow"
}

public struct NpmEcosystem: EcosystemDescriptor {
  public static let identifier = "npm"
  public static let displayName = "npm"
  public static let iconName = "shippingbox"
}

public struct PipEcosystem: EcosystemDescriptor {
  public static let identifier = "pip"
  public static let displayName = "pip"
  public static let iconName = "cube"
}

public struct GemEcosystem: EcosystemDescriptor {
  public static let identifier = "gem"
  public static let displayName = "RubyGems"
  public static let iconName = "diamond"
}

// MARK: - EcosystemRegistry

/// 生态系统注册表 (支持动态注册)
public actor EcosystemRegistry {
  public static let shared = EcosystemRegistry()

  private var descriptors: [String: any EcosystemDescriptor.Type] = [:]

  private init() {
    // 注册内置生态系统
    registerBuiltins()
  }

  private func registerBuiltins() {
    register(HomebrewFormulaEcosystem.self)
    register(HomebrewCaskEcosystem.self)
    register(NpmEcosystem.self)
    register(PipEcosystem.self)
    register(GemEcosystem.self)
  }

  /// 注册新的生态系统描述
  public func register<T: EcosystemDescriptor>(_ descriptor: T.Type) {
    descriptors[descriptor.identifier] = descriptor
  }

  /// 获取生态系统描述
  public func descriptor(for id: String) -> (any EcosystemDescriptor.Type)? {
    descriptors[id]
  }

  /// 获取显示名称
  public func displayName(for id: String) -> String {
    descriptor(for: id)?.displayName ?? id
  }

  /// 获取图标名称
  public func iconName(for id: String) -> String {
    descriptor(for: id)?.iconName ?? "shippingbox"
  }

  /// 所有已注册的生态系统 ID
  public var allIds: [String] {
    Array(descriptors.keys).sorted()
  }
}
