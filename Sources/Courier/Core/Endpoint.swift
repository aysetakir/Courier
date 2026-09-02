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
}
