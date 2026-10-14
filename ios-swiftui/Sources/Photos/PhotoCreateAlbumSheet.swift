import Photos
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Create album (mirrors the web CreateAlbumDialog)

/// «อัลบั้มใหม่»: name, pick photos/videos before the album exists, report date.
/// With files it creates, starts uploading and opens the album; without files it shows the share card.
struct PhotoCreateAlbumSheet: View {
    let onCreated: (PhotoAlbumSummary) -> Void
    let onOpen: (PhotoAlbumSummary, [PhotosPickerItem]) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var reportDate = Date()
    @State private var items: [PhotosPickerItem] = []
    @State private var titleError: String?
    @State private var message: String?
    @State private var busy = false
    @State private var created: PhotoAlbumSummary?
    @FocusState private var titleFocused: Bool

    init(
        onCreated: @escaping (PhotoAlbumSummary) -> Void,
        onOpen: @escaping (PhotoAlbumSummary, [PhotosPickerItem]) -> Void
    ) {
        self.onCreated = onCreated
        self.onOpen = onOpen
    }

    private var cleanTitle: String { PhotoAlbumFormat.normalizedTitle(title) }
    private var reportKey: String { PhotoAlbumFormat.reportDateKey(reportDate) }
    private var titleTooLong: Bool { cleanTitle.count > PhotoAlbumFormat.maxTitleLength }

    private var dateHint: String {
        let longDate = DashboardAggregations.thaiDateLong(reportKey)
        return "\(longDate) · เก็บใน \(PhotoAlbumFormat.drivePath(reportKey)) · คนที่มีลิงก์เพิ่มรูปได้"
    }

