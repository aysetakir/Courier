import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    
    public var isIdempotent: Bool {
        switch self {
        case .get, .head, .put, .delete:
            return true
        case .post, .patch:
            return false
        }
    }
}


