import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/admin_user.dart';
import '../utils/photo_album_format.dart';
import 'session_service.dart';

/// PIN ก่อนเข้าเมนูอัลบั้มในหน้าบันทึกประจำวัน
const String kPhotoAlbumMenuPin = '8888';

bool photoAlbumPinMatches(String input) => input.trim() == kPhotoAlbumMenuPin;

/// แก้ไข/ลบอัลบั้มและรูป — เซิร์ฟเวอร์บังคับสิทธิ์เดียวกัน (`requireStaff({ superAdmin: true })`)
bool canManagePhotoAlbums(AdminUser admin) => admin.role.trim() == 'SuperAdmin';

// MARK: - Models (mirror apps/photo/shared/types.ts)

class PhotoMediaSources {
  const PhotoMediaSources({
    required this.thumb,
    required this.thumbFallback,
    required this.large,
    required this.download,
    this.preview,
  });

  final String thumb;
  final String thumbFallback;
  final String large;
  final String download;

  /// Drive player — videos only.
  final String? preview;

  factory PhotoMediaSources.fromJson(Map<String, dynamic> json) {
    return PhotoMediaSources(
      thumb: (json['thumb'] ?? '').toString(),
      thumbFallback: (json['thumbFallback'] ?? '').toString(),
      large: (json['large'] ?? '').toString(),
      download: (json['download'] ?? '').toString(),
      preview: json['preview']?.toString(),
    );
  }
}

class PhotoMediaItem {
  const PhotoMediaItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAt,
    required this.src,
    this.mime = '',
    this.width = 0,
    this.height = 0,
    this.takenAt,
    this.uploadedByName,
  });

  final String id;
  final String kind;
  final String mime;
  final String name;
  final int width;
  final int height;
  final String? takenAt;
  final String createdAt;
  final String? uploadedByName;
  final PhotoMediaSources src;

  bool get isVideo => kind == 'video';

  /// Drive file id, taken from the download URL.
  String? get driveFileId => Uri.tryParse(src.download)?.queryParameters['id'];

  /// Direct file download (follows Drive's large-file confirmation). Album folders are link-shared.
  Uri? get directDownloadUrl {
    final id = driveFileId;
    if (id == null || id.isEmpty) return null;
    return Uri.https('drive.usercontent.google.com', '/download', {
      'id': id,
      'export': 'download',
      'confirm': 't',
    });
  }

  factory PhotoMediaItem.fromJson(Map<String, dynamic> json) {
    return PhotoMediaItem(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? 'image').toString(),
      mime: (json['mime'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      takenAt: json['takenAt']?.toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      uploadedByName: json['uploadedByName']?.toString(),
      src: PhotoMediaSources.fromJson(_map(json['src'])),
    );
  }
}

List<PhotoMediaItem> sortPhotoMediaItems(Iterable<PhotoMediaItem> media) =>
    sortPhotoMedia(media, takenAt: (m) => m.takenAt, createdAt: (m) => m.createdAt);

class PhotoAlbumSummary {
  const PhotoAlbumSummary({
    required this.id,
    required this.title,
    required this.reportDate,
    required this.mediaCount,
    required this.shareUrl,
    required this.driveFolderUrl,
    this.cover,
    this.allowLinkUpload = true,
  });

  final String id;
  final String title;

  /// YYYY-MM-DD
  final String reportDate;
  final int mediaCount;
  final PhotoMediaSources? cover;
  final String shareUrl;
  final String driveFolderUrl;

  /// คนที่มีลิงก์แชร์เพิ่มรูปได้
  final bool allowLinkUpload;

  /// ข้อความคัดลอกไปวางในกลุ่ม — ชื่ออัลบั้ม แล้วลิงก์ (เหมือนเว็บ)
  String get shareText => '$title\n$shareUrl';

  factory PhotoAlbumSummary.fromJson(Map<String, dynamic> json) {
    final cover = json['cover'];
    return PhotoAlbumSummary(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      reportDate: (json['reportDate'] ?? '').toString(),
      mediaCount: (json['mediaCount'] as num?)?.toInt() ?? 0,
      cover: cover is Map ? PhotoMediaSources.fromJson(_map(cover)) : null,
      shareUrl: (json['shareUrl'] ?? '').toString(),
      driveFolderUrl: (json['driveFolderUrl'] ?? '').toString(),
      allowLinkUpload: json['allowLinkUpload'] != false,
    );
  }
}

class PhotoAlbumDetail {
  const PhotoAlbumDetail({required this.album, required this.media});

  final PhotoAlbumSummary album;
  final List<PhotoMediaItem> media;

