import Foundation
@testable import Courier

/// Sabit bir header ekler.
struct HeaderInterceptor: RequestInterceptor {
    let name: String
    let value: String

    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        var request = request
        request.setValue(value, forHTTPHeaderField: name)
        return request
    }
}

/// `X-Order` header'ının sonuna kendi harfini ekler; zincir sırasını kanıtlar.
struct OrderInterceptor: RequestInterceptor {
    let letter: String

    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        var request = request
        let current = request.value(forHTTPHeaderField: "X-Order") ?? ""
        request.setValue(current + letter, forHTTPHeaderField: "X-Order")
        return request
    }
}

struct InterceptorFailure: Error {}

/// adapt aşamasında patlar.
struct FailingInterceptor: RequestInterceptor {
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        throw InterceptorFailure()
    }
}

/// Her hatada koşulsuz tekrar ister; tavanın interceptor'ları da bağladığını kanıtlar.
struct AlwaysRetryInterceptor: RequestInterceptor {
    func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        .retry
    }
}
