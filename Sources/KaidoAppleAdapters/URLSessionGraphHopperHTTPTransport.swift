import Foundation
import KaidoSurfaceRouting

public enum URLSessionGraphHopperHTTPTransportInitializationError:
  Error, Equatable, Sendable
{
  case invalidBaseURL
  case invalidResponseLimit
  case invalidRequestTimeout
}

/// Minimal bounded GET transport for a self-hosted GraphHopper service.
///
/// Only `/info` and `/route` are reachable. Build identity, route construction,
/// point-detail validation, and Kaido graph translation stay outside this I/O
/// adapter.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor URLSessionGraphHopperHTTPTransport: GraphHopperHTTPTransport {
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
      throw URLSessionGraphHopperHTTPTransportInitializationError.invalidBaseURL
    }
    guard maximumResponseBytes > 0 else {
      throw URLSessionGraphHopperHTTPTransportInitializationError.invalidResponseLimit
    }
    guard requestTimeoutSeconds.isFinite, requestTimeoutSeconds > 0 else {
      throw URLSessionGraphHopperHTTPTransportInitializationError.invalidRequestTimeout
    }
    self.baseURL = baseURL
    self.session = session
    self.maximumResponseBytes = maximumResponseBytes
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }

  public func get(
    _ request: GraphHopperHTTPRequest
  ) async throws -> GraphHopperHTTPResponse {
    guard ["/info", "/route"].contains(request.path),
      request.queryItems.allSatisfy({ !$0.name.isEmpty }),
      request.path == "/route" || request.queryItems.isEmpty
    else {
      throw GraphHopperHTTPTransportFailure.invalidRequest
    }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw GraphHopperHTTPTransportFailure.invalidRequest
    }
    let basePath =
      components.path.hasSuffix("/")
      ? String(components.path.dropLast()) : components.path
    components.path = basePath + request.path
    components.queryItems = request.queryItems.map {
      URLQueryItem(name: $0.name, value: $0.value)
    }
    guard let url = components.url else {
      throw GraphHopperHTTPTransportFailure.invalidRequest
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "GET"
    urlRequest.timeoutInterval = requestTimeoutSeconds
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await session.data(for: urlRequest)
      guard let response = response as? HTTPURLResponse else {
        throw GraphHopperHTTPTransportFailure.invalidResponse
      }
      guard data.count <= maximumResponseBytes else {
        throw GraphHopperHTTPTransportFailure.responseTooLarge
      }
      return GraphHopperHTTPResponse(statusCode: response.statusCode, body: data)
    } catch is CancellationError {
      throw GraphHopperHTTPTransportFailure.cancelled
    } catch let failure as GraphHopperHTTPTransportFailure {
      throw failure
    } catch let error as URLError where error.code == .cancelled {
      throw GraphHopperHTTPTransportFailure.cancelled
    } catch let error as URLError where error.code == .timedOut {
      throw GraphHopperHTTPTransportFailure.timedOut
    } catch let error as URLError {
      throw GraphHopperHTTPTransportFailure.network(error.code.rawValue.description)
    } catch {
      throw GraphHopperHTTPTransportFailure.network(nil)
    }
  }
}
