import Foundation
import MetricKit
import UIKit

/// File-private helpers that must stay off the MainActor — used from MetricKit callbacks
/// and `NSSetUncaughtExceptionHandler` (crash-time, synchronous, nonisolated).
private enum ErrorReportSupport {
    static let maxSummary = 220
    static let maxDetail = 12_000
    static let queueKey = "diag.offlineQueue.v1"
    static let reporterUsernameKey = "diag.reportedByUsername"
    static let reporterNameKey = "diag.reportedByName"
    static let maxQueue = 30

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func clip(_ text: String?, _ max: Int) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "\n…(ตัดข้อความ)"
    }

    /// Non-optional clip: empty input becomes `fallback`.
    static func clipOr(_ text: String, _ max: Int, fallback: String) -> String {
        clip(text, max) ?? fallback
    }

    static func deviceLine() -> String {
        let device = UIDevice.current
        return "\(device.model) · \(device.systemName) \(device.systemVersion)"
    }

    static func appVersionLine() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)+\(build)"
    }

    static func fingerprint(source: String, summary: String) -> String {
        let s = "\(source.trimmingCharacters(in: .whitespacesAndNewlines))|\(summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        return s.count <= 200 ? s : String(s.prefix(200))
    }

    static func diagnosticDetail(callStack: MXCallStackTree, meta: MXMetaData) -> String {
        var parts: [String] = []
        if let metaJSON = String(data: meta.jsonRepresentation(), encoding: .utf8) {
            parts.append("meta: \(metaJSON)")
        }
        if let stackJSON = String(data: callStack.jsonRepresentation(), encoding: .utf8) {
            parts.append("callstack: \(stackJSON)")
        }
        return parts.joined(separator: "\n\n")
    }

    static func loadQueue() -> [MobileErrorReportInsert] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? decoder.decode([MobileErrorReportInsert].self, from: data)) ?? []
    }

    static func saveQueue(_ rows: [MobileErrorReportInsert]) {
        if rows.isEmpty {
            UserDefaults.standard.removeObject(forKey: queueKey)
        } else if let data = try? encoder.encode(rows) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    static func enqueue(_ row: MobileErrorReportInsert) {
        var queue = loadQueue()
        queue.append(row)
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        saveQueue(queue)
    }

    /// Best-effort persist from the uncaught-exception handler (next launch flush).
    static func persistUncaught(_ exception: NSException) {
        let summary = clipOr(
            "\(exception.name.rawValue): \(exception.reason ?? "")",
            maxSummary,
            fallback: exception.name.rawValue
        )
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
        enqueue(row)
    }
}

/// Collects iOS crashes / hangs (via MetricKit) and runtime errors, then writes them into the
/// shared `mobile_error_reports` table (`platform = "ios"`) so they show up in the web app under
/// ตั้งค่า > รายงานจากแอป iOS. Mirrors the Android `MobileErrorReportService` + submit guard.
///
/// Fully automatic: there is no in-app UI. Reports are rate-limited/deduped, and are queued in
/// `UserDefaults` when offline / before Supabase is configured so nothing is lost.
@MainActor
final class ErrorReportCenter: NSObject {
    static let shared = ErrorReportCenter()

    private static let minInterval: TimeInterval = 45
    private static let duplicateWindow: TimeInterval = 5 * 60

    private var service: SupabaseService?
    private var configured = false

    private var lastSubmitAt: Date?
    private var lastFingerprint: String?
    private var lastDuplicateAt: Date?

    private override init() { super.init() }

    // MARK: - Setup

    func configure(service: SupabaseService) {
        self.service = service
        if !configured {
            configured = true
            MXMetricManager.shared.add(self)
            installUncaughtHandler()
        }
        flushQueue()
    }

    static func setReporter(username: String?, name: String?) {
        let d = UserDefaults.standard
        d.set(username, forKey: ErrorReportSupport.reporterUsernameKey)
        d.set(name, forKey: ErrorReportSupport.reporterNameKey)
    }

    // MARK: - Public reporting

