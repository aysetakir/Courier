import Foundation

/// Ağa çıkmadan sahte HTTP yanıtı döndürür.
///
/// URLSession'ı protokolle sarmalamak yerine bunu kullanıyoruz: böylece
/// testler gerçek URLSession kod yolunu da çalıştırıyor.
final class MockURLProtocol: URLProtocol {

    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    // Handler session başına tutuluyor; tek global olsaydı paralel testler
    // birbirinin handler'ını ezerdi.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let sessionHeader = "X-Courier-Mock-Session"

    static func makeSession(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [sessionHeader: id]
        return URLSession(configuration: configuration)
    }

    /// Sabit yanıt döndüren session.
    static func makeSession(
        statusCode: Int = 200,
        data: Data = Data(),
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> URLSession {
        makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (response, data)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: MockURLProtocol.sessionHeader),
            let handler = MockURLProtocol.lock.withLock({ MockURLProtocol.handlers[id] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        do {
            let (response, data) = try handler(request)
            // Üçü de zorunlu ve sıra önemli; biri eksikse test asılı kalır.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
