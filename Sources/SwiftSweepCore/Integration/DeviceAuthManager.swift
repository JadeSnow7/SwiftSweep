import Foundation

/// Manages device-code authentication flow for Sys AI Box.
/// Implements: start → poll status → exchange tokens
public actor DeviceAuthManager {
  public static let shared = DeviceAuthManager()

  private var pollingTask: Task<Void, Error>?

  private init() {}

  // MARK: - Device Code Flow

  /// Start device-code pairing flow.
  /// - Parameter baseURL: The Sys AI Box base URL.
  /// - Returns: Pairing info including user code and verification URI.
  public func startPairing(baseURL: URL) async throws -> DevicePairingInfo {
    let url = baseURL.appendingPathComponent("api/v1/auth/device/start")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw AuthError.startFailed
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(DevicePairingInfo.self, from: data)
  }

  /// Poll for authorization status.
  /// - Parameters:
  ///   - deviceCode: The device code from startPairing.
  ///   - baseURL: The Sys AI Box base URL.
  /// - Returns: Authorization status.
  public func pollStatus(deviceCode: String, baseURL: URL) async throws -> AuthorizationStatus {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/v1/auth/device/status"),
      resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "device_code", value: deviceCode)]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "GET"
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw AuthError.pollFailed
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let statusResponse = try decoder.decode(StatusResponse.self, from: data)

    switch statusResponse.status {
    case "pending":
      return .pending
    case "authorized":
      return .authorized
    case "expired":
      return .expired
    default:
      return .pending
    }
  }

  /// Exchange device code for access and refresh tokens.
  /// - Parameters:
  ///   - deviceCode: The device code from startPairing.
  ///   - baseURL: The Sys AI Box base URL.
  /// - Returns: Token pair (access + refresh).
  public func exchangeForTokens(deviceCode: String, baseURL: URL) async throws -> TokenPair {
    let url = baseURL.appendingPathComponent("api/v1/auth/device/token")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["device_code": deviceCode]
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw AuthError.tokenExchangeFailed
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(TokenPair.self, from: data)
  }

  /// Complete pairing flow: poll until authorized, then exchange for tokens.
  /// - Parameters:
  ///   - pairingInfo: The pairing info from startPairing.
  ///   - baseURL: The Sys AI Box base URL.
  ///   - onStatusChange: Callback for status updates.
  /// - Returns: Token pair on success.
  public func completePairing(
    pairingInfo: DevicePairingInfo,
    baseURL: URL,
    onStatusChange: @escaping (AuthorizationStatus) -> Void
  ) async throws -> TokenPair {
    let interval = TimeInterval(pairingInfo.interval)
    let expiresAt = Date().addingTimeInterval(TimeInterval(pairingInfo.expiresIn))

    while Date() < expiresAt {
      try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

      let status = try await pollStatus(deviceCode: pairingInfo.deviceCode, baseURL: baseURL)
      onStatusChange(status)

      switch status {
      case .authorized:
        return try await exchangeForTokens(deviceCode: pairingInfo.deviceCode, baseURL: baseURL)
      case .expired:
        throw AuthError.expired
      case .pending:
        continue
      }
    }

    throw AuthError.expired
  }

  /// Cancel any ongoing polling.
  public func cancelPairing() {
    pollingTask?.cancel()
    pollingTask = nil
  }
}

// MARK: - Data Types

public struct DevicePairingInfo: Codable, Sendable {
  public let deviceCode: String
  public let userCode: String
  public let verificationUri: String
  public let expiresIn: Int
  public let interval: Int
}

public enum AuthorizationStatus: Sendable {
  case pending
  case authorized
  case expired
}

private struct StatusResponse: Codable {
  let status: String
}

public struct TokenPair: Codable, Sendable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresIn: Int?
}

public enum AuthError: Error, LocalizedError {
  case startFailed
  case pollFailed
  case tokenExchangeFailed
  case expired
  case refreshFailed
  case revokeFailed

  public var errorDescription: String? {
    switch self {
    case .startFailed:
      return "Failed to start device pairing"
    case .pollFailed:
      return "Failed to poll authorization status"
    case .tokenExchangeFailed:
      return "Failed to exchange device code for tokens"
    case .expired:
      return "Device code expired"
    case .refreshFailed:
      return "Failed to refresh access token"
    case .revokeFailed:
      return "Failed to revoke session"
    }
  }
}
