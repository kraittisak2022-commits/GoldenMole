import SwiftUI

/// Create or edit one or more tasks. Reminder time defaults to midday on the chosen due date;
/// deadline defaults to 17:00 on that same day when enabled.
struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let admins: [AdminUser]
    let onSave: ([WorkTask]) -> Void
    var onDelete: ((WorkTask) -> Void)?

    private let original: WorkTask
    private let isNew: Bool

    @State private var title: String
    @State private var note: String
    @State private var scope: TaskScope
    @State private var dueDate: Date
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var visibility: TaskVisibility
    @State private var assigneeId: String
    @State private var isFocus: Bool
    @State private var remindEnabled: Bool
    @State private var remindDate: Date
    @State private var deadlineEnabled: Bool
    @State private var deadlineDate: Date
    @State private var showDeleteConfirm = false

    init(
        task: WorkTask,
        isNew: Bool,
        admins: [AdminUser],
        onSave: @escaping ([WorkTask]) -> Void,
        onDelete: ((WorkTask) -> Void)? = nil
    ) {
        self.original = task
        self.isNew = isNew
        self.admins = admins
        self.onSave = onSave
        self.onDelete = onDelete

        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _scope = State(initialValue: task.scope)
        _dueDate = State(initialValue: TaskDates.middayOf(task.dueDate))
        _priority = State(initialValue: task.priority)
        _status = State(initialValue: task.status)
        _visibility = State(initialValue: task.visibility)
        _assigneeId = State(initialValue: task.assigneeAdminId ?? "")
        _isFocus = State(initialValue: task.isFocus)
        _remindEnabled = State(initialValue: task.remindDate != nil)
        _remindDate = State(initialValue: task.remindDate ?? TaskDates.middayOf(task.dueDate))
        _deadlineEnabled = State(initialValue: task.deadlineDate != nil)
        _deadlineDate = State(initialValue: task.deadlineDate ?? TaskDates.eveningOf(task.dueDate))
    }

    /// Non-empty title lines when creating; a single trimmed title when editing.
    private var titleLines: [String] {
        if isNew {
            return title
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private var canSave: Bool { !titleLines.isEmpty }

    private var deadlineBeforeStart: Bool {
        guard deadlineEnabled else { return false }
        let startDay = DashboardAggregations.formatYMD(dueDate)
        let deadlineDay = DashboardAggregations.formatYMD(deadlineDate)
        return deadlineDay < startDay
    }

    private var saveButtonTitle: String {
        if isNew, titleLines.count > 1 {
            return "บันทึก \(titleLines.count) งาน"
        }
        return "บันทึก"
    }

    var body: some View {
        NavigationStack {
            Form {
                detailSection
                scheduleSection
                classificationSection
                sharingSection
                if !isNew, onDelete != nil {
                    deleteSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "งานใหม่" : "แก้ไขงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) { submit() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "ลบงานนี้?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("ลบงาน", role: .destructive) {
                    onDelete?(original)
                    dismiss()
                }
                Button("ยกเลิก", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var detailSection: some View {
        Section("รายละเอียด") {
            if isNew {
                TextField("สิ่งที่ต้องทำ (ขึ้นบรรทัดใหม่ = อีก 1 งาน)", text: $title, axis: .vertical)
                    .lineLimit(3...10)
                    .font(.body.weight(.medium))
                if titleLines.count > 1 {
                    Text("จะสร้าง \(titleLines.count) งาน")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.brand.opacity(0.12)))
                }
            } else {
                TextField("สิ่งที่ต้องทำ", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body.weight(.medium))
            }
            TextField("โน้ตเพิ่มเติม (ไม่บังคับ)", text: $note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var scheduleSection: some View {
        Section("ช่วงเวลา") {
            Picker("ขอบเขต", selection: $scope) {
                ForEach(TaskScope.allCases) { item in
                    Label(item.label, systemImage: item.systemImage).tag(item)
                }
            }
            DatePicker("วันที่เริ่ม", selection: $dueDate, displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "th_TH"))

            Toggle("กำหนดเดดไลน์", isOn: $deadlineEnabled.animation(.snappy(duration: 0.2)))
                .tint(AppTheme.brand)
            if deadlineEnabled {
                DatePicker(
                    "เดดไลน์",
                    selection: $deadlineDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.locale, Locale(identifier: "th_TH"))
                if deadlineBeforeStart {
                    Text("เดดไลน์อยู่ก่อนวันที่เริ่ม — ปรับให้อยู่วันเดียวกันหรือหลังจากนั้น")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.expense)
                }
            }

            Toggle("ตั้งเตือนความจำ", isOn: $remindEnabled.animation(.snappy(duration: 0.2)))
                .tint(AppTheme.brand)
            if remindEnabled {
                DatePicker(
                    "เตือนเมื่อ",
                    selection: $remindDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.locale, Locale(identifier: "th_TH"))
                Text("การเตือนทำงานบนเครื่องนี้เท่านั้น")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private var classificationSection: some View {
        Section("ความสำคัญและสถานะ") {
            Picker("ความสำคัญ", selection: $priority) {
                ForEach(TaskPriority.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            Picker("สถานะ", selection: $status) {
                ForEach(TaskStatus.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            Toggle(isOn: $isFocus) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ปักเป็นงานโฟกัส")
                    Text("สูงสุด \(TaskStore.focusLimit) งานต่อวัน")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            .tint(AppTheme.brand)
        }
    }

    private var sharingSection: some View {
        Section("การมองเห็น") {
            Picker("ใครเห็นได้", selection: $visibility) {
                ForEach(TaskVisibility.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("มอบหมายให้", selection: $assigneeId) {
                Text("ไม่ระบุ").tag("")
                ForEach(admins) { admin in
                    Text(admin.displayName).tag(admin.id)
                }
            }

            Text(visibility == .shared
                 ? "ทุกคนที่เข้าใช้แอปจะเห็นงานนี้"
                 : "เห็นเฉพาะคุณเท่านั้น")
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("ลบงานนี้", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Save

    private func submit() {
        let lines = titleLines
        guard !lines.isEmpty else { return }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueYMD = DashboardAggregations.formatYMD(dueDate)
        let remindISO = remindEnabled ? TaskDates.toISO(remindDate) : nil
        let deadlineISO = deadlineEnabled ? TaskDates.toISO(deadlineDate) : nil

        let assignee: (id: String?, name: String?) = {
            if assigneeId.isEmpty { return (nil, nil) }
            return (assigneeId, admins.first { $0.id == assigneeId }?.displayName)
        }()

        let tasks: [WorkTask] = lines.enumerated().map { index, line in
            var task = original
            if isNew, index > 0 {
                task.id = UUID().uuidString
                task.createdAt = TaskDates.nowISO()
            }
            task.title = line
            task.note = trimmedNote.isEmpty ? nil : trimmedNote
            task.scope = scope
            task.dueDate = dueYMD
            task.priority = priority
            task.status = status
            task.visibility = visibility
            task.isFocus = isFocus
            task.assigneeAdminId = assignee.id
            task.assigneeName = assignee.name
            task.remindAt = remindISO
            task.deadline = deadlineISO
            return task
        }

        onSave(tasks)
        dismiss()
    }
}
