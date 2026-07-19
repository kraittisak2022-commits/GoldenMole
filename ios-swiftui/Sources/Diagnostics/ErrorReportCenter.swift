import Foundation
import MetricKit
import UIKit

/// Collects iOS crashes / hangs (via MetricKit) and runtime errors, then writes them into the
/// shared `mobile_error_reports` table (`platform = "ios"`) so they show up in the web app under
/// ตั้งค่า > รายงานจากแอป iOS. Mirrors the Android `MobileErrorReportService` + submit guard.
///
/// Fully automatic: there is no in-app UI. Reports are rate-limited/deduped, and are queued in
/// `UserDefaults` when offline / before Supabase is configured so nothing is lost.
@MainActor
final class ErrorReportCenter: NSObject {
    static let shared = ErrorReportCenter()

    // MARK: Tuning (mirrors Android guard)
    private static let maxSummary = 220
    private static let maxDetail = 12_000
    private static let minInterval: TimeInterval = 45          // seconds between any two sends
    private static let duplicateWindow: TimeInterval = 5 * 60  // same fingerprint suppressed for 5 min
    private static let queueKey = "diag.offlineQueue.v1"
    private static let reporterUsernameKey = "diag.reportedByUsername"
    private static let reporterNameKey = "diag.reportedByName"
    private static let maxQueue = 30

    private var service: SupabaseService?
    private var configured = false

    // Rate-limit / dedup state
    private var lastSubmitAt: Date?
    private var lastFingerprint: String?
    private var lastDuplicateAt: Date?

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private override init() { super.init() }

    // MARK: - Setup

    /// Call once, as early as possible after the Supabase client exists.
    func configure(service: SupabaseService) {
        self.service = service
        if !configured {
            configured = true
            MXMetricManager.shared.add(self)
            installUncaughtHandler()
        }
        flushQueue()
    }

    /// Remember who is signed in so crashes that happen before the next login are still attributed.
    static func setReporter(username: String?, name: String?) {
        let d = UserDefaults.standard
        d.set(username, forKey: reporterUsernameKey)
        d.set(name, forKey: reporterNameKey)
    }

    // MARK: - Public reporting

    /// Report a runtime error caught by the app (data load / login / etc.).
    func reportError(_ error: Error, source: String = "error", screenPage: String? = nil) {
        let summary = Self.clip(String(describing: error), Self.maxSummary)
        let detail = Self.clip("\(error)\n\n\((error as NSError).userInfo)", Self.maxDetail)
        submit(source: source, summary: summary, detail: detail, screenPage: screenPage)
    }

    /// Report a described problem (e.g. failed critical fetch) with an explicit summary.
    func reportMessage(_ summary: String, detail: String? = nil, source: String = "error", screenPage: String? = nil) {
        submit(source: source,
               summary: Self.clip(summary, Self.maxSummary),
               detail: detail.map { Self.clip($0, Self.maxDetail) },
               screenPage: screenPage)
    }

    // MARK: - Core submit

    private func submit(source: String, summary: String, detail: String?, screenPage: String?) {
        let fingerprint = Self.fingerprint(source: source, summary: summary)
        if isBlocked(fingerprint: fingerprint) { return }

        let d = UserDefaults.standard
        let row = MobileErrorReportInsert(
            id: "mer_ios_\(Int(Date().timeIntervalSince1970 * 1000))",
            platform: "ios",
            reportedByUsername: d.string(forKey: Self.reporterUsernameKey),
            reportedByName: d.string(forKey: Self.reporterNameKey),
            appVersion: Self.appVersionLine(),
            deviceInfo: Self.deviceLine(),
            errorSummary: summary,
            errorDetail: detail,
            userNote: nil,
            source: source,
            screenPage: screenPage,
            screenPageId: nil,
            screenStepId: nil,
            screenAction: nil,
            screenButton: nil,
            errorField: nil,
            reviewed: false
        )

        recordSuccess(fingerprint: fingerprint)
        send(row)
    }

    /// Try to send now; on failure (or when not configured) enqueue for the next launch.
    private func send(_ row: MobileErrorReportInsert) {
        guard let service else { enqueue(row); return }
        Task { [weak self] in
            do {
                try await service.submitErrorReport(row)
            } catch {
                self?.enqueue(row)
            }
        }
    }

    // MARK: - Offline queue

    private func enqueue(_ row: MobileErrorReportInsert) {
        var queue = loadQueue()
        queue.append(row)
        if queue.count > Self.maxQueue { queue.removeFirst(queue.count - Self.maxQueue) }
        saveQueue(queue)
    }

    private func flushQueue() {
        guard let service else { return }
        let queue = loadQueue()
        guard !queue.isEmpty else { return }
        saveQueue([])
        Task { [weak self] in
            var failed: [MobileErrorReportInsert] = []
            for row in queue {
                do { try await service.submitErrorReport(row) }
                catch { failed.append(row) }
            }
            guard let self, !failed.isEmpty else { return }
            // Re-queue failures ahead of anything that accumulated while we were sending.
            self.saveQueue(failed + self.loadQueue())
        }
    }

