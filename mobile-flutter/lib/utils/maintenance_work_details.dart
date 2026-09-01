import 'dart:convert';

/// เมทาดาต้ารูปบำรุงรักษา — เก็บใน JSON คอลัมน์ `work_details` (ซิงก์กับเว็บได้)
class MaintenancePhotoMeta {
  MaintenancePhotoMeta({
    this.localPaths = const [],
    this.remoteUrls = const [],
  });

  static const schemaVersion = 1;

  /// พาธสัมพัทธ์ภายใต้ app documents (เช่น maintenance_photos/txId/0.jpg)
  final List<String> localPaths;

  /// URL สาธารณะหลังอัปโหลด Supabase Storage
  final List<String> remoteUrls;

  bool get isEmpty => localPaths.isEmpty && remoteUrls.isEmpty;

  int get count =>
      localPaths.isNotEmpty ? localPaths.length : remoteUrls.length;

  static MaintenancePhotoMeta decode(String? workDetails) {
    final raw = workDetails?.trim();
    if (raw == null || raw.isEmpty) {
      return MaintenancePhotoMeta();
    }
    if (!raw.startsWith('{') || !raw.endsWith('}')) {
      return MaintenancePhotoMeta();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return MaintenancePhotoMeta();
      }
      final block = decoded['gm_maint_photos'];
      if (block is! Map<String, dynamic>) {
        return MaintenancePhotoMeta();
      }
      return MaintenancePhotoMeta(
        localPaths: _stringList(block['local']),
        remoteUrls: _stringList(block['remote']),
      );
    } catch (_) {
      return MaintenancePhotoMeta();
    }
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String encodeIntoWorkDetails({
    String? existingWorkDetails,
    required MaintenancePhotoMeta meta,
  }) {
    Map<String, dynamic> root = {};
    final ex = existingWorkDetails?.trim();
    if (ex != null && ex.startsWith('{') && ex.endsWith('}')) {
      try {
        final d = jsonDecode(ex);
        if (d is Map<String, dynamic>) {
          root = Map<String, dynamic>.from(d);
        }
      } catch (_) {}
    }
    if (meta.isEmpty) {
      root.remove('gm_maint_photos');
    } else {
      root['gm_maint_photos'] = <String, dynamic>{
        'local': meta.localPaths,
        'remote': meta.remoteUrls,
        'schema_version': schemaVersion,
      };
    }
    if (root.isEmpty) return '';
    return jsonEncode(root);
  }
}
