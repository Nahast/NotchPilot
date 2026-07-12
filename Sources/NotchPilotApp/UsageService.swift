import AgentCore
import Combine
import Foundation
import Security

/// Fetches the account's rate-limit windows (5h session, 7d, per-model) from
/// Anthropic's usage endpoint — the numbers `/usage` shows in Claude Code.
///
/// Reads Claude Code's own OAuth access token from the macOS Keychain
/// (the "Claude Code-credentials" item); macOS asks the user for permission
/// on first access. No credentials ever leave the machine except to
/// api.anthropic.com itself. Failures (denied Keychain access, expired
/// token, offline) hide the usage section — never block the app.
final class UsageService {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    let snapshotPublisher: AnyPublisher<UsageSnapshot?, Never>
    /// True when usage is enabled but no Claude Code credentials exist in the
    /// Keychain — the UI shows a sign-in hint instead of silently hiding.
    let signedOutPublisher: AnyPublisher<Bool, Never>
    private let snapshotSubject = CurrentValueSubject<UsageSnapshot?, Never>(nil)
    private let signedOutSubject = CurrentValueSubject<Bool, Never>(false)
    private let isEnabled: () -> Bool
    private var timer: Timer?
    /// Survives a disable/enable cycle so re-enabling can show numbers
    /// instantly (slightly stale) while the fresh fetch is in flight.
    private(set) var cachedSnapshot: UsageSnapshot?
    /// One pending rate-limit retry at a time.
    private var retryScheduled = false

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        snapshotPublisher = snapshotSubject.eraseToAnyPublisher()
        signedOutPublisher = signedOutSubject.removeDuplicates().eraseToAnyPublisher()
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
            return
        }
        // Respect a pending rate-limit backoff — extra requests during the
        // window (periodic timer, toggle) would only extend the throttle.
        if retryScheduled { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let token = Self.readAccessToken() else {
                NSLog("NotchPilot usage: no Claude Code credentials in Keychain (denied or absent)")
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
                if let data,
                   let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    snapshot = UsageSnapshot.parse(from: data)
                    NSLog("NotchPilot usage: HTTP %d, parsed %d window(s)",
                          http.statusCode, snapshot?.windows.count ?? 0)
                } else {
                    snapshot = nil
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? -1
                    NSLog("NotchPilot usage: fetch failed (HTTP %d, error: %@)",
                          status, error?.localizedDescription ?? "none")
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
            guard let self, !self.retryScheduled else { return }
            self.retryScheduled = true
            NSLog("NotchPilot usage: retrying in %.0fs", seconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.retryScheduled = false
                self?.refresh()
            }
        }
    }

    /// Claude Code stores its credentials as a generic-password Keychain
    /// item whose payload is JSON: {"claudeAiOauth": {"accessToken": …}}.
    private static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let oauth = dictionary["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }
}