    func reportError(_ error: Error, source: String = "error", screenPage: String? = nil) {
        let summary = ErrorReportSupport.clipOr(
            String(describing: error),
            ErrorReportSupport.maxSummary,
            fallback: "error"
        )
        let detail = ErrorReportSupport.clip(
            "\(error)\n\n\((error as NSError).userInfo)",
            ErrorReportSupport.maxDetail
        )
        submit(source: source, summary: summary, detail: detail, screenPage: screenPage)
    }

    func reportMessage(_ summary: String, detail: String? = nil, source: String = "error", screenPage: String? = nil) {
        submit(
            source: source,
            summary: ErrorReportSupport.clipOr(summary, ErrorReportSupport.maxSummary, fallback: summary),
            detail: detail.flatMap { ErrorReportSupport.clip($0, ErrorReportSupport.maxDetail) },
            screenPage: screenPage
        )
    }

    // MARK: - Core submit

    fileprivate func submit(source: String, summary: String, detail: String?, screenPage: String?) {
        let fingerprint = ErrorReportSupport.fingerprint(source: source, summary: summary)
        if isBlocked(fingerprint: fingerprint) { return }

        let d = UserDefaults.standard
        let row = MobileErrorReportInsert(
            id: "mer_ios_\(Int(Date().timeIntervalSince1970 * 1000))",
            platform: "ios",
            reportedByUsername: d.string(forKey: ErrorReportSupport.reporterUsernameKey),
            reportedByName: d.string(forKey: ErrorReportSupport.reporterNameKey),
            appVersion: ErrorReportSupport.appVersionLine(),
            deviceInfo: ErrorReportSupport.deviceLine(),
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

    private func send(_ row: MobileErrorReportInsert) {
        guard let service else {
            ErrorReportSupport.enqueue(row)
            return
        }
        Task { [weak self] in
            do {
                try await service.submitErrorReport(row)
            } catch {
                ErrorReportSupport.enqueue(row)
                _ = self
            }
        }
    }

    private func flushQueue() {
        guard let service else { return }
        let queue = ErrorReportSupport.loadQueue()
        guard !queue.isEmpty else { return }
        ErrorReportSupport.saveQueue([])
        Task {
            var failed: [MobileErrorReportInsert] = []
            for row in queue {
                do { try await service.submitErrorReport(row) }
                catch { failed.append(row) }
            }
            if !failed.isEmpty {
                ErrorReportSupport.saveQueue(failed + ErrorReportSupport.loadQueue())
            }
        }
    }

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

    private func installUncaughtHandler() {
        NSSetUncaughtExceptionHandler { exception in
            ErrorReportSupport.persistUncaught(exception)
        }
    }
}

// MARK: - MetricKit (crash + hang diagnostics)

extension ErrorReportCenter: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {}

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var reports: [(source: String, summary: String, detail: String?)] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let meta = crash.metaData
                let type = crash.exceptionType?.stringValue ?? "?"
                let code = crash.exceptionCode?.stringValue ?? "?"
                let signal = crash.signal?.stringValue ?? "?"
                let summary = ErrorReportSupport.clipOr(
                    "crash · type \(type) code \(code) signal \(signal) · \(meta.applicationBuildVersion)",
                    ErrorReportSupport.maxSummary,
                    fallback: "crash"
                )
                let detail = ErrorReportSupport.clip(
                    ErrorReportSupport.diagnosticDetail(callStack: crash.callStackTree, meta: meta),
                    ErrorReportSupport.maxDetail
                )
                reports.append(("crash", summary, detail))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let meta = hang.metaData
                let duration = hang.hangDuration.value
                let summary = ErrorReportSupport.clipOr(
                    "hang · \(String(format: "%.1f", duration))s · \(meta.applicationBuildVersion)",
                    ErrorReportSupport.maxSummary,
                    fallback: "hang"
                )
                let detail = ErrorReportSupport.clip(
                    ErrorReportSupport.diagnosticDetail(callStack: hang.callStackTree, meta: meta),
                    ErrorReportSupport.maxDetail
                )
                reports.append(("hang", summary, detail))
            }
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor [reports] in
            for r in reports {
                ErrorReportCenter.shared.submit(
                    source: r.source,
                    summary: r.summary,
                    detail: r.detail,
                    screenPage: nil
                )
            }
        }
    }
}
