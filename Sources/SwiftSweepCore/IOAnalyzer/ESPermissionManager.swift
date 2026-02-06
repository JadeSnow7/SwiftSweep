import AppKit
import Foundation

#if canImport(EndpointSecurity) && !SWIFTSWEEP_NO_ENDPOINT_SECURITY
  import EndpointSecurity
#endif

#if canImport(EndpointSecurity) && !SWIFTSWEEP_NO_ENDPOINT_SECURITY

// MARK: - Endpoint Security Permission Manager

/// 管理 Endpoint Security 权限状态
public final class ESPermissionManager: @unchecked Sendable {
  public static let shared = ESPermissionManager()

  public enum PermissionStatus: Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted  // No ES entitlement
  }

  private init() {}

  // MARK: - Status Check

  /// 检查 ES 权限状态
  public func checkStatus() -> PermissionStatus {
    // 首先检查是否有 entitlement
    guard hasEndpointSecurityEntitlement() else {
      return .restricted
    }

    // 尝试创建 ES 客户端来测试权限
    var testClient: OpaquePointer?
    let result = es_new_client(&testClient) { _, _ in }

    defer {
      if let client = testClient {
        es_delete_client(client)
      }
    }

    switch result {
    case ES_NEW_CLIENT_RESULT_SUCCESS:
      return .authorized
    case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
      return .denied
    case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
      return .restricted
    default:
      return .notDetermined
    }
  }

  /// 是否已授权
  public var isAuthorized: Bool {
    checkStatus() == .authorized
  }

  // MARK: - Entitlement Check

  /// 检查是否有 ES entitlement（通过尝试创建客户端）
  private func hasEndpointSecurityEntitlement() -> Bool {
    var client: OpaquePointer?
    let result = es_new_client(&client) { _, _ in }

    if let client = client {
      es_delete_client(client)
    }

    // NOT_ENTITLED 表示没有 entitlement
    // NOT_PERMITTED 表示有 entitlement 但没有 Full Disk Access
    return result != ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED
  }

  // MARK: - User Guidance

  /// 打开系统偏好设置的安全与隐私面板
  public func openSecurityPreferences() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    NSWorkspace.shared.open(url)
  }

  /// 获取用户友好的状态描述
  public func statusDescription(_ status: PermissionStatus) -> (title: String, message: String) {
    switch status {
    case .notDetermined:
      return (
        "Permission Required",
        "Full Disk Access permission is needed for system-wide I/O monitoring."
      )
    case .denied:
      return (
        "Permission Denied",
        "Please grant Full Disk Access in System Preferences > Security & Privacy > Privacy > Full Disk Access."
      )
    case .authorized:
      return ("Authorized", "System-wide I/O monitoring is available.")
    case .restricted:
      return ("Not Available", "This app does not have the required Endpoint Security entitlement.")
    }
  }
}

#else

public final class ESPermissionManager: @unchecked Sendable {
  public static let shared = ESPermissionManager()

  public enum PermissionStatus: Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
  }

  private init() {}

  public func checkStatus() -> PermissionStatus {
    .restricted
  }

  public var isAuthorized: Bool {
    false
  }

  public func openSecurityPreferences() {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    NSWorkspace.shared.open(url)
  }

  public func statusDescription(_ status: PermissionStatus) -> (title: String, message: String) {
    switch status {
    case .notDetermined:
      return (
        "Permission Required",
        "Full Disk Access permission is needed for system-wide I/O monitoring."
      )
    case .denied:
      return (
        "Permission Denied",
        "Please grant Full Disk Access in System Preferences > Security & Privacy > Privacy > Full Disk Access."
      )
    case .authorized:
      return ("Authorized", "System-wide I/O monitoring is available.")
    case .restricted:
      return ("Not Available", "Endpoint Security is unavailable in this build.")
    }
  }
}

#endif
