import Foundation
import OSLog

/// İstekleri, yanıtları ve hataları OSLog'a yazar.
///
/// `print` yerine OSLog: seviyeye göre filtrelenebiliyor, Console.app'te
/// kategoriyle aranabiliyor ve release'te debug kayıtları maliyet üretmiyor.
///
/// Zincirin sonuna koy; yoksa sonraki interceptor'ların eklediği header'ları
/// (ör. Authorization) görmez.
public struct LoggingInterceptor: RequestInterceptor {

    /// Değeri loglara asla yazılmayan header'lar (büyük/küçük harf duyarsız).
    public static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
    ]

    private static let mask = "***"

    private let logger: Logger
    private let logsCURL: Bool

    /// - Parameter logsCURL: İsteği cURL komutu olarak da yazar. Gövde (ör.
    ///   login parolası) maskelenmediği için varsayılan olarak kapalı.
    public init(
        logger: Logger = Logger(subsystem: "Courier", category: "network"),
        logsCURL: Bool = false
    ) {
        self.logger = logger
        self.logsCURL = logsCURL
    }

    public func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "?"
        logger.debug("→ \(method, privacy: .public) \(url, privacy: .public)")
        if logsCURL {
            // .private: cihaz dışına alınan loglarda gövde görünmez.
            logger.debug("\(Self.cURL(for: request), privacy: .private)")
        }
        return request
    }

    public func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        let url = request.url?.absoluteString ?? "?"
        logger.debug(
            "← \(response.statusCode, privacy: .public) \(url, privacy: .public) (\(data.count, privacy: .public) bayt)"
        )
    }

    public func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        let url = request.url?.absoluteString ?? "?"
        logger.error(
            "✕ \(url, privacy: .public) deneme \(attempt, privacy: .public): \(String(describing: error), privacy: .private)"
        )
        // Sadece gözlemci: karar diğer interceptor'lara ve politikaya kalıyor.
        return .doNotRetry
    }

    /// İsteği terminalde çalıştırılabilir bir cURL komutuna çevirir.
    /// Hassas header'lar maskelenir.
    public static func cURL(for request: URLRequest) -> String {
        var parts = ["curl"]

        let method = request.httpMethod ?? "GET"
        if method != "GET" {
            parts.append("-X \(method)")
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }
        for (name, value) in headers {
            let shown = sensitiveHeaders.contains(name.lowercased()) ? mask : value
            parts.append("-H \(shellQuoted("\(name): \(shown)"))")
        }

        if let body = request.httpBody, !body.isEmpty {
            parts.append("-d \(shellQuoted(String(decoding: body, as: UTF8.self)))")
        }

        parts.append(shellQuoted(request.url?.absoluteString ?? ""))
        return parts.joined(separator: " \\\n  ")
    }

    /// Tek tırnak içinde her şey düz metin; içteki tırnak `'\''` ile kaçırılır.
    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
