import XCTest

@testable import SwiftSweepCLI

final class CLIPeripheralsFormattingTests: XCTestCase {
  func testPeripheralBuiltInLabelTriState() {
    XCTAssertEqual(peripheralBuiltInLabel(true), "Built-in")
    XCTAssertEqual(peripheralBuiltInLabel(false), "External")
    XCTAssertEqual(peripheralBuiltInLabel(nil), "Unknown")
  }
}
