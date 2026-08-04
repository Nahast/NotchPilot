import AgentCore
import Combine
import Foundation
import OSLog
import Security

/// Fetches the account's rate-limit windows (5h session, 7d, per-model) from
/// Anthropic's usage endpoint — the numbers `/usage` shows in Claude Code.
///
/// Reads Claude Code's own OAuth access token from the macOS Keychain
/// (the "Claude Code-credentials" item); macOS asks the user for permission
/// on first access. That read goes through `UsageTokenCache`, which holds the
/// token for the life of the launch — the refresh timer must never touch the
/// Keychain, or macOS re-prompts on every tick. No credentials ever leave the
/// machine except to api.anthropic.com itself. Failures (denied Keychain
/// access, expired token, offline) hide the usage section — never block the app.
final class UsageService {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    let snapshotPublisher: AnyPublisher<UsageSnapshot?, Never>
    /// True when usage is enabled but no Claude Code credentials exist in the
    /// Keychain — the UI shows a sign-in hint instead of silently hiding.
    let signedOutPublisher: AnyPublisher<Bool, Never>
    /// True while a rate-limit (429) backoff is pending — the UI shows a
    /// loading row so an empty usage block reads as "waiting", not "broken".
    let waitingPublisher: AnyPublisher<Bool, Never>
    private let snapshotSubject = CurrentValueSubject<UsageSnapshot?, Never>(nil)
    private let signedOutSubject = CurrentValueSubject<Bool, Never>(false)
    private let waitingSubject = CurrentValueSubject<Bool, Never>(false)
    private let isEnabled: () -> Bool
    private var timer: Timer?
    /// Survives a disable/enable cycle so re-enabling can show numbers
    /// instantly (slightly stale) while the fresh fetch is in flight.
    private(set) var cachedSnapshot: UsageSnapshot?
    /// One pending rate-limit retry at a time.
    private var retryScheduled = false
    /// Keeps the 120s refresh timer away from the Keychain.
    private let tokenCache = UsageTokenCache()

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        snapshotPublisher = snapshotSubject.eraseToAnyPublisher()
        signedOutPublisher = signedOutSubject.removeDuplicates().eraseToAnyPublisher()
        waitingPublisher = waitingSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func start(refreshInterval: TimeInterval = 120) {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard isEnabled() else {
            snapshotSubject.send(nil)
            signedOutSubject.send(false)
            waitingSubject.send(false)
            return
        }
        // Respect a pending rate-limit backoff — extra requests during the
        // window (periodic timer, toggle) would only extend the throttle.
        if retryScheduled { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let token = self.tokenCache.token(read: Self.readCredential) else {
                Log.usage.info("no Claude Code credentials in Keychain (denied or absent)")
                DispatchQueue.main.async {
                    self.snapshotSubject.send(nil)
                    self.signedOutSubject.send(true)
                }
                return
            }
            DispatchQueue.main.async { self.signedOutSubject.send(false) }
            var request = URLRequest(url: Self.usageURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                let snapshot: UsageSnapshot?
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? -1
                if let data, (200..<300).contains(status) {
                    snapshot = UsageSnapshot.parse(from: data)
                    Log.usage.info("HTTP \(status, privacy: .public), parsed \(snapshot?.windows.count ?? 0, privacy: .public) window(s)")
                } else {
                    snapshot = nil
                    Log.usage.error("fetch failed (HTTP \(status, privacy: .public), error: \(error?.localizedDescription ?? "none", privacy: .public))")
                    // The token we hold was refused — Claude Code has rotated
                    // it. Let the cache spend one re-read on the next tick;
                    // it stops by itself if the Keychain returns the same one.
                    if status == 401 || status == 403 {
                        self.tokenCache.invalidate()
                    }
                    // Rate limited: retry after the server-suggested delay
                    // instead of going blank until the 120s timer.
                    if status == 429 {
                        let suggested = http?.value(forHTTPHeaderField: "Retry-After")
                            .flatMap(Double.init) ?? 60
                        self.scheduleRetry(after: min(600, max(30, suggested)))
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if snapshot != nil { self.cachedSnapshot = snapshot }
                    // A rate-limited fetch keeps its "waiting" state (set by
                    // scheduleRetry); any other outcome resolves it.
                    if status != 429 { self.waitingSubject.send(false) }
                    // Keep showing the last good snapshot through transient
                    // failures; it ages out visually via fetchedAt if needed.
                    if snapshot != nil || self.snapshotSubject.value == nil {
                        self.snapshotSubject.send(snapshot)
                    }
                }
            }
            task.resume()
        }
    }

    private func scheduleRetry(after seconds: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.waitingSubject.send(true)
            guard !self.retryScheduled else { return }
            self.retryScheduled = true
            Log.usage.info("retrying in \(Int(seconds), privacy: .public)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.retryScheduled = false
                self?.refresh()
            }
        }
    }

    /// Claude Code stores its credentials as a generic-password Keychain
    /// item whose payload is JSON: {"claudeAiOauth": {"accessToken": …}}.
    ///
    /// The distinction the cache needs is *why* a read came back empty: an
    /// absent item costs nothing to re-check, whereas a refusal means macOS
    /// put a dialog in front of the user that we must not raise again.
    private static func readCredential() -> UsageTokenCache.ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            Log.usage.error("Keychain read returned OSStatus \(status, privacy: .public)")
            return status == errSecItemNotFound ? .unavailable : .denied
        }
        guard let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let oauth = dictionary["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return .unavailable }
        return .token(token)
    }

    /// The user asked us to try again (they re-enabled usage in Settings) —
    /// the one thing that reopens the Keychain after a denial.
    func retryCredentials() {
        tokenCache.reset()
    }
}
