import Foundation

/// Disk cache for AppState read models (transactions / employees / settings).
/// Stored under Application Support — not UserDefaults (transactions can be large).
enum LocalDataCache {
    static let transactionsFreshTTL: TimeInterval = 2 * 60
    static let rosterTTL: TimeInterval = 25 * 60
    /// How often an ID-index reconcile is required on foreground / cold paths.
    static let reconcileTTL: TimeInterval = 10 * 60

    struct Meta: Codable, Sendable, Equatable {
        var savedAt: Date
        var transactionCount: Int
        var employeeCount: Int
        var maxUpdatedAt: String?
        var transactionsSavedAt: Date
        var employeesSavedAt: Date
        var settingsSavedAt: Date
        var lastReconcileAt: Date?
    }

    struct Snapshot: Sendable {
        var transactions: [Transaction]
        var employees: [Employee]
        var settings: AppSettings
        var meta: Meta
    }

    private static let folderName = "GoldenmoleCache"
    private static let transactionsFile = "transactions_v1.json"
    private static let employeesFile = "employees_v1.json"
    private static let settingsFile = "settings_v1.json"
    private static let metaFile = "meta_v1.json"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Paths

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func fileURL(_ name: String) -> URL {
        directoryURL.appendingPathComponent(name)
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Load / Save

    static func loadSnapshot() async -> Snapshot? {
        await Task.detached(priority: .utility) {
            loadSnapshotSync()
        }.value
    }

    @discardableResult
    static func saveSnapshot(
        transactions: [Transaction],
        employees: [Employee],
        settings: AppSettings,
        preservingReconcileAt: Date? = nil
    ) async -> Meta {
        let now = Date()
        let meta = Meta(
            savedAt: now,
            transactionCount: transactions.count,
            employeeCount: employees.count,
            maxUpdatedAt: transactions.compactMap(\.updatedAt).max(),
            transactionsSavedAt: now,
            employeesSavedAt: now,
            settingsSavedAt: now,
            lastReconcileAt: preservingReconcileAt
        )
        let snap = Snapshot(
            transactions: transactions,
            employees: employees,
            settings: settings,
            meta: meta
        )
        await Task.detached(priority: .utility) {
            saveSnapshotSync(snap)
        }.value
        return meta
    }

    /// Partial write helpers keep timestamps independent when only one source refreshed.
    @discardableResult
    static func saveTransactions(
        _ transactions: [Transaction],
        preserving metaBase: Meta?,
        lastReconcileAt: Date? = nil
    ) async -> Meta {
        let now = Date()
        let prior = metaBase
        let meta = Meta(
            savedAt: now,
            transactionCount: transactions.count,
            employeeCount: prior?.employeeCount ?? 0,
            maxUpdatedAt: transactions.compactMap(\.updatedAt).max(),
            transactionsSavedAt: now,
            employeesSavedAt: prior?.employeesSavedAt ?? now,
            settingsSavedAt: prior?.settingsSavedAt ?? now,
            lastReconcileAt: lastReconcileAt ?? prior?.lastReconcileAt
        )
        await Task.detached(priority: .utility) {
            do {
                try ensureDirectory()
                try atomicWrite(encode(transactions), to: fileURL(transactionsFile))
                try atomicWrite(encode(meta), to: fileURL(metaFile))
            } catch {
                // Best-effort cache; ignore disk errors.
            }
        }.value
        return meta
    }

    @discardableResult
    static func saveEmployees(_ employees: [Employee], preserving metaBase: Meta?) async -> Meta {
        let now = Date()
        let prior = metaBase
        let meta = Meta(
            savedAt: now,
            transactionCount: prior?.transactionCount ?? 0,
            employeeCount: employees.count,
            maxUpdatedAt: prior?.maxUpdatedAt,
            transactionsSavedAt: prior?.transactionsSavedAt ?? now,
            employeesSavedAt: now,
            settingsSavedAt: prior?.settingsSavedAt ?? now,
            lastReconcileAt: prior?.lastReconcileAt
        )
        await Task.detached(priority: .utility) {
            do {
                try ensureDirectory()
                try atomicWrite(encode(employees), to: fileURL(employeesFile))
                try atomicWrite(encode(meta), to: fileURL(metaFile))
            } catch {}
        }.value
        return meta
    }

    @discardableResult
    static func saveSettings(_ settings: AppSettings, preserving metaBase: Meta?) async -> Meta {
        let now = Date()
        let prior = metaBase
        let meta = Meta(
            savedAt: now,
            transactionCount: prior?.transactionCount ?? 0,
            employeeCount: prior?.employeeCount ?? 0,
            maxUpdatedAt: prior?.maxUpdatedAt,
            transactionsSavedAt: prior?.transactionsSavedAt ?? now,
            employeesSavedAt: prior?.employeesSavedAt ?? now,
            settingsSavedAt: now,
            lastReconcileAt: prior?.lastReconcileAt
        )
        await Task.detached(priority: .utility) {
            do {
                try ensureDirectory()
                try atomicWrite(encode(settings), to: fileURL(settingsFile))
                try atomicWrite(encode(meta), to: fileURL(metaFile))
            } catch {}
        }.value
        return meta
    }

    static func invalidate() {
        let dir = directoryURL
        try? FileManager.default.removeItem(at: dir)
    }

    static func isWithinTTL(_ date: Date?, ttl: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= ttl
    }

    // MARK: - Sync IO

    private static func loadSnapshotSync() -> Snapshot? {
        let metaURL = fileURL(metaFile)
        let txURL = fileURL(transactionsFile)
        let empURL = fileURL(employeesFile)
        let setURL = fileURL(settingsFile)

        guard FileManager.default.fileExists(atPath: metaURL.path) else { return nil }

        do {
            let meta = try decoder.decode(Meta.self, from: Data(contentsOf: metaURL))
            let transactions: [Transaction]
            if FileManager.default.fileExists(atPath: txURL.path) {
                transactions = try decoder.decode([Transaction].self, from: Data(contentsOf: txURL))
            } else {
                transactions = []
            }
            let employees: [Employee]
            if FileManager.default.fileExists(atPath: empURL.path) {
                employees = try decoder.decode([Employee].self, from: Data(contentsOf: empURL))
            } else {
                employees = []
            }
            let settings: AppSettings
            if FileManager.default.fileExists(atPath: setURL.path) {
                settings = try decoder.decode(AppSettings.self, from: Data(contentsOf: setURL))
            } else {
                settings = .fallback
            }
            return Snapshot(
                transactions: transactions,
                employees: employees,
                settings: settings,
                meta: meta
            )
        } catch {
            // Corrupt cache — wipe and force network reload next.
            try? FileManager.default.removeItem(at: directoryURL)
            return nil
        }
    }

    private static func saveSnapshotSync(_ snap: Snapshot) {
        do {
            try ensureDirectory()
            try atomicWrite(encode(snap.transactions), to: fileURL(transactionsFile))
            try atomicWrite(encode(snap.employees), to: fileURL(employeesFile))
            try atomicWrite(encode(snap.settings), to: fileURL(settingsFile))
            try atomicWrite(encode(snap.meta), to: fileURL(metaFile))
        } catch {
            // Best-effort.
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}
