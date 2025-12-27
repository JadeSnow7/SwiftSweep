import Foundation

// MARK: - RuleCategory

/// Categories for grouping recommendation rules
public enum RuleCategory: String, CaseIterable, Codable {
  case storage = "Storage"
  case privacy = "Privacy"
  case performance = "Performance"
  case security = "Security"

  public var icon: String {
    switch self {
    case .storage: return "internaldrive"
    case .privacy: return "hand.raised"
    case .performance: return "speedometer"
    case .security: return "lock.shield"
    }
  }
}

// MARK: - RuleSettings

/// Persistent settings for recommendation rules.
public final class RuleSettings: @unchecked Sendable {
  public static let shared = RuleSettings()

  private let userDefaults = UserDefaults.standard
  private let enabledRulesKey = "com.swiftsweep.enabledRules"
  private let thresholdsKey = "com.swiftsweep.ruleThresholds"

  /// All available rule IDs
  public static let allRuleIDs: [String] = [
    "low_disk_space",
    "old_downloads",
    "developer_caches",
    "large_caches",
    "unused_apps",
    "screenshot_cleanup",
    "browser_cache",
    "trash_reminder",
    "mail_attachments",
  ]

  /// Rule category mappings
  public static let ruleCategories: [String: RuleCategory] = [
    "low_disk_space": .storage,
    "old_downloads": .storage,
    "developer_caches": .storage,
    "large_caches": .storage,
    "unused_apps": .performance,
    "screenshot_cleanup": .storage,
    "browser_cache": .privacy,
    "trash_reminder": .storage,
    "mail_attachments": .privacy,
  ]

  /// Default thresholds for rules
  public static let defaultThresholds: [String: [String: Int]] = [
    "old_downloads": ["days": 30],
    "unused_apps": ["days": 90],
    "large_caches": ["sizeMB": 200],
    "trash_reminder": ["sizeMB": 1000],
    "low_disk_space": ["usagePercent": 80],
  ]

  private init() {}

  // MARK: - Enabled Rules

  /// Get enabled rule IDs. Returns all rules if not customized.
  public var enabledRuleIDs: Set<String> {
    get {
      if let array = userDefaults.array(forKey: enabledRulesKey) as? [String] {
        return Set(array)
      }
      return Set(RuleSettings.allRuleIDs)
    }
    set {
      userDefaults.set(Array(newValue), forKey: enabledRulesKey)
    }
  }

  /// Check if a rule is enabled
  public func isRuleEnabled(_ ruleID: String) -> Bool {
    enabledRuleIDs.contains(ruleID)
  }

  /// Enable or disable a rule
  public func setRuleEnabled(_ ruleID: String, enabled: Bool) {
    var current = enabledRuleIDs
    if enabled {
      current.insert(ruleID)
    } else {
      current.remove(ruleID)
    }
    enabledRuleIDs = current
  }

  /// Reset to default (all enabled)
  public func resetToDefaults() {
    userDefaults.removeObject(forKey: enabledRulesKey)
    userDefaults.removeObject(forKey: thresholdsKey)
  }

  // MARK: - Thresholds

  /// Get custom threshold for a rule, falling back to default
  public func threshold(forRule ruleID: String, key: String) -> Int {
    // Check custom first
    if let thresholds = userDefaults.dictionary(forKey: thresholdsKey) as? [String: [String: Int]],
      let ruleThresholds = thresholds[ruleID],
      let value = ruleThresholds[key]
    {
      return value
    }
    // Fall back to default
    return RuleSettings.defaultThresholds[ruleID]?[key] ?? 0
  }

  /// Set custom threshold for a rule
  public func setThreshold(forRule ruleID: String, key: String, value: Int) {
    var thresholds =
      userDefaults.dictionary(forKey: thresholdsKey) as? [String: [String: Int]] ?? [:]
    var ruleThresholds = thresholds[ruleID] ?? [:]
    ruleThresholds[key] = value
    thresholds[ruleID] = ruleThresholds
    userDefaults.set(thresholds, forKey: thresholdsKey)
  }

  // MARK: - Category Helpers

  /// Get category for a rule
  public static func category(for ruleID: String) -> RuleCategory {
    ruleCategories[ruleID] ?? .storage
  }

  /// Get all rules in a category
  public static func rules(in category: RuleCategory) -> [String] {
    allRuleIDs.filter { ruleCategories[$0] == category }
  }
}

// MARK: - Rule Display Info

extension RuleSettings {
  /// Human-readable rule names
  public static func displayName(for ruleID: String) -> String {
    switch ruleID {
    case "low_disk_space": return "低磁盘空间告警"
    case "old_downloads": return "旧下载文件"
    case "developer_caches": return "开发者缓存"
    case "large_caches": return "大型应用缓存"
    case "unused_apps": return "未使用应用"
    case "screenshot_cleanup": return "截图/临时文件"
    case "browser_cache": return "浏览器缓存"
    case "trash_reminder": return "废纸篓提醒"
    case "mail_attachments": return "邮件附件"
    default: return ruleID
    }
  }

  /// Rule descriptions
  public static func description(for ruleID: String) -> String {
    switch ruleID {
    case "low_disk_space": return "磁盘使用率超过阈值时告警"
    case "old_downloads": return "检测下载文件夹中的旧文件"
    case "developer_caches": return "检测Xcode、CocoaPods等开发工具缓存"
    case "large_caches": return "检测超过阈值的应用缓存"
    case "unused_apps": return "检测长时间未使用的应用"
    case "screenshot_cleanup": return "检测桌面上的旧截图和临时文件"
    case "browser_cache": return "检测Safari、Chrome等浏览器缓存"
    case "trash_reminder": return "废纸篓超过阈值时提醒清空"
    case "mail_attachments": return "检测并清理邮件附件缓存"
    default: return ""
    }
  }
}
