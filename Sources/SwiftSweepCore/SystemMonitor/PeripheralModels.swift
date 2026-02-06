import Foundation

public enum InputDeviceKind: String, Codable, CaseIterable, Sendable {
  case keyboard
  case mouse
  case trackpad
  case other
}

public enum MachineArchitecture: String, Codable, Sendable {
  case appleSilicon
  case intel
  case unknown
}

public struct DisplayInfo: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  /// Best-effort display name; unavailable values remain nil.
  public let name: String?
  public let isBuiltin: Bool?
  public let isMain: Bool?
  public let pixelsWidth: Int?
  public let pixelsHeight: Int?
  public let vendorID: Int?
  public let modelID: Int?
  /// Sensitive hardware identifier; nil unless sensitive output is explicitly requested.
  public let serialNumber: String?

  public init(
    id: String,
    name: String?,
    isBuiltin: Bool?,
    isMain: Bool?,
    pixelsWidth: Int?,
    pixelsHeight: Int?,
    vendorID: Int?,
    modelID: Int?,
    serialNumber: String?
  ) {
    self.id = id
    self.name = name
    self.isBuiltin = isBuiltin
    self.isMain = isMain
    self.pixelsWidth = pixelsWidth
    self.pixelsHeight = pixelsHeight
    self.vendorID = vendorID
    self.modelID = modelID
    self.serialNumber = serialNumber
  }
}

public struct InputDeviceInfo: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  public let kind: InputDeviceKind
  public let name: String?
  public let transport: String?
  public let vendorID: Int?
  public let productID: Int?
  public let isBuiltin: Bool?
  /// Sensitive device location identifier; nil unless sensitive output is explicitly requested.
  public let location: String?

  public init(
    id: String,
    kind: InputDeviceKind,
    name: String?,
    transport: String?,
    vendorID: Int?,
    productID: Int?,
    isBuiltin: Bool?,
    location: String?
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.transport = transport
    self.vendorID = vendorID
    self.productID = productID
    self.isBuiltin = isBuiltin
    self.location = location
  }
}

public struct PeripheralSnapshot: Equatable, Codable, Sendable {
  public let displays: [DisplayInfo]
  public let inputDevices: [InputDeviceInfo]
  public let collectedAt: Date

  public init(
    displays: [DisplayInfo] = [],
    inputDevices: [InputDeviceInfo] = [],
    collectedAt: Date = Date()
  ) {
    self.displays = displays
    self.inputDevices = inputDevices
    self.collectedAt = collectedAt
  }
}

public struct AppleDiagnosticsGuide: Codable, Sendable {
  public let architecture: MachineArchitecture
  public let steps: [String]
  public let supportURL: URL
  /// Guidance notes for Apple's official diagnostics flow. This is not an in-app diagnostics engine.
  public let notes: [String]

  public init(
    architecture: MachineArchitecture,
    steps: [String],
    supportURL: URL,
    notes: [String]
  ) {
    self.architecture = architecture
    self.steps = steps
    self.supportURL = supportURL
    self.notes = notes
  }
}