  factory PhotoAlbumDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['media'];
    return PhotoAlbumDetail(
      album: PhotoAlbumSummary.fromJson(json),
      media: raw is List
          ? raw.whereType<Map>().map((m) => PhotoMediaItem.fromJson(_map(m))).toList()
          : const [],
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

// MARK: - Errors

class PhotoAlbumException implements Exception {
  const PhotoAlbumException(this.code, [this.detail]);

  /// Server error code (`unauthorized`, `forbidden`, `drive_not_connected`…), or `network` / `needs_password`.
  final String code;
  final String? detail;

  String get message => photoAlbumErrorMessage(code, detail);

  @override
  String toString() => 'PhotoAlbumException($code${detail == null ? '' : ': $detail'})';
}

String photoAlbumErrorMessage(String code, [String? detail]) {
  switch (code) {
    case 'needs_password':
    case 'unauthorized':
      return 'กรุณายืนยันรหัสผ่านเพื่อเข้าอัลบั้ม';
    case 'bad_credentials':
      return 'รหัสผ่านไม่ถูกต้อง';
    case 'forbidden':
      return 'บัญชีนี้ไม่มีสิทธิ์ใช้อัลบั้ม — ขอสิทธิ์ «อัลบั้มรูป» จาก SuperAdmin';
    case 'too_many_attempts':
      return 'ใส่รหัสผิดหลายครั้ง — รอ 15 นาทีแล้วลองใหม่';
    case 'not_found':
      return 'ไม่พบอัลบั้มนี้ (อาจถูกลบแล้ว)';
    case 'network':
      return 'เชื่อมต่อ GoldenMole Photos ไม่ได้ — ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    case 'drive_not_connected':
      return 'ยังไม่ได้เชื่อม Google Drive — ให้ SuperAdmin เชื่อมที่เว็บ GoldenMole Photos (ตั้งค่า)';
    case 'drive_error':
      return 'Google Drive ขัดข้อง — ลองใหม่อีกครั้ง';
    case 'bad_type':
      return 'รองรับเฉพาะรูปและวิดีโอ';
    case 'too_large':
      return 'ไฟล์ใหญ่เกินไป (รูปไม่เกิน 50 MB · วิดีโอไม่เกิน 2 GB)';
    case 'upload_disabled':
      return 'อัลบั้มนี้ปิดการเพิ่มรูปผ่านลิงก์';
    case 'empty_file':
      return 'ไฟล์ว่าง';
    case 'bad_request':
      return 'ข้อมูลไม่ถูกต้อง';
    case 'wrong_folder':
      return 'ไฟล์ไม่ได้อยู่ในโฟลเดอร์ของอัลบั้มนี้';
    case 'upload_expired':
      return 'การอัปโหลดหมดเวลา — ลองใหม่';
    case 'upload_failed':
      return 'อัปโหลดไม่สำเร็จ — ลองใหม่';
    default:
      return 'GoldenMole Photos ขัดข้อง ($code)';
  }
}

// MARK: - Helpers

const Map<String, String> _kMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
};

const int kPhotoMaxImageBytes = 50 * 1024 * 1024;
const int kPhotoMaxVideoBytes = 2 * 1024 * 1024 * 1024;

bool photoPathIsVideo(String path) => photoMimeTypeForPath(path).startsWith('video/');

/// MIME จากนามสกุลไฟล์ — ไม่รู้จักให้ถือเป็น JPEG (กล้อง/แกลเลอรีส่วนใหญ่)
String photoMimeTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return _kMimeByExtension[ext] ?? 'image/jpeg';
}

/// Drive `Range: bytes=0-1048575` → 1048576 (next byte to send).
int driveNextOffset(String? range) {
  if (range == null) return 0;
  final dash = range.lastIndexOf('-');
  if (dash < 0) return 0;
  final last = int.tryParse(range.substring(dash + 1).trim());
  return last == null ? 0 : last + 1;
}

String photoUploadFileName(DateTime now, int index, String ext, {bool video = false}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return '${video ? 'VID' : 'IMG'}_${stamp}_${index + 1}.$ext';
}

// MARK: - API (photo.goldenmole.pro Vercel functions)

