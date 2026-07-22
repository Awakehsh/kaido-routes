import Foundation
import KaidoAppleAdapters
import KaidoSurfaceRouting
import Testing

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession Valhalla transport posts to the bounded action endpoint")
func urlSessionValhallaTransportPostsJSON() async throws {
  let transport = try URLSessionValhallaHTTPTransport(
    baseURL: try #require(URL(string: "https://valhalla.test/api")),
    session: makeValhallaStubSession(),
    requestTimeoutSeconds: 7
  )

  let response = try await transport.post(
    action: .route,
    jsonBody: Data("{\"probe\":true}".utf8)
  )

  #expect(response.statusCode == 200)
  #expect(
    String(decoding: response.body, as: UTF8.self)
      == "POST /api/route application/json 7.0"
  )
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession Valhalla transport classifies timeout and cancellation")
func urlSessionValhallaTransportClassifiesFailures() async throws {
  let transport = try URLSessionValhallaHTTPTransport(
    baseURL: try #require(URL(string: "https://failure.valhalla.test")),
    session: makeValhallaFailureSession()
  )

  await #expect(throws: ValhallaHTTPTransportFailure.timedOut) {
    try await transport.post(action: .route, jsonBody: Data("{}".utf8))
  }
  await #expect(throws: ValhallaHTTPTransportFailure.cancelled) {
    try await transport.post(action: .traceAttributes, jsonBody: Data("{}".utf8))
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession Valhalla transport rejects invalid safety limits")
func urlSessionValhallaTransportRejectsInvalidLimits() throws {
  let baseURL = try #require(URL(string: "https://valhalla.test"))
  #expect(
    throws: URLSessionValhallaHTTPTransportInitializationError.invalidResponseLimit
  ) {
    try URLSessionValhallaHTTPTransport(baseURL: baseURL, maximumResponseBytes: 0)
  }
  #expect(
    throws: URLSessionValhallaHTTPTransportInitializationError.invalidRequestTimeout
  ) {
    try URLSessionValhallaHTTPTransport(baseURL: baseURL, requestTimeoutSeconds: 0)
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession Valhalla transport rejects an oversized response")
func urlSessionValhallaTransportRejectsLargeResponse() async throws {
  let transport = try URLSessionValhallaHTTPTransport(
    baseURL: try #require(URL(string: "https://valhalla.test/api")),
    session: makeValhallaStubSession(),
    maximumResponseBytes: 4
  )

  await #expect(throws: ValhallaHTTPTransportFailure.responseTooLarge) {
    try await transport.post(
      action: .traceAttributes,
      jsonBody: Data("{}".utf8)
    )
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeValhallaStubSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ValhallaURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeValhallaFailureSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ValhallaFailureURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

private final class ValhallaURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "valhalla.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    let body = Data(
      "\(request.httpMethod ?? "") \(url.path) \(request.value(forHTTPHeaderField: "Content-Type") ?? "") \(request.timeoutInterval)"
        .utf8
    )
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class ValhallaFailureURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "failure.valhalla.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let code: URLError.Code = request.url?.path == "/route" ? .timedOut : .cancelled
    client?.urlProtocol(self, didFailWithError: URLError(code))
  }

  override func stopLoading() {}
}
