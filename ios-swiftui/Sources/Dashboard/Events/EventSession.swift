import Foundation
import Observation

struct EventDraft: Equatable, Sendable {
    var txId: String?
    var kind: EventLogic.EventKind = .info
    var priority: EventLogic.Priority = .normal
    var description: String = ""

    var isPersisted: Bool {
        !(txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func fromTransaction(_ t: Transaction) -> EventDraft {
        EventDraft(
            txId: t.id,
            kind: EventLogic.EventKind.from(raw: t.eventType),
            priority: EventLogic.Priority.from(raw: t.eventPriority),
            description: EventLogic.stripRecorder(t.description)
        )
    }
}

enum EventSaveError: LocalizedError {
    case emptyDescription

    var errorDescription: String? {
        switch self {
        case .emptyDescription: return "กรุณาระบุรายละเอียดเหตุการณ์"
        }
    }
}

@MainActor
@Observable
final class EventSession {
    var draft = EventDraft()
    var todayEvents: [Transaction] = []
    var suggestions: [String] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var confirmDeleteId: String?

    private(set) var dayKey: String
    private var skipExternalReload = 0

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(appState: AppState, force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        todayEvents = EventLogic.dayEvents(dayKey: dayKey, transactions: appState.transactions)
        suggestions = EventLogic.suggestions(from: appState.transactions)
    }

    func clearDraft() {
        draft = EventDraft()
        clearStatus()
    }

    func loadForEdit(_ t: Transaction) {
        draft = EventDraft.fromTransaction(t)
        statusMessage = "โหลดเหตุการณ์มาแก้ไข"
        isErrorStatus = false
    }

    func appendQuickPhrase(_ phrase: String) {
        let prev = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = prev.isEmpty ? phrase : "\(prev), \(phrase)"
        clearStatus()
    }

    func applySuggestion(_ text: String) {
        draft.description = text
        clearStatus()
    }

    func save(appState: AppState) async {
        guard !isSaving else { return }
        let text = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setError(EventSaveError.emptyDescription.localizedDescription)
            return
        }

        isSaving = true
        defer { isSaving = false }

        let existing = (draft.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = existing.isEmpty ? EventWriter.newId() : existing
        let payload = EventWriter.payload(
            id: id,
            dateYmd: dayKey,
            description: text,
            eventType: draft.kind,
            priority: draft.priority,
            omitCreatedAt: !existing.isEmpty
        )

        skipExternalReload += 1
        _ = await EventWriter.persist(payload: payload, wasPersisted: !existing.isEmpty)
        clearDraft()
        setOk(existing.isEmpty ? "บันทึกเหตุการณ์สำเร็จ" : "บันทึกการแก้ไขแล้ว")
        reload(appState: appState, force: true)
    }

    func delete(id: String, appState: AppState) async {
        skipExternalReload += 1
        _ = await EventWriter.delete(id: id)
        if draft.txId == id { clearDraft() }
        setOk("ลบเหตุการณ์แล้ว")
        reload(appState: appState, force: true)
    }

    private func setOk(_ message: String) {
        statusMessage = message
        isErrorStatus = false
    }

    private func setError(_ message: String) {
        statusMessage = message
        isErrorStatus = true
    }

    private func clearStatus() {
        statusMessage = nil
        isErrorStatus = false
    }
}
