import Foundation

public enum RequestBody: Sendable {
    case json(any Encodable & Sendable)
    case data(Data)
    case form([String: String])
}