class PhotoAlbumApi {
  PhotoAlbumApi({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://photo.goldenmole.pro/api';

  /// Drive requires chunk sizes in multiples of 256 KiB (except the last chunk).
  static const int chunkSize = 32 * 256 * 1024;
  static const int _maxRetries = 6;

  final http.Client _client;

  Future<String> login(String username, String password) async {
    final body = await _send('POST', 'auth/login', json: {
      'username': username,
      'password': password,
    });
    return (body['token'] ?? '').toString();
  }

  /// Renewed session token (the server extends it by 30 days).
  Future<String> renew(String token) async {
    final body = await _send('GET', 'auth/me', token: token);
    return (body['token'] ?? '').toString();
  }

  Future<List<PhotoAlbumSummary>> albums(String token) async {
    final body = await _send('GET', 'albums', token: token);
    final list = body['_list'];
    return list is List
        ? list.whereType<Map>().map((m) => PhotoAlbumSummary.fromJson(_map(m))).toList()
        : const [];
  }

  Future<PhotoAlbumDetail> album(String id, String token) async {
    return PhotoAlbumDetail.fromJson(await _send('GET', 'albums/$id', token: token));
  }

  /// `reportDate` is YYYY-MM-DD; the server creates the Drive folder under year/month.
  Future<PhotoAlbumSummary> createAlbum({
    required String title,
    required String reportDate,
    required String token,
  }) async {
    return PhotoAlbumSummary.fromJson(await _send(
      'POST',
      'albums',
      token: token,
      json: {'title': title, 'reportDate': reportDate},
    ));
  }

  /// SuperAdmin only. Sends just the fields given; renaming or changing the date also moves the Drive folder.
  Future<PhotoAlbumDetail> updateAlbum(
    String id,
    String token, {
    String? title,
    String? reportDate,
    bool? allowLinkUpload,
    bool regenerateLink = false,
    String? coverMediaId,
  }) async {
    return PhotoAlbumDetail.fromJson(await _send('PATCH', 'albums/$id', token: token, json: {
      'title': ?title,
      'reportDate': ?reportDate,
      'allowLinkUpload': ?allowLinkUpload,
      if (regenerateLink) 'regenerateLink': true,
      'coverMediaId': ?coverMediaId,
    }));
  }

  /// SuperAdmin only. The Drive folder goes to the Drive trash (restorable for 30 days).
  Future<void> deleteAlbum(String id, String token) async {
    await _send('DELETE', 'albums/$id', token: token);
  }

  /// SuperAdmin only. The file goes to the Drive trash (restorable for 30 days).
  Future<void> deleteMedia(String id, String token) async {
    await _send('DELETE', 'media/$id', token: token);
  }

  /// Drive resumable upload session URL for one file.
  Future<Uri> startUpload({
    required String albumId,
    required String name,
    required String mimeType,
    required int size,
    required String token,
  }) async {
    final body = await _send('POST', 'uploads/start', token: token, json: {
      'albumId': albumId,
      'name': name,
      'mimeType': mimeType,
      'size': size,
    });
    final url = Uri.tryParse((body['uploadUrl'] ?? '').toString());
    if (url == null || !url.hasScheme) throw const PhotoAlbumException('upload_failed');
    return url;
  }

  /// Width/height 0 → the server reads them from Drive (with EXIF rotation applied).
  Future<PhotoMediaItem> completeUpload({
    required String albumId,
    required String fileId,
    required String token,
    String? takenAt,
  }) async {
    return PhotoMediaItem.fromJson(await _send('POST', 'uploads/complete', token: token, json: {
      'albumId': albumId,
      'fileId': fileId,
      'width': 0,
      'height': 0,
      'takenAt': takenAt,
    }));
  }

  /// SuperAdmin only. Renames in Drive too (extension kept); null uploader name or date clears it.
  Future<PhotoMediaItem> updateMedia(
    String id,
    String token, {
    required String name,
    required String? uploadedByName,
    required String? takenAt,
  }) async {
    return PhotoMediaItem.fromJson(await _send('PATCH', 'media/$id', token: token, json: {
      'name': name,
      'uploadedByName': uploadedByName,
      'takenAt': takenAt,
    }));
  }

  /// Sends the file in chunks; after a network error or 5xx asks Drive how much it has and resumes.
  /// Returns the Drive file id.
  Future<String> uploadFile({
    required File file,
    required int size,
    required Uri sessionUrl,
    void Function(double progress)? onProgress,
  }) async {
    final raf = await file.open();
    try {
      var offset = 0;
      var attempt = 0;
      while (true) {
        final end = math.min(offset + chunkSize, size);
        await raf.setPosition(offset);
        final chunk = await raf.read(end - offset);
        var res = await _put(sessionUrl, chunk, 'bytes $offset-${end - 1}/$size');

        if (res.status == 200 || res.status == 201) {
          onProgress?.call(1);
          return _driveFileId(res.body);
        }
        if (res.status == 308) {
          offset = res.range == null ? end : driveNextOffset(res.range);
          attempt = 0;
          onProgress?.call(offset / math.max(size, 1));
          continue;
        }
        if (res.status == 404 || res.status == 410) throw const PhotoAlbumException('upload_expired');
        final retryable = res.status == 0 || res.status == 429 || res.status >= 500;
        if (!retryable || attempt >= _maxRetries) throw const PhotoAlbumException('upload_failed');

        await Future<void>.delayed(Duration(milliseconds: math.min(1000 * (1 << attempt), 30000)));
        attempt++;
        res = await _put(sessionUrl, const [], 'bytes */$size');
        if (res.status == 200 || res.status == 201) {
          onProgress?.call(1);
          return _driveFileId(res.body);
        }
        if (res.status == 404 || res.status == 410) throw const PhotoAlbumException('upload_expired');
        if (res.status == 308) offset = driveNextOffset(res.range);
      }
    } finally {
      await raf.close();
    }
  }

  String _driveFileId(String body) {
    try {
      final decoded = jsonDecode(body);
      final id = decoded is Map ? decoded['id']?.toString() : null;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    throw const PhotoAlbumException('upload_failed');
  }

  Future<({int status, String body, String? range})> _put(
    Uri url,
    List<int> body,
    String contentRange,
  ) async {
    try {
      final res = await _client
          .put(url, headers: {'Content-Range': contentRange}, body: body)
          .timeout(const Duration(seconds: 120));
      return (status: res.statusCode, body: res.body, range: res.headers['range']);
    } catch (_) {
      return (status: 0, body: '', range: null);
    }
  }

  /// JSON object response; a top-level array is returned under `_list`.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? json,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl/$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 25)),
      );
    } catch (e) {
      throw PhotoAlbumException('network', e.toString());
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code = decoded is Map ? decoded['error']?.toString() : null;
      throw PhotoAlbumException(code ?? 'http_${res.statusCode}');
    }
    if (decoded is List) return {'_list': decoded};
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const PhotoAlbumException('decode');
  }
}

