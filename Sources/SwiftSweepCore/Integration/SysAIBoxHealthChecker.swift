import Foundation

/// Health check client for Sys AI Box API.
/// Calls `GET /api/v1/health` to validate connectivity.
public struct SysAIBoxHealthChecker: Sendable {
  public static let shared = SysAIBoxHealthChecker()

  private init() {}

  /// Check health of the Sys AI Box server.
  /// - Parameter baseURL: The base URL of Sys AI Box.
  /// - Returns: `HealthResponse` containing server status and version.
  /// - Throws: Network or decoding errors.
  public func checkHealth(baseURL: URL) async throws -> HealthResponse {
    let healthURL = baseURL.appendingPathComponent("api/v1/health")
    var request = URLRequest(url: healthURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw HealthError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      throw HealthError.serverError(statusCode: httpResponse.statusCode)
    }

    let decoder = JSONDecoder()
    return try decoder.decode(HealthResponse.self, from: data)
  }

  public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let version: String?

    public var isHealthy: Bool {
      return status == "ok"
    }
  }

  public enum HealthError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)

    public var errorDescription: String? {
      switch self {
      case .invalidResponse:
        return "Invalid response from server"
      case .serverError(let code):
        return "Server returned status code \(code)"
      }
    }
  }
}
