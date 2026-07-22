import Foundation
import KaidoSurfaceRouting

public enum URLSessionValhallaHTTPTransportInitializationError: Error, Equatable, Sendable {
  case invalidBaseURL
  case invalidResponseLimit
  case invalidRequestTimeout
}

/// Minimal POST transport for a self-hosted Valhalla service.
///
/// Request construction, dataset checks, path translation, and route ownership
/// remain in `KaidoSurfaceRouting`; this adapter only performs HTTP I/O.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor URLSessionValhallaHTTPTransport: ValhallaHTTPTransport {
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
      throw URLSessionValhallaHTTPTransportInitializationError.invalidBaseURL
    }
    guard maximumResponseBytes > 0 else {
      throw URLSessionValhallaHTTPTransportInitializationError.invalidResponseLimit
    }
    guard requestTimeoutSeconds.isFinite, requestTimeoutSeconds > 0 else {
      throw URLSessionValhallaHTTPTransportInitializationError.invalidRequestTimeout
    }
    self.baseURL = baseURL
    self.session = session
    self.maximumResponseBytes = maximumResponseBytes
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }

  public func post(
    action: ValhallaServiceAction,
    jsonBody: Data
  ) async throws -> ValhallaHTTPResponse {
    let url = baseURL.appendingPathComponent(action.rawValue)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = jsonBody
    request.timeoutInterval = requestTimeoutSeconds
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw ValhallaHTTPTransportFailure.invalidResponse
      }
      guard data.count <= maximumResponseBytes else {
        throw ValhallaHTTPTransportFailure.responseTooLarge
      }
      return ValhallaHTTPResponse(statusCode: response.statusCode, body: data)
    } catch is CancellationError {
      throw ValhallaHTTPTransportFailure.cancelled
    } catch let failure as ValhallaHTTPTransportFailure {
      throw failure
    } catch let error as URLError where error.code == .cancelled {
      throw ValhallaHTTPTransportFailure.cancelled
    } catch let error as URLError where error.code == .timedOut {
      throw ValhallaHTTPTransportFailure.timedOut
    } catch let error as URLError {
      throw ValhallaHTTPTransportFailure.network(error.code.rawValue.description)
    } catch {
      throw ValhallaHTTPTransportFailure.network(nil)
    }
  }
}
