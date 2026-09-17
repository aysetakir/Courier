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
    private let retryPolicy: RetryPolicy

    public init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        interceptors: [any RequestInterceptor] = [],
        retryPolicy: RetryPolicy = .default
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.interceptors = interceptors
        self.retryPolicy = retryPolicy
    }

    public func send(_ endpoint: any Endpoint) async throws -> Data {
        let baseRequest = try endpoint.makeURLRequest(encoder: encoder)
        var attempt = 1

        while true {
            try Task.checkCancellation()

            // Her denemede ham istekten yeniden: token yenilendiyse yeni header
            // bu turda girsin, önceki turun header'ları da üst üste binmesin.
            let request = try await adapt(baseRequest, for: endpoint)

            do {
                return try await perform(request)
            } catch let error as CancellationError {
                throw error
            } catch {
                // Tavan interceptor kararlarını da bağlar: hatalı bir interceptor
                // sonsuz döngü kuramaz.
                guard attempt < retryPolicy.maxAttempts else { throw error }

                switch await retryDecision(for: request, endpoint: endpoint, error: error, attempt: attempt) {
                case .doNotRetry:
                    throw error
                case .retry:
                    break
                case .retryAfter(let delay):
                    // İptal edilirse uyku CancellationError fırlatır, döngü biter.
                    try await Task.sleep(for: .seconds(delay))
                }
                attempt += 1
            }
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

    private func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        var request = request
        // Sırayla: her interceptor bir öncekinin çıktısı üzerine yazar.
        for interceptor in interceptors {
            request = try await interceptor.adapt(request, for: endpoint)
        }
        return request
    }

    /// Önce interceptor'lar sorulur, ilk "tekrar dene" diyen kazanır. Hiçbiri
    /// istemezse politika devreye girer; ama yalnızca idempotent metotlarda:
    /// 500 alan bir POST sunucuda işlenmiş olabilir, tekrarı çift kayıt demek.
    private func retryDecision(
        for request: URLRequest,
        endpoint: any Endpoint,
        error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        for interceptor in interceptors {
            let decision = await interceptor.retry(request, for: endpoint, dueTo: error, attempt: attempt)
            if decision != .doNotRetry { return decision }
        }

        guard
            endpoint.method.isIdempotent,
            let networkError = error as? NetworkError,
            networkError.isRetryable
        else { return .doNotRetry }

        return .retryAfter(retryPolicy.delay(forAttempt: attempt))
    }

    /// Tek bir deneme: isteği atar, yanıtı veriye ya da hataya çevirir.
    private func perform(_ request: URLRequest) async throws -> Data {
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
}
