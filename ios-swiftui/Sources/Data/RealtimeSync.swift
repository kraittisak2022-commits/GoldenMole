import Foundation
import Supabase

private struct RealtimeIdOnly: Decodable, Sendable {
    let id: String
}

/// Keeps `AppState.transactions` in sync using Supabase Realtime (WebSocket) for instant
/// incremental updates, with a delta poll fallback and a periodic ID-index reconcile.
///
/// - Realtime INSERT/UPDATE -> upsert the single row (no full refetch)
/// - Realtime DELETE -> remove by id
/// - Fallback loop (every 30s): delta poll (`updated_at` > lastSync); every 5th cycle an
///   ID-index reconcile so deletes missed while disconnected are corrected.
@MainActor
final class RealtimeSyncCoordinator {
    private let service: SupabaseService
    private weak var appState: AppState?

    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var fallbackTask: Task<Void, Never>?

    private static let encoder = JSONEncoder()

    init(service: SupabaseService, appState: AppState) {
        self.service = service
        self.appState = appState
    }

    func start() {
        stop()

        // Hydrate disk cache immediately so UI has data before network.
        // Network refresh is owned by AppState.loadInitial / DashboardShell (avoids double full fetch).
        Task {
            await appState?.hydrateFromCacheIfNeeded()
        }

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

        Task {
            do {
                try await channel.subscribeWithError()
            } catch {
                // Fallback poll loop still covers missed realtime events.
            }
        }
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
        // Encode on main (cheap); decode Transaction off-main so bursts don't hitch the UI.
        guard let data = try? Self.encoder.encode(record) else {
            await appState?.refresh()
            return
        }
        let tx = await Task.detached(priority: .userInitiated) {
            SupabaseService.decodeSingleTransaction(from: data)
        }.value
        guard let tx else {
            await appState?.refresh()
            return
        }
        appState?.upsertTransaction(tx)
    }

    private func handleDelete(_ oldRecord: JSONObject) async {
        guard let data = try? Self.encoder.encode(oldRecord) else {
            await appState?.refresh()
            return
        }
        let id = await Task.detached(priority: .userInitiated) {
            (try? JSONDecoder().decode(RealtimeIdOnly.self, from: data))?.id
        }.value
        guard let id else {
            await appState?.refresh()
            return
        }
        appState?.removeTransaction(id: id)
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
                // Every ~2.5 minutes: lightweight id/updated_at reconcile (detects remote deletes).
                if cycles % 5 == 0 {
                    await self.appState?.reconcileTransactionsWithIndex()
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
            if !result.transactions.isEmpty {
                appState.applyTransactionDelta(result.transactions)
            }
        } catch {
            // Ignore transient errors; the next cycle retries.
        }
    }
}
