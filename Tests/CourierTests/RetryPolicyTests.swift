import Foundation
import Testing
@testable import Courier

@Suite("RetryPolicy")
struct RetryPolicyTests {

    @Test("gecikme üstel artıyor")
    func backoffGrowsExponentially() {
        let policy = RetryPolicy(baseDelay: 0.5, maxDelay: 100, jitter: 0)

        #expect(policy.backoff(forAttempt: 1) == 0.5)
        #expect(policy.backoff(forAttempt: 2) == 1)
        #expect(policy.backoff(forAttempt: 3) == 2)
        #expect(policy.backoff(forAttempt: 4) == 4)
        #expect(policy.backoff(forAttempt: 5) == 8)
    }

    @Test("maxDelay aşılmıyor")
    func backoffIsCappedAtMaxDelay() {
        let policy = RetryPolicy(baseDelay: 0.5, maxDelay: 3, jitter: 0.5)

        #expect(policy.backoff(forAttempt: 20) == 3)
        // Jitter eklenince de aşmamalı: 200 örnekte bir kez bile.
        for _ in 0..<200 {
            #expect(policy.delay(forAttempt: 20) <= 3)
        }
    }

    @Test("jitter aynı attempt için farklı ama beklenen aralıkta değer üretiyor")
    func jitterVariesWithinBounds() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 100, jitter: 0.5)
        let ceiling = policy.backoff(forAttempt: 3)  // 4 saniye

        let samples = (0..<200).map { _ in policy.delay(forAttempt: 3) }

        // Hepsi aralıkta
        #expect(samples.allSatisfy { $0 >= ceiling * 0.5 && $0 <= ceiling })
        // Ve gerçekten dağılıyor: sabit bir değer dönseydi thundering herd
        // çözülmemiş olurdu.
        #expect(Set(samples).count > 1)
    }

    @Test("jitter kapalıyken gecikme deterministik")
    func zeroJitterIsDeterministic() {
        let policy = RetryPolicy(baseDelay: 0.5, maxDelay: 100, jitter: 0)

        #expect(policy.delay(forAttempt: 3) == policy.delay(forAttempt: 3))
        #expect(policy.delay(forAttempt: 3) == 2)
    }

    @Test("immediate hiç beklemiyor ama tekrar deniyor")
    func immediatePolicyDoesNotWait() {
        #expect(RetryPolicy.immediate.delay(forAttempt: 1) == 0)
        #expect(RetryPolicy.immediate.delay(forAttempt: 5) == 0)
        #expect(RetryPolicy.immediate.maxAttempts == 3)
    }

    @Test("geçersiz değerler güvenli aralığa çekiliyor")
    func clampsInvalidInput() {
        let policy = RetryPolicy(maxAttempts: 0, baseDelay: -1, maxDelay: -1, jitter: 5)

        #expect(policy.maxAttempts == 1)
        #expect(policy.baseDelay == 0)
        #expect(policy.jitter == 1)
    }
}
