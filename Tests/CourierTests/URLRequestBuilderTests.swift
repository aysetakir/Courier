import Foundation
import Testing
@testable import Courier

@Suite("URLRequest builder")
struct URLRequestBuilderTests {

    @Test("baseURL ile path doğru birleşiyor")
    func joinsBaseURLAndPath() throws {
        let request = try TestAPI.plain.makeURLRequest()

        #expect(request.url?.absoluteString == "https://api.example.com/users")
        #expect(request.httpMethod == "GET")
    }

    @Test("query item'lar URL'e ekleniyor")
    func appendsQueryItems() throws {
        let request = try TestAPI.search(query: "swift").makeURLRequest()

        #expect(request.url?.absoluteString == "https://api.example.com/users/search?q=swift")
    }

    @Test("query yokken URL'in sonunda çıplak bir ? kalmıyor")
    func omitsQuestionMarkWhenThereIsNoQuery() throws {
        let request = try TestAPI.plain.makeURLRequest()

        // URLComponents'a boş bir dizi verirsen sonuna "?" yapıştırır.
        // Gözle fark edilmesi zor, ama bazı sunucular bunu farklı bir yol sayar.
        let url = try #require(request.url?.absoluteString)
        #expect(!url.contains("?"))
    }

    @Test("boşluk ve Türkçe karakter doğru encode ediliyor")
    func percentEncodesQueryValues() throws {
        let request = try TestAPI.search(query: "iOS geliştirici").makeURLRequest()

        // Boşluk -> %20, ş (U+015F) -> UTF-8'de C5 9F -> %C5%9F
        #expect(
            request.url?.absoluteString
                == "https://api.example.com/users/search?q=iOS%20geli%C5%9Ftirici"
        )
    }

    @Test("JSON gövde encode ediliyor ve Content-Type yazılıyor")
    func encodesJSONBody() throws {
        let request = try TestAPI.create(name: "Ayşegül").makeURLRequest()

        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode([String: String].self, from: body)

        #expect(decoded == ["name": "Ayşegül"])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpMethod == "POST")
    }

    @Test("GET isteğinin gövdesi ve Content-Type'ı yok")
    func getRequestHasNoBody() throws {
        let request = try TestAPI.plain.makeURLRequest()

        // Builder kendiliğinden boş bir gövde ya da Content-Type uydurmamalı.
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("endpoint'in kendi header'ı varsayılan Content-Type'ı eziyor")
    func endpointHeadersWinOverDefaults() throws {
        let request = try TestAPI.createV2(name: "Ayşegül").makeURLRequest()

        // Karar: endpoint'in headers'ı en son uygulanır. Böylece özel bir
        // medya tipi kullanan uçlar builder'ı değiştirmeden çalışabilir.
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/vnd.example.v2+json"
        )
        #expect(request.httpBody != nil)
    }
}
