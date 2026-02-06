import XCTest

@testable import SwiftSweepCore

final class PeripheralInspectorTests: XCTestCase {
  func testSnapshotContainsProviderData() async {
    let inspector = PeripheralInspector(
      displayProvider: FakeDisplayProvider(),
      hidProvider: FakeHIDProvider()
    )

    let snapshot = await inspector.getSnapshot(includeSensitive: true)

    XCTAssertEqual(snapshot.displays.count, 1)
    XCTAssertEqual(snapshot.inputDevices.count, 1)
    XCTAssertEqual(snapshot.displays.first?.name, "Studio Display")
    XCTAssertEqual(snapshot.inputDevices.first?.kind, .keyboard)
  }

  func testSensitiveFlagPassThrough() async {
    let inspector = PeripheralInspector(
      displayProvider: FakeDisplayProvider(),
      hidProvider: FakeHIDProvider()
    )

    let redacted = await inspector.getSnapshot(includeSensitive: false)
    XCTAssertNil(redacted.displays.first?.serialNumber)
    XCTAssertNil(redacted.inputDevices.first?.location)

    let sensitive = await inspector.getSnapshot(includeSensitive: true)
    XCTAssertEqual(sensitive.displays.first?.serialNumber, "SERIAL-001")
    XCTAssertEqual(sensitive.inputDevices.first?.location, "0x00112233")
  }

  func testSnapshotSupportsMultipleDisplays() async {
    let inspector = PeripheralInspector(
      displayProvider: MultiDisplayProvider(),
      hidProvider: EmptyHIDProvider()
    )

    let snapshot = await inspector.getSnapshot(includeSensitive: false)
    XCTAssertEqual(snapshot.displays.count, 2)
    XCTAssertEqual(snapshot.displays.filter { $0.isBuiltin == true }.count, 1)
    XCTAssertEqual(snapshot.displays.filter { $0.isBuiltin == false }.count, 1)
    XCTAssertTrue(snapshot.inputDevices.isEmpty)
  }

  func testSnapshotReturnsEmptyArraysWhenProvidersHaveNoData() async {
    let inspector = PeripheralInspector(
      displayProvider: EmptyDisplayProvider(),
      hidProvider: EmptyHIDProvider()
    )

    let snapshot = await inspector.getSnapshot(includeSensitive: false)
    XCTAssertTrue(snapshot.displays.isEmpty)
    XCTAssertTrue(snapshot.inputDevices.isEmpty)
  }
}

private struct FakeDisplayProvider: DisplayProvider {
  func fetchDisplays(includeSensitive: Bool) -> [DisplayInfo] {
    [
      DisplayInfo(
        id: "display-1",
        name: "Studio Display",
        isBuiltin: false,
        isMain: true,
        pixelsWidth: 5120,
        pixelsHeight: 2880,
        vendorID: 610,
        modelID: 1234,
        serialNumber: includeSensitive ? "SERIAL-001" : nil
      )
    ]
  }
}

private struct FakeHIDProvider: HIDProvider {
  func fetchInputDevices(includeSensitive: Bool) -> [InputDeviceInfo] {
    [
      InputDeviceInfo(
        id: "hid-1",
        kind: .keyboard,
        name: "Magic Keyboard",
        transport: "Bluetooth",
        vendorID: 1452,
        productID: 835,
        isBuiltin: false,
        location: includeSensitive ? "0x00112233" : nil
      )
    ]
  }
}

private struct MultiDisplayProvider: DisplayProvider {
  func fetchDisplays(includeSensitive: Bool) -> [DisplayInfo] {
    [
      DisplayInfo(
        id: "display-built-in",
        name: "Color LCD",
        isBuiltin: true,
        isMain: true,
        pixelsWidth: 3024,
        pixelsHeight: 1964,
        vendorID: 610,
        modelID: 7788,
        serialNumber: includeSensitive ? "SERIAL-A" : nil
      ),
      DisplayInfo(
        id: "display-external",
        name: "Studio Display",
        isBuiltin: false,
        isMain: false,
        pixelsWidth: 5120,
        pixelsHeight: 2880,
        vendorID: 610,
        modelID: 7799,
        serialNumber: includeSensitive ? "SERIAL-B" : nil
      ),
    ]
  }
}

private struct EmptyDisplayProvider: DisplayProvider {
  func fetchDisplays(includeSensitive: Bool) -> [DisplayInfo] {
    []
  }
}

private struct EmptyHIDProvider: HIDProvider {
  func fetchInputDevices(includeSensitive: Bool) -> [InputDeviceInfo] {
    []
  }
}
