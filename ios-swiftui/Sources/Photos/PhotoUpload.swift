import AVFoundation
import Foundation
import ImageIO
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Picked media → file on disk

/// A picked file ready to send: always a temp file we own (deleted after upload).
struct PreparedUpload: Sendable {
    let fileURL: URL
    let name: String
    let mimeType: String
    let size: Int64
    let width: Int
    let height: Int
    let takenAt: Date?
}

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("photo-upload-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum PhotoUploadPreparer {
    /// Formats sent as-is; anything else (HEIC, RAW…) is re-encoded to JPEG so every viewer can show it.
    private static let passthroughImageTypes: [UTType] = [.jpeg, .png, .gif]

    static func isVideo(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) }
    }

    static func prepare(_ item: PhotosPickerItem, index: Int) async throws -> PreparedUpload {
        if isVideo(item) {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw PhotoAlbumError.server("bad_type")
            }
            return try await prepareVideo(at: movie.url, index: index)
        }
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoAlbumError.server("bad_type")
        }
        let passthrough = passthroughImageTypes.first { type in
            item.supportedContentTypes.first?.conforms(to: type) == true
        }
        return try await Task.detached(priority: .userInitiated) {
            try Self.prepareImage(data: data, passthrough: passthrough, index: index)
        }.value
    }

    private static func prepareImage(data: Data, passthrough: UTType?, index: Int) throws -> PreparedUpload {
        let takenAt = exifDate(data)
        let output: Data
        let type: UTType
        let pixelSize: CGSize
        if let passthrough, let image = UIImage(data: data) {
            output = data
            type = passthrough
            pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        } else {
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                throw PhotoAlbumError.server("bad_type")
            }
            output = jpeg
            type = .jpeg
            pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }
        let ext = type.preferredFilenameExtension ?? "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-upload-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try output.write(to: url)
        return PreparedUpload(
            fileURL: url,
            name: fileName(prefix: "IMG", date: takenAt, index: index, ext: ext),
            mimeType: type.preferredMIMEType ?? "image/jpeg",
            size: Int64(output.count),
            width: Int(pixelSize.width.rounded()),
            height: Int(pixelSize.height.rounded()),
            takenAt: takenAt
        )
    }

    private static func prepareVideo(at url: URL, index: Int) async throws -> PreparedUpload {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let ext = url.pathExtension.lowercased()
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "video/quicktime"
        let asset = AVURLAsset(url: url)
        var width = 0
        var height = 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            width = Int(abs(rect.width).rounded())
            height = Int(abs(rect.height).rounded())
        }
        var takenAt: Date?
        if let item = try? await asset.load(.creationDate) {
            takenAt = try? await item.load(.dateValue)
        }
        return PreparedUpload(
            fileURL: url,
            name: fileName(prefix: "VID", date: takenAt, index: index, ext: ext.isEmpty ? "mov" : ext),
            mimeType: mime,
            size: size,
            width: width,
            height: height,
            takenAt: takenAt
        )
    }

    /// EXIF DateTimeOriginal is local wall-clock time; site photos are taken in Thailand.
    private static func exifDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            f.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            return f.date(from: raw + offset)
        }
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: raw)
    }

    private static func fileName(prefix: String, date: Date?, index: Int, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return "\(prefix)_\(f.string(from: date ?? Date()))_\(index + 1).\(ext)"
    }
}

// MARK: - Drive resumable upload (mirrors apps/photo/src/lib/resumable.ts)

enum DriveResumableUploader {
    /// Drive requires chunk sizes in multiples of 256 KiB (except the last chunk).
    static let chunkSize: Int64 = 32 * 256 * 1024
    private static let maxRetries = 6

    /// Sends the file in chunks; after a network error or 5xx asks Drive how much it has and resumes.
    /// Returns the Drive file id.
    static func upload(
        fileURL: URL,
        size: Int64,
        to sessionURL: URL,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var offset: Int64 = 0
        var attempt = 0

        while true {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, size)
            try handle.seek(toOffset: UInt64(offset))
            let chunk = try handle.read(upToCount: Int(end - offset)) ?? Data()
            let res = await put(sessionURL, body: chunk, contentRange: "bytes \(offset)-\(end - 1)/\(size)")

            if res.status == 200 || res.status == 201 {
                await onProgress(1)
                return try fileId(from: res.data)
            }
            if res.status == 308 {
                offset = res.range.map(nextOffset) ?? end
                attempt = 0
                await onProgress(Double(offset) / Double(max(size, 1)))
                continue
            }
            if res.status == 404 || res.status == 410 { throw PhotoAlbumError.server("upload_expired") }
            let retryable = res.status == 0 || res.status == 429 || res.status >= 500
            guard retryable, attempt < maxRetries else { throw PhotoAlbumError.server("upload_failed") }

            let delayMs = min(1000 * (1 << attempt), 30_000)
            attempt += 1
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            let status = await put(sessionURL, body: Data(), contentRange: "bytes */\(size)")
            if status.status == 200 || status.status == 201 {
                await onProgress(1)
                return try fileId(from: status.data)
            }
            if status.status == 404 || status.status == 410 { throw PhotoAlbumError.server("upload_expired") }
            if status.status == 308 { offset = status.range.map(nextOffset) ?? 0 }
        }
    }

    /// `bytes=0-1048575` → 1048576 (next byte to send).
    private static func nextOffset(_ range: String) -> Int64 {
        guard let dash = range.lastIndex(of: "-"), let last = Int64(range[range.index(after: dash)...]) else { return 0 }
        return last + 1
    }

    private static func fileId(from data: Data) throws -> String {
        struct DriveFile: Decodable { let id: String }
        guard let file = try? JSONDecoder().decode(DriveFile.self, from: data) else {
            throw PhotoAlbumError.server("upload_failed")
        }
        return file.id
    }

    private static func put(_ url: URL, body: Data, contentRange: String) async -> (status: Int, data: Data, range: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentRange, forHTTPHeaderField: "Content-Range")
        request.timeoutInterval = 120
        guard let result = try? await URLSession.shared.upload(for: request, from: body),
              let http = result.1 as? HTTPURLResponse
        else { return (0, Data(), nil) }
        return (http.statusCode, result.0, http.value(forHTTPHeaderField: "Range"))
    }
}

