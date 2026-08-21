import Foundation
import Testing

@testable import AppShowcaseCore

/// Serves a canned status and body, so the transport's classification can be
/// tested without a network.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failure: (any Error)?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Serialized: the stub carries its canned response in static storage, so these
/// cases must not run concurrently with each other.
@Suite("URLSessionTransport", .serialized)
struct URLSessionTransportTests {
    private let url = URL(string: "https://itunes.apple.com/lookup?id=1")!

    private func transport(status: Int, body: Data = Data("{}".utf8)) -> URLSessionTransport {
        StubURLProtocol.failure = nil
        StubURLProtocol.statusCode = status
        StubURLProtocol.body = body
        return URLSessionTransport(session: StubURLProtocol.session())
    }

    @Test("returns the body on a 2xx")
    func passesThroughSuccess() async throws {
        let data = try await transport(status: 200, body: Data("{\"ok\":1}".utf8)).data(from: url)

        #expect(String(decoding: data, as: UTF8.self) == "{\"ok\":1}")
    }

    /// At the boundary: a throttled caller gets a status, not a
    /// connection error, and the body that comes with it is not JSON. Reading it
    /// as a decode failure would classify a rate limit as the wire format
    /// changing — and the loader answers those two in opposite ways.
    @Test(
        "classifies a non-2xx as a transport failure rather than letting its body decode",
        arguments: [403, 429, 500, 503]
    )
    func mapsErrorStatusToTransportFailure(status: Int) async {
        let transport = transport(status: status, body: Data("You have exceeded".utf8))

        await #expect(throws: LookupError.transportFailed) {
            try await transport.data(from: url)
        }
    }

    @Test("maps a connection failure to a transport failure")
    func mapsConnectionFailure() async {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = Data()
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        let transport = URLSessionTransport(session: StubURLProtocol.session())

        await #expect(throws: LookupError.transportFailed) {
            try await transport.data(from: url)
        }
    }

    /// Cancellation is not a network failure. Folding it into `transportFailed`
    /// would let a superseded load fall back to a stale cache and resolve
    /// anyway, which is not what a canceled task is supposed to do.
    @Test("propagates cancellation instead of reporting a transport failure")
    func propagatesCancellation() async {
        StubURLProtocol.failure = URLError(.cancelled)
        let transport = URLSessionTransport(session: StubURLProtocol.session())

        await #expect(throws: CancellationError.self) {
            try await transport.data(from: url)
        }
    }
}
