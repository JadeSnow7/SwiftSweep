import Foundation

#if canImport(SwiftSweepCore)
  import SwiftSweepCore
#endif

struct PeripheralSnapshotJSONDTO: Encodable {
  let snapshot: PeripheralSnapshot

  enum CodingKeys: String, CodingKey {
    case displays
    case inputDevices = "input_devices"
    case collectedAt = "collected_at"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(snapshot.displays.map(DisplayJSONDTO.init), forKey: .displays)
    try container.encode(snapshot.inputDevices.map(InputDeviceJSONDTO.init), forKey: .inputDevices)
    try container.encode(Self.iso8601.string(from: snapshot.collectedAt), forKey: .collectedAt)
  }

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

struct DisplayJSONDTO: Encodable {
  let value: DisplayInfo

  init(_ value: DisplayInfo) {
    self.value = value
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case isBuiltin = "is_builtin"
    case isMain = "is_main"
    case pixelsWidth = "pixels_width"
    case pixelsHeight = "pixels_height"
    case vendorID = "vendor_id"
    case modelID = "model_id"
    case serialNumber = "serial_number"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value.id, forKey: .id)
    try container.encodeOptional(value.name, forKey: .name)
    try container.encodeOptional(value.isBuiltin, forKey: .isBuiltin)
    try container.encodeOptional(value.isMain, forKey: .isMain)
    try container.encodeOptional(value.pixelsWidth, forKey: .pixelsWidth)
    try container.encodeOptional(value.pixelsHeight, forKey: .pixelsHeight)
    try container.encodeOptional(value.vendorID, forKey: .vendorID)
    try container.encodeOptional(value.modelID, forKey: .modelID)
    try container.encodeOptional(value.serialNumber, forKey: .serialNumber)
  }
}

struct InputDeviceJSONDTO: Encodable {
  let value: InputDeviceInfo

  init(_ value: InputDeviceInfo) {
    self.value = value
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case name
    case transport
    case vendorID = "vendor_id"
    case productID = "product_id"
    case isBuiltin = "is_builtin"
    case location
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(value.id, forKey: .id)
    try container.encode(value.kind.rawValue, forKey: .kind)
    try container.encodeOptional(value.name, forKey: .name)
    try container.encodeOptional(value.transport, forKey: .transport)
    try container.encodeOptional(value.vendorID, forKey: .vendorID)
    try container.encodeOptional(value.productID, forKey: .productID)
    try container.encodeOptional(value.isBuiltin, forKey: .isBuiltin)
    try container.encodeOptional(value.location, forKey: .location)
  }
}

private extension KeyedEncodingContainer {
  mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: K) throws {
    if let value {
      try encode(value, forKey: key)
    } else {
      try encodeNil(forKey: key)
    }
  }
}
