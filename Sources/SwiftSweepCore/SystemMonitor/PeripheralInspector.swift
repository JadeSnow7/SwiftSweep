import ApplicationServices
import Foundation

#if canImport(IOKit)
  import IOKit
  import IOKit.graphics
  import IOKit.hid
#endif

protocol DisplayProvider: Sendable {
  func fetchDisplays(includeSensitive: Bool) -> [DisplayInfo]
}

protocol HIDProvider: Sendable {
  func fetchInputDevices(includeSensitive: Bool) -> [InputDeviceInfo]
}

/// 外设检测服务（显示器 + 常见输入设备）
public final class PeripheralInspector: @unchecked Sendable {
  public static let shared = PeripheralInspector()

  private let displayProvider: any DisplayProvider
  private let hidProvider: any HIDProvider

  init(
    displayProvider: any DisplayProvider = NativeDisplayProvider(),
    hidProvider: any HIDProvider = NativeHIDProvider()
  ) {
    self.displayProvider = displayProvider
    self.hidProvider = hidProvider
  }

  public func getSnapshot(includeSensitive: Bool = false) async -> PeripheralSnapshot {
    PeripheralSnapshot(
      displays: displayProvider.fetchDisplays(includeSensitive: includeSensitive),
      inputDevices: hidProvider.fetchInputDevices(includeSensitive: includeSensitive),
      collectedAt: Date()
    )
  }
}

struct NativeDisplayProvider: DisplayProvider {
  func fetchDisplays(includeSensitive: Bool) -> [DisplayInfo] {
    let maxDisplays: UInt32 = 32
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    var count: UInt32 = 0

    guard CGGetActiveDisplayList(maxDisplays, &displayIDs, &count) == .success else {
      return []
    }

    let mainDisplayID = CGMainDisplayID()
    return displayIDs.prefix(Int(count)).map { displayID in
      let vendorRaw = CGDisplayVendorNumber(displayID)
      let modelRaw = CGDisplayModelNumber(displayID)
      let serialRaw = CGDisplaySerialNumber(displayID)

      return DisplayInfo(
        id: "display-\(displayID)",
        name: displayName(for: displayID),
        isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
        isMain: displayID == mainDisplayID,
        pixelsWidth: Int(CGDisplayPixelsWide(displayID)),
        pixelsHeight: Int(CGDisplayPixelsHigh(displayID)),
        vendorID: vendorRaw == 0 ? nil : Int(vendorRaw),
        modelID: modelRaw == 0 ? nil : Int(modelRaw),
        serialNumber: includeSensitive && serialRaw != 0 ? String(serialRaw) : nil
      )
    }
  }

  private func displayName(for displayID: CGDirectDisplayID) -> String? {
    #if canImport(IOKit)
      let vendorID = Int(CGDisplayVendorNumber(displayID))
      let modelID = Int(CGDisplayModelNumber(displayID))
      let serialID = Int(CGDisplaySerialNumber(displayID))
      return lookupDisplayName(vendorID: vendorID, modelID: modelID, serialID: serialID)
    #else
      return nil
    #endif
  }

  #if canImport(IOKit)
    private func lookupDisplayName(vendorID: Int, modelID: Int, serialID: Int) -> String? {
      var iterator: io_iterator_t = 0
      guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
      guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return nil
      }
      defer { IOObjectRelease(iterator) }

      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }

        let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary

        let candidateVendor = extractInt(from: info["DisplayVendorID"])
        let candidateModel = extractInt(from: info["DisplayProductID"])
        let candidateSerial = extractInt(from: info["DisplaySerialNumber"])

        guard candidateVendor == vendorID, candidateModel == modelID else {
          continue
        }
        if serialID != 0, let candidateSerial, candidateSerial != serialID {
          continue
        }

        if let names = info["DisplayProductName"] as? [String: Any] {
          if let enName = names["en_US"] as? String {
            return enName
          }
          return names.values.compactMap { $0 as? String }.first
        }
      }

      return nil
    }

    private func extractInt(from value: Any?) -> Int? {
      if let number = value as? NSNumber {
        return number.intValue
      }
      return nil
    }
  #endif
}

struct NativeHIDProvider: HIDProvider {
  private enum HIDUsage {
    static let genericDesktopPage = 0x01
    static let digitizerPage = 0x0D
    static let keyboard = 0x06
    static let mouse = 0x02
    static let trackpad = 0x05
  }

  private enum HIDKey {
    static let product = "Product" as CFString
    static let vendorID = "VendorID" as CFString
    static let productID = "ProductID" as CFString
    static let transport = "Transport" as CFString
    static let locationID = "LocationID" as CFString
    static let builtIn = "Built-In" as CFString
    static let primaryUsagePage = "PrimaryUsagePage" as CFString
    static let primaryUsage = "PrimaryUsage" as CFString
  }

