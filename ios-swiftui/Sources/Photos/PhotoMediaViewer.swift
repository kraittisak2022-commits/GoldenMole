import AVFoundation
import AVKit
import Combine
import Photos
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Full-screen viewer

struct PhotoMediaViewer: View {
    @State private var items: [PhotoMediaItem]
    @State private var index: Int
    let canManage: Bool
    /// Each returns an error message, or nil on success.
    let onSetCover: (PhotoMediaItem) async -> String?
    let onDelete: (PhotoMediaItem) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var working = false
    @State private var toast: String?
    @State private var chromeVisible = true
    @State private var zoomed = false
    @State private var dragY: CGFloat = 0

    init(
        items: [PhotoMediaItem],
        startIndex: Int,
        canManage: Bool,
        onSetCover: @escaping (PhotoMediaItem) async -> String?,
        onDelete: @escaping (PhotoMediaItem) async -> String?
    ) {
        _items = State(initialValue: items)
        _index = State(initialValue: startIndex)
        self.canManage = canManage
        self.onSetCover = onSetCover
        self.onDelete = onDelete
    }

    private var currentItem: PhotoMediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    private var showsBottomBar: Bool {
        chromeVisible && currentItem?.isVideo != true
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(dragY / 600, 0.6))
                .ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    page(item, isActive: i == index)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragY)
            .scaleEffect(1 - min(dragY / 2000, 0.12))
            .simultaneousGesture(dismissDrag, including: zoomed ? .subviews : .all)
        }
        .overlay(alignment: .top) {
            if chromeVisible {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomBar {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .photoToast($toast)
        .onChange(of: index) { _, _ in zoomed = false }
        .sensoryFeedback(.selection, trigger: index)
        .confirmationDialog("ลบรายการนี้?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("ลบ", role: .destructive) { Task { await deleteCurrent() } }
        } message: {
            Text("ไฟล์จะถูกย้ายไปถังขยะของ Google Drive (กู้คืนได้ใน 30 วัน)")
        }
    }

    @ViewBuilder
    private func page(_ item: PhotoMediaItem, isActive: Bool) -> some View {
        if item.isVideo {
            PhotoVideoPage(item: item, isActive: isActive)
                .padding(.top, 100)
                .padding(.bottom, 34)
        } else {
            ZoomablePhoto(
                sources: item.src,
                isActive: isActive,
                onZoomChange: { zoomed = $0 },
                onSingleTap: { chromeVisible.toggle() }
            )
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let dy = value.translation.height
                if dragY > 0 || (dy > 0 && dy > abs(value.translation.width) * 1.5) {
                    dragY = max(0, dy)
                }
            }
            .onEnded { value in
                guard dragY > 0 else { return }
                if dragY > 140 || value.predictedEndTranslation.height > 500 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragY = 0 }
                }
            }
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack {
            Text("\(index + 1) / \(items.count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            HStack(spacing: 10) {
                Button { dismiss() } label: { chromeIcon("xmark") }
                    .accessibilityLabel("ปิด")
                Spacer()
                Button { Task { await saveCurrent() } } label: {
                    chromeIcon(working ? "hourglass" : "square.and.arrow.down")
                }
                .disabled(working)
                .accessibilityLabel("บันทึกลงเครื่อง")
                if let item = currentItem, let url = URL(string: item.src.download) {
                    ShareLink(item: url) { chromeIcon("square.and.arrow.up") }
                        .accessibilityLabel("แชร์ลิงก์ดาวน์โหลด")
                }
                if canManage {
                    manageMenu
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.top, AppTheme.spaceSM)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let item = currentItem, let info = PhotoAlbumFormat.mediaInfo(item) {
                Text(info)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, AppTheme.spaceLG)
            }
            if items.count > 1 {
                thumbStrip
            }
        }
        .padding(.top, AppTheme.spaceXL)
        .padding(.bottom, AppTheme.spaceSM)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var thumbStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { index = i } label: {
                            PhotoRemoteImage(sources: item.src)
                                .frame(width: i == index ? 52 : 38, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white, lineWidth: i == index ? 2 : 0)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if item.isVideo {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                    }
                                }
                                .opacity(i == index ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel("ไปที่รายการที่ \(i + 1)")
                    }
                }
                .padding(.horizontal, AppTheme.spaceLG)
                .animation(.easeInOut(duration: 0.2), value: index)
            }
            .frame(height: 52)
            .onAppear { proxy.scrollTo(index, anchor: .center) }
            .onChange(of: index) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func chromeIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.headline)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var manageMenu: some View {
        Menu {
            if currentItem?.isVideo == false {
                Button {
                    Task { await setCover() }
                } label: {
                    Label("ตั้งเป็นรูปปกอัลบั้ม", systemImage: "photo.badge.checkmark")
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("ลบรายการนี้", systemImage: "trash")
            }
        } label: {
            chromeIcon("ellipsis")
        }
        .disabled(working)
        .accessibilityLabel("จัดการรูป")
    }

    // MARK: Actions

    private func saveCurrent() async {
        guard let item = currentItem, !working else { return }
        working = true
        defer { working = false }
        toast = "กำลังบันทึก…"
        do {
            try await PhotoLibrarySaver.save(item)
            toast = item.isVideo ? "บันทึกวิดีโอลงเครื่องแล้ว" : "บันทึกรูปลงเครื่องแล้ว"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func setCover() async {
        guard let item = currentItem else { return }
        working = true
        defer { working = false }
        toast = await onSetCover(item) ?? "ตั้งเป็นรูปปกแล้ว"
    }

    private func deleteCurrent() async {
        guard let item = currentItem else { return }
        working = true
        defer { working = false }
        if let message = await onDelete(item) {
            toast = message
            return
        }
        items.removeAll { $0.id == item.id }
        if items.isEmpty {
            dismiss()
        } else {
            index = min(index, items.count - 1)
        }
    }
}

// MARK: - Video page

/// Streams the Drive file with AVPlayer; Drive's web player is only a fallback for formats iOS can't play.
struct PhotoVideoPage: View {
    let item: PhotoMediaItem
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var failed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                PhotoRemoteImage(sources: item.src, large: true, contentMode: .fit)
                if !failed {
                    Button(action: start) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    .accessibilityLabel("เล่นวิดีโอ")
                }
            }
            if failed {
                VStack(spacing: 10) {
                    Text("เล่นวิดีโอนี้ในแอปไม่ได้")
                        .font(.subheadline.weight(.semibold))
                    if let url = URL(string: item.src.preview ?? item.src.download) {
                        Button("เปิดใน Google Drive") { openURL(url) }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brand)
                    }
                }
                .foregroundStyle(.white)
                .padding(AppTheme.spaceLG)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
            }
        }
        .onChange(of: isActive) { _, active in
            if !active { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func start() {
        guard let url = item.streamURL else {
            failed = true
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: item.mime])
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        newPlayer.play()
        Task {
            for await status in playerItem.publisher(for: \.status).values {
                if status == .failed {
                    player = nil
                    failed = true
                    return
                }
                if status == .readyToPlay { return }
            }
        }
    }
}