    private func loadQueue() -> [MobileErrorReportInsert] {
        guard let data = UserDefaults.standard.data(forKey: Self.queueKey) else { return [] }
        return (try? Self.decoder.decode([MobileErrorReportInsert].self, from: data)) ?? []
    }

    private func saveQueue(_ rows: [MobileErrorReportInsert]) {
        if rows.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.queueKey)
        } else if let data = try? Self.encoder.encode(rows) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }

    // MARK: - Rate limit / dedup

    private func isBlocked(fingerprint: String) -> Bool {
        let now = Date()
        if lastFingerprint == fingerprint,
           let dup = lastDuplicateAt,
           now.timeIntervalSince(dup) < Self.duplicateWindow {
            return true
        }
        if let last = lastSubmitAt, now.timeIntervalSince(last) < Self.minInterval {
            return true
        }
        return false
    }

    private func recordSuccess(fingerprint: String) {
        let now = Date()
        lastSubmitAt = now
        lastFingerprint = fingerprint
        lastDuplicateAt = now
    }

    private static func fingerprint(source: String, summary: String) -> String {
        let s = "\(source.trimmingCharacters(in: .whitespacesAndNewlines))|\(summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return s.count <= 200 ? s : String(s.prefix(200))
    }

    // MARK: - Device / version / clipping

    private static func deviceLine() -> String {
        let device = UIDevice.current
        return "\(device.model) · \(device.systemName) \(device.systemVersion)"
    }

    private static func appVersionLine() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)+\(build)"
    }

    static func clip(_ text: String?, _ max: Int) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "\n…(ตัดข้อความ)"
    }

    // MARK: - Uncaught exceptions (best-effort, delivered next launch)

    private func installUncaughtHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // Runs in a crashing context: only touch UserDefaults synchronously, no async work.
            ErrorReportCenter.persistUncaught(exception)
        }
    }

    /// Static, self-contained persistence so it is safe to call from the crash handler.
    private nonisolated static func persistUncaught(_ exception: NSException) {
        let summary = clip("\(exception.name.rawValue): \(exception.reason ?? "")", maxSummary) ?? exception.name.rawValue
        let detail = clip(exception.callStackSymbols.joined(separator: "\n"), maxDetail)
        let d = UserDefaults.standard
        let row = MobileErrorReportInsert(
            id: "mer_ios_\(Int(Date().timeIntervalSince1970 * 1000))",
            platform: "ios",
            reportedByUsername: d.string(forKey: reporterUsernameKey),
            reportedByName: d.string(forKey: reporterNameKey),
            appVersion: appVersionLine(),
            deviceInfo: deviceLine(),
            errorSummary: summary,
            errorDetail: detail,
            userNote: nil,
            source: "crash",
            screenPage: nil,
            screenPageId: nil,
            screenStepId: nil,
            screenAction: nil,
            screenButton: nil,
            errorField: nil,
            reviewed: false
        )
        var queue = (UserDefaults.standard.data(forKey: queueKey)
            .flatMap { try? decoder.decode([MobileErrorReportInsert].self, from: $0) }) ?? []
        queue.append(row)
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        if let data = try? encoder.encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
}

// MARK: - MetricKit (crash + hang diagnostics)

extension ErrorReportCenter: MXMetricManagerSubscriber {
    // Required by the protocol; we only use diagnostics.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var reports: [(source: String, summary: String, detail: String?)] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let meta = crash.metaData
                let type = crash.exceptionType?.stringValue ?? "?"
                let code = crash.exceptionCode?.stringValue ?? "?"
                let signal = crash.signal?.stringValue ?? "?"
                let summary = Self.clip("crash · type \(type) code \(code) signal \(signal) · \(meta.applicationBuildVersion)", Self.maxSummary)
                    ?? "crash"
                let detail = Self.clip(Self.diagnosticDetail(callStack: crash.callStackTree, meta: meta), Self.maxDetail)
                reports.append(("crash", summary, detail))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let meta = hang.metaData
                let duration = hang.hangDuration.value
                let summary = Self.clip("hang · \(String(format: "%.1f", duration))s · \(meta.applicationBuildVersion)", Self.maxSummary)
                    ?? "hang"
                let detail = Self.clip(Self.diagnosticDetail(callStack: hang.callStackTree, meta: meta), Self.maxDetail)
                reports.append(("hang", summary, detail))
            }
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor [reports] in
            for r in reports {
                ErrorReportCenter.shared.submit(source: r.source, summary: r.summary, detail: r.detail, screenPage: nil)
            }
        }
    }

    private nonisolated static func diagnosticDetail(callStack: MXCallStackTree, meta: MXMetaData) -> String {
        var parts: [String] = []
        if let metaJSON = String(data: meta.jsonRepresentation(), encoding: .utf8) {
            parts.append("meta: \(metaJSON)")
        }
        if let stackJSON = String(data: callStack.jsonRepresentation(), encoding: .utf8) {
            parts.append("callstack: \(stackJSON)")
        }
        return parts.joined(separator: "\n\n")
    }
}
