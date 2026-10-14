import SwiftUI
import UIKit

enum PhotoAlbumSort: String, CaseIterable, Identifiable {
    case newest, oldest, mostMedia, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "วันที่ใหม่สุด"
        case .oldest: return "วันที่เก่าสุด"
        case .mostMedia: return "จำนวนรูปมากสุด"
        case .title: return "ชื่อ ก–ฮ"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .mostMedia: return "photo.stack"
        case .title: return "textformat"
        }
    }

    var groupsByMonth: Bool { self == .newest || self == .oldest }
}

/// «อัลบั้ม» tab — albums from GoldenMole Photos (photo.goldenmole.pro): browse, create, upload.
struct PhotoAlbumsView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("photoAlbums.sort") private var sortRaw = PhotoAlbumSort.newest.rawValue
    @AppStorage("photoAlbums.listLayout") private var listLayout = false

    @State private var albums: [PhotoAlbumSummary] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: PhotoAlbumError?
    @State private var search = ""
    @State private var showCreate = false
    @State private var openedAlbum: PhotoAlbumSummary?
    @State private var toast: String?

    private struct AlbumSection: Identifiable {
        let id: String
        let title: String?
        var albums: [PhotoAlbumSummary]
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 158), spacing: AppTheme.spaceMD)]

    private var sort: PhotoAlbumSort { PhotoAlbumSort(rawValue: sortRaw) ?? .newest }
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedSearch.isEmpty }
    private var totalMedia: Int { albums.reduce(0) { $0 + $1.mediaCount } }
    private var thisMonthCount: Int {
        let month = String(PhotoAlbumFormat.reportDateKey(Date()).prefix(7))
        return albums.filter { $0.reportDate.hasPrefix(month) }.count
    }

    private var sortedAlbums: [PhotoAlbumSummary] {
        let q = trimmedSearch
        let base = q.isEmpty ? albums : albums.filter {
            $0.title.localizedCaseInsensitiveContains(q) || PhotoAlbumFormat.shortDate($0.reportDate).contains(q)
        }
        switch sort {
        case .newest:
            return base.sorted { $0.reportDate != $1.reportDate ? $0.reportDate > $1.reportDate : $0.title < $1.title }
        case .oldest:
            return base.sorted { $0.reportDate != $1.reportDate ? $0.reportDate < $1.reportDate : $0.title < $1.title }
        case .mostMedia:
            return base.sorted { $0.mediaCount != $1.mediaCount ? $0.mediaCount > $1.mediaCount : $0.reportDate > $1.reportDate }
        case .title:
            return base.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// The latest album gets a hero card on the default view; the rest are grouped by report month.
    private func arrangedAlbums() -> (hero: PhotoAlbumSummary?, sections: [AlbumSection]) {
        var list = sortedAlbums
        var hero: PhotoAlbumSummary?
        if sort == .newest, !isSearching, list.count > 1 {
            hero = list.removeFirst()
        }
        guard sort.groupsByMonth else {
            return (hero, list.isEmpty ? [] : [AlbumSection(id: "all", title: nil, albums: list)])
        }
        var sections: [AlbumSection] = []
        for album in list {
            let key = String(album.reportDate.prefix(7))
            if let last = sections.last, last.id == key {
                sections[sections.count - 1].albums.append(album)
            } else {
                sections.append(AlbumSection(id: key, title: PhotoAlbumFormat.monthTitle(key), albums: [album]))
            }
        }
        return (hero, sections)
    }

    var body: some View {
        content
            .background(DashboardBackground())
            .navigationTitle("อัลบั้ม")
            .navigationDestination(for: PhotoAlbumSummary.self) { album in
                PhotoAlbumDetailView(album: album)
            }
            .navigationDestination(item: $openedAlbum) { album in
                PhotoAlbumDetailView(album: album)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if error == nil {
                        viewMenu
                        Button { showCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("สร้างอัลบั้ม")
                    } else {
                        Link(destination: PhotoAlbumAPI.webURL) {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("เปิด GoldenMole Photos บนเว็บ")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                PhotoCreateAlbumSheet { album in
                    albums.insert(album, at: 0)
                    openedAlbum = album
                }
                .environment(auth)
            }
            .photoToast($toast)
            .task(id: auth.currentAdmin?.id) { await load() }
            .onAppear {
                // Quiet refresh when coming back from an album (counts / covers after uploads).
                if !albums.isEmpty { Task { await load() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        if error == .needsPassword || error == .unauthorized {
            PhotoAlbumSignInCard { await load() }
        } else if albums.isEmpty && error == nil && (loading || !loaded) {
            skeleton
        } else if albums.isEmpty, let error {
            ScrollView {
                ContentUnavailableView {
                    Label("โหลดอัลบั้มไม่สำเร็จ", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    if error != .forbidden {
                        Button("ลองใหม่") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brand)
                    }
                }
                .padding(.top, 60)
            }
            .refreshable { await load() }
        } else {
            albumScroll
        }
    }

    private var albumScroll: some View {
        let layout = arrangedAlbums()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                if !isSearching && !albums.isEmpty {
                    statsHeader
                }
                if layout.hero == nil && layout.sections.isEmpty {
                    emptyResults
                }
                if let hero = layout.hero {
                    VStack(alignment: .leading, spacing: AppTheme.spaceSM) {
                        sectionTitle("ล่าสุด", detail: nil)
                        albumLink(hero) {
                            PhotoAlbumCard(album: hero, style: .hero)
                        }
                    }
                }
                ForEach(layout.sections) { section in
                    VStack(alignment: .leading, spacing: AppTheme.spaceSM) {
                        if let title = section.title {
                            sectionTitle(title, detail: "\(section.albums.count) อัลบั้ม")
                        }
                        if listLayout {
                            VStack(spacing: AppTheme.spaceSM) {
                                ForEach(section.albums) { album in
                                    albumLink(album) { PhotoAlbumRow(album: album) }
                                }
                            }
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: AppTheme.spaceMD) {
                                ForEach(section.albums) { album in
                                    albumLink(album) { PhotoAlbumCard(album: album, style: .regular) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.spaceLG)
            .animation(.snappy, value: sortRaw)
            .animation(.snappy, value: listLayout)
        }
        .searchable(text: $search, prompt: "ค้นหาชื่อหรือวันที่")
        .refreshable { await load() }
    }

    // MARK: Pieces

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statItem(value: albums.count, label: "อัลบั้ม", systemImage: "rectangle.stack.fill", tint: AppTheme.brand)
            Divider().frame(height: 34)
            statItem(value: totalMedia, label: "รูปและวิดีโอ", systemImage: "photo.fill", tint: AppTheme.info)
            Divider().frame(height: 34)
            statItem(value: thisMonthCount, label: "อัลบั้มเดือนนี้", systemImage: "calendar", tint: AppTheme.warning)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func statItem(value: Int, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(value.formatted())
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func albumLink<Content: View>(
        _ album: PhotoAlbumSummary,
        @ViewBuilder label: () -> Content
    ) -> some View {
        NavigationLink(value: album) {
            label()
        }
        .buttonStyle(PhotoPressableStyle())
        .contextMenu { albumMenu(album) }
    }

    @ViewBuilder
    private func albumMenu(_ album: PhotoAlbumSummary) -> some View {
        Button { openedAlbum = album } label: {
            Label("เปิดอัลบั้ม", systemImage: "photo.on.rectangle")
        }
        if let url = URL(string: album.shareUrl) {
            ShareLink(item: url, subject: Text(album.title), message: Text(album.title)) {
                Label("แชร์ลิงก์อัลบั้ม", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = album.shareUrl
                toast = "คัดลอกลิงก์แล้ว"
            } label: {
                Label("คัดลอกลิงก์", systemImage: "doc.on.doc")
            }
        }
        if let drive = URL(string: album.driveFolderUrl) {
            Link(destination: drive) {
                Label("เปิดใน Google Drive", systemImage: "folder")
            }
        }
    }

    private var viewMenu: some View {
        Menu {
            Picker(selection: $sortRaw) {
                ForEach(PhotoAlbumSort.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
                }
            } label: {
                Text("เรียงตาม")
            }
            .pickerStyle(.inline)
            Picker(selection: $listLayout) {
                Label("ตาราง", systemImage: "square.grid.2x2").tag(false)
                Label("รายการ", systemImage: "list.bullet").tag(true)
            } label: {
                Text("มุมมอง")
            }
            .pickerStyle(.inline)
            Divider()
            Link(destination: PhotoAlbumAPI.webURL) {
                Label("เปิด GoldenMole Photos บนเว็บ", systemImage: "safari")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("เรียงลำดับและมุมมอง")
    }

    @ViewBuilder
    private var emptyResults: some View {
        if isSearching {
            ContentUnavailableView {
                Label("ไม่พบอัลบั้ม", systemImage: "magnifyingglass")
            } description: {
                Text("ไม่มีอัลบั้มที่ตรงกับ «\(trimmedSearch)»")
            }
            .padding(.top, 40)
        } else {
            ContentUnavailableView {
                Label("ยังไม่มีอัลบั้ม", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("สร้างอัลบั้มแรกเพื่อเก็บรูปหน้างานไว้ใน Google Drive")
            } actions: {
                Button { showCreate = true } label: {
                    Label("สร้างอัลบั้ม", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
            }
            .padding(.top, 40)
        }
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: AppTheme.spaceLG) {
                PhotoShimmer()
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
                PhotoShimmer()
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL, style: .continuous))
                LazyVGrid(columns: gridColumns, spacing: AppTheme.spaceMD) {
                    ForEach(0..<4, id: \.self) { _ in
                        PhotoShimmer()
                            .aspectRatio(0.8, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
                    }
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollDisabled(true)
        .accessibilityLabel("กำลังโหลดอัลบั้ม")
    }

    private func load() async {
        guard let admin = auth.currentAdmin else { return }
        loading = true
        defer {
            loading = false
            loaded = true
        }
        do {
            albums = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.albums(token: $0)
            }
            error = nil
        } catch let err as PhotoAlbumError {
            error = err
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}

// MARK: - Album card (grid / hero)

struct PhotoAlbumCard: View {
    enum Style { case regular, hero }

    let album: PhotoAlbumSummary
    var style: Style = .regular

    private var isHero: Bool { style == .hero }
    private var radius: CGFloat { isHero ? AppTheme.radiusXL : AppTheme.radiusLG }

    var body: some View {
        Color.clear
            .aspectRatio(isHero ? 1.6 : 0.8, contentMode: .fit)
            .overlay { coverLayer }
            .overlay {
                LinearGradient(colors: [.clear, .clear, Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .topTrailing) {
                countBadge
                    .padding(isHero ? 12 : 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: isHero ? 14 : 8, y: isHero ? 6 : 3)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(album.title), \(PhotoAlbumFormat.shortDate(album.reportDate)), \(album.mediaCount) รายการ")
    }

    @ViewBuilder
    private var coverLayer: some View {
        if let cover = album.cover {
            PhotoRemoteImage(sources: cover, large: isHero)
        } else {
            LinearGradient(
                colors: [AppTheme.brandMid, AppTheme.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: isHero ? 44 : 30, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.title)
                .font(isHero ? Font.title3.bold() : Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(isHero ? DashboardAggregations.thaiDateLong(album.reportDate) : PhotoAlbumFormat.shortDate(album.reportDate))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(isHero ? AppTheme.spaceLG : AppTheme.spaceMD)
    }

    private var countBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "photo.on.rectangle")
            Text("\(album.mediaCount)")
        }
        .font(.caption2.weight(.bold).monospacedDigit())
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4), in: Capsule())
    }
}

// MARK: - Album row (list layout)

struct PhotoAlbumRow: View {
    let album: PhotoAlbumSummary

    var body: some View {
        HStack(spacing: AppTheme.spaceMD) {
            Color.clear
                .frame(width: 68, height: 68)
                .overlay {
                    if let cover = album.cover {
                        PhotoRemoteImage(sources: cover)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3.weight(.light))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }
                .background(AppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    Label(PhotoAlbumFormat.shortDate(album.reportDate), systemImage: "calendar")
                    Label("\(album.mediaCount)", systemImage: "photo")
                }
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(PhotoAlbumFormat.shortDate(album.reportDate)), \(album.mediaCount) รายการ")
    }
}

// MARK: - One-time sign-in for the photo site

private struct PhotoAlbumSignInCard: View {
    let onSignedIn: () async -> Void

    @Environment(AuthService.self) private var auth
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            SectionCard("เข้าสู่ระบบอัลบั้ม", systemImage: "lock.shield", subtitle: "ใช้รหัสผ่านเดียวกับที่เข้าแอปนี้ — ถามครั้งเดียว") {
                VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                    Label(auth.currentAdmin?.username ?? "-", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                    SecureField("รหัสผ่าน", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .padding(12)
                        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                    if let message {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? "กำลังเข้าสู่ระบบ…" : "เข้าสู่ระบบ")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brand)
                    .disabled(busy || password.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(AppTheme.spaceLG)
        }
    }

    private func submit() async {
        guard let admin = auth.currentAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoAlbumSession.shared.signIn(
                admin: admin,
                password: password.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            password = ""
            message = nil
            await onSignedIn()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Formatting

enum PhotoAlbumFormat {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func thaiFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = format
        return f
    }

    private static let display = thaiFormatter("d MMM yy")
    private static let monthDisplay = thaiFormatter("LLLL yyyy")
    private static let dateTimeDisplay = thaiFormatter("d MMM yy · HH:mm 'น.'")

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()

    static func shortDate(_ ymd: String) -> String {
        guard let date = Self.ymd.date(from: ymd) else { return ymd }
        return display.string(from: date)
    }

    static func reportDateKey(_ date: Date) -> String {
        ymd.string(from: date)
    }

    static func date(fromReportKey key: String) -> Date? {
        ymd.date(from: key)
    }

    /// "2026-10" → "ตุลาคม 2569"
    static func monthTitle(_ yearMonth: String) -> String {
        guard let date = ymd.date(from: "\(yearMonth)-01") else { return yearMonth }
        return monthDisplay.string(from: date)
    }

    /// ISO timestamp → Bangkok calendar day "YYYY-MM-DD".
    static func dayKey(_ iso: String) -> String {
        guard let date = parseISO(iso) else { return String(iso.prefix(10)) }
        return ymd.string(from: date)
    }

    static func dayTitle(_ key: String) -> String {
        DashboardAggregations.thaiDateLong(key)
    }

    /// Capture time and uploader for the viewer caption.
    static func mediaInfo(_ item: PhotoMediaItem) -> String? {
        var parts: [String] = []
        if let date = parseISO(item.takenAt ?? item.createdAt) {
            parts.append(dateTimeDisplay.string(from: date))
        }
        if let name = item.uploadedByName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append("อัปโหลดโดย \(name)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func parseISO(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? isoPlain.date(from: value)
    }
}

// MARK: - Create album

private struct PhotoCreateAlbumSheet: View {
    let onCreated: (PhotoAlbumSummary) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var reportDate = Date()
    @State private var busy = false
    @State private var message: String?
    @FocusState private var titleFocused: Bool

    private var cleanTitle: String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ชื่อรายงาน เช่น เทปูนชั้น 2", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    DatePicker("วันที่รายงาน", selection: $reportDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "th_TH"))
                        .environment(\.calendar, Calendar(identifier: .buddhist))
                } footer: {
                    Text("เก็บรูปใน Google Drive ใต้โฟลเดอร์ ปี / เดือน ของวันที่รายงาน · ทุกคนที่มีลิงก์อัลบั้มเพิ่มรูปได้")
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                    }
                }
            }
            .navigationTitle("สร้างอัลบั้ม")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "กำลังสร้าง…" : "สร้าง") { Task { await submit() } }
                        .fontWeight(.semibold)
                        .disabled(busy || cleanTitle.isEmpty || cleanTitle.count > 200)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private func submit() async {
        guard let admin = auth.currentAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        let title = cleanTitle
        let reportDate = PhotoAlbumFormat.reportDateKey(reportDate)
        do {
            let album = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.createAlbum(title: title, reportDate: reportDate, token: $0)
            }
            dismiss()
            onCreated(album)
        } catch {
            message = error.localizedDescription
        }
    }
}