// MARK: - Upload queue (one album, files sent one at a time)

@MainActor
@Observable
final class PhotoUploadQueue {
    enum JobState: Equatable {
        case waiting
        case uploading(Double)
        case done
        case failed(String)
    }

    struct Job: Identifiable {
        let id = UUID()
        let item: PhotosPickerItem
        let index: Int
        let isVideo: Bool
        var state: JobState = .waiting
    }

    let albumId: String
    private(set) var jobs: [Job] = []
    @ObservationIgnored var onUploaded: ((PhotoMediaItem) -> Void)?
    @ObservationIgnored private var runner: Task<Void, Never>?

    init(albumId: String) {
        self.albumId = albumId
    }

    var isRunning: Bool { runner != nil }
    var doneCount: Int { jobs.filter { $0.state == .done }.count }
    var failedCount: Int { jobs.filter { if case .failed = $0.state { return true } else { return false } }.count }
    var hasActiveJobs: Bool { jobs.contains { $0.state != .done && !isFailed($0.state) } }

    /// Overall progress across all jobs, 0…1.
    var progress: Double {
        guard !jobs.isEmpty else { return 0 }
        let sum = jobs.reduce(0.0) { total, job in
            switch job.state {
            case .done: return total + 1
            case .uploading(let p): return total + p
            default: return total
            }
        }
        return sum / Double(jobs.count)
    }

    func enqueue(_ items: [PhotosPickerItem], admin: AdminUser) {
        let start = jobs.count
        jobs += items.enumerated().map { offset, item in
            Job(item: item, index: start + offset, isVideo: PhotoUploadPreparer.isVideo(item))
        }
        run(admin: admin)
    }

    func retryFailed(admin: AdminUser) {
        for i in jobs.indices where isFailed(jobs[i].state) {
            jobs[i].state = .waiting
        }
        run(admin: admin)
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.state == .done || isFailed($0.state) }
    }

    func cancelAll() {
        runner?.cancel()
        runner = nil
        jobs.removeAll { $0.state != .done }
    }

    private func isFailed(_ state: JobState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func run(admin: AdminUser) {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            let background = UIApplication.shared.beginBackgroundTask(withName: "photo-upload")
            defer { UIApplication.shared.endBackgroundTask(background) }
            while let self, !Task.isCancelled, let i = self.jobs.firstIndex(where: { $0.state == .waiting }) {
                await self.upload(jobAt: i, admin: admin)
            }
            self?.runner = nil
        }
    }

    private func upload(jobAt i: Int, admin: AdminUser) async {
        let jobId = jobs[i].id
        func update(_ state: JobState) {
            if let j = jobs.firstIndex(where: { $0.id == jobId }) { jobs[j].state = state }
        }
        update(.uploading(0))
        var prepared: PreparedUpload?
        do {
            let file = try await PhotoUploadPreparer.prepare(jobs[i].item, index: jobs[i].index)
            prepared = file
            let albumId = albumId
            let sessionURL = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.startUpload(
                    albumId: albumId,
                    name: file.name,
                    mimeType: file.mimeType,
                    size: file.size,
                    token: $0
                )
            }
            let fileId = try await DriveResumableUploader.upload(fileURL: file.fileURL, size: file.size, to: sessionURL) { p in
                update(.uploading(min(0.99, p)))
            }
            let media = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.completeUpload(
                    albumId: albumId,
                    fileId: fileId,
                    width: file.width,
                    height: file.height,
                    takenAt: file.takenAt,
                    token: $0
                )
            }
            update(.done)
            onUploaded?(media)
        } catch is CancellationError {
            update(.waiting)
        } catch {
            update(.failed(error.localizedDescription))
        }
        if let prepared { try? FileManager.default.removeItem(at: prepared.fileURL) }
    }
}
