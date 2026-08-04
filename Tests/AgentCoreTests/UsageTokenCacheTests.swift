import AgentCore
import XCTest

final class UsageTokenCacheTests: XCTestCase {
    /// Records every Keychain read so tests can assert on how *often* the
    /// Keychain is touched — each read is a macOS authorization prompt.
    private final class Spy {
        private(set) var reads = 0
        var results: [UsageTokenCache.ReadResult]
        init(_ results: [UsageTokenCache.ReadResult]) { self.results = results }
        func read() -> UsageTokenCache.ReadResult {
            defer { reads += 1 }
            return reads < results.count ? results[reads] : results[results.count - 1]
        }
    }

    func testReadsKeychainOnFirstUse() {
        let spy = Spy([.token("abc")])
        let cache = UsageTokenCache()
        XCTAssertEqual(cache.token(read: spy.read), "abc")
        XCTAssertEqual(spy.reads, 1)
    }

    /// The bug: a 120s refresh timer used to hit the Keychain on every tick,
    /// so macOS asked for authorization every two minutes forever.
    func testReusesCachedTokenWithoutTouchingKeychainAgain() {
        let spy = Spy([.token("abc")])
        let cache = UsageTokenCache()
        for _ in 0..<50 { XCTAssertEqual(cache.token(read: spy.read), "abc") }
        XCTAssertEqual(spy.reads, 1, "the Keychain must be read exactly once")
    }

    /// A missing item returns errSecItemNotFound *without* prompting, so
    /// retrying is free — and it is how we notice a fresh Claude Code login.
    func testMissingCredentialsKeepRetrying() {
        let spy = Spy([.unavailable, .unavailable, .token("fresh")])
        let cache = UsageTokenCache()
        XCTAssertNil(cache.token(read: spy.read))
        XCTAssertNil(cache.token(read: spy.read))
        XCTAssertEqual(cache.token(read: spy.read), "fresh")
        XCTAssertEqual(spy.reads, 3)
    }

    /// Denial is latched: re-reading would re-prompt, which is the nagging
    /// behaviour we are fixing.
    func testDeniedAccessIsNeverRetriedOnItsOwn() {
        let spy = Spy([.denied])
        let cache = UsageTokenCache()
        for _ in 0..<20 { XCTAssertNil(cache.token(read: spy.read)) }
        XCTAssertEqual(spy.reads, 1, "a denial must not produce a second prompt")
    }

    /// Toggling "Show usage" off and on is the user explicitly asking again.
    func testResetClearsTheDenialLatch() {
        let spy = Spy([.denied, .token("abc")])
        let cache = UsageTokenCache()
        XCTAssertNil(cache.token(read: spy.read))
        cache.reset()
        XCTAssertEqual(cache.token(read: spy.read), "abc")
        XCTAssertEqual(spy.reads, 2)
    }

    /// A 401 means Claude Code rotated the token; one re-read picks up the new one.
    func testInvalidateAllowsOneReReadAfterRotation() {
        let spy = Spy([.token("old"), .token("new")])
        let cache = UsageTokenCache()
        XCTAssertEqual(cache.token(read: spy.read), "old")
        cache.invalidate()
        XCTAssertEqual(cache.token(read: spy.read), "new")
        XCTAssertEqual(cache.token(read: spy.read), "new")
        XCTAssertEqual(spy.reads, 2)
    }

    /// If the re-read hands back the same token the server just rejected,
    /// reading again would only re-prompt on every poll — so stop.
    func testInvalidateDoesNotLoopWhenTheTokenIsUnchanged() {
        let spy = Spy([.token("stale")])
        let cache = UsageTokenCache()
        XCTAssertEqual(cache.token(read: spy.read), "stale")
        cache.invalidate()
        XCTAssertNil(cache.token(read: spy.read), "the rejected token must not be reused")
        for _ in 0..<20 { XCTAssertNil(cache.token(read: spy.read)) }
        XCTAssertEqual(spy.reads, 2, "one re-read, then silence")
    }
}
