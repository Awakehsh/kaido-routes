import Foundation
import KaidoSurfaceRouting

public enum URLSessionOSRMHTTPTransportInitializationError: Error, Equatable, Sendable {
  case invalidBaseURL
  case invalidResponseLimit
  case invalidRequestTimeout
}

/// Minimal GET transport for a self-hosted OSRM service.
///
/// Dataset checks, node-path translation, and route ownership remain in
/// `KaidoSurfaceRouting`; this adapter only performs bounded HTTP I/O.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor URLSessionOSRMHTTPTransport: OSRMHTTPTransport {
  private let baseURL: URL
  private let session: URLSession
  private let maximumResponseBytes: Int
  private let requestTimeoutSeconds: TimeInterval

  public init(
    baseURL: URL,
    session: URLSession = .shared,
    maximumResponseBytes: Int = 8 * 1_024 * 1_024,
    requestTimeoutSeconds: TimeInterval = 15
  ) throws {
    guard ["http", "https"].contains(baseURL.scheme?.lowercased()), baseURL.host != nil else {
      throw URLSessionOSRMHTTPTransportInitializationError.invalidBaseURL
    }
    guard maximumResponseBytes > 0 else {
      throw URLSessionOSRMHTTPTransportInitializationError.invalidResponseLimit
    }
    guard requestTimeoutSeconds.isFinite, requestTimeoutSeconds > 0 else {
      throw URLSessionOSRMHTTPTransportInitializationError.invalidRequestTimeout
    }
    self.baseURL = baseURL
    self.session = session
    self.maximumResponseBytes = maximumResponseBytes
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }

  public func get(_ request: OSRMHTTPRequest) async throws -> OSRMHTTPResponse {
    guard request.path.hasPrefix("/route/v1/"), !request.path.contains(".."),
      request.queryItems.allSatisfy({ !$0.name.isEmpty })
    else {
      throw OSRMHTTPTransportFailure.invalidRequest
    }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw OSRMHTTPTransportFailure.invalidRequest
    }
    let basePath =
      components.path.hasSuffix("/")
      ? String(components.path.dropLast()) : components.path
    components.path = basePath + request.path
    components.queryItems = request.queryItems.map {
      URLQueryItem(name: $0.name, value: $0.value)
    }
    guard let url = components.url else {
      throw OSRMHTTPTransportFailure.invalidRequest
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "GET"
    urlRequest.timeoutInterval = requestTimeoutSeconds
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await session.data(for: urlRequest)
      guard let response = response as? HTTPURLResponse else {
        throw OSRMHTTPTransportFailure.invalidResponse
      }
      guard data.count <= maximumResponseBytes else {
        throw OSRMHTTPTransportFailure.responseTooLarge
      }
      return OSRMHTTPResponse(statusCode: response.statusCode, body: data)
    } catch is CancellationError {
      throw OSRMHTTPTransportFailure.cancelled
    } catch let failure as OSRMHTTPTransportFailure {
      throw failure
    } catch let error as URLError where error.code == .cancelled {
      throw OSRMHTTPTransportFailure.cancelled
    } catch let error as URLError where error.code == .timedOut {
      throw OSRMHTTPTransportFailure.timedOut
    } catch let error as URLError {
      throw OSRMHTTPTransportFailure.network(error.code.rawValue.description)
    } catch {
      throw OSRMHTTPTransportFailure.network(nil)
    }
  }
}