    private var mediaSummary: String? {
        guard !items.isEmpty else { return nil }
        let videos = items.filter { PhotoUploadPreparer.isVideo($0) }.count
        let photos = items.count - videos
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) รูป") }
        if videos > 0 { parts.append("\(videos) วิดีโอ") }
        return parts.joined(separator: " · ")
    }

    private var submitTitle: String {
        if busy { return "กำลังสร้าง…" }
        return items.isEmpty ? "สร้างอัลบั้ม" : "สร้างและอัปโหลด \(items.count) รายการ"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    successView(created)
                } else {
                    formView
                }
            }
            .background(DashboardBackground())
            .navigationTitle(created == nil ? "อัลบั้มใหม่" : "สร้างอัลบั้มแล้ว")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
        .sensoryFeedback(.success, trigger: created?.id)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(created == nil ? "ยกเลิก" : "ปิด") { dismiss() }
                .disabled(busy)
        }
    }

    // MARK: Form

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                titleCard
                mediaCard
                dateCard
                if let message {
                    errorBanner(message)
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { submitBar }
    }

    private var titleCard: some View {
        formCard("ชื่อรายงาน", trailing: "\(cleanTitle.count)/\(PhotoAlbumFormat.maxTitleLength)", trailingIsError: titleTooLong) {
            TextField("เช่น เทปูนชั้น 2 อาคาร A", text: $title)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(12)
                .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                        .strokeBorder(titleError == nil ? Color.clear : AppTheme.expense, lineWidth: 1.5)
                )
                .onChange(of: title) { _, _ in titleError = nil }
                .disabled(busy)
            if let titleError {
                Label(titleError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.expense)
            }
        }
    }

    private var mediaCard: some View {
        formCard("รูปและวิดีโอ", trailing: mediaSummary) {
            PhotoPickedMediaGrid(items: $items)
                .disabled(busy)
            Text(items.isEmpty
                 ? "เลือกไว้ก่อนได้เลย ระบบจะอัปโหลดให้ทันทีหลังสร้างอัลบั้ม"
                 : "ระหว่างอัปโหลดเปิดหน้าอื่นในแอปได้ · เลือกได้สูงสุด 100 รายการต่อครั้ง")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
    }

    private var dateCard: some View {
        formCard("วันที่รายงาน", trailing: nil) {
            HStack(spacing: 8) {
                quickDate("วันนี้", daysAgo: 0)
                quickDate("เมื่อวาน", daysAgo: 1)
                Spacer(minLength: 0)
                DatePicker("วันที่รายงาน", selection: $reportDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "th_TH"))
                    .environment(\.calendar, Calendar(identifier: .buddhist))
            }
            .disabled(busy)
            Text(dateHint)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
    }

    private func quickDate(_ label: String, daysAgo: Int) -> some View {
        let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let isSelected = PhotoAlbumFormat.reportDateKey(target) == reportKey
        return Button { reportDate = target } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : AppTheme.brand)
                .background(isSelected ? AppTheme.brand : AppTheme.brand.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func formCard<Content: View>(
        _ title: String,
        trailing: String?,
        trailingIsError: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(trailingIsError ? AppTheme.expense : AppTheme.inkMuted)
                }
            }
            content()
        }
        .padding(AppTheme.spaceLG)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.expense)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.expense.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
    }

    private var submitBar: some View {
        Button { Task { await submit() } } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(Color.white)
                } else {
                    Image(systemName: items.isEmpty ? "plus.circle.fill" : "arrow.up.circle.fill")
                }
                Text(submitTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Color.white)
            .background(AppTheme.brand, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
        }
        .buttonStyle(PhotoPressableStyle())
        .disabled(busy)
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, AppTheme.spaceSM)
        .background(.regularMaterial)
    }

    private func submit() async {
        guard !busy else { return }
        let clean = cleanTitle
        guard !clean.isEmpty else {
            titleError = "ตั้งชื่อรายงาน"
            titleFocused = true
            return
        }
        guard clean.count <= PhotoAlbumFormat.maxTitleLength else {
            titleError = "ชื่อยาวเกิน \(PhotoAlbumFormat.maxTitleLength) ตัวอักษร"
            return
        }
        guard let admin = auth.currentAdmin else { return }
        titleFocused = false
        busy = true
        message = nil
        defer { busy = false }
        let key = reportKey
        do {
            let album = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.createAlbum(title: clean, reportDate: key, token: $0)
            }
            onCreated(album)
            if items.isEmpty {
                withAnimation(.snappy) { created = album }
            } else {
                let uploads = items
                dismiss()
                onOpen(album, uploads)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Created (no files picked)

    private func successView(_ album: PhotoAlbumSummary) -> some View {
        ScrollView {
            VStack(spacing: AppTheme.spaceLG) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.income)
                        .symbolEffect(.bounce, value: album.id)
                    Text(album.title)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    Label(PhotoAlbumFormat.drivePath(album.reportDate), systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(.top, AppTheme.spaceMD)
                PhotoShareCard(title: album.title, shareUrl: album.shareUrl, driveFolderUrl: album.driveFolderUrl)
            }
            .padding(AppTheme.spaceLG)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("ปิด") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button {
                    dismiss()
                    onOpen(album, [])
                } label: {
                    Label("เปิดอัลบั้มและเพิ่มรูป", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brand)
                .controlSize(.large)
            }
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.vertical, AppTheme.spaceSM)
            .background(.regularMaterial)
        }
    }
}

// MARK: - Picked media grid (mirrors the web MediaPicker)

/// Photos/videos chosen before the album exists; tap ✕ to drop one, "+N" past the preview limit.
struct PhotoPickedMediaGrid: View {
    @Binding var items: [PhotosPickerItem]
    @State private var thumbs: [String: UIImage] = [:]

    /// Decoding every full-size photo would exhaust memory; the rest are counted in a "+N" tile.
    private static let maxPreviews = 30
    private static let maxSelection = 100
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    private var previewed: [PhotosPickerItem] { Array(items.prefix(Self.maxPreviews)) }
    private var hiddenCount: Int { max(0, items.count - Self.maxPreviews) }
    private var previewKeys: [String] { previewed.map { Self.key($0) } }

