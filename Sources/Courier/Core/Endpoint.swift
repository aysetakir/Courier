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

    /// Tarifi (`Endpoint`) gerçek isteğe (`URLRequest`) çeviren köprü.
    ///
    /// Bilerek protokol gereksinimi değil, sadece extension'da: her uç için
    /// aynı şekilde çalışmasını istiyoruz. Uçların özelleştirebileceği yer
    /// yukarıdaki alanlar, bu fonksiyonun gövdesi değil.
    ///
    /// `encoder` parametre olarak alınıyor çünkü JSON gövdenin nasıl
    /// kodlanacağına (tarih formatı, snake_case) uygulama karar verir —
    /// adım 6'da `HTTPClient` kendi encoder'ını buraya geçirecek.
    func makeURLRequest(encoder: JSONEncoder = JSONEncoder()) throws -> URLRequest {
        // URL'i string birleştirerek kurmuyoruz. "?q=iOS geliştirici" gibi bir
        // string'den URL üretmeye çalışırsan nil alırsın; URLComponents
        // encode'u kendisi halleder.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        components.path = joinedPath(base: components.path, adding: path)

        // Boş dizi vermek URL'in sonuna çıplak bir "?" yapıştırır.
        // Query yoksa alanı hiç doldurmuyoruz.
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Gövde yoksa httpBody'ye de Content-Type'a da hiç dokunmuyoruz:
        // boş bir Data ya da uydurma bir Content-Type göndermek, sunucunun
        // isteği farklı yorumlamasına sebep olabilir.
        if let body {
            switch body {
            case .json(let value):
                do {
                    request.httpBody = try encoder.encode(value)
                } catch {
                    // Burası sunucunun değil bizim hatamız: model Encodable
                    // sözleşmesini tutturamadı.
                    throw NetworkError.encoding(error)
                }
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            case .data(let data):
                // Ham veride içeriğin ne olduğunu bilmiyoruz (PDF? PNG?).
                // Content-Type'ı uydurmak yerine uca bırakıyoruz.
                request.httpBody = data

            case .form(let fields):
                request.httpBody = Data(formURLEncoded(fields).utf8)
                request.setValue(
                    "application/x-www-form-urlencoded; charset=utf-8",
                    forHTTPHeaderField: "Content-Type"
                )
            }
        }

        // Karar: endpoint'in kendi header'ları EN SON uygulanıyor, yani
        // yukarıda yazdığımız Content-Type'ı ezebilirler. Sebebi: bizim
        // yazdığımız değer makul bir varsayılan, kural değil. Özel bir medya
        // tipi kullanan uç (application/vnd.example.v2+json) kütüphaneyi
        // değiştirmek zorunda kalmamalı.
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }
}

/// baseURL'in path'i ile uç path'ini, aradaki "/" sayısı ne olursa olsun
/// tek bir "/" ile birleştirir.
///
/// baseURL "https://api.example.com/v1" + path "users" -> "/v1/users"
/// baseURL "https://api.example.com/"   + path "/users" -> "/users"
private func joinedPath(base: String, adding path: String) -> String {
    let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
    guard !path.isEmpty else { return trimmedBase }
    let prefixedPath = path.hasPrefix("/") ? path : "/" + path
    return trimmedBase + prefixedPath
}

/// `key=value&key=value` — her parçası percent-encode edilmiş halde.
///
/// Anahtarlar sıralanıyor: Dictionary'nin sırası her çalıştırmada değişir,
/// sıralamazsak aynı gövde farklı byte'lar üretir ve test edilemez hale gelir.
private func formURLEncoded(_ fields: [String: String]) -> String {
    fields
        .sorted { $0.key < $1.key }
        .map { "\(percentEncodedFormComponent($0.key))=\(percentEncodedFormComponent($0.value))" }
        .joined(separator: "&")
}

private func percentEncodedFormComponent(_ string: String) -> String {
    // RFC 3986'nın "unreserved" kümesi. Kalan her şey (& = + boşluk dahil)
    // encode edilmeli, yoksa değerin içindeki bir "&" alan sınırı sanılır.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
}
