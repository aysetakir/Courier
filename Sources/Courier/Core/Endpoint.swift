import Foundation

public protocol Endpoint: Sendable {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem]? { get }
    var body: RequestBody? { get }
    var requiresAuthentication: Bool { get }
}

public extension Endpoint {
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem]? { nil }
    var body: RequestBody? { nil }
    var requiresAuthentication: Bool { true }

    /// Uçların özelleştireceği yer yukarıdaki alanlar, bu fonksiyon değil;
    /// o yüzden protokol gereksinimi değil.
    func makeURLRequest(encoder: JSONEncoder = JSONEncoder()) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        components.path = joinedPath(base: components.path, adding: path)

        // Boş dizi URL'in sonuna çıplak bir "?" yapıştırır.
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let body {
            switch body {
            case .json(let value):
                do {
                    request.httpBody = try encoder.encode(value)
                } catch {
                    throw NetworkError.encoding(error)
                }
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            case .data(let data):
                // İçeriğin ne olduğunu bilmiyoruz, Content-Type'ı uca bırakıyoruz.
                request.httpBody = data

            case .form(let fields):
                request.httpBody = Data(formURLEncoded(fields).utf8)
                request.setValue(
                    "application/x-www-form-urlencoded; charset=utf-8",
                    forHTTPHeaderField: "Content-Type"
                )
            }
        }

        // En son uygulanıyor ki uç, yukarıdaki Content-Type'ı ezebilsin.
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}

/// Aradaki "/" sayısı ne olursa olsun tek bir "/" ile birleştirir.
private func joinedPath(base: String, adding path: String) -> String {
    let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
    guard !path.isEmpty else { return trimmedBase }
    let prefixedPath = path.hasPrefix("/") ? path : "/" + path
    return trimmedBase + prefixedPath
}

/// Anahtarlar sıralı, yoksa aynı gövde her çalıştırmada farklı byte üretir.
private func formURLEncoded(_ fields: [String: String]) -> String {
    fields
        .sorted { $0.key < $1.key }
        .map { "\(percentEncodedFormComponent($0.key))=\(percentEncodedFormComponent($0.value))" }
        .joined(separator: "&")
}

private func percentEncodedFormComponent(_ string: String) -> String {
    // RFC 3986 "unreserved" kümesi.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
}
