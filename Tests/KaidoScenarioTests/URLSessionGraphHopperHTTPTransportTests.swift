import Foundation
import KaidoAppleAdapters
import KaidoSurfaceRouting
import Testing

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession GraphHopper transport preserves repeated bounded GET parameters")
func urlSessionGraphHopperTransportGetsRoute() async throws {
  let transport = try URLSessionGraphHopperHTTPTransport(
    baseURL: try #require(URL(string: "https://graphhopper.test/api")),
    session: makeGraphHopperStubSession(),
    requestTimeoutSeconds: 7
  )
  let response = try await transport.get(
    GraphHopperHTTPRequest(
      path: "/route",
      queryItems: [
        .init(name: "point", value: "35,139"),
        .init(name: "point", value: "35,139.1"),
        .init(name: "details", value: "edge_key"),
        .init(name: "details", value: "osm_way_id"),
      ]
    )
  )

  #expect(response.statusCode == 200)
  let body = String(decoding: response.body, as: UTF8.self)
  #expect(body.contains("GET /api/route"))
  #expect(body.contains("point=35,139&point=35,139.1"))
  #expect(body.contains("details=edge_key&details=osm_way_id"))
  #expect(body.contains("application/json 7.0"))
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession GraphHopper transport classifies timeout and cancellation")
func urlSessionGraphHopperTransportClassifiesFailures() async throws {
  let transport = try URLSessionGraphHopperHTTPTransport(
    baseURL: try #require(URL(string: "https://failure.graphhopper.test")),
    session: makeGraphHopperFailureSession()
  )

  await #expect(throws: GraphHopperHTTPTransportFailure.timedOut) {
    try await transport.get(GraphHopperHTTPRequest(path: "/info"))
  }
  await #expect(throws: GraphHopperHTTPTransportFailure.cancelled) {
    try await transport.get(
      GraphHopperHTTPRequest(path: "/route", queryItems: [.init(name: "point", value: "0,0")])
    )
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession GraphHopper transport rejects invalid input and safety limits")
func urlSessionGraphHopperTransportRejectsInvalidInput() async throws {
  let baseURL = try #require(URL(string: "https://graphhopper.test"))
  #expect(
    throws: URLSessionGraphHopperHTTPTransportInitializationError.invalidResponseLimit
  ) {
    try URLSessionGraphHopperHTTPTransport(baseURL: baseURL, maximumResponseBytes: 0)
  }
  #expect(
    throws: URLSessionGraphHopperHTTPTransportInitializationError.invalidRequestTimeout
  ) {
    try URLSessionGraphHopperHTTPTransport(baseURL: baseURL, requestTimeoutSeconds: 0)
  }

  let transport = try URLSessionGraphHopperHTTPTransport(
    baseURL: baseURL,
    session: makeGraphHopperStubSession()
  )
  await #expect(throws: GraphHopperHTTPTransportFailure.invalidRequest) {
    try await transport.get(GraphHopperHTTPRequest(path: "/health"))
  }
  await #expect(throws: GraphHopperHTTPTransportFailure.invalidRequest) {
    try await transport.get(
      GraphHopperHTTPRequest(path: "/info", queryItems: [.init(name: "probe", value: "1")])
    )
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("URLSession GraphHopper transport rejects an oversized response")
func urlSessionGraphHopperTransportRejectsLargeResponse() async throws {
  let transport = try URLSessionGraphHopperHTTPTransport(
    baseURL: try #require(URL(string: "https://graphhopper.test/api")),
    session: makeGraphHopperStubSession(),
    maximumResponseBytes: 4
  )

  await #expect(throws: GraphHopperHTTPTransportFailure.responseTooLarge) {
    try await transport.get(GraphHopperHTTPRequest(path: "/info"))
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeGraphHopperStubSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [GraphHopperURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeGraphHopperFailureSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [GraphHopperFailureURLProtocolStub.self]
  return URLSession(configuration: configuration)
}

private final class GraphHopperURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "graphhopper.test"
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

private final class GraphHopperFailureURLProtocolStub: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "failure.graphhopper.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let code: URLError.Code = request.url?.path == "/info" ? .timedOut : .cancelled
    client?.urlProtocol(self, didFailWithError: URLError(code))
  }

  override func stopLoading() {}
}