  func fetchInputDevices(includeSensitive: Bool) -> [InputDeviceInfo] {
    #if canImport(IOKit)
      let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
      IOHIDManagerSetDeviceMatching(manager, nil)

      guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        return []
      }
      defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

      guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
        return []
      }

      return deviceSet.compactMap { device in
        mapDevice(device, includeSensitive: includeSensitive)
      }
      .sorted { lhs, rhs in
        let left = lhs.name ?? lhs.id
        let right = rhs.name ?? rhs.id
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
      }
    #else
      return []
    #endif
  }

  private func mapDevice(_ device: IOHIDDevice, includeSensitive: Bool) -> InputDeviceInfo? {
    let name = stringProperty(HIDKey.product, from: device)
    let transport = stringProperty(HIDKey.transport, from: device)
    let usagePage = intProperty(HIDKey.primaryUsagePage, from: device)
    let usage = intProperty(HIDKey.primaryUsage, from: device)

    let kind = classifyKind(name: name, usagePage: usagePage, usage: usage)
    guard kind != .other else { return nil }

    let vendorID = intProperty(HIDKey.vendorID, from: device)
    let productID = intProperty(HIDKey.productID, from: device)
    let locationRaw = intProperty(HIDKey.locationID, from: device)
    let isBuiltin = boolProperty(HIDKey.builtIn, from: device)
      ?? inferBuiltin(transport: transport, name: name)

    let location: String?
    if includeSensitive, let locationRaw {
      location = String(format: "0x%08X", locationRaw)
    } else {
      location = nil
    }

    return InputDeviceInfo(
      id: deviceIdentifier(for: device, vendorID: vendorID, productID: productID, location: locationRaw),
      kind: kind,
      name: name,
      transport: transport,
      vendorID: vendorID,
      productID: productID,
      isBuiltin: isBuiltin,
      location: location
    )
  }

  private func classifyKind(
    name: String?,
    usagePage: Int?,
    usage: Int?
  ) -> InputDeviceKind {
    if usagePage == HIDUsage.genericDesktopPage, usage == HIDUsage.keyboard {
      return .keyboard
    }
    if usagePage == HIDUsage.genericDesktopPage, usage == HIDUsage.mouse {
      return .mouse
    }
    if usagePage == HIDUsage.digitizerPage, usage == HIDUsage.trackpad {
      return .trackpad
    }

    let lowercasedName = name?.lowercased() ?? ""
    if lowercasedName.contains("trackpad") || lowercasedName.contains("touchpad") {
      return .trackpad
    }
    if lowercasedName.contains("keyboard") {
      return .keyboard
    }
    if lowercasedName.contains("mouse") {
      return .mouse
    }
    return .other
  }

  private func inferBuiltin(transport: String?, name: String?) -> Bool? {
    let normalizedTransport = transport?.uppercased()
    if normalizedTransport == "USB" || normalizedTransport == "BLUETOOTH" {
      return false
    }
    if normalizedTransport == "SPI" || normalizedTransport == "I2C" {
      return true
    }

    let lowercasedName = name?.lowercased() ?? ""
    if lowercasedName.contains("internal") || lowercasedName.contains("built-in") {
      return true
    }
    return nil
  }

  private func stringProperty(_ key: CFString, from device: IOHIDDevice) -> String? {
    guard let rawValue = IOHIDDeviceGetProperty(device, key) else { return nil }
    if let stringValue = rawValue as? String {
      let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }

  private func intProperty(_ key: CFString, from device: IOHIDDevice) -> Int? {
    guard let rawValue = IOHIDDeviceGetProperty(device, key) else { return nil }
    if let number = rawValue as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private func boolProperty(_ key: CFString, from device: IOHIDDevice) -> Bool? {
    guard let rawValue = IOHIDDeviceGetProperty(device, key) else { return nil }
    if let boolValue = rawValue as? Bool {
      return boolValue
    }
    if let number = rawValue as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private func deviceIdentifier(
    for device: IOHIDDevice,
    vendorID: Int?,
    productID: Int?,
    location: Int?
  ) -> String {
    #if canImport(IOKit)
      var registryID: UInt64 = 0
      let ioService = IOHIDDeviceGetService(device)
      if ioService != 0, IORegistryEntryGetRegistryEntryID(ioService, &registryID) == KERN_SUCCESS {
        return "hid-\(registryID)"
      }
    #endif

    let vendorPart = vendorID.map(String.init) ?? "unknownVendor"
    let productPart = productID.map(String.init) ?? "unknownProduct"
    let locationPart = location.map(String.init) ?? "unknownLocation"
    return "hid-\(vendorPart)-\(productPart)-\(locationPart)"
  }
}
