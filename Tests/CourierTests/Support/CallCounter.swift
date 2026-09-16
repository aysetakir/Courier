import Foundation

/// MockURLProtocol handler'ı senkron ve @Sendable olduğu için actor yerine
/// kilitli sayaç kullanıyoruz.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() {
        lock.withLock { value += 1 }
    }
}
