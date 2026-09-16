import Foundation

/// Endpoint alır, isteği atar, sonucu modele çevirir.
///
/// Actor değil: üç alan da `let`, korunacak değişken durum yok. Actor sadece
/// her çağrıya gereksiz bir await eklerdi. (TokenRefresher'da durum farklı.)
public final class HTTPClient: HTTPClientProtocol {

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let interceptors: [any RequestInterceptor]

    public init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        interceptors: [any RequestInterceptor] = []
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.interceptors = interceptors
    }

    public func send(_ endpoint: any Endpoint) async throws -> Data {
        try Task.checkCancellation()

        var request = try endpoint.makeURLRequest(encoder: encoder)
        // Sırayla: her interceptor bir öncekinin çıktısı üzerine yazar.
        for interceptor in interceptors {
            request = try await interceptor.adapt(request, for: endpoint)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // İptal bir ağ hatası değil, akış kontrolü: retry döngüsüne düşmesin.
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
            throw NetworkError.unauthorized
        default:
            // Gövdeyi atmıyoruz; API'nin asıl hata mesajı orada.
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
            throw NetworkError.decoding(error, raw: data)
        }
    }
}
