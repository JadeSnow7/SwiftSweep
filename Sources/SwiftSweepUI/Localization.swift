import Foundation
import SwiftUI

/// Localization helper for SwiftSweep
extension String {
  /// Returns a localized string using the key as the lookup
  var localized: String {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    return NSLocalizedString(self, tableName: nil, bundle: bundle, value: self, comment: "")
  }

  /// Returns a localized string with format arguments
  func localized(_ args: CVarArg...) -> String {
    String(format: self.localized, arguments: args)
  }
}

/// LocalizedStringKey helper
extension LocalizedStringKey {
  /// Creates a LocalizedStringKey from a string key
  static func key(_ key: String) -> LocalizedStringKey {
    LocalizedStringKey(key)
  }
}

/// Localization keys namespace
enum L10n {
  // MARK: - Navigation
  enum Nav {
    static let system = "nav.system"
    static let status = "nav.status"
    static let maintenance = "nav.maintenance"
    static let clean = "nav.clean"
    static let uninstall = "nav.uninstall"
    static let optimize = "nav.optimize"
    static let tools = "nav.tools"
    static let analyze = "nav.analyze"
    static let applications = "nav.applications"
    static let packages = "nav.packages"
    static let settings = "nav.settings"
  }

  // MARK: - Status
  enum Status {
    static let title = "status.title"
    static let cpu = "status.cpu"
    static let memory = "status.memory"
    static let disk = "status.disk"
    static let network = "status.network"
    static let battery = "status.battery"
    static let used = "status.used"
    static let free = "status.free"
  }

  // MARK: - Clean
  enum Clean {
    static let title = "clean.title"
    static let scan = "clean.scan"
    static let scanning = "clean.scanning"
    static let clean = "clean.clean"
    static let noItems = "clean.noItems"
    static let totalSize = "clean.totalSize"
    static let selectAll = "clean.selectAll"
    static let deselectAll = "clean.deselectAll"
  }

  // MARK: - Uninstall
  enum Uninstall {
    static let title = "uninstall.title"
    static let search = "uninstall.search"
    static let noApps = "uninstall.noApps"
    static let loading = "uninstall.loading"
    static let appSize = "uninstall.appSize"
    static let residualFiles = "uninstall.residualFiles"
    static let totalSize = "uninstall.totalSize"
    static let uninstall = "uninstall.uninstall"
    static let confirm = "uninstall.confirm"
    static let confirmMessage = "uninstall.confirmMessage"
    static let cancel = "uninstall.cancel"
  }

  // MARK: - Optimize
  enum Optimize {
    static let title = "optimize.title"
    static let run = "optimize.run"
    static let running = "optimize.running"
    static let success = "optimize.success"
    static let failed = "optimize.failed"
  }

  // MARK: - Analyze
  enum Analyze {
    static let title = "analyze.title"
    static let selectFolder = "analyze.selectFolder"
    static let analyzing = "analyze.analyzing"
    static let topFiles = "analyze.topFiles"
    static let topFolders = "analyze.topFolders"
    static let totalSize = "analyze.totalSize"
  }

  // MARK: - Settings
  enum Settings {
    static let title = "settings.title"
    static let general = "settings.general"
    static let language = "settings.language"
    static let about = "settings.about"
    static let version = "settings.version"
  }

  // MARK: - Common
  enum Common {
    static let ok = "common.ok"
    static let cancel = "common.cancel"
    static let done = "common.done"
    static let error = "common.error"
    static let success = "common.success"
    static let loading = "common.loading"
    static let refresh = "common.refresh"
    static let delete = "common.delete"
    static let open = "common.open"
    static let openInFinder = "common.openInFinder"
  }
}
