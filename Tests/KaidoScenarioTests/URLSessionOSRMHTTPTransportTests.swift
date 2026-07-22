import Foundation
import KaidoAppleAdapters
import KaidoSurfaceRouting
import Testing

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession OSRM transport sends one bounded GET request")
func urlSessionOSRMTransportGetsRoute() async throws {
  let transport = try URLSessionOSRMHTTPTransport(
    baseURL: try #require(URL(string: "https://osrm.test/api")),
    session: makeOSRMStubSession(),
    requestTimeoutSeconds: 7
  )
  let response = try await transport.get(
    OSRMHTTPRequest(
      path: "/route/v1/driving/139.0,35.0;139.1,35.1",
      queryItems: [
        OSRMHTTPQueryItem(name: "annotations", value: "nodes"),
        OSRMHTTPQueryItem(name: "bearings", value: ";90,10"),
      ]
    )
  )

  #expect(response.statusCode == 200)
  let body = String(decoding: response.body, as: UTF8.self)
  #expect(body.contains("GET /api/route/v1/driving/139.0,35.0;139.1,35.1"))
  #expect(body.contains("annotations=nodes"))
  #expect(body.contains("bearings=;90,10") || body.contains("bearings=%3B90,10"))
  #expect(body.contains("application/json 7.0"))
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession OSRM transport classifies timeout and cancellation")
func urlSessionOSRMTransportClassifiesFailures() async throws {
  let transport = try URLSessionOSRMHTTPTransport(
    baseURL: try #require(URL(string: "https://failure.osrm.test")),
    session: makeOSRMFailureSession()
  )

  await #expect(throws: OSRMHTTPTransportFailure.timedOut) {
    try await transport.get(makeOSRMTransportRequest(pathSuffix: "timeout"))
  }
  await #expect(throws: OSRMHTTPTransportFailure.cancelled) {
    try await transport.get(makeOSRMTransportRequest(pathSuffix: "cancel"))
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession OSRM transport rejects invalid request and safety limits")
func urlSessionOSRMTransportRejectsInvalidInput() async throws {
  let baseURL = try #require(URL(string: "https://osrm.test"))
  #expect(throws: URLSessionOSRMHTTPTransportInitializationError.invalidResponseLimit) {
    try URLSessionOSRMHTTPTransport(baseURL: baseURL, maximumResponseBytes: 0)
  }
  #expect(throws: URLSessionOSRMHTTPTransportInitializationError.invalidRequestTimeout) {
    try URLSessionOSRMHTTPTransport(baseURL: baseURL, requestTimeoutSeconds: 0)
  }

  let transport = try URLSessionOSRMHTTPTransport(
    baseURL: baseURL,
    session: makeOSRMStubSession()
  )
  await #expect(throws: OSRMHTTPTransportFailure.invalidRequest) {
    try await transport.get(OSRMHTTPRequest(path: "/nearest/v1/driving/0,0", queryItems: []))
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession OSRM transport rejects an oversized response")
func urlSessionOSRMTransportRejectsLargeResponse() async throws {
  let transport = try URLSessionOSRMHTTPTransport(
    baseURL: try #require(URL(string: "https://osrm.test/api")),
    session: makeOSRMStubSession(),
    maximumResponseBytes: 4
  )

  await #expect(throws: OSRMHTTPTransportFailure.responseTooLarge) {
    try await transport.get(makeOSRMTransportRequest(pathSuffix: "large"))
  }
}

private func makeOSRMTransportRequest(pathSuffix: String) -> OSRMHTTPRequest {
  OSRMHTTPRequest(
    path: "/route/v1/driving/0,0;1,1/\(pathSuffix)",
    queryItems: []
  )
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeOSRMStubSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [OSRMURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeOSRMFailureSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [OSRMFailureURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

private final class OSRMURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "osrm.test"
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
      "\(request.httpMethod ?? "") \(url.path) \(url.query ?? "") \(request.value(forHTTPHeaderField: "Accept") ?? "") \(request.timeoutInterval)"
        .utf8
    )
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class OSRMFailureURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "failure.osrm.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let code: URLError.Code =
      request.url?.path.hasSuffix("timeout") == true
      ? .timedOut : .cancelled
    client?.urlProtocol(self, didFailWithError: URLError(code))
  }

  override func stopLoading() {}
}
