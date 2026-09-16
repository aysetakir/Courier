import Foundation

/// Hatayı kaynağına göre ayırır: her case'in farklı bir tepkisi var.
public enum NetworkError: Error {
    case invalidURL
    case encoding(any Error)
    case transport(any Error)
    case invalidResponse
    case unauthorized
    /// Ham gövde saklanıyor: API hata mesajını orada döner.
    case server(statusCode: Int, data: Data)
    /// Ham gövde saklanıyor: hatayı ayıklamanın tek yolu gelen veriyi görmek.
    case decoding(any Error, raw: Data)

    public var isRetryable: Bool {
        switch self {
        case .transport(let error):
            // İptal edilen istek asla tekrar denenmez.
            if error is CancellationError { return false }
            if let urlError = error as? URLError, urlError.code == .cancelled { return false }
            return true

        case .server(let statusCode, _):
            return [408, 429, 500, 502, 503, 504].contains(statusCode)

        case .unauthorized:
            // Önce token yenilenmeli; kararı AuthInterceptor verecek.
            return false

        case .invalidURL, .encoding, .invalidResponse, .decoding:
            return false
        }
    }
}