// MARK: - Zoomable photo

struct ZoomablePhoto: View {
    let sources: PhotoMediaSources
    let isActive: Bool
    var onZoomChange: (Bool) -> Void = { _ in }
    var onSingleTap: () -> Void = {}

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            PhotoRemoteImage(sources: sources, large: true, contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(panGesture(in: geo.size), including: scale > 1 ? .all : .none)
                .gesture(magnifyGesture(in: geo.size))
                .onTapGesture(count: 2) { toggleZoom() }
                .onTapGesture { onSingleTap() }
        }
        .onChange(of: scale > 1) { _, isZoomed in onZoomChange(isZoomed) }
        .onChange(of: isActive) { _, active in
            if !active { reset() }
        }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clamped(proposed, in: size)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(5, max(1, lastScale * value.magnification))
                offset = clamped(offset, in: size)
            }
            .onEnded { _ in
                if scale <= 1.01 {
                    withAnimation(.spring(duration: 0.3)) { reset() }
                } else {
                    lastScale = scale
                    lastOffset = offset
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.3)) {
            if scale > 1 {
                reset()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = max(0, (size.width * scale - size.width) / 2)
        let maxY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }
}

// MARK: - Save to Photos

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case denied
        case badURL
        case download

        var errorDescription: String? {
            switch self {
            case .denied: return "ไม่ได้รับสิทธิ์บันทึกรูป — เปิดได้ที่ การตั้งค่า › Goldenmole Dashboard › รูปภาพ"
            case .badURL: return "ไม่พบลิงก์ไฟล์"
            case .download: return "ดาวน์โหลดไฟล์จาก Google Drive ไม่สำเร็จ"
            }
        }
    }

    static func save(_ item: PhotoMediaItem) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        guard let source = item.streamURL ?? URL(string: item.src.download) else { throw SaveError.badURL }

        let (downloaded, response) = try await URLSession.shared.download(from: source)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SaveError.download
        }
        let ext = UTType(mimeType: item.mime)?.preferredFilenameExtension ?? (item.isVideo ? "mp4" : "jpg")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.moveItem(at: downloaded, to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let isVideo = item.isVideo
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
        }
    }
}
