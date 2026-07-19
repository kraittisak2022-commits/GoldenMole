import Foundation
import Supabase

/// Keeps `AppState.transactions` in sync using Supabase Realtime (WebSocket) for instant
/// incremental updates, with a delta poll fallback and a periodic full reconcile.
///
/// - Realtime INSERT/UPDATE -> upsert the single row (no full refetch)
/// - Realtime DELETE -> remove by id
/// - Fallback loop (every 30s): delta poll (`updated_at` > lastSync); every 5th cycle a full
///   reconcile so deletes missed while disconnected are corrected.
@MainActor
final class RealtimeSyncCoordinator {
    private let service: SupabaseService
    private weak var appState: AppState?

    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var fallbackTask: Task<Void, Never>?

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private struct IdOnly: Decodable { let id: String }

    init(service: SupabaseService, appState: AppState) {
        self.service = service
        self.appState = appState
    }

    func start() {
        stop()

        // Initial load / reconcile.
        Task { await appState?.refresh() }

        let channel = service.realtimeChannel("realtime:public:transactions")
        self.channel = channel

        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "transactions")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "transactions")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "transactions")

        streamTasks.append(Task { [weak self] in
            for await action in inserts { await self?.handleUpsert(action.record) }
        })
        streamTasks.append(Task { [weak self] in
            for await action in updates { await self?.handleUpsert(action.record) }
        })
        streamTasks.append(Task { [weak self] in
            for await action in deletes { await self?.handleDelete(action.oldRecord) }
        })

        Task { await channel.subscribe() }
        startFallback()
    }

    func stop() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        fallbackTask?.cancel()
        fallbackTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    // MARK: - Realtime event handlers

    private func handleUpsert(_ record: JSONObject) async {
        guard let tx = Self.decodeTransaction(record) else {
            await appState?.refresh()
            return
        }
        appState?.upsertTransaction(tx)
    }

    private func handleDelete(_ oldRecord: JSONObject) async {
        guard let data = try? Self.encoder.encode(oldRecord),
              let idOnly = try? Self.decoder.decode(IdOnly.self, from: data) else {
            await appState?.refresh()
            return
        }
        appState?.removeTransaction(id: idOnly.id)
    }

    private static func decodeTransaction(_ record: JSONObject) -> Transaction? {
        guard let data = try? encoder.encode(record) else { return nil }
        return SupabaseService.decodeSingleTransaction(from: data)
    }

    // MARK: - Fallback

    private func startFallback() {
        fallbackTask = Task { [weak self] in
            var cycles = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                if Task.isCancelled { break }
                guard let self else { break }
                cycles += 1
                if cycles % 5 == 0 {
                    await self.appState?.refresh()
                } else {
                    await self.deltaPoll()
                }
            }
        }
    }

    private func deltaPoll() async {
        guard let appState else { return }
        guard let since = appState.maxTransactionUpdatedAt, !since.isEmpty else {
            await appState.refresh()
            return
        }
        do {
            let result = try await service.fetchTransactionsSince(since)
            for tx in result.transactions { appState.upsertTransaction(tx) }
        } catch {
            // Ignore transient errors; the next cycle retries.
        }
    }
}
