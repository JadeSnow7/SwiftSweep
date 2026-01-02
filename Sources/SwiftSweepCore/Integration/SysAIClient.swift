import Foundation

/// HTTP client for Sys AI Box API with automatic token refresh and offline handling.
public actor SysAIClient {
  public static let shared = SysAIClient()

  private var lastOnlineCheck: Date?
  private var isOffline: Bool = false

  private init() {}

  // MARK: - Public API

  /// Make an authenticated GET request.
  /// - Parameters:
  ///   - path: API path (e.g., "/api/v1/servers")
  ///   - baseURL: The Sys AI Box base URL.
  /// - Returns: Response data.
  public func get(path: String, baseURL: URL) async throws -> Data {
    return try await makeRequest(method: "GET", path: path, body: nil, baseURL: baseURL)
  }

  /// Make an authenticated POST request.
  /// - Parameters:
  ///   - path: API path
  ///   - body: Request body (Encodable)
  ///   - baseURL: The Sys AI Box base URL.
  /// - Returns: Response data.
  public func post<T: Encodable>(path: String, body: T, baseURL: URL) async throws -> Data {
    let bodyData = try JSONEncoder().encode(body)
    return try await makeRequest(method: "POST", path: path, body: bodyData, baseURL: baseURL)
  }

  /// Check if the client is currently offline.
  public func checkIsOffline() -> Bool {
    return isOffline
  }

  /// Get the last time we successfully connected.
  public func getLastOnlineCheck() -> Date? {
    return lastOnlineCheck
  }

  // MARK: - Private Implementation

  private func makeRequest(method: String, path: String, body: Data?, baseURL: URL) async throws
    -> Data
  {
    let url = baseURL.appendingPathComponent(path)
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = method
    urlRequest.timeoutInterval = 15

    // Get access token (auto-refreshes if needed)
    do {
      let token = try await TokenManager.shared.getAccessToken(baseURL: baseURL)
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    } catch TokenError.notAuthenticated {
      throw ClientError.notAuthenticated
    }

    // Add client version header
    urlRequest.setValue("SwiftSweep/1.0.0", forHTTPHeaderField: "X-Client-Version")
    urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

    if let body = body {
      urlRequest.httpBody = body
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // Make request
    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: urlRequest)
      isOffline = false
      lastOnlineCheck = Date()
    } catch {
      isOffline = true
      throw ClientError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ClientError.invalidResponse
    }

    // Handle 401 - try to refresh and retry once
    if httpResponse.statusCode == 401 {
      do {
        try await TokenManager.shared.refresh(baseURL: baseURL)
        return try await makeRequest(method: method, path: path, body: body, baseURL: baseURL)
      } catch {
        throw ClientError.notAuthenticated
      }
    }

    // Handle other errors
    guard (200...299).contains(httpResponse.statusCode) else {
      throw ClientError.serverError(statusCode: httpResponse.statusCode, data: data)
    }

    return data
  }
}

// MARK: - Errors

public enum ClientError: Error, LocalizedError {
  case notAuthenticated
  case networkError(Error)
  case invalidResponse
  case serverError(statusCode: Int, data: Data)

  public var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated. Please pair your device."
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .invalidResponse:
      return "Invalid response from server"
    case .serverError(let code, _):
      return "Server error: \(code)"
    }
  }
}
