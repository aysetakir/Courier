import Foundation
import Testing
@testable import Courier

@Suite("HTTPClient")
struct HTTPClientTests {

    @Test("200 yanıtı modele çevriliyor")
    func decodesSuccessfulResponse() async throws {
        let client = HTTPClient(
            session: MockURLProtocol.makeSession(
                data: Data(#"{"id":"42","name":"Ayşegül"}"#.utf8)
            )
        )

        let user: User = try await client.send(TestAPI.plain)

        #expect(user == User(id: "42", name: "Ayşegül"))
    }

    @Test("500 yanıtında hata gövdesi KORUNUYOR")
    func preservesServerErrorBody() async throws {
        let errorBody = #"{"error":"email already registered"}"#
        let client = HTTPClient(
            session: MockURLProtocol.makeSession(statusCode: 500, data: Data(errorBody.utf8)),
            retryPolicy: .immediate
        )

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain)
            }
        )

        guard case .server(let statusCode, let data) = error else {
            Issue.record("Beklenen .server, gelen: \(error)")
            return
        }
        #expect(statusCode == 500)
        // Asıl mesele: gövde kaybolmuyor.
        #expect(String(decoding: data, as: UTF8.self) == errorBody)
        #expect(error.isRetryable)
    }

    @Test("401 ayrı bir hataya dönüşüyor")
    func mapsUnauthorized() async throws {
        let client = HTTPClient(session: MockURLProtocol.makeSession(statusCode: 401))

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain)
            }
        )

        guard case .unauthorized = error else {
            Issue.record("Beklenen .unauthorized, gelen: \(error)")
            return
        }
    }

    @Test("404 tekrar denenebilir sayılmıyor")
    func clientErrorIsNotRetryable() async throws {
        let client = HTTPClient(session: MockURLProtocol.makeSession(statusCode: 404))

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain)
            }
        )

        #expect(error.isRetryable == false)
    }

    @Test("bozuk JSON .decoding'e dönüşüyor ve ham veri hatada duruyor")
    func decodingFailureKeepsRawData() async throws {
        let malformed = #"{"id":"42","nmae":"Ayşegül"}"#  // alan adı yanlış
        let client = HTTPClient(session: MockURLProtocol.makeSession(data: Data(malformed.utf8)))

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain, as: User.self)
            }
        )

        guard case .decoding(_, let raw) = error else {
            Issue.record("Beklenen .decoding, gelen: \(error)")
            return
        }
        #expect(String(decoding: raw, as: UTF8.self) == malformed)
    }

    @Test("internet yoksa .transport dönüyor")
    func mapsTransportError() async throws {
        let client = HTTPClient(
            session: MockURLProtocol.makeSession { _ in
                throw URLError(.notConnectedToInternet)
            },
            retryPolicy: .immediate
        )

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain)
            }
        )

        guard case .transport(let underlying) = error else {
            Issue.record("Beklenen .transport, gelen: \(error)")
            return
        }
        #expect((underlying as? URLError)?.code == .notConnectedToInternet)
        #expect(error.isRetryable)
    }

    @Test("iptal edilen istek CancellationError fırlatıyor")
    func cancellationThrowsCancellationError() async throws {
        // Gecikme olmazsa istek iptal yetişmeden biter, test yanlış sebepten yeşil olur.
        let client = HTTPClient(
            session: MockURLProtocol.makeSession { request in
                Thread.sleep(forTimeInterval: 0.3)
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data("{}".utf8))
            }
        )

        let task = Task { try await client.send(TestAPI.plain) }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // .transport değil: iptal ağ hatası değil.
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
