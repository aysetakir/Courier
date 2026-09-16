import Foundation

/// Testlerde ağa hiç çıkmadan sahte HTTP yanıtı döndüren `URLProtocol`.
///
/// Neden `URLSession`'ı bir protokolle sarmalamıyoruz: sarmalarsak testler
/// gerçek `URLSession` kodunu hiç çalıştırmaz, sadece bizim taklidimizi test
/// eder. `URLProtocol` Apple'ın kendi bıraktığı uzantı noktası — session
/// normal akışıyla çalışır, sadece veriyi ağdan değil buradan alır.
final class MockURLProtocol: URLProtocol {

    /// İsteği alıp ne döneceğine karar veren fonksiyon. Fırlatırsa session da
    /// fırlatır — "internet yok" senaryosunu böyle üretiyoruz.
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// URLSession, URLProtocol'ü kendisi örnekliyor; handler'ı ona doğrudan
    /// geçirebileceğimiz bir yer yok. O yüzden statik bir tabloda tutuyoruz.
    ///
    /// Tek bir global handler yerine session başına ayrı handler tutmamızın
    /// sebebi: swift-testing testleri PARALEL çalıştırır. Tek değişken olsaydı
    /// iki test birbirinin handler'ını ezerdi ve testler "tek tek yeşil,
    /// hep birlikte rastgele kırmızı" olurdu — bulması en zor hata türü.
    ///
    /// Swift 6 statik değişkenlere izin vermiyor: `nonisolated(unsafe)` ile
    /// "eşzamanlılık güvenliğini ben üstleniyorum" diyoruz, `NSLock` ile de
    /// gerçekten üsteniyoruz.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    /// Session'ı handler'ına bağlayan gizli header.
    private static let sessionHeader = "X-Courier-Mock-Session"

    /// Verilen handler'a bağlı, ağa çıkmayan bir session üretir.
    ///
    /// `.ephemeral`: disk cache ve cookie saklamaz, yani testler birbirini
    /// kirletmez. `protocolClasses` ise session'a "isteği önce buna sor" der.
    static func makeSession(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        // Bu header session'ın attığı her isteğe ekleniyor; startLoading
        // içinde hangi handler'a ait olduğunu böyle buluyoruz.
        configuration.httpAdditionalHeaders = [sessionHeader: id]
        return URLSession(configuration: configuration)
    }

    /// Sabit bir yanıt döndüren session için kısayol.
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

    // MARK: - URLProtocol

    /// Bu session'a düşen her isteği biz karşılıyoruz.
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// İsteği normalleştirme (cache anahtarı üretme) işi; taklit ederken
    /// dokunmamız gereken bir şey yok.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: MockURLProtocol.sessionHeader),
            let handler = MockURLProtocol.lock.withLock({ MockURLProtocol.handlers[id] })
        else {
            // Session'ı makeSession ile kurmayı unuttuysan test asılı kalmasın,
            // açık bir hata alsın.
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        do {
            let (response, data) = try handler(request)
            // Bu üç çağrının SIRASI önemli ve üçü de zorunlu.
            // didFinishLoading'i atlarsan test sonsuza kadar asılı kalır.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// İstek iptal edildiğinde çağrılır. Gerçek bir protokolde burada soket
    /// kapatılır; bizim tutunan bir kaynağımız yok.
    override func stopLoading() {}
}
