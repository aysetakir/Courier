import Foundation

struct User: Decodable, Sendable, Equatable {
    let id: String
    let name: String
}
