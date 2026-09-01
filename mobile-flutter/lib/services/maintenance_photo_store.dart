import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _joinPath(String a, String b) {
  if (a.endsWith('/') || a.endsWith('\\')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}

String _dirname(String path) {
  final i = path.lastIndexOf(Platform.pathSeparator);
  if (i <= 0) return path;
  return path.substring(0, i);
}

String _basename(String path) {
  final i = path.lastIndexOf(Platform.pathSeparator);
  if (i < 0) return path;
  return path.substring(i + 1);
}

String _extension(String path) {
  final base = _basename(path);
  final dot = base.lastIndexOf('.');
  if (dot < 0) return '';
  return base.substring(dot);
}

/// จัดเก็บรูปบำรุงรักษาในเครื่อง + อัปโหลด Supabase Storage เมื่อออนไลน์
class MaintenancePhotoStore {
  MaintenancePhotoStore._();

  static const bucket = 'gm-maintenance-photos';
  static const relativeRoot = 'maintenance_photos';

  static Future<Directory> _docsDir() => getApplicationDocumentsDirectory();

  static Future<String> absolutePathForRelative(String relative) async {
    final docs = await _docsDir();
    return _joinPath(docs.path, relative);
  }

  static bool isAbsolutePath(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    return p.startsWith('/') || RegExp(r'^[a-zA-Z]:\\').hasMatch(p);
  }

  /// พาธสำหรับแสดง thumbnail — รองรับทั้งพาธสัมพัทธ์และพาธเต็มจาก image_picker
  static Future<String> resolveDisplayPath(String pathOrRelative) async {
    final p = pathOrRelative.trim();
    if (p.isEmpty) return p;
    if (isAbsolutePath(p)) return p;
    return absolutePathForRelative(p);
  }

  static String relativePathFor({required String txId, required String fileName}) {
    final safeId = txId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '$relativeRoot/$safeId/$fileName';
  }

  /// คัดลอกไฟล์ที่เลือก/ถ่ายไปเก็บถาวรภายใต้ documents
  static Future<String> persistSourceFile({
    required String txId,
    required String sourcePath,
    required int index,
  }) async {
    final ext = _extension(sourcePath).isNotEmpty
        ? _extension(sourcePath).toLowerCase()
        : '.jpg';
    final rel = relativePathFor(txId: txId, fileName: '$index$ext');
    final dest = await absolutePathForRelative(rel);
    final destDir = Directory(_dirname(dest));
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    await File(sourcePath).copy(dest);
    return rel;
  }

  static Future<void> deleteRelative(String relative) async {
    try {
      final abs = await absolutePathForRelative(relative);
      final file = File(abs);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> deleteAllForTx(String txId) async {
    try {
      final docs = await _docsDir();
      final safeId = txId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dir = Directory(_joinPath(_joinPath(docs.path, relativeRoot), safeId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// อัปโหลดรูปที่ยังไม่มี URL — คืน remote URLs ตามลำดับ local
  static Future<List<String>> uploadMissing({
    required SupabaseClient client,
    required String txId,
    required List<String> localPaths,
    required List<String> existingRemote,
  }) async {
    if (localPaths.isEmpty) return List<String>.from(existingRemote);
    final out = List<String>.from(existingRemote);
    while (out.length < localPaths.length) {
      out.add('');
    }
    for (var i = 0; i < localPaths.length; i++) {
      if (out[i].trim().isNotEmpty) continue;
      final rel = localPaths[i];
      final abs = await absolutePathForRelative(rel);
      final file = File(abs);
      if (!await file.exists()) continue;
      final ext = _extension(abs).replaceFirst('.', '');
      final storagePath =
          'maintenance/$txId/${DateTime.now().millisecondsSinceEpoch}_$i.${ext.isEmpty ? 'jpg' : ext}';
      try {
        final bytes = await file.readAsBytes();
        await client.storage.from(bucket).uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: _mimeForExt(ext),
              ),
            );
        final url = client.storage.from(bucket).getPublicUrl(storagePath);
        out[i] = url;
      } catch (e) {
        debugPrint('MaintenancePhotoStore upload skip: $e');
      }
    }
    return out.where((u) => u.trim().isNotEmpty).toList();
  }

  static String _mimeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
