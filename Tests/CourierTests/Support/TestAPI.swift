import Foundation
@testable import Courier

struct CreateUserPayload: Encodable, Sendable {
    let name: String
}

enum TestAPI: Endpoint {
    case plain
    case search(query: String)
    case create(name: String)

    var baseURL: URL { URL(string: "https://api.example.com")! }

    var path: String {
        switch self {
        case .plain:  return "/users"
        case .search: return "/users/search"
        case .create: return "/users"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .plain, .search: return .get
        case .create:         return .post
        }
    }
    
    var queryItems: [URLQueryItem]? {
        switch self {
        case .plain, .create:
            return nil
        case .search(let query):
            return [URLQueryItem(name: "q", value: query)]
        }
    }

    var body: RequestBody? {
        switch self {
        case .plain, .search:
            return nil
        case .create(let name):
            return .json(CreateUserPayload(name: name))
        }
    }
}
