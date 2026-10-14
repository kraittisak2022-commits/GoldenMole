import ImageIO
import SwiftUI
import UIKit

/// Memory + disk cache for Drive images, decoded off the main thread at display size.
final class PhotoImagePipeline: @unchecked Sendable {
    static let shared = PhotoImagePipeline()

    /// Grid / card thumbnails.
    static let thumbPixels: CGFloat = 640
    /// Full-screen viewer and hero covers.
    static let largePixels: CGFloat = 2400

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 150 * 1024 * 1024
        let config = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PhotoAlbumImages", isDirectory: true)
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 500 * 1024 * 1024,
            directory: directory
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL, maxPixels: CGFloat) -> UIImage? {
        memory.object(forKey: Self.key(url, maxPixels))
    }

    func image(for url: URL, maxPixels: CGFloat) async throws -> UIImage {
        let key = Self.key(url, maxPixels)
        if let hit = memory.object(forKey: key) { return hit }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let image = try await Task.detached(priority: .userInitiated) {
            guard let decoded = PhotoImagePipeline.downsample(data, maxPixels: maxPixels) else {
                throw URLError(.cannotDecodeContentData)
            }
            return decoded
        }.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func key(_ url: URL, _ maxPixels: CGFloat) -> NSString {
        "\(Int(maxPixels))|\(url.absoluteString)" as NSString
    }

    static func downsample(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Remote image

/// Drive image with cache, fade-in, and fallback; `large` shows the cached thumbnail while the big one loads.
struct PhotoRemoteImage: View {
    let sources: PhotoMediaSources
    let large: Bool
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var placeholder: UIImage?
    @State private var loadedFor: PhotoMediaSources?
    @State private var failed = false

    init(sources: PhotoMediaSources, large: Bool = false, contentMode: ContentMode = .fill) {
        self.sources = sources
        self.large = large
        self.contentMode = contentMode
        let pipeline = PhotoImagePipeline.shared
        let hit = Self.primaryURL(sources, large: large).flatMap {
            pipeline.cached($0, maxPixels: Self.maxPixels(large: large))
        }
        _image = State(initialValue: hit)
        _loadedFor = State(initialValue: hit == nil ? nil : sources)
        _placeholder = State(initialValue: large
            ? URL(string: sources.thumb).flatMap { pipeline.cached($0, maxPixels: PhotoImagePipeline.thumbPixels) }
            : nil)
    }

    private static func primaryURL(_ sources: PhotoMediaSources, large: Bool) -> URL? {
        URL(string: large ? sources.large : sources.thumb)
    }

    private static func maxPixels(large: Bool) -> CGFloat {
        large ? PhotoImagePipeline.largePixels : PhotoImagePipeline.thumbPixels
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if let placeholder {
                Image(uiImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(AppTheme.inkMuted)
            } else if large {
                ProgressView()
            } else {
                PhotoShimmer()
            }
        }
        .task(id: sources) { await load() }
    }

    private func load() async {
        if loadedFor == sources, image != nil { return }
        let maxPixels = Self.maxPixels(large: large)
        if let primary = Self.primaryURL(sources, large: large),
           let hit = PhotoImagePipeline.shared.cached(primary, maxPixels: maxPixels) {
            image = hit
            loadedFor = sources
            return
        }
        image = nil
        failed = false
        let candidates = [large ? sources.large : sources.thumb, sources.thumbFallback].compactMap { URL(string: $0) }
        for url in candidates {
            if let loaded = try? await PhotoImagePipeline.shared.image(for: url, maxPixels: maxPixels) {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                loadedFor = sources
                return
            }
            if Task.isCancelled { return }
        }
        failed = true
    }
}

// MARK: - Shimmer placeholder

struct PhotoShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            AppTheme.surfaceSoft
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.28), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width)
                    }
                }
                .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Press feedback

struct PhotoPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Toast

private struct PhotoToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text = message {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
                        .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
                        .padding(.horizontal, AppTheme.spaceXL)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: text) {
                            try? await Task.sleep(for: .seconds(2.2))
                            guard !Task.isCancelled else { return }
                            message = nil
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: message)
    }
}

extension View {
    /// Short auto-hiding status message at the bottom of the screen.
    func photoToast(_ message: Binding<String?>) -> some View {
        modifier(PhotoToastModifier(message: message))
    }
}
