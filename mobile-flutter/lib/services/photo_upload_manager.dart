import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/admin_user.dart';
import '../utils/photo_album_format.dart';
import '../utils/photo_file_meta.dart';
import 'photo_album_service.dart';

/// A photo or video chosen on the device, before it is uploaded.
class PickedPhotoMedia {
  const PickedPhotoMedia(this.path, this.size);

  final String path;
  final int size;

  String get mimeType => photoMimeTypeForPath(path);
  bool get isVideo => mimeType.startsWith('video/');
  bool get withinLimit => size > 0 && size <= (isVideo ? kPhotoMaxVideoBytes : kPhotoMaxImageBytes);
}

enum PhotoUploadStatus { queued, uploading, done, error, canceled }

class PhotoUploadItem {
  PhotoUploadItem._(this.id, this.admin, this.album, this.media, this.name);

  final String id;
  final AdminUser admin;
  final PhotoAlbumSummary album;
  final PickedPhotoMedia media;

  /// Name given to the file in Drive.
  final String name;

  PhotoUploadStatus status = PhotoUploadStatus.queued;
  double progress = 0;
  String? error;

  /// Set once Drive has the bytes; a retry then only repeats `complete` instead of uploading a second copy.
  String? driveFileId;
  bool _cancelRequested = false;

  bool get isActive => status == PhotoUploadStatus.queued || status == PhotoUploadStatus.uploading;
}

typedef PhotoUploaded = ({String albumId, PhotoMediaItem media});

/// App-wide upload queue (like the web's UploadProvider): keeps going after leaving the album,
/// three files at a time, and holds the screen awake while busy.
class PhotoUploadManager extends ChangeNotifier {
  PhotoUploadManager._();

  static final PhotoUploadManager instance = PhotoUploadManager._();
  static const int concurrency = 3;

  final List<PhotoUploadItem> _items = [];
  final StreamController<PhotoUploaded> _uploaded = StreamController.broadcast();
  int _seq = 0;
  bool _awake = false;
  bool _ownsWakelock = false;

  List<PhotoUploadItem> get items => List.unmodifiable(_items);

  /// Each media item as soon as its upload completes.
  Stream<PhotoUploaded> get uploaded => _uploaded.stream;

  List<PhotoUploadItem> itemsFor(String? albumId) =>
      albumId == null ? items : _items.where((i) => i.album.id == albumId).toList();

  bool isBusy([String? albumId]) => itemsFor(albumId).any((i) => i.isActive);

  void enqueue(AdminUser admin, PhotoAlbumSummary album, List<PickedPhotoMedia> files) {
    if (files.isEmpty) return;
    final now = DateTime.now();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final (_, dotExt) = splitPhotoExtension(f.path.split(RegExp(r'[\\/]')).last);
      final ext = dotExt.isEmpty ? (f.isVideo ? 'mp4' : 'jpg') : dotExt.substring(1).toLowerCase();
      final item = PhotoUploadItem._(
        'u${++_seq}',
        admin,
        album,
        f,
        photoUploadFileName(now, i, ext, video: f.isVideo),
      );
      if (!f.withinLimit) {
        item
          ..status = PhotoUploadStatus.error
          ..error = photoAlbumErrorMessage(f.size <= 0 ? 'empty_file' : 'too_large');
      }
      _items.add(item);
    }
    notifyListeners();
    _pump();
  }

  void retry(String id) {
    final item = _items.where((i) => i.id == id).firstOrNull;
    if (item == null || item.isActive || !item.media.withinLimit) return;
    item
      ..status = PhotoUploadStatus.queued
      ..error = null
      .._cancelRequested = false;
    notifyListeners();
    _pump();
  }

  void retryFailed([String? albumId]) {
    for (final item in itemsFor(albumId)) {
      if (item.status == PhotoUploadStatus.error && item.media.withinLimit) {
        item
          ..status = PhotoUploadStatus.queued
          ..error = null
          .._cancelRequested = false;
      }
    }
    notifyListeners();
    _pump();
  }

  void cancel(String id) {
    final item = _items.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    if (item.status == PhotoUploadStatus.queued) {
      item.status = PhotoUploadStatus.canceled;
      notifyListeners();
      _syncWakelock();
    } else if (item.status == PhotoUploadStatus.uploading) {
      item._cancelRequested = true;
    }
  }

  void clearFinished([String? albumId]) {
    _items.removeWhere((i) => !i.isActive && (albumId == null || i.album.id == albumId));
    notifyListeners();
  }

  void _pump() {
    final active = _items.where((i) => i.status == PhotoUploadStatus.uploading).length;
    final next = _items
        .where((i) => i.status == PhotoUploadStatus.queued)
        .take(math.max(0, concurrency - active))
        .toList();
    for (final item in next) {
      unawaited(_run(item));
    }
    _syncWakelock();
  }

  Future<void> _run(PhotoUploadItem item) async {
    item
      ..status = PhotoUploadStatus.uploading
      ..progress = item.driveFileId == null ? 0 : 1
      ..error = null;
    notifyListeners();

    final session = PhotoAlbumSession.instance;
    final api = session.api;
    try {
      final file = File(item.media.path);
      final meta = await readPhotoFileMeta(file, item.media.mimeType);
      var fileId = item.driveFileId;
      if (fileId == null) {
        final sessionUrl = await session.withToken(
          item.admin,
          (t) => api.startUpload(
            albumId: item.album.id,
            name: item.name,
            mimeType: item.media.mimeType,
            size: item.media.size,
            token: t,
          ),
        );
        var shown = 0.0;
        fileId = await api.uploadFile(
          file: file,
          size: item.media.size,
          sessionUrl: sessionUrl,
          isCanceled: () => item._cancelRequested,
          onProgress: (p) {
            if (p - shown >= 0.01 || p >= 1) {
              shown = p;
              item.progress = p.clamp(0, 0.99);
              notifyListeners();
            }
          },
        );
        item.driveFileId = fileId;
      }
      if (item._cancelRequested) throw const PhotoAlbumException('canceled');
      final media = await session.withToken(
        item.admin,
        (t) => api.completeUpload(
          albumId: item.album.id,
          fileId: fileId!,
          takenAt: meta.takenAt,
          width: meta.width,
          height: meta.height,
          token: t,
        ),
      );
      item
        ..status = PhotoUploadStatus.done
        ..progress = 1;
      _uploaded.add((albumId: item.album.id, media: media));
    } on PhotoAlbumException catch (e) {
      if (item._cancelRequested || e.code == 'canceled') {
        item.status = PhotoUploadStatus.canceled;
      } else {
        item
          ..status = PhotoUploadStatus.error
          ..error = e.code == 'needs_password' ? 'เปิดอัลบั้มแล้วยืนยันรหัสผ่านก่อน แล้วกดลองใหม่' : e.message;
      }
    } catch (_) {
      item
        ..status = PhotoUploadStatus.error
        ..error = 'อัปโหลดไม่สำเร็จ';
    } finally {
      notifyListeners();
      _pump();
    }
  }

  /// Only releases a wakelock this queue took, so another screen's keep-awake survives.
  void _syncWakelock() {
    final busy = isBusy();
    if (busy == _awake) return;
    _awake = busy;
    unawaited(() async {
      try {
        if (busy) {
          if (!await WakelockPlus.enabled) {
            await WakelockPlus.enable();
            _ownsWakelock = true;
          }
        } else if (_ownsWakelock) {
          _ownsWakelock = false;
          await WakelockPlus.disable();
        }
      } catch (_) {}
    }());
  }
}
