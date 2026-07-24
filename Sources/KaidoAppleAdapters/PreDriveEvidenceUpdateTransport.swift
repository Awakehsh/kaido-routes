import Foundation

/// One compile-time reviewed endpoint for an exact product's signed evidence.
///
/// The endpoint supplies only a self-contained signed envelope. It never
/// supplies route, prompt, location, or unsigned evidence authority.
public struct PreDriveEvidenceUpdateEndpoint:
  Codable, Equatable, Sendable
{
  public let url: String

  public init(url: String) {
    self.url = url
  }

  public var validatedURL: URL? {
    guard
      !url.isEmpty,
      url == url.trimmingCharacters(in: .whitespacesAndNewlines),
      let components = URLComponents(string: url),
      components.scheme == "https",
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.query == nil,
      components.fragment == nil,
      let host = components.host,
      host == host.lowercased(),
      Self.isValidDNSHost(host),
      components.percentEncodedPath.hasPrefix("/"),
      components.percentEncodedPath.lowercased().hasSuffix(".json"),
      !components.percentEncodedPath.lowercased().contains("%2f"),
      !components.percentEncodedPath.lowercased().contains("%5c"),
      !components.pathComponentsContainTraversal,
      let resolved = components.url,
      resolved.absoluteString == url
    else {
      return nil
    }
    return resolved
  }

  private static func isValidDNSHost(_ host: String) -> Bool {
    guard
      host.count <= 253,
      host.contains("."),
      host != "localhost",
      !host.hasSuffix(".local")
    else {
      return false
    }
    let labels = host.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard
      labels.count >= 2,
      !labels.allSatisfy({
        $0.allSatisfy(\.isNumber)
      })
    else {
      return false
    }
    return labels.allSatisfy { label in
      guard
        !label.isEmpty,
        label.count <= 63,
        label.first != "-",
        label.last != "-"
      else {
        return false
      }
      return label.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
      }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case url
  }
}

extension URLComponents {
  fileprivate var pathComponentsContainTraversal: Bool {
    percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
      .contains { component in
        guard
          let decoded = component.removingPercentEncoding?.lowercased()
        else {
          return true
        }
        return decoded == "." || decoded == ".."
      }
  }
}

public enum PreDriveEvidenceUpdateFetchError:
  Error, Equatable, Sendable
{
  case invalidEndpoint
  case invalidResponse
  case endpointChanged
  case invalidHTTPStatus
  case invalidContentType
  case responseTooLarge
  case timedOut
  case cancelled
  case network

  public var code: String {
    switch self {
    case .invalidEndpoint:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_ENDPOINT_INVALID"
    case .invalidResponse:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_RESPONSE_INVALID"
    case .endpointChanged:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_ENDPOINT_CHANGED"
    case .invalidHTTPStatus:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_HTTP_STATUS_INVALID"
    case .invalidContentType:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_CONTENT_TYPE_INVALID"
    case .responseTooLarge:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_RESPONSE_TOO_LARGE"
    case .timedOut:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_TIMED_OUT"
    case .cancelled:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_CANCELLED"
    case .network:
      "PRE_DRIVE_EVIDENCE_UPDATE_FETCH_NETWORK_FAILED"
    }
  }
}

public protocol PreDriveEvidenceUpdateFetching: Sendable {
  func fetch(
    endpoint: PreDriveEvidenceUpdateEndpoint
  ) async throws -> Data
}

/// Bounded, credential-free HTTPS transport for a signed evidence envelope.
///
/// The default session is ephemeral, sends no cookies or credentials, rejects
/// redirects, bypasses URL caches, and accepts only JSON from the exact
/// compile-time endpoint. Signature and whole-product validation remain in
/// `PreDriveEvidenceUpdateCodec`.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public actor URLSessionPreDriveEvidenceUpdateFetcher:
  PreDriveEvidenceUpdateFetching
{
  private let session: URLSession
  private let maximumResponseBytes: Int
  private let requestTimeoutSeconds: TimeInterval

  public init(
    session: URLSession? = nil,
    maximumResponseBytes: Int =
      PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount,
    requestTimeoutSeconds: TimeInterval = 15
  ) throws {
    guard
      maximumResponseBytes > 0,
      maximumResponseBytes
        <= PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount
    else {
      throw PreDriveEvidenceUpdateFetchError.responseTooLarge
    }
    guard requestTimeoutSeconds.isFinite, requestTimeoutSeconds > 0 else {
      throw PreDriveEvidenceUpdateFetchError.timedOut
    }
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.urlCredentialStorage = nil
      self.session = URLSession(
        configuration: configuration,
        delegate: PreDriveEvidenceUpdateRedirectRejector(),
        delegateQueue: nil
      )
    }
    self.maximumResponseBytes = maximumResponseBytes
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }

  public func fetch(
    endpoint: PreDriveEvidenceUpdateEndpoint
  ) async throws -> Data {
    guard let url = endpoint.validatedURL else {
      throw PreDriveEvidenceUpdateFetchError.invalidEndpoint
    }
    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: requestTimeoutSeconds
    )
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        throw PreDriveEvidenceUpdateFetchError.invalidResponse
      }
      guard response.url == url else {
        throw PreDriveEvidenceUpdateFetchError.endpointChanged
      }
      guard response.statusCode == 200 else {
        throw PreDriveEvidenceUpdateFetchError.invalidHTTPStatus
      }
      guard
        response.expectedContentLength < 0
          || response.expectedContentLength <= maximumResponseBytes
      else {
        throw PreDriveEvidenceUpdateFetchError.responseTooLarge
      }
      guard
        let contentType = response.value(
          forHTTPHeaderField: "Content-Type"
        )?.split(separator: ";", maxSplits: 1).first,
        contentType.trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased() == "application/json"
      else {
        throw PreDriveEvidenceUpdateFetchError.invalidContentType
      }
      guard
        !data.isEmpty,
        data.count <= maximumResponseBytes
      else {
        throw PreDriveEvidenceUpdateFetchError.responseTooLarge
      }
      return data
    } catch is CancellationError {
      throw PreDriveEvidenceUpdateFetchError.cancelled
    } catch let error as PreDriveEvidenceUpdateFetchError {
      throw error
    } catch let error as URLError where error.code == .cancelled {
      throw PreDriveEvidenceUpdateFetchError.cancelled
    } catch let error as URLError where error.code == .timedOut {
      throw PreDriveEvidenceUpdateFetchError.timedOut
    } catch {
      throw PreDriveEvidenceUpdateFetchError.network
    }
  }
}

private final class PreDriveEvidenceUpdateRedirectRejector:
  NSObject, URLSessionTaskDelegate, @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
