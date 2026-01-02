import Foundation
import Security

/// Manages access and refresh tokens in Keychain.
/// Handles token refresh and session revocation.
public actor TokenManager {
  public static let shared = TokenManager()

  private let service = "com.swiftsweep.sysaibox"
  private let accessTokenKey = "accessToken"
  private let refreshTokenKey = "refreshToken"
  private let expirationKey = "tokenExpiration"

  private init() {}

  // MARK: - Token Storage

  /// Store tokens in Keychain.
  public func storeTokens(_ tokenPair: TokenPair) throws {
    try storeInKeychain(key: accessTokenKey, value: tokenPair.accessToken)
    try storeInKeychain(key: refreshTokenKey, value: tokenPair.refreshToken)

    if let expiresIn = tokenPair.expiresIn {
      let expiration = Date().addingTimeInterval(TimeInterval(expiresIn))
      UserDefaults.standard.set(expiration.timeIntervalSince1970, forKey: expirationKey)
    }
  }

  /// Get valid access token, refreshing if needed.
  /// - Parameter baseURL: The Sys AI Box base URL for refresh.
  /// - Returns: Valid access token.
  public func getAccessToken(baseURL: URL) async throws -> String {
    // Check if token is expired
    if isTokenExpired() {
      try await refresh(baseURL: baseURL)
    }

    guard let token = try? loadFromKeychain(key: accessTokenKey) else {
      throw TokenError.notAuthenticated
    }

    return token
  }

  /// Check if currently authenticated (has tokens).
  public func isAuthenticated() -> Bool {
    return (try? loadFromKeychain(key: accessTokenKey)) != nil
  }

  /// Clear all tokens (logout).
  public func clearTokens() {
    deleteFromKeychain(key: accessTokenKey)
    deleteFromKeychain(key: refreshTokenKey)
    UserDefaults.standard.removeObject(forKey: expirationKey)
  }

  // MARK: - Token Refresh

  /// Refresh the access token using the refresh token.
  public func refresh(baseURL: URL) async throws {
    guard let refreshToken = try? loadFromKeychain(key: refreshTokenKey) else {
      throw TokenError.notAuthenticated
    }

    let url = baseURL.appendingPathComponent("api/v1/auth/refresh")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["refresh_token": refreshToken]
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      // Refresh failed, clear tokens
      clearTokens()
      throw AuthError.refreshFailed
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let tokenPair = try decoder.decode(TokenPair.self, from: data)
    try storeTokens(tokenPair)
  }

  /// Revoke the current session.
  public func revoke(baseURL: URL) async throws {
    guard let accessToken = try? loadFromKeychain(key: accessTokenKey) else {
      clearTokens()
      return
    }

    let url = baseURL.appendingPathComponent("api/v1/auth/revoke")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)

    // Clear tokens regardless of server response
    clearTokens()

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw AuthError.revokeFailed
    }
  }

  // MARK: - Private Helpers

  private func isTokenExpired() -> Bool {
    let expiration = UserDefaults.standard.double(forKey: expirationKey)
    guard expiration > 0 else { return false }

    // Consider expired if less than 60 seconds remaining
    return Date().timeIntervalSince1970 > (expiration - 60)
  }

  private func storeInKeychain(key: String, value: String) throws {
    let data = Data(value.utf8)

    // Delete existing item first
    deleteFromKeychain(key: key)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw TokenError.keychainError(status)
    }
  }

  private func loadFromKeychain(key: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      throw TokenError.keychainError(status)
    }

    return value
  }

  private func deleteFromKeychain(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]

    SecItemDelete(query as CFDictionary)
  }
}

// MARK: - Errors

public enum TokenError: Error, LocalizedError {
  case notAuthenticated
  case keychainError(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated. Please pair your device."
    case .keychainError(let status):
      return "Keychain error: \(status)"
    }
  }
}
