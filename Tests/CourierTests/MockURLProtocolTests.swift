import Foundation
import Testing
@testable import Courier

@Suite("MockURLProtocol")
struct MockURLProtocolTests {

    private let url = URL(string: "https://api.example.com/users")!

    @Test("kurulan yanıt gerçek URLSession'a ulaşıyor")
    func returnsStubbedResponse() async throws {
        let session = MockURLProtocol.makeSession(
            statusCode: 200,
            data: Data(#"{"id":"42"}"#.utf8)
        )

        let (data, response) = try await session.data(for: URLRequest(url: url))

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == #"{"id":"42"}"#)
    }

    @Test("handler hata fırlatınca session da fırlatıyor")
    func propagatesHandlerError() async throws {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: URLError.self) {
            _ = try await session.data(for: URLRequest(url: self.url))
        }
    }

    @Test("handler giden isteği görebiliyor")
    func handlerSeesOutgoingRequest() async throws {
        // Adım 13'te "gönderilen istekte Authorization header'ı var mı" gibi
        // şeyleri böyle doğrulayacağız.
        let session = MockURLProtocol.makeSession { request in
            let echoed = Data((request.url?.absoluteString ?? "").utf8)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, echoed)
        }

        let request = try TestAPI.search(query: "swift").makeURLRequest()
        let (data, _) = try await session.data(for: request)

        #expect(
            String(decoding: data, as: UTF8.self)
                == "https://api.example.com/users/search?q=swift"
        )
    }
}
