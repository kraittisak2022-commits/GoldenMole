import Foundation
import UIKit

/// Soft (optional) update check for TestFlight / App Store builds.
enum AppUpdateChecker {
    struct Offer: Identifiable, Equatable, Sendable {
        let id: String
        let latestVersion: String
        let latestBuild: String?
        let currentVersion: String
        let currentBuild: String
        let message: String?
        let openURL: URL
        let sourceLabel: String

        var versionLine: String {
            if let latestBuild, !latestBuild.isEmpty {
                return "v\(latestVersion) (\(latestBuild))"
            }
            return "v\(latestVersion)"
        }

        var currentLine: String {
            "v\(currentVersion) (\(currentBuild))"
        }
    }

    struct RemoteHint: Sendable {
        var latestVersion: String?
        var latestBuild: String?
        var testFlightURL: String?
        var message: String?
    }

    private static let snoozePrefix = "appUpdate.snoozeUntil."
    private static let snoozeDays: TimeInterval = 60 * 60 * 72 // 3 days

    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var installedBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.goldenmole.dashboard"
    }

    /// Info.plist / xcconfig optional override.
    static var configuredTestFlightURL: URL? {
        urlFromInfo("TESTFLIGHT_URL") ?? urlFromInfo("AppTestFlightURL")
    }

    static var configuredAppStoreId: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty, raw != "$(APP_STORE_ID)" else { return nil }
        return raw
    }

    // MARK: - Public API

    /// Returns an offer when a newer build is available and not snoozed.
    /// Pass `force: true` to ignore snooze (manual “เช็คอัพเดต”).
    ///
    /// Source of truth: Supabase `app_settings.app_defaults`
    /// (`iosLatestVersion` / `iosLatestBuild` — written by Codemagic after each IPA).
    /// App Store lookup is only a fallback when the DB has no version yet.
    static func check(remote: RemoteHint? = nil, force: Bool = false) async -> Offer? {
        let currentV = installedVersion
        let currentB = installedBuild

        let dbVersion = remote?.latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDbVersion = !(dbVersion ?? "").isEmpty

        let storeInfo: LookupResult?
        if hasDbVersion {
            storeInfo = nil
        } else {
            storeInfo = await fetchAppStoreLookup()
        }

        let candidateVersion: String?
        let candidateBuild: String?
        let sourceLabel: String

        if hasDbVersion, let dbVersion {
            candidateVersion = dbVersion
            let build = remote?.latestBuild?.trimmingCharacters(in: .whitespacesAndNewlines)
            candidateBuild = (build?.isEmpty == false) ? build : nil
            sourceLabel = "TestFlight"
        } else if let store = storeInfo {
            candidateVersion = store.version
            candidateBuild = nil
            sourceLabel = "App Store"
        } else {
            return nil
        }

        guard let candidateVersion else { return nil }

        guard isNewer(version: candidateVersion, build: candidateBuild, thanVersion: currentV, build: currentB) else {
            return nil
        }

        let offerId = "\(candidateVersion)|\(candidateBuild ?? "-")"
        if !force, isSnoozed(offerId: offerId) {
            return nil
        }

        let openURL = resolveOpenURL(
            remoteURL: remote?.testFlightURL,
            storeURL: storeInfo?.trackViewUrl
        )

        let message = remote?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Offer(
            id: offerId,
            latestVersion: candidateVersion,
            latestBuild: candidateBuild,
            currentVersion: currentV,
            currentBuild: currentB,
            message: (message?.isEmpty == false) ? message : defaultMessage(version: candidateVersion),
            openURL: openURL,
            sourceLabel: sourceLabel
        )
    }

    static func snooze(_ offer: Offer) {
        let until = Date().addingTimeInterval(snoozeDays).timeIntervalSince1970
        UserDefaults.standard.set(until, forKey: snoozePrefix + offer.id)
    }

    static func open(_ offer: Offer) {
        UIApplication.shared.open(offer.openURL, options: [:], completionHandler: nil)
    }

    // MARK: - Remote hint from app_defaults

    static func remoteHint(from defaults: AppDefaultsBlob?) -> RemoteHint? {
        guard let defaults else { return nil }
        let hint = RemoteHint(
            latestVersion: defaults.iosLatestVersion,
            latestBuild: defaults.iosLatestBuild,
            testFlightURL: defaults.iosTestFlightURL,
            message: defaults.iosUpdateMessage
        )
        if hint.latestVersion == nil && hint.testFlightURL == nil && hint.message == nil {
            return nil
        }
        return hint
    }

    // MARK: - Internals

    private struct LookupResult: Sendable {
        let version: String
        let trackViewUrl: String?
    }

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String?
            let trackViewUrl: String?
        }
        let resultCount: Int?
        let results: [Result]?
    }

    private static func fetchAppStoreLookup() async -> LookupResult? {
        let id = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&t=\(Int(Date().timeIntervalSince1970))") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let first = decoded.results?.first, let version = first.version, !version.isEmpty else {
                return nil
            }
            return LookupResult(version: version, trackViewUrl: first.trackViewUrl)
        } catch {
            return nil
        }
    }

    private static func resolveOpenURL(remoteURL: String?, storeURL: String?) -> URL {
        if let remote = url(from: remoteURL) { return remote }
        if let configured = configuredTestFlightURL { return configured }
        if let store = url(from: storeURL) { return store }
        if let appId = configuredAppStoreId,
           let store = URL(string: "https://apps.apple.com/app/id\(appId)") {
            return store
        }
        return URL(string: "itms-beta://")!
    }

    private static func url(from raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "itms-beta" || scheme == "itms-apps"
        else { return nil }
        return url
    }

    private static func urlFromInfo(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return url(from: trimmed)
    }

    static func isNewer(version: String, build: String?, thanVersion currentVersion: String, build currentBuild: String) -> Bool {
        let vCmp = compareVersions(version, currentVersion)
        if vCmp > 0 { return true }
        if vCmp < 0 { return false }
        guard let build, !build.isEmpty else { return false }
        return compareVersions(build, currentBuild) > 0
    }

    /// Dot-separated numeric compare: `1.10.0` > `1.9.2`. Non-numeric segments compare as strings.
    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map(String.init)
        let right = rhs.split(separator: ".").map(String.init)
        let count = max(left.count, right.count)
        for i in 0..<count {
            let l = i < left.count ? left[i] : "0"
            let r = i < right.count ? right[i] : "0"
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li < ri ? -1 : 1 }
            } else if l != r {
                return l < r ? -1 : 1
            }
        }
        return 0
    }

    private static func isSnoozed(offerId: String) -> Bool {
        let key = snoozePrefix + offerId
        let until = UserDefaults.standard.double(forKey: key)
        guard until > 0 else { return false }
        return Date().timeIntervalSince1970 < until
    }

    private static func defaultMessage(version: String) -> String {
        "มีเวอร์ชัน \(version) บน TestFlight แล้ว — อัปเดตได้เมื่อสะดวก ไม่บังคับ"
    }
}
