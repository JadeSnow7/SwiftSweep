import Foundation

/// Natural Language Command Parser
/// Converts user natural language input into filter conditions or actions.
/// This is a rule-based implementation (not LLM) to demonstrate the concept.
public struct NLCommandParser: Sendable {
  public static let shared = NLCommandParser()

  private init() {}

  /// Parse a natural language command into a structured result.
  /// - Parameter input: User's natural language input.
  /// - Returns: A parsed command result, or nil if unparseable.
  public func parse(_ input: String) -> ParsedCommand? {
    let lowercased = input.lowercased()

    // Size-based commands
    if let sizeCommand = parseSizeCommand(lowercased) {
      return sizeCommand
    }

    // Time-based commands
    if let timeCommand = parseTimeCommand(lowercased) {
      return timeCommand
    }

    // Category commands
    if let categoryCommand = parseCategoryCommand(lowercased) {
      return categoryCommand
    }

    // Action commands
    if let actionCommand = parseActionCommand(lowercased) {
      return actionCommand
    }

    return nil
  }

  // MARK: - Size Parsing

  private func parseSizeCommand(_ input: String) -> ParsedCommand? {
    // Patterns: "larger than 2GB", "over 500MB", "bigger than 1 GB"
    let sizePatterns = [
      "larger than", "bigger than", "over", "exceeds", "more than",
      "大于", "超过",
    ]

    for pattern in sizePatterns {
      if input.contains(pattern) {
        if let size = extractSize(from: input) {
          return ParsedCommand(
            type: .filter,
            filter: FilterCondition(field: .size, comparator: .greaterThan, value: .bytes(size)),
            action: nil,
            originalInput: input
          )
        }
      }
    }

    let smallerPatterns = ["smaller than", "less than", "under", "小于"]
    for pattern in smallerPatterns {
      if input.contains(pattern) {
        if let size = extractSize(from: input) {
          return ParsedCommand(
            type: .filter,
            filter: FilterCondition(field: .size, comparator: .lessThan, value: .bytes(size)),
            action: nil,
            originalInput: input
          )
        }
      }
    }

    return nil
  }

  private func extractSize(from input: String) -> Int64? {
    // Match patterns like "2GB", "500 MB", "1.5 GB"
    let pattern = #"(\d+\.?\d*)\s*(gb|mb|kb|g|m|k)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return nil
    }

    let range = NSRange(input.startIndex..., in: input)
    guard let match = regex.firstMatch(in: input, options: [], range: range) else {
      return nil
    }

    guard let numberRange = Range(match.range(at: 1), in: input),
      let unitRange = Range(match.range(at: 2), in: input)
    else {
      return nil
    }

    guard let number = Double(input[numberRange]) else { return nil }
    let unit = String(input[unitRange]).lowercased()

    let multiplier: Int64
    switch unit {
    case "gb", "g": multiplier = 1_000_000_000
    case "mb", "m": multiplier = 1_000_000
    case "kb", "k": multiplier = 1_000
    default: multiplier = 1
    }

    return Int64(number * Double(multiplier))
  }

  // MARK: - Time Parsing

  private func parseTimeCommand(_ input: String) -> ParsedCommand? {
    // Patterns: "older than 30 days", "not used for 3 months"
    let timePatterns = ["older than", "not used for", "unused for", "超过", "天未使用"]

    for pattern in timePatterns {
      if input.contains(pattern) {
        if let days = extractDays(from: input) {
          return ParsedCommand(
            type: .filter,
            filter: FilterCondition(field: .age, comparator: .greaterThan, value: .days(days)),
            action: nil,
            originalInput: input
          )
        }
      }
    }

    return nil
  }

  private func extractDays(from input: String) -> Int? {
    // Match "30 days", "3 months", "1 year"
    let dayPattern = #"(\d+)\s*(days?|天)"#
    let monthPattern = #"(\d+)\s*(months?|月)"#
    let yearPattern = #"(\d+)\s*(years?|年)"#

    if let regex = try? NSRegularExpression(pattern: dayPattern, options: .caseInsensitive),
      let match = regex.firstMatch(
        in: input, options: [], range: NSRange(input.startIndex..., in: input)),
      let range = Range(match.range(at: 1), in: input),
      let days = Int(input[range])
    {
      return days
    }

    if let regex = try? NSRegularExpression(pattern: monthPattern, options: .caseInsensitive),
      let match = regex.firstMatch(
        in: input, options: [], range: NSRange(input.startIndex..., in: input)),
      let range = Range(match.range(at: 1), in: input),
      let months = Int(input[range])
    {
      return months * 30
    }

    if let regex = try? NSRegularExpression(pattern: yearPattern, options: .caseInsensitive),
      let match = regex.firstMatch(
        in: input, options: [], range: NSRange(input.startIndex..., in: input)),
      let range = Range(match.range(at: 1), in: input),
      let years = Int(input[range])
    {
      return years * 365
    }

    return nil
  }

  // MARK: - Category Parsing

  private func parseCategoryCommand(_ input: String) -> ParsedCommand? {
    let categoryMap: [(keywords: [String], category: String)] = [
      (["cache", "缓存"], "cache"),
      (["download", "下载"], "downloads"),
      (["screenshot", "截图"], "screenshots"),
      (["log", "日志"], "logs"),
      (["trash", "垃圾", "废纸篓"], "trash"),
    ]

    for (keywords, category) in categoryMap {
      for keyword in keywords {
        if input.contains(keyword) {
          return ParsedCommand(
            type: .filter,
            filter: FilterCondition(
              field: .category, comparator: .equals, value: .string(category)),
            action: nil,
            originalInput: input
          )
        }
      }
    }

    return nil
  }

  // MARK: - Action Parsing

  private func parseActionCommand(_ input: String) -> ParsedCommand? {
    let cleanKeywords = ["clean", "clear", "delete", "remove", "清理", "删除", "清空"]
    let scanKeywords = ["scan", "analyze", "check", "扫描", "分析", "检查"]

    for keyword in cleanKeywords {
      if input.contains(keyword) {
        return ParsedCommand(
          type: .action,
          filter: nil,
          action: .clean,
          originalInput: input
        )
      }
    }

    for keyword in scanKeywords {
      if input.contains(keyword) {
        return ParsedCommand(
          type: .action,
          filter: nil,
          action: .scan,
          originalInput: input
        )
      }
    }

    return nil
  }
}

// MARK: - Supporting Types

public struct ParsedCommand: Sendable {
  public let type: CommandType
  public let filter: FilterCondition?
  public let action: CommandAction?
  public let originalInput: String
}

public enum CommandType: Sendable {
  case filter
  case action
}

public struct FilterCondition: Sendable {
  public let field: FilterField
  public let comparator: FilterComparator
  public let value: FilterValue
}

public enum FilterField: Sendable {
  case size
  case age
  case category
  case name
}

public enum FilterComparator: Sendable {
  case greaterThan
  case lessThan
  case equals
  case contains
}

public enum FilterValue: Sendable {
  case bytes(Int64)
  case days(Int)
  case string(String)
}

public enum CommandAction: Sendable {
  case clean
  case scan
  case preview
}
