import PhotosUI
import SwiftUI

// MARK: - Album detail

struct PhotoAlbumDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @AppStorage("photoAlbums.gridColumns") private var gridColumns = 3
    @State private var album: PhotoAlbumSummary
    @State private var media: [PhotoMediaItem] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: PhotoAlbumError?
    @State private var filter: MediaFilter = .all
    @State private var viewerStart: ViewerStart?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var queue: PhotoUploadQueue
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var saving = false
    @State private var toast: String?
    // SuperAdmin management
    @State private var showEdit = false
    @State private var confirmDeleteSelected = false
    @State private var confirmDeleteAlbum = false
    @State private var pendingDelete: PhotoMediaItem?
    @State private var working = false
    @State private var actionError: String?

    enum MediaFilter: String, CaseIterable, Identifiable {
        case all, photos, videos
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "ทั้งหมด"
            case .photos: return "รูป"
            case .videos: return "วิดีโอ"
            }
        }
    }

    private struct ViewerStart: Identifiable {
        let items: [PhotoMediaItem]
        let index: Int
        var id: Int { index }
    }

    private var canManage: Bool { auth.currentAdmin?.role == .superAdmin }
    private var photoCount: Int { media.filter { !$0.isVideo }.count }
    private var videoCount: Int { media.count - photoCount }

    private var visibleMedia: [PhotoMediaItem] {
        switch filter {
        case .all: return media
        case .photos: return media.filter { !$0.isVideo }
        case .videos: return media.filter(\.isVideo)
        }
    }

    private var selectedItems: [PhotoMediaItem] { media.filter { selected.contains($0.id) } }
    private var allVisibleSelected: Bool {
        !visibleMedia.isEmpty && visibleMedia.allSatisfy { selected.contains($0.id) }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: min(5, max(2, gridColumns)))
    }

    init(album: PhotoAlbumSummary) {
        _album = State(initialValue: album)
        _queue = State(initialValue: PhotoUploadQueue(albumId: album.id))
    }

    private var hasSingleKind: Bool { videoCount == 0 || photoCount == 0 }

    var body: some View {
        pageWithDialogs
            .overlay {
                if working {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
                }
            }
            .disabled(working)
            .photoToast($toast)
            .sensoryFeedback(.selection, trigger: selected)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty, let admin = auth.currentAdmin else { return }
                queue.enqueue(items, admin: admin)
                pickerItems = []
            }
            .onChange(of: hasSingleKind) { _, single in
                if single { filter = .all }
            }
            .refreshable { await load() }
            .task {
                queue.onUploaded = { item in
                    if !media.contains(where: { $0.id == item.id }) { media.append(item) }
                }
                await load()
            }
            .fullScreenCover(item: $viewerStart) { start in
                PhotoMediaViewer(
                    items: start.items,
                    startIndex: start.index,
                    canManage: canManage,
                    onSetCover: { item in await setCover(item) },
                    onDelete: { item in await deleteMedia([item.id]) }
                )
            }
    }

    // MARK: Body pieces (split so the type checker stays fast)

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                hero
                    .padding(.horizontal, AppTheme.spaceLG)
                actionsPanel
                    .padding(.horizontal, AppTheme.spaceLG)
                if !hasSingleKind {
                    filterPicker
                }
                mediaContent
            }
            .padding(.vertical, AppTheme.spaceMD)
        }
    }

    private var filterPicker: some View {
        Picker("แสดง", selection: $filter) {
            ForEach(MediaFilter.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.spaceLG)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if selecting {
                Button(allVisibleSelected ? "ไม่เลือก" : "เลือกทั้งหมด") {
                    selected = allVisibleSelected ? [] : Set(visibleMedia.map(\.id))
                }
                Button("เสร็จ") {
                    selecting = false
                    selected = []
                }
                .fontWeight(.semibold)
            } else {
                addMediaPicker {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("เพิ่มรูปหรือวิดีโอ")
                optionsMenu
            }
        }
    }

    @ViewBuilder
    private var bottomInset: some View {
        if selecting {
            selectionBar
        } else if !queue.jobs.isEmpty {
            PhotoUploadTray(queue: queue)
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.bottom, AppTheme.spaceSM)
        }
    }

    private var page: some View {
        scrollContent
            .background(DashboardBackground())
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomInset }
            .sheet(isPresented: $showEdit) {
                PhotoEditAlbumSheet(album: album) { detail in
                    album = detail.summary
                    media = detail.media
                }
                .environment(auth)
            }
    }

    private var pendingDeleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var actionErrorShown: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private var pageWithDialogs: some View {
        page
            .confirmationDialog(
                "ลบ \(selected.count) รายการที่เลือก?",
                isPresented: $confirmDeleteSelected,
                titleVisibility: .visible
            ) {
                Button("ลบ \(selected.count) รายการ", role: .destructive) {
                    Task { await deleteSelected() }
                }
            } message: {
                Text("ไฟล์จะถูกย้ายไปถังขยะของ Google Drive (กู้คืนได้ใน 30 วัน)")
            }
            .confirmationDialog(
                "ลบรายการนี้?",
                isPresented: pendingDeleteShown,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { (item: PhotoMediaItem) in
                Button("ลบ", role: .destructive) {
                    Task { await deleteOne(item) }
                }
            } message: { (_: PhotoMediaItem) in
                Text("ไฟล์จะถูกย้ายไปถังขยะของ Google Drive (กู้คืนได้ใน 30 วัน)")
            }
            .confirmationDialog(
                "ลบอัลบั้ม «\(album.title)»?",
                isPresented: $confirmDeleteAlbum,
                titleVisibility: .visible
            ) {
                Button("ลบอัลบั้ม", role: .destructive) {
                    Task { await deleteAlbum() }
                }
            } message: {
                Text("อัลบั้มและไฟล์ทั้งหมด \(media.count) รายการจะถูกย้ายไปถังขยะของ Google Drive (กู้คืนได้ใน 30 วัน) และลิงก์แชร์จะใช้ไม่ได้")
            }
            .alert("ทำรายการไม่สำเร็จ", isPresented: actionErrorShown) {
                Button("ตกลง", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    private func deleteOne(_ item: PhotoMediaItem) async {
        if let message = await deleteMedia([item.id]) {
            actionError = message
        }
    }

    // MARK: Header

    private var hero: some View {
        Color.clear
            .frame(height: 210)
            .overlay {
                if let cover = album.cover {
                    PhotoRemoteImage(sources: cover, large: true)
                } else {
                    LinearGradient(
                        colors: [AppTheme.brandMid, AppTheme.brandDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(album.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Label(DashboardAggregations.thaiDateLong(album.reportDate), systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(AppTheme.spaceLG)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 14, y: 6)
            .accessibilityElement(children: .combine)
    }

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            HStack(spacing: 8) {
                if loaded {
                    countChip("\(photoCount) รูป", systemImage: "photo")
                    if videoCount > 0 {
                        countChip("\(videoCount) วิดีโอ", systemImage: "video")
                    }
                } else {
                    countChip("\(album.mediaCount) รายการ", systemImage: "photo.stack")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                addMediaPicker {
                    actionTile("เพิ่มรูป", systemImage: "plus", prominent: true)
                }
                if let url = URL(string: album.shareUrl) {
                    ShareLink(item: url, subject: Text(album.title), message: Text(album.title)) {
                        actionTile("แชร์อัลบั้ม", systemImage: "square.and.arrow.up")
                    }
                }
                if let drive = URL(string: album.driveFolderUrl) {
                    Link(destination: drive) {
                        actionTile("Google Drive", systemImage: "folder")
                    }
                }
            }
        }
    }

    private func countChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.brand)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.brand.opacity(0.12), in: Capsule())
    }

    private func actionTile(_ title: String, systemImage: String, prominent: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(prominent ? Color.white : AppTheme.brand)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(prominent ? AppTheme.brand : AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(prominent ? Color.clear : AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: Media grid

    @ViewBuilder
    private var mediaContent: some View {
        if media.isEmpty && error == nil && (loading || !loaded) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<12, id: \.self) { _ in
                    PhotoShimmer()
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        } else if media.isEmpty, let error {
            ContentUnavailableView {
                Label("โหลดรูปไม่สำเร็จ", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("ลองใหม่") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brand)
            }
            .padding(.top, AppTheme.spaceXL)
        } else if media.isEmpty {
            ContentUnavailableView {
                Label("อัลบั้มนี้ยังไม่มีรูป", systemImage: "photo.on.rectangle")
            } description: {
                Text("เพิ่มรูปหรือวิดีโอจากคลังรูปในเครื่องได้ครั้งละ 100 ไฟล์")
            } actions: {
                addMediaPicker {
                    Label("เพิ่มรูป / วิดีโอ", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(AppTheme.brand, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.top, AppTheme.spaceXL)
        } else {
            mediaGrid(items: visibleMedia)
        }
    }

    private func mediaGrid(items: [PhotoMediaItem]) -> some View {
        let sections = PhotoDaySection.group(items)
        return LazyVStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if sections.count > 1 {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(section.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                            Text("\(section.entries.count) รายการ")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppTheme.spaceLG)
                        .accessibilityAddTraits(.isHeader)
                    }
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(section.entries) { entry in
                            cell(entry, items: items)
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: gridColumns)
        .simultaneousGesture(densityGesture)
    }

    private func cell(_ entry: PhotoDaySection.Entry, items: [PhotoMediaItem]) -> some View {
        let item = entry.item
        return Button {
            if selecting {
                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            } else {
                viewerStart = ViewerStart(items: items, index: entry.index)
            }
        } label: {
            PhotoGridCell(item: item, selection: selecting ? selected.contains(item.id) : nil)
        }
        .buttonStyle(.plain)
        .contextMenu {
            cellMenu(item, index: entry.index, items: items)
        } preview: {
            PhotoRemoteImage(sources: item.src, contentMode: .fit)
                .frame(width: 320, height: 320 * previewRatio(item))
        }
    }

    private func previewRatio(_ item: PhotoMediaItem) -> CGFloat {
        guard item.width > 0, item.height > 0 else { return 1 }
        return min(1.6, max(0.5, CGFloat(item.height) / CGFloat(item.width)))
    }

    @ViewBuilder
    private func cellMenu(_ item: PhotoMediaItem, index: Int, items: [PhotoMediaItem]) -> some View {
        Button {
            viewerStart = ViewerStart(items: items, index: index)
        } label: {
            Label(item.isVideo ? "เล่นวิดีโอ" : "ดูรูป", systemImage: item.isVideo ? "play.circle" : "eye")
        }
        Button {
            Task { await save([item]) }
        } label: {
            Label("บันทึกลงเครื่อง", systemImage: "square.and.arrow.down")
        }
        if let url = URL(string: item.src.download) {
            ShareLink(item: url) {
                Label("แชร์ลิงก์ดาวน์โหลด", systemImage: "square.and.arrow.up")
            }
        }
        if canManage {
            Divider()
            if !item.isVideo {
                Button {
                    Task {
                        if let message = await setCover(item) {
                            actionError = message
                        } else {
                            toast = "ตั้งเป็นรูปปกแล้ว"
                        }
                    }
                } label: {
                    Label("ตั้งเป็นรูปปกอัลบั้ม", systemImage: "photo.badge.checkmark")
                }
            }
            Button(role: .destructive) { pendingDelete = item } label: {
                Label("ลบ", systemImage: "trash")
            }
        }
    }

    /// Pinch the grid to change thumbnail size, like the Photos app.
    private var densityGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.15 {
                    gridColumns = max(2, gridColumns - 1)
                } else if value.magnification < 0.87 {
                    gridColumns = min(5, gridColumns + 1)
                }
            }
    }

    // MARK: Toolbar menu

    private var optionsMenu: some View {
        Menu {
            if !media.isEmpty {
                Button { selecting = true } label: {
                    Label("เลือกหลายรายการ", systemImage: "checkmark.circle")
                }
            }
            Picker(selection: $gridColumns) {
                Text("ใหญ่").tag(2)
                Text("ปกติ").tag(3)
                Text("เล็ก").tag(4)
                Text("เล็กมาก").tag(5)
            } label: {
                Label("ขนาดรูป", systemImage: "square.grid.3x3")
            }
            .pickerStyle(.menu)
            if canManage {
                Divider()
                Button { showEdit = true } label: {
                    Label("แก้ไขอัลบั้ม", systemImage: "pencil")
                }
                Button(role: .destructive) { confirmDeleteAlbum = true } label: {
                    Label("ลบอัลบั้ม", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("ตัวเลือกอัลบั้ม")
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text(selected.isEmpty ? "แตะรูปเพื่อเลือก" : "เลือกแล้ว \(selected.count) รายการ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Button {
                Task { await save(selectedItems) }
            } label: {
                Label("บันทึก", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.brand)
            .disabled(selected.isEmpty || saving)
            if canManage {
                Button(role: .destructive) { confirmDeleteSelected = true } label: {
                    Label("ลบ", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.expense)
                .disabled(selected.isEmpty || saving)
            }
        }
        .padding(AppTheme.spaceMD)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func save(_ items: [PhotoMediaItem]) async {
        guard !items.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }
        var saved = 0
        var failure: String?
        for (i, item) in items.enumerated() {
            toast = items.count > 1 ? "กำลังบันทึก \(i + 1)/\(items.count)…" : "กำลังบันทึก…"
            do {
                try await PhotoLibrarySaver.save(item)
                saved += 1
            } catch {
                failure = error.localizedDescription
                if let saveError = error as? PhotoLibrarySaver.SaveError, case .denied = saveError { break }
            }
        }
        if let failure {
            toast = saved > 0 ? "บันทึกแล้ว \(saved)/\(items.count) — \(failure)" : failure
        } else {
            toast = "บันทึกลงเครื่องแล้ว \(saved) รายการ"
            if selecting {
                selecting = false
                selected = []
            }
        }
    }

    private func deleteSelected() async {
        let ids = media.map(\.id).filter(selected.contains)
        if let message = await deleteMedia(ids) {
            actionError = message
        }
        selected = []
        if media.isEmpty { selecting = false }
    }

    /// Deletes one by one so a failure keeps the rest; returns an error message or nil.
    private func deleteMedia(_ ids: [String]) async -> String? {
        guard let admin = auth.currentAdmin else { return nil }
        working = true
        defer { working = false }
        var failure: String?
        for id in ids {
            do {
                try await PhotoAlbumSession.shared.withToken(admin: admin) {
                    try await PhotoAlbumAPI.deleteMedia(id: id, token: $0)
                }
                media.removeAll { $0.id == id }
            } catch {
                failure = error.localizedDescription
            }
        }
        if failure == nil { await load() }
        return failure
    }

    private func setCover(_ item: PhotoMediaItem) async -> String? {
        guard let admin = auth.currentAdmin else { return nil }
        do {
            let detail = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.updateAlbum(id: album.id, coverMediaId: item.id, token: $0)
            }
            album = detail.summary
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func deleteAlbum() async {
        guard let admin = auth.currentAdmin else { return }
        working = true
        defer { working = false }
        do {
            try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.deleteAlbum(id: album.id, token: $0)
            }
            queue.cancelAll()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func addMediaPicker<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 100,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current,
            label: label
        )
    }

    private func load() async {
        guard let admin = auth.currentAdmin else { return }
        loading = true
        defer {
            loading = false
            loaded = true
        }
        do {
            let detail = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.album(id: album.id, token: $0)
            }
            album = detail.summary
            media = detail.media
            error = nil
        } catch let err as PhotoAlbumError {
            error = err
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}

// MARK: - Day sections

/// Consecutive items on the same Thai calendar day (mirrors apps/photo groupByDay); `index` is the position in the list.
struct PhotoDaySection: Identifiable {
    struct Entry: Identifiable {
        let index: Int
        let item: PhotoMediaItem
        var id: String { item.id }
    }

    let id: String
    let key: String
    let title: String
    var entries: [Entry]

    static func group(_ media: [PhotoMediaItem]) -> [PhotoDaySection] {
        var out: [PhotoDaySection] = []
        for (index, item) in media.enumerated() {
            let key = PhotoAlbumFormat.dayKey(item.takenAt ?? item.createdAt)
            let entry = Entry(index: index, item: item)
            if let last = out.last, last.key == key {
                out[out.count - 1].entries.append(entry)
            } else {
                out.append(PhotoDaySection(
                    id: "\(key)#\(index)",
                    key: key,
                    title: PhotoAlbumFormat.dayTitle(key),
                    entries: [entry]
                ))
            }
        }
        return out
    }
}

// MARK: - Grid cell

private struct PhotoGridCell: View {
    let item: PhotoMediaItem
    /// nil = not in select mode.
    var selection: Bool? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { PhotoRemoteImage(sources: item.src) }
            .background(AppTheme.surfaceSoft)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(5)
                }
            }
            .overlay {
                if selection == true {
                    Color.black.opacity(0.25)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selection {
                    Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection ? AppTheme.brand : .white)
                        .background(Circle().fill(selection ? Color.white : Color.black.opacity(0.2)))
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .scaleEffect(selection == true ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: selection)
            .contentShape(Rectangle())
            .accessibilityLabel(item.isVideo ? "วิดีโอ \(item.name)" : "รูป \(item.name)")
            .accessibilityAddTraits(selection == true ? .isSelected : [])
    }
}

// MARK: - Edit album (SuperAdmin)

private struct PhotoEditAlbumSheet: View {
    let album: PhotoAlbumSummary
    let onSaved: (PhotoAlbumDetail) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var reportDate: Date
    @State private var busy = false
    @State private var message: String?
    @State private var confirmNewLink = false

    init(album: PhotoAlbumSummary, onSaved: @escaping (PhotoAlbumDetail) -> Void) {
        self.album = album
        self.onSaved = onSaved
        _title = State(initialValue: album.title)
        _reportDate = State(initialValue: PhotoAlbumFormat.date(fromReportKey: album.reportDate) ?? Date())
    }

    private var cleanTitle: String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private var reportKey: String { PhotoAlbumFormat.reportDateKey(reportDate) }
    private var hasChanges: Bool { cleanTitle != album.title || reportKey != album.reportDate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ชื่อรายงาน", text: $title)
                    DatePicker("วันที่รายงาน", selection: $reportDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "th_TH"))
                        .environment(\.calendar, Calendar(identifier: .buddhist))
                } footer: {
                    Text(reportKey != album.reportDate
                         ? "เปลี่ยนวันที่แล้ว — โฟลเดอร์ใน Google Drive จะย้ายไปปี/เดือนใหม่ให้อัตโนมัติ"
                         : "เปลี่ยนชื่อได้ — โฟลเดอร์ใน Google Drive จะเปลี่ยนชื่อตามให้")
                }
                Section {
                    Button { confirmNewLink = true } label: {
                        Label("สร้างลิงก์แชร์ใหม่", systemImage: "link")
                    }
                } footer: {
                    Text("ลิงก์เดิมที่แชร์ไปแล้วจะใช้ไม่ได้ทันที")
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                    }
                }
            }
            .navigationTitle("แก้ไขอัลบั้ม")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "กำลังบันทึก…" : "บันทึก") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(busy || !hasChanges || cleanTitle.isEmpty || cleanTitle.count > 200)
                }
            }
            .confirmationDialog("สร้างลิงก์แชร์ใหม่?", isPresented: $confirmNewLink, titleVisibility: .visible) {
                Button("สร้างลิงก์ใหม่", role: .destructive) { Task { await regenerateLink() } }
            } message: {
                Text("ลิงก์เดิมที่แชร์ไปแล้วจะใช้ไม่ได้ทันที — ต้องแชร์ลิงก์ใหม่อีกครั้ง")
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private func save() async {
        let title = cleanTitle == album.title ? nil : cleanTitle
        let reportDate = reportKey == album.reportDate ? nil : reportKey
        await patch { token in
            try await PhotoAlbumAPI.updateAlbum(id: album.id, title: title, reportDate: reportDate, token: token)
        }
    }

    private func regenerateLink() async {
        await patch { token in
            try await PhotoAlbumAPI.updateAlbum(id: album.id, regenerateLink: true, token: token)
        }
    }

    private func patch(_ call: (String) async throws -> PhotoAlbumDetail) async {
        guard let admin = auth.currentAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let detail = try await PhotoAlbumSession.shared.withToken(admin: admin, call)
            onSaved(detail)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Upload tray

private struct PhotoUploadTray: View {
    let queue: PhotoUploadQueue
    @Environment(AuthService.self) private var auth
    @State private var expanded = false

    private var title: String {
        if queue.hasActiveJobs {
            return "กำลังอัปโหลด \(queue.doneCount + 1)/\(queue.jobs.count)"
        }
        if queue.failedCount > 0 {
            return "อัปโหลดไม่สำเร็จ \(queue.failedCount) ไฟล์"
        }
        return "อัปโหลดเสร็จ \(queue.doneCount) ไฟล์"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: queue.hasActiveJobs
                      ? "arrow.up.circle.fill"
                      : (queue.failedCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.title3)
                    .foregroundStyle(queue.hasActiveJobs ? AppTheme.brand : (queue.failedCount > 0 ? AppTheme.expense : AppTheme.income))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if queue.failedCount > 0 && !queue.hasActiveJobs, let admin = auth.currentAdmin {
                    Button("ลองใหม่") { queue.retryFailed(admin: admin) }
                        .font(.caption.weight(.bold))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                }
                .accessibilityLabel(expanded ? "ซ่อนรายการ" : "แสดงรายการ")
                if queue.hasActiveJobs {
                    Button { queue.cancelAll() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("ยกเลิกการอัปโหลด")
                } else {
                    Button { queue.clearFinished() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("ปิด")
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.inkSecondary)

            if queue.hasActiveJobs {
                ProgressView(value: queue.progress)
                    .tint(AppTheme.brand)
            }

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(queue.jobs) { job in
                            HStack(spacing: 8) {
                                Image(systemName: job.isVideo ? "video" : "photo")
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text("ไฟล์ที่ \(job.index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 0)
                                jobStatus(job.state)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(AppTheme.spaceMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func jobStatus(_ state: PhotoUploadQueue.JobState) -> some View {
        switch state {
        case .waiting:
            Text("รอคิว").font(.caption2).foregroundStyle(AppTheme.inkMuted)
        case .uploading(let p):
            Text("\(Int((p * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(AppTheme.brand)
        case .done:
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(AppTheme.income)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(AppTheme.expense)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