// MARK: - Session (photo-site token per admin, kept in secure storage)

class PhotoAlbumSession {
  PhotoAlbumSession._();

  static final PhotoAlbumSession instance = PhotoAlbumSession._();

  static const _keyPrefix = 'gm_photo_session_';
  static const _storage = FlutterSecureStorage();

  final PhotoAlbumApi api = PhotoAlbumApi();
  final Set<String> _renewedAdminIds = {};

  static String _profileId(AdminUser admin) => admin.id.trim().isNotEmpty
      ? admin.id.trim()
      : 'user_${admin.username.trim().toLowerCase()}';

  Future<String> signIn(AdminUser admin, String password) async {
    final token = await api.login(admin.username, password);
    await _store(admin, token);
    _renewedAdminIds.add(_profileId(admin));
    return token;
  }

  Future<void> signOut(AdminUser admin) async {
    _renewedAdminIds.remove(_profileId(admin));
    try {
      await _storage.delete(key: '$_keyPrefix${_profileId(admin)}');
    } catch (_) {}
  }

  /// Runs [call] with a valid token; on 401 drops the stale token and retries once.
  Future<T> withToken<T>(AdminUser admin, Future<T> Function(String token) call) async {
    final token = await _token(admin);
    try {
      return await call(token);
    } on PhotoAlbumException catch (e) {
      if (e.code != 'unauthorized') rethrow;
      await signOut(admin);
      return call(await _token(admin));
    }
  }

  Future<String> _token(AdminUser admin) async {
    final id = _profileId(admin);
    final stored = await _read(admin);
    if (stored != null) {
      if (!_renewedAdminIds.contains(id)) {
        try {
          final renewed = await api.renew(stored);
          if (renewed.isNotEmpty) {
            _renewedAdminIds.add(id);
            await _store(admin, renewed);
            return renewed;
          }
        } on PhotoAlbumException catch (e) {
          if (e.code == 'forbidden') rethrow;
          if (e.code != 'unauthorized') return stored;
        }
      } else {
        return stored;
      }
    }
    final password = await SessionService().getProfilePassword(id);
    if (password == null || password.isEmpty) {
      throw const PhotoAlbumException('needs_password');
    }
    try {
      return await signIn(admin, password);
    } on PhotoAlbumException catch (e) {
      if (e.code == 'bad_credentials') throw const PhotoAlbumException('needs_password');
      rethrow;
    }
  }

  Future<String?> _read(AdminUser admin) async {
    try {
      final v = await _storage
          .read(key: '$_keyPrefix${_profileId(admin)}')
          .timeout(const Duration(seconds: 4));
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _store(AdminUser admin, String token) async {
    if (token.isEmpty) return;
    try {
      await _storage
          .write(key: '$_keyPrefix${_profileId(admin)}', value: token)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}
