import XCTest

@testable import SwiftSweepCore
@testable import SwiftSweepUI

@MainActor
final class PeripheralsSheetLocalizationTests: XCTestCase {
  func testLocalizedDeviceKindLabelsInEnglish() {
    let previousLanguage = LanguageManager.shared.currentLanguage
    defer { LanguageManager.shared.currentLanguage = previousLanguage }

    LanguageManager.shared.currentLanguage = "en"

    XCTAssertEqual(localizedDeviceKindLabel(.keyboard), "Keyboard")
    XCTAssertEqual(localizedDeviceKindLabel(.mouse), "Mouse")
    XCTAssertEqual(localizedDeviceKindLabel(.trackpad), "Trackpad")
    XCTAssertEqual(localizedDeviceKindLabel(.other), "Other")
    XCTAssertEqual(L10n.Status.na.localized, "N/A")
  }
}
