import Foundation

/// Rations access to Claude Code's Keychain credentials so macOS asks the
/// user for authorization as rarely as possible.
///
/// Reading another app's Keychain item is authorization-gated, and the grant
/// cannot be made durable from this side: the ACL belongs to the item's owner
/// (Claude Code), which resets it whenever it rotates its OAuth token. So
/// "Always Allow" is not a fix — asking less is. The access token is valid for
/// hours, so one read per launch is enough; a rotation only becomes visible
/// when the server rejects what we hold, which is exactly when we re-read.
///
/// Every state transition here exists to prevent one class of repeat prompt:
/// a poll tick, a denial, or a 401 loop must never turn into a second dialog.
public final class UsageTokenCache {
    public enum ReadResult: Equatable {
        /// The item was read and carries a usable access token.
        case token(String)
        /// No credentials exist yet (errSecItemNotFound) — no prompt was shown.
        case unavailable
        /// The user denied access, or the read failed in a way that prompted.
        case denied
    }

    private enum State {
        /// Nothing held; the next request may read.
        case unread
        /// Serve this token; never read again while it holds.
        case valid(String)
        /// The server rejected this token; exactly one re-read is allowed.
        case rotating(rejected: String)
        /// Latched shut — reading again would only re-prompt.
        case exhausted
    }

    private var state: State = .unread
    /// Held across `read` on purpose: two concurrent refreshes must not race
    /// into two simultaneous Keychain dialogs.
    private let lock = NSLock()

    public init() {}

    /// The token to authenticate with, reading the Keychain only when it must.
    /// `read` is invoked at most once per call, and not at all when a cached
    /// token is available or the cache has latched shut.
    public func token(read: () -> ReadResult) -> String? {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .valid(let token):
            return token
        case .exhausted:
            return nil
        case .unread:
            return store(read(), rejecting: nil)
        case .rotating(let rejected):
            return store(read(), rejecting: rejected)
        }
    }

    /// The server rejected the cached token (401/403) — Claude Code has most
    /// likely rotated it. Permits a single re-read on the next request.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        if case .valid(let token) = state { state = .rotating(rejected: token) }
    }

    /// The user explicitly asked us to try again (toggling "Show usage"),
    /// which is the only thing that reopens a latched cache.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .unread
    }

    private func store(_ result: ReadResult, rejecting rejected: String?) -> String? {
        switch result {
        // The Keychain handed back the very token the server just refused;
        // re-reading on every poll from here would re-prompt every poll.
        case .token(let token) where token == rejected:
            state = .exhausted
            return nil
        case .token(let token):
            state = .valid(token)
            return token
        // Absent credentials cost nothing to re-check — no dialog is shown,
        // and it is how a later Claude Code login gets picked up.
        case .unavailable:
            state = .unread
            return nil
        case .denied:
            state = .exhausted
            return nil
        }
    }
}
