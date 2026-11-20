import Foundation
import SwiftUI

extension FeedMedia {
    /// Adapts feed Drive media to the album viewer model.
    func asPhotoMediaItem() -> PhotoMediaItem {
        let payload: [String: Any] = [
            "id": driveFileId,
            "kind": kind,
            "mime": mimeType,
            "name": isVideo ? "video" : "photo",
            "width": width,
            "height": height,
            "takenAt": NSNull(),
            "createdAt": "",
            "uploadedByName": NSNull(),
            "src": [
                "thumb": sources.thumb,
                "thumbFallback": sources.thumbFallback,
                "large": sources.large,
                "download": sources.download,
                "preview": sources.preview as Any,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(PhotoMediaItem.self, from: data)
    }
}

/// Authentic Facebook-style edge-to-edge 1 / 2 / 3 / 4+ media grid for a feed post.
struct FeedMediaGrid: View {
    let media: [FeedMedia]
    var edgeToEdge: Bool = true
    var onTap: (Int) -> Void

    private var shown: [FeedMedia] { Array(media.prefix(4)) }
    private var overflow: Int { max(0, media.count - 4) }

    private var singlePhotoHeight: CGFloat {
        guard let first = shown.first, first.width > 0, first.height > 0 else { return 280 }
        let ratio = CGFloat(first.height) / CGFloat(first.width)
        if ratio > 1.2 { return 360 }
        if ratio < 0.72 { return 235 }
        return 305
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            gridContent
                .background(FeedPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: edgeToEdge ? 0 : 12, style: .continuous))

            if media.count > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(media.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.56)))
                .padding(10)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        switch shown.count {
        case 0:
            EmptyView()
        case 1:
            tile(shown[0], index: 0, height: singlePhotoHeight)
        case 2:
            HStack(spacing: 2) {
                tile(shown[0], index: 0, height: 240)
                tile(shown[1], index: 1, height: 240)
            }
        case 3:
            HStack(spacing: 2) {
                tile(shown[0], index: 0, height: 280)
                VStack(spacing: 2) {
                    tile(shown[1], index: 1, height: 139)
                    tile(shown[2], index: 2, height: 139)
                }
            }
        default:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    tile(shown[0], index: 0, height: 162)
                    tile(shown[1], index: 1, height: 162)
                }
                HStack(spacing: 2) {
                    tile(shown[2], index: 2, height: 162)
                    ZStack {
                        tile(shown[3], index: 3, height: 162)
                        if overflow > 0 {
                            Color.black.opacity(0.48)
                                .allowsHitTesting(false)
                            Text("+\(overflow)")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 162)
                    .clipped()
                }
            }
        }
    }

    private func tile(_ item: FeedMedia, index: Int, height: CGFloat) -> some View {
        Button {
            onTap(index)
        } label: {
            ZStack {
                FeedPalette.surfaceMuted
                PhotoRemoteImage(sources: item.sources, large: shown.count == 1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()

                if item.isVideo {
                    Color.black.opacity(0.18)
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.leading, 3)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Label("วิดีโอ", systemImage: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.56)))
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isVideo ? "วิดีโอ" : "รูปภาพ")
    }
}

struct FeedMediaViewerSheet: View {
    let media: [FeedMedia]
    let startIndex: Int

    var body: some View {
        PhotoMediaViewer(
            items: media.map { $0.asPhotoMediaItem() },
            startIndex: startIndex,
            canManage: false,
            onSetCover: { _ in nil },
            onDelete: { _ in nil }
        )
    }
}
