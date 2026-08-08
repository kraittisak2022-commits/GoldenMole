import Foundation
import Network
import Observation

/// Offline upsert/delete queue for count-record (Flutter parity, simplified).
@MainActor
@Observable
final class CountRecordOfflineSync {
    static let shared = CountRecordOfflineSync()

    private static let queueKey = "ios_count_record_offline_queue_v1"
    private static let failedKey = "ios_count_record_failed_queue_v1"

    var pendingCount = 0
    var failedCount = 0
    var isSyncing = false
    var isOnline = true

    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    @ObservationIgnored private var service: SupabaseService?
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var backoffSeconds: UInt64 = 2

    private init() {
        refreshCounts()
    }

    func configure(service: SupabaseService, appState: AppState) {
        self.service = service
        self.appState = appState
        startPathMonitor()
        scheduleCycle(immediate: true)
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    /// Returns true when queued offline (not uploaded yet).
    @discardableResult
    func persist(payload: TransactionWritePayload, wasPersisted: Bool) async -> Bool {
        if let local = Transaction.localFromPayload(payload) {
            appState?.upsertTransaction(local)
        }

        if isOnline, let service {
            do {
                let toSend = wasPersisted ? payload.withoutCreatedAt() : payload
                let saved = try await service.upsertTransaction(toSend)
                appState?.upsertTransaction(saved)
                removeQueued(for: payload.id)
                refreshCounts()
                return false
            } catch {
                // queue below
            }
        }

        enqueue(.upsert(payload: wasPersisted ? payload.withoutCreatedAt() : payload, omitCreatedAt: wasPersisted))
        scheduleCycle(immediate: true)
        return true
    }

    @discardableResult
    func delete(id: String) async -> Bool {
        appState?.removeTransaction(id: id)

        if isOnline, let service {
            do {
                try await service.deleteTransaction(id: id)
                removeQueued(for: id)
                refreshCounts()
                return false
            } catch {
                // queue below
            }
        }

        enqueue(.delete(id: id))
        scheduleCycle(immediate: true)
        return true
    }

    func syncNow() {
        scheduleCycle(immediate: true)
    }

    func retryFailed() {
        var failed = loadFailed()
        var queue = loadQueue()
        for op in failed {
            queue.removeAll { $0.transactionId == op.transactionId }
            queue.append(op)
        }
        saveFailed([])
        saveQueue(queue)
        refreshCounts()
        scheduleCycle(immediate: true)
    }

    func discardFailed() {
        saveFailed([])
        refreshCounts()
    }

    enum PendingOp: Codable, Equatable {
        case upsert(payload: TransactionWritePayload, omitCreatedAt: Bool)
        case delete(id: String)

        var transactionId: String {
            switch self {
            case .upsert(let payload, _): return payload.id
            case .delete(let id): return id
            }
        }

        private enum Kind: String, Codable { case upsert, delete }
        private enum CodingKeys: String, CodingKey {
            case kind, payload, omitCreatedAt, id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(Kind.self, forKey: .kind) {
            case .upsert:
                self = .upsert(
                    payload: try c.decode(TransactionWritePayload.self, forKey: .payload),
                    omitCreatedAt: try c.decode(Bool.self, forKey: .omitCreatedAt)
                )
            case .delete:
                self = .delete(id: try c.decode(String.self, forKey: .id))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .upsert(let payload, let omit):
                try c.encode(Kind.upsert, forKey: .kind)
                try c.encode(payload, forKey: .payload)
                try c.encode(omit, forKey: .omitCreatedAt)
            case .delete(let id):
                try c.encode(Kind.delete, forKey: .kind)
                try c.encode(id, forKey: .id)
            }
        }
    }

    private func startPathMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    self.scheduleCycle(immediate: true)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "countrecord.path"))
    }

    private func scheduleCycle(immediate: Bool) {
        schedulerTask?.cancel()
        let delay = immediate ? UInt64(0) : backoffSeconds
        schedulerTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.runCycle()
        }
    }

    private func runCycle() async {
        guard let service, isOnline, !isSyncing else { return }
        var queue = loadQueue()
        guard !queue.isEmpty else {
            backoffSeconds = 2
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        var stillPending: [PendingOp] = []
        var newlyFailed: [PendingOp] = []
        var uploaded = 0

        for op in queue {
            guard !Task.isCancelled else {
                stillPending.append(op)
                continue
            }
            do {
                switch op {
                case .upsert(let payload, let omit):
                    let toSend = omit ? payload.withoutCreatedAt() : payload
                    let saved = try await service.upsertTransaction(toSend)
                    appState?.upsertTransaction(saved)
                    uploaded += 1
                case .delete(let id):
                    try await service.deleteTransaction(id: id)
                    appState?.removeTransaction(id: id)
                    uploaded += 1
                }
            } catch {
                newlyFailed.append(op)
            }
        }

        // Keep unprocessed (cancelled mid-loop) + leave failed in failed list
        saveQueue(stillPending)
        if !newlyFailed.isEmpty {
            var failed = loadFailed()
            for op in newlyFailed {
                if let i = failed.firstIndex(where: { $0.transactionId == op.transactionId }) {
                    failed[i] = op
                } else {
                    failed.append(op)
                }
            }
            saveFailed(failed)
        }

        refreshCounts()
        if uploaded > 0 {
            backoffSeconds = 2
        }
        if pendingCount > 0 || (!newlyFailed.isEmpty && isOnline) {
            if uploaded == 0 && !newlyFailed.isEmpty {
                backoffSeconds = min(30, max(2, backoffSeconds * 2))
            }
            scheduleCycle(immediate: false)
        }
    }

    private func enqueue(_ op: PendingOp) {
        var queue = loadQueue()
        queue.removeAll { $0.transactionId == op.transactionId }
        queue.append(op)
        var failed = loadFailed()
        failed.removeAll { $0.transactionId == op.transactionId }
        saveFailed(failed)
        saveQueue(queue)
        refreshCounts()
    }

    private func removeQueued(for id: String) {
        var queue = loadQueue()
        queue.removeAll { $0.transactionId == id }
        saveQueue(queue)
        var failed = loadFailed()
        failed.removeAll { $0.transactionId == id }
        saveFailed(failed)
    }

    private func refreshCounts() {
        pendingCount = loadQueue().count
        failedCount = loadFailed().count
    }

    private func loadQueue() -> [PendingOp] {
        guard let data = UserDefaults.standard.data(forKey: Self.queueKey),
              let ops = try? JSONDecoder().decode([PendingOp].self, from: data)
        else { return [] }
        return ops
    }

    private func saveQueue(_ ops: [PendingOp]) {
        if let data = try? JSONEncoder().encode(ops) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }

    private func loadFailed() -> [PendingOp] {
        guard let data = UserDefaults.standard.data(forKey: Self.failedKey),
              let ops = try? JSONDecoder().decode([PendingOp].self, from: data)
        else { return [] }
        return ops
    }

    private func saveFailed(_ ops: [PendingOp]) {
        if let data = try? JSONEncoder().encode(ops) {
            UserDefaults.standard.set(data, forKey: Self.failedKey)
        }
    }
}

extension TransactionWritePayload {
    func withoutCreatedAt() -> TransactionWritePayload {
        var copy = self
        copy.createdAt = nil
        return copy
    }
}
