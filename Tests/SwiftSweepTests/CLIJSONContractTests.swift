import Foundation
import XCTest

@testable import SwiftSweepCLI
@testable import SwiftSweepCore

final class CLIJSONContractTests: XCTestCase {
  func testPeripheralJSONIncludesNullKeysForOptionalValues() throws {
    let snapshot = PeripheralSnapshot(
      displays: [
        DisplayInfo(
          id: "display-1",
          name: nil,
          isBuiltin: nil,
          isMain: nil,
          pixelsWidth: nil,
          pixelsHeight: nil,
          vendorID: nil,
          modelID: nil,
          serialNumber: nil
        )
      ],
      inputDevices: [
        InputDeviceInfo(
          id: "hid-1",
          kind: .keyboard,
          name: nil,
          transport: nil,
          vendorID: nil,
          productID: nil,
          isBuiltin: nil,
          location: nil
        )
      ],
      collectedAt: Date(timeIntervalSince1970: 1_735_000_000)
    )

    let data = try JSONEncoder().encode(PeripheralSnapshotJSONDTO(snapshot: snapshot))
    let jsonObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    let displays = try XCTUnwrap(jsonObject["displays"] as? [[String: Any]])
    let display = try XCTUnwrap(displays.first)
    XCTAssertTrue(display["name"] is NSNull)
    XCTAssertTrue(display["serial_number"] is NSNull)
    XCTAssertTrue(display["vendor_id"] is NSNull)

    let inputDevices = try XCTUnwrap(jsonObject["input_devices"] as? [[String: Any]])
    let input = try XCTUnwrap(inputDevices.first)
    XCTAssertTrue(input["transport"] is NSNull)
    XCTAssertTrue(input["location"] is NSNull)
    XCTAssertTrue(input["is_builtin"] is NSNull)
  }

  func testPeripheralJSONUsesISO8601CollectedAt() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_735_000_000)
    let snapshot = PeripheralSnapshot(collectedAt: fixedDate)
    let data = try JSONEncoder().encode(PeripheralSnapshotJSONDTO(snapshot: snapshot))
    let jsonObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let collectedAt = try XCTUnwrap(jsonObject["collected_at"] as? String)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    XCTAssertNotNil(formatter.date(from: collectedAt))
  }
}
