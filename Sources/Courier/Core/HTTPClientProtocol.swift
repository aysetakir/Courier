import Foundation

/// Katmanın dış dünyaya bakan yüzü. Ekranlar HTTPClient'ı değil bunu tanır.
public protocol HTTPClientProtocol: Sendable {
    func send(_ endpoint: any Endpoint) async throws -> Data

    /// T'nin Sendable olma sebebi: decode edilen değer izolasyon sınırı aşıyor.
    func send<T: Decodable & Sendable>(_ endpoint: any Endpoint, as type: T.Type) async throws -> T
}

public extension HTTPClientProtocol {
    /// `let user: User = try await client.send(UserAPI.profile(id: "42"))`
    func send<T: Decodable & Sendable>(_ endpoint: any Endpoint) async throws -> T {
        try await send(endpoint, as: T.self)
    }
}
