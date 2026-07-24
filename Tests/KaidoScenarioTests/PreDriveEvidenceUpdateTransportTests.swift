import Foundation
import KaidoAppleAdapters
import Testing

@Test("Signed evidence endpoints require one exact credential-free HTTPS URL")
func preDriveEvidenceUpdateEndpointIsStrict() throws {
  let valid = PreDriveEvidenceUpdateEndpoint(
    url:
      "https://updates.kaido.test/pre-drive/product-release-v2.json"
  )
  #expect(
    valid.validatedURL?.absoluteString
      == "https://updates.kaido.test/pre-drive/product-release-v2.json"
  )

  let invalid = [
    "http://updates.kaido.test/update.json",
    "https://localhost/update.json",
    "https://127.0.0.1/update.json",
    "https://user@updates.kaido.test/update.json",
    "https://updates.kaido.test:443/update.json",
    "https://updates.kaido.test/update.json?release=2",
    "https://updates.kaido.test/update.json#latest",
    "https://updates.kaido.test/a/../update.json",
    "https://updates.kaido.test/update",
    " https://updates.kaido.test/update.json",
  ]
  for value in invalid {
    #expect(
      PreDriveEvidenceUpdateEndpoint(url: value).validatedURL == nil
    )
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("Signed evidence fetch uses one bounded uncached credential-free GET")
func preDriveEvidenceUpdateFetcherIsBounded() async throws {
  let fetcher = try URLSessionPreDriveEvidenceUpdateFetcher(
    session: makePreDriveEvidenceUpdateSession(),
    requestTimeoutSeconds: 7
  )
  let data = try await fetcher.fetch(
    endpoint: PreDriveEvidenceUpdateEndpoint(
      url: "https://updates.kaido.test/evidence/current.json"
    )
  )

  #expect(
    String(decoding: data, as: UTF8.self)
      == "GET|application/json|7.0|0"
  )
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test("Signed evidence fetch rejects response and network drift")
func preDriveEvidenceUpdateFetcherRejectsDrift() async throws {
  let fetcher = try URLSessionPreDriveEvidenceUpdateFetcher(
    session: makePreDriveEvidenceUpdateSession(),
    maximumResponseBytes: 32
  )

  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.invalidHTTPStatus
  ) {
    try await fetcher.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/status.json"
      )
    )
  }
  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.invalidContentType
  ) {
    try await fetcher.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/content.json"
      )
    )
  }
  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.endpointChanged
  ) {
    try await fetcher.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/drift.json"
      )
    )
  }
  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.responseTooLarge
  ) {
    try await fetcher.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/large.json"
      )
    )
  }

  let failures = try URLSessionPreDriveEvidenceUpdateFetcher(
    session: makePreDriveEvidenceUpdateFailureSession()
  )
  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.timedOut
  ) {
    try await failures.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://failure.kaido.test/timeout.json"
      )
    )
  }
  await #expect(
    throws: PreDriveEvidenceUpdateFetchError.cancelled
  ) {
    try await failures.fetch(
      endpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://failure.kaido.test/cancel.json"
      )
    )
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makePreDriveEvidenceUpdateSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [
    PreDriveEvidenceUpdateURLProtocolStub.self
  ]
  return URLSession(configuration: configuration)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makePreDriveEvidenceUpdateFailureSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [
    PreDriveEvidenceUpdateFailureURLProtocolStub.self
  ]
  return URLSession(configuration: configuration)
}

private final class PreDriveEvidenceUpdateURLProtocolStub:
  URLProtocol, @unchecked Sendable
{
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "updates.kaido.test"
  }

  override class func canonicalRequest(
    for request: URLRequest
  ) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let requestURL = request.url else {
      client?.urlProtocol(
        self,
        didFailWithError: URLError(.badURL)
      )
      return
    }
    let path = requestURL.path
    let responseURL =
      path.hasSuffix("/drift.json")
      ? URL(string: "https://other.kaido.test/evidence/drift.json")!
      : requestURL
    let statusCode = path.hasSuffix("/status.json") ? 503 : 200
    let contentType =
      path.hasSuffix("/content.json")
      ? "text/plain" : "application/json; charset=utf-8"
    let body: Data
    if path.hasSuffix("/large.json") {
      body = Data(repeating: 0x61, count: 64)
    } else {
      body = Data(
        [
          request.httpMethod ?? "",
          request.value(forHTTPHeaderField: "Accept") ?? "",
          String(request.timeoutInterval),
          request.httpShouldHandleCookies ? "1" : "0",
        ].joined(separator: "|").utf8
      )
    }
    let response = HTTPURLResponse(
      url: responseURL,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": contentType,
        "Content-Length": "\(body.count)",
      ]
    )!
    client?.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class PreDriveEvidenceUpdateFailureURLProtocolStub:
  URLProtocol, @unchecked Sendable
{
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "failure.kaido.test"
  }

  override class func canonicalRequest(
    for request: URLRequest
  ) -> URLRequest {
    request
  }

  override func startLoading() {
    let code: URLError.Code =
      request.url?.path.hasSuffix("/timeout.json") == true
      ? .timedOut : .cancelled
    client?.urlProtocol(
      self,
      didFailWithError: URLError(code)
    )
  }

  override func stopLoading() {}
}
