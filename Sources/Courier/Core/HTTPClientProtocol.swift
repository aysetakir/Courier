import Foundation

/// Katmanın dış dünyaya bakan yüzü.
///
/// Ekranlar `HTTPClient`'ı değil bu protokolü tanır: böylece ViewModel
/// testlerinde ağa hiç çıkmayan sahte bir client verebilirsin.
/// (`MockURLProtocol` ağ katmanının KENDİ testleri için; bu protokol ise
/// ağ katmanını KULLANAN kodun testleri için.)
public protocol HTTPClientProtocol: Sendable {

    /// Ham yanıt gövdesi. JSON olmayan uçlar (resim indirme, CSV) için.
    func send(_ endpoint: any Endpoint) async throws -> Data

    /// Yanıtı modele çevirir.
    ///
    /// `T`'nin `Sendable` olması isteniyor çünkü decode edilen değer
    /// nonisolated bir async fonksiyondan çağırana (çoğunlukla `@MainActor`
    /// bir ViewModel'e) geçiyor — yani bir izolasyon sınırını aşıyor.
    func send<T: Decodable & Sendable>(_ endpoint: any Endpoint, as type: T.Type) async throws -> T
}

public extension HTTPClientProtocol {

    /// Dönüş tipini bağlamdan çıkaran kısayol:
    /// `let user: User = try await client.send(UserAPI.profile(id: "42"))`
    func send<T: Decodable & Sendable>(_ endpoint: any Endpoint) async throws -> T {
        try await send(endpoint, as: T.self)
    }
}
