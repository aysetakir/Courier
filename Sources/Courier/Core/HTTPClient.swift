import Foundation

/// `Endpoint` alır, isteği atar, sonucu modele çevirir.
///
/// **Neden `actor` değil:** Actor, aynı anda birden fazla yerden erişilen
/// *değişken* durumu korumak için var. Buradaki üç alanın üçü de `let` —
/// kurulduktan sonra hiçbiri değişmiyor. Korunacak durum yokken actor
/// kullanmak hiçbir güvenlik kazandırmaz, sadece her çağrıya gereksiz bir
/// `await` ve bir bağlam değişimi ekler.
///
/// (Adım 11'deki `TokenRefresher`'da gerçekten değişken durum olacak —
/// devam eden yenileme task'ı — ve orada actor gerçekten gerekli olacak.
/// Farkı görmek için bu iki tipi yan yana koy.)
public final class HTTPClient: HTTPClientProtocol {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    public func send(_ endpoint: any Endpoint) async throws -> Data {
        // İptal edilmiş bir task için istek kurmaya başlamanın anlamı yok.
        try Task.checkCancellation()

        let request = try endpoint.makeURLRequest(encoder: encoder)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // İptal bir ağ hatası DEĞİL, akış kontrolü. URLSession bunu
            // URLError(.cancelled) olarak bildiriyor ama biz Swift'in
            // standart sinyaline çeviriyoruz: çağıran taraf `catch is
            // CancellationError` yazabilsin, ve bu asla "tekrar dene"
            // dalına düşmesin (adım 9).
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw NetworkError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data

        case 401:
            // Ayrı case, çünkü tek başına farklı bir tepkisi var:
            // token yenile ve tekrarla (adım 13).
            throw NetworkError.unauthorized

        default:
            // Gövdeyi ATMIYORUZ. API'nin asıl hata mesajı orada:
            // {"error": "email already registered"}
            throw NetworkError.server(statusCode: httpResponse.statusCode, data: data)
        }
    }

    public func send<T: Decodable & Sendable>(
        _ endpoint: any Endpoint,
        as type: T.Type
    ) async throws -> T {
        let data = try await send(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Ham veriyi hataya iliştiriyoruz: decoding hatasını ayıklamanın
            // tek yolu sunucunun gerçekte ne gönderdiğini görmek.
            throw NetworkError.decoding(error, raw: data)
        }
    }
}