    private static func key(_ item: PhotosPickerItem) -> String {
        item.itemIdentifier ?? "\(item.hashValue)"
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            PhotosPicker(
                selection: $items,
                maxSelectionCount: Self.maxSelection,
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            ) {
                addTile
            }
            .buttonStyle(.plain)
            .accessibilityLabel(items.isEmpty ? "เลือกรูปและวิดีโอ" : "เพิ่มรูปและวิดีโออีก")
            ForEach(previewed, id: \.self) { item in
                tile(item)
            }
            if hiddenCount > 0 {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Text("+\(hiddenCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .animation(.snappy, value: items)
        .task(id: previewKeys) { await loadThumbs() }
    }

    private var addTile: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                    Text(items.isEmpty ? "เลือก" : "เพิ่มอีก")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppTheme.brand)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.brand.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.brand.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tile(_ item: PhotosPickerItem) -> some View {
        let isVideo = PhotoUploadPreparer.isVideo(item)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbLayer(item, isVideo: isVideo) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) { removeButton(item) }
    }

    @ViewBuilder
    private func thumbLayer(_ item: PhotosPickerItem, isVideo: Bool) -> some View {
        if let image = thumbs[Self.key(item)] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                AppTheme.surfaceSoft
                Image(systemName: isVideo ? "film" : "photo")
                    .font(.title3.weight(.light))
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private func removeButton(_ item: PhotosPickerItem) -> some View {
        Button {
            items.removeAll { $0 == item }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.6), in: Circle())
                .padding(4)
                .frame(width: 40, height: 40, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เอาออก")
    }

    /// One at a time so a 30-photo selection never holds 30 full-size images in memory.
    private func loadThumbs() async {
        for item in previewed {
            let key = Self.key(item)
            guard thumbs[key] == nil, !PhotoUploadPreparer.isVideo(item) else { continue }
            if Task.isCancelled { return }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let image = await Task.detached(priority: .utility) {
                PhotoImagePipeline.downsample(data, maxPixels: 240)
            }.value
            if let image { thumbs[key] = image }
        }
    }
}

// MARK: - Share card (mirrors the web ShareCard)

/// Preview of exactly what will be pasted into the group, with Copy, Share and Open-in-Drive.
struct PhotoShareCard: View {
    let title: String
    let shareUrl: String
    let driveFolderUrl: String

    @State private var copied = false

    private var shareText: String { PhotoAlbumFormat.shareText(title: title, url: shareUrl) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ข้อความที่จะคัดลอก")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            preview
            Text("ทุกคนที่มีลิงก์ดูรูปได้ โดยไม่ต้องเข้าสู่ระบบ")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
            Button(action: copy) {
                actionLabel(
                    copied ? "คัดลอกแล้ว" : "คัดลอกชื่อรายงาน + ลิงก์",
                    systemImage: copied ? "checkmark" : "doc.on.doc",
                    filled: true
                )
            }
            .buttonStyle(PhotoPressableStyle())
            HStack(spacing: 10) {
                ShareLink(item: shareText) {
                    actionLabel("แชร์", systemImage: "square.and.arrow.up", filled: false)
                }
                .buttonStyle(PhotoPressableStyle())
                if let drive = URL(string: driveFolderUrl) {
                    Link(destination: drive) {
                        actionLabel("เปิดใน Google Drive", systemImage: "arrow.up.right.square", filled: false)
                    }
                    .buttonStyle(PhotoPressableStyle())
                }
            }
        }
        .padding(AppTheme.spaceLG)
        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous))
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(shareUrl)
                .font(.subheadline)
                .foregroundStyle(AppTheme.brand)
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
    }

    private func actionLabel(_ text: String, systemImage: String, filled: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(filled ? Color.white : AppTheme.brand)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .fill(filled ? (copied ? AppTheme.income : AppTheme.brand) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                    .strokeBorder(filled ? Color.clear : AppTheme.brand.opacity(0.35), lineWidth: 1)
            )
    }

    private func copy() {
        UIPasteboard.general.string = shareText
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { copied = false }
        }
    }
}
