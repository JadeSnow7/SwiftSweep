import XCTest

@testable import SwiftSweepCore

final class DiagnosticsGuideTests: XCTestCase {
  func testGuideContainsExpectedMetadata() {
    let guide = DiagnosticsGuideService.shared.getGuide()

    XCTAssertFalse(guide.steps.isEmpty)
    XCTAssertEqual(guide.supportURL.absoluteString, "https://support.apple.com/en-us/102550")
    XCTAssertTrue(guide.notes.contains { $0.localizedCaseInsensitiveContains("Tahoe 26") })
  }

  func testGuideMatchesArchitecturePath() {
    let guide = DiagnosticsGuideService.shared.getGuide()

    switch guide.architecture {
    case .appleSilicon:
      XCTAssertTrue(guide.steps.contains { $0.contains("Command (⌘)-D") })
    case .intel:
      XCTAssertTrue(guide.steps.contains { $0.contains("hold D") })
    case .unknown:
      XCTAssertTrue(guide.steps.contains { $0.contains("holding D") || $0.contains("Command (⌘)-D") })
    }
  }
}
