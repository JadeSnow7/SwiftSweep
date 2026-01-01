import Foundation
import Logging

/// Context provided to a plugin during analysis.
/// safe file access and logging.
public struct PluginContext {
  public let logger: Logger
  public let rootURL: URL

  public init(logger: Logger, rootURL: URL) {
    self.logger = logger
    self.rootURL = rootURL
  }
}
