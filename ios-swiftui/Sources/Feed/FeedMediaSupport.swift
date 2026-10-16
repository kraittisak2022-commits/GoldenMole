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

/// Facebook-style 1 / 2 / 3 / 4+ media grid for a feed post.
struct FeedMediaGrid: View {
    let media: [FeedMedia]
    var onTap: (Int) -> Void

    private var shown: [FeedMedia] { Array(media.prefix(4)) }
    private var overflow: Int { max(0, media.count - 4) }

    var body: some View {
        Group {
            switch shown.count {
            case 0:
                EmptyView()
            case 1:
                tile(shown[0], index: 0, height: 260)
            case 2:
                HStack(spacing: 2) {
                    tile(shown[0], index: 0, height: 200)
                    tile(shown[1], index: 1, height: 200)
                }
            case 3:
                HStack(spacing: 2) {
                    tile(shown[0], index: 0, height: 220)
                    VStack(spacing: 2) {
                        tile(shown[1], index: 1, height: 109)
                        tile(shown[2], index: 2, height: 109)
                    }
                }
            default:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(shown[0], index: 0, height: 140)
                        tile(shown[1], index: 1, height: 140)
                    }
                    HStack(spacing: 2) {
                        tile(shown[2], index: 2, height: 140)
                        ZStack {
                            tile(shown[3], index: 3, height: 140)
                            if overflow > 0 {
                                Color.black.opacity(0.45)
                                Text("+\(overflow)")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tile(_ item: FeedMedia, index: Int, height: CGFloat) -> some View {
        Button {
            onTap(index)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                PhotoRemoteImage(sources: item.sources, large: false, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
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
