import Foundation

/// Kaç kez ve ne kadar beklenerek tekrar deneneceği.
public struct RetryPolicy: Sendable, Equatable {

    /// İlk deneme dahil toplam deneme sayısı.
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    /// Gecikmenin ne kadarının rastgeleye bırakılacağı (0...1).
    public let jitter: Double

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 8,
        jitter: Double = 0.5
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(0, maxDelay)
        self.jitter = min(max(0, jitter), 1)
    }

    public static let `default` = RetryPolicy()

    /// Testler beklemesin diye: tekrar dener ama hiç uyumaz.
    public static let immediate = RetryPolicy(baseDelay: 0, maxDelay: 0, jitter: 0)

    /// Jitter'sız üstel gecikme; `attempt` az önce başarısız olan denemenin
    /// sırası (1 → baseDelay, 2 → 2×, 3 → 4×...), `maxDelay` ile sınırlı.
    public func backoff(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        return min(exponential, maxDelay)
    }

    /// Gerçekte beklenecek süre.
    ///
    /// Jitter yalnızca aşağı sapıyor — böylece `maxDelay` hiçbir zaman
    /// aşılmıyor ve 10.000 cihaz aynı milisaniyede geri gelmiyor.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let ceiling = backoff(forAttempt: attempt)
        guard jitter > 0, ceiling > 0 else { return ceiling }
        return Double.random(in: ceiling * (1 - jitter)...ceiling)
    }
}
