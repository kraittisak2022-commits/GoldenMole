import 'dart:async';
import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/admin_user.dart';
import '../services/photo_album_service.dart';
import '../services/photo_upload_manager.dart';
import '../theme/daily_palette.dart';
import '../utils/maintenance_image_permissions.dart';
import '../utils/photo_album_format.dart';

const Color kPhotoAlbumAccent = DailyPalette.moduleAlbum;

void photoSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.kanit()),
      behavior: SnackBarBehavior.floating,
    ));
}

String photoErrorText(Object e, String fallback) =>
    e is PhotoAlbumException ? e.message : fallback;

/// Calls the Photos API with the admin's session; asks for the password once when no saved one works.
Future<T> photoCall<T>(
  BuildContext context,
  AdminUser admin,
  Future<T> Function(PhotoAlbumApi api, String token) call,
) async {
  final session = PhotoAlbumSession.instance;
  try {
    return await session.withToken(admin, (t) => call(session.api, t));
  } on PhotoAlbumException catch (e) {
    if (e.code != 'needs_password' || !context.mounted) rethrow;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswordDialog(admin: admin),
    );
    if (ok != true) rethrow;
    return session.withToken(admin, (t) => call(session.api, t));
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.admin});

  final AdminUser admin;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PhotoAlbumSession.instance.signIn(widget.admin, password);
      if (mounted) Navigator.of(context).pop(true);
    } on PhotoAlbumException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ยืนยันรหัสผ่าน', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ใส่รหัสผ่านของบัญชี «${widget.admin.username}» เพื่อเชื่อมต่อ GoldenMole Photos (ทำครั้งเดียว)',
            style: GoogleFonts.kanit(fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'รหัสผ่าน',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ตกลง'),
        ),
      ],
    );
  }
}

Future<bool> photoConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      content: Text(body, style: GoogleFonts.kanit()),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// MARK: - Share / copy / open

/// Copies the report name and share link (same two lines as the web's Copy button).
Future<void> copyPhotoAlbumShareText(BuildContext context, PhotoAlbumSummary album) async {
  await Clipboard.setData(ClipboardData(text: album.shareText));
  if (context.mounted) photoSnack(context, 'คัดลอกชื่อรายงานและลิงก์แล้ว');
}

/// Opens the share sheet (LINE, Messages…) with the report name and link.
Future<void> sharePhotoAlbumText(PhotoAlbumSummary album) =>
    SharePlus.instance.share(ShareParams(text: album.shareText));

Future<void> openPhotoUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) photoSnack(context, 'เปิดลิงก์ไม่ได้');
}

/// Preview of exactly what will be pasted into the group, with Copy, Share and Open-in-Drive.
class PhotoShareCard extends StatelessWidget {
  const PhotoShareCard({super.key, required this.album});

  final PhotoAlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPhotoAlbumAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ข้อความที่จะคัดลอก', style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${album.title}\n',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: p.ink),
                ),
                TextSpan(
                  text: album.shareUrl,
                  style: GoogleFonts.kanit(color: Colors.blue.shade700, fontSize: 13),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ทุกคนที่มีลิงก์ดูรูปได้ โดยไม่ต้องเข้าสู่ระบบ',
            style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
          ),
          const SizedBox(height: 12),
          PhotoAlbumShareButtons(album: album),
        ],
      ),
    );
  }
}

/// Copy (primary) + Share + Google Drive — used on the share card, the album header and after uploads.
class PhotoAlbumShareButtons extends StatelessWidget {
  const PhotoAlbumShareButtons({super.key, required this.album, this.showDrive = true});

  final PhotoAlbumSummary album;
  final bool showDrive;

  @override
  Widget build(BuildContext context) {
    final label = GoogleFonts.kanit(fontWeight: FontWeight.w600);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kPhotoAlbumAccent),
          onPressed: album.shareUrl.isEmpty ? null : () => copyPhotoAlbumShareText(context, album),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text('คัดลอกชื่อรายงาน + ลิงก์', style: label),
        ),
        OutlinedButton.icon(
          onPressed: album.shareUrl.isEmpty ? null : () => sharePhotoAlbumText(album),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: Text('แชร์', style: label),
        ),
        if (showDrive)
          OutlinedButton.icon(
            onPressed: album.driveFolderUrl.isEmpty
                ? null
                : () => openPhotoUrl(context, album.driveFolderUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text('Google Drive', style: label),
          ),
      ],
    );
  }
}

// MARK: - Drive image + error view

class DriveImage extends StatelessWidget {
  const DriveImage({super.key, required this.url, required this.fallbackUrl, this.fit = BoxFit.cover});

  final String url;
  final String fallbackUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: DailyPalette.of(context).hairline.withValues(alpha: 0.5),
      child: const Center(child: Icon(Icons.image_outlined, color: Colors.black26)),
    );
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
      errorBuilder: (context, _, _) => fallbackUrl.isEmpty
          ? placeholder
          : Image.network(
              fallbackUrl,
              fit: fit,
              errorBuilder: (context, _, _) => placeholder,
            ),
    );
  }
}

class PhotoAlbumErrorView extends StatelessWidget {
  const PhotoAlbumErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.black38),
        const SizedBox(height: 12),
        Text(
          photoErrorText(error, 'โหลดไม่สำเร็จ'),
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(fontSize: 15),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ลองใหม่'),
          ),
        ),
      ],
    );
  }
}

// MARK: - Album edit / delete (SuperAdmin)

/// Name, report date and link uploads — returns the saved album.
Future<PhotoAlbumDetail?> editPhotoAlbum(BuildContext context, AdminUser admin, PhotoAlbumSummary album) {
  return showDialog<PhotoAlbumDetail>(
    context: context,
    builder: (_) => _EditAlbumDialog(admin: admin, album: album),
  );
}

/// Moves the folder to the Drive trash — true when deleted.
Future<bool> deletePhotoAlbum(BuildContext context, AdminUser admin, PhotoAlbumSummary album) async {
  final ok = await photoConfirm(
    context,
    title: 'ลบอัลบั้ม «${album.title}»?',
    body: 'รูปทั้งหมด ${album.mediaCount} รายการจะถูกย้ายไปถังขยะของ Google Drive และกู้คืนได้ภายใน 30 วัน',
    action: 'ลบอัลบั้ม',
  );
  if (!ok || !context.mounted) return false;
  try {
    await photoCall(context, admin, (api, t) => api.deleteAlbum(album.id, t));
    if (context.mounted) photoSnack(context, 'ลบอัลบั้ม «${album.title}» แล้ว');
    return true;
  } catch (e) {
    if (context.mounted) photoSnack(context, photoErrorText(e, 'ลบอัลบั้มไม่สำเร็จ'));
    return false;
  }
}

/// New share link (the old one stops working) — returns the saved album.
Future<PhotoAlbumDetail?> regeneratePhotoAlbumLink(
  BuildContext context,
  AdminUser admin,
  PhotoAlbumSummary album,
) async {
  final ok = await photoConfirm(
    context,
    title: 'สร้างลิงก์แชร์ใหม่?',
    body: 'ลิงก์เดิมที่ส่งในกลุ่มไปแล้วจะเปิดไม่ได้อีก',
    action: 'สร้างลิงก์ใหม่',
  );
  if (!ok || !context.mounted) return null;
  try {
    final detail = await photoCall(
      context,
      admin,
      (api, t) => api.updateAlbum(album.id, t, regenerateLink: true),
    );
    await Clipboard.setData(ClipboardData(text: detail.album.shareText));
    if (context.mounted) photoSnack(context, 'สร้างลิงก์ใหม่และคัดลอกแล้ว');
    return detail;
  } catch (e) {
    if (context.mounted) photoSnack(context, photoErrorText(e, 'สร้างลิงก์ใหม่ไม่สำเร็จ'));
    return null;
  }
}

Future<DateTime?> pickPhotoReportDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
}

class _EditAlbumDialog extends StatefulWidget {
  const _EditAlbumDialog({required this.admin, required this.album});

  final AdminUser admin;
  final PhotoAlbumSummary album;

  @override
  State<_EditAlbumDialog> createState() => _EditAlbumDialogState();
}

class _EditAlbumDialogState extends State<_EditAlbumDialog> {
  late final _title = TextEditingController(text: widget.album.title);
  late DateTime _date = DateTime.tryParse(widget.album.reportDate) ?? DateTime.now();
  late bool _allowLinkUpload = widget.album.allowLinkUpload;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'ตั้งชื่อรายงาน');
      return;
    }
    final a = widget.album;
    final reportDate = photoYmd(_date);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await photoCall(
        context,
        widget.admin,
        (api, t) => api.updateAlbum(
          a.id,
          t,
          title: title != a.title ? title : null,
          reportDate: reportDate != a.reportDate ? reportDate : null,
          allowLinkUpload: _allowLinkUpload != a.allowLinkUpload ? _allowLinkUpload : null,
        ),
      );
      if (mounted) Navigator.of(context).pop(detail);
    } catch (e) {
      if (mounted) setState(() => _error = photoErrorText(e, 'บันทึกไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ymd = photoYmd(_date);
    return AlertDialog(
      title: Text('แก้ไขอัลบั้ม', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              enabled: !_busy,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'ชื่อรายงาน', border: OutlineInputBorder()),
            ),
            PhotoReportDateTile(
              ymd: ymd,
              enabled: !_busy,
              onTap: () async {
                final picked = await pickPhotoReportDate(context, _date);
                if (picked != null && mounted) setState(() => _date = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowLinkUpload,
              onChanged: _busy ? null : (v) => setState(() => _allowLinkUpload = v),
              title: Text('ให้คนที่มีลิงก์เพิ่มรูปได้', style: GoogleFonts.kanit(fontSize: 14)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: GoogleFonts.kanit(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}

/// Report date with where it is filed in Drive (same hint as the web create dialog).
class PhotoReportDateTile extends StatelessWidget {
  const PhotoReportDateTile({super.key, required this.ymd, required this.onTap, this.enabled = true});

  final String ymd;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_rounded),
      title: Text(
        'วันที่รายงาน · ${formatPhotoAlbumDateLong(ymd)}',
        style: GoogleFonts.kanit(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'เก็บใน ${photoDrivePathLabel(ymd)}',
        style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
      ),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: enabled ? onTap : null,
    );
  }
}

// MARK: - Picking photos and videos

/// Source sheet (gallery photos/videos, camera photo, camera video), permissions, then the picker.
/// Files over the size limits are skipped with a notice, as on the web.
Future<List<PickedPhotoMedia>> pickPhotoAlbumMedia(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('เลือกรูป/วิดีโอจากเครื่อง', style: GoogleFonts.kanit()),
            subtitle: Text('เลือกได้หลายรายการ', style: GoogleFonts.kanit(fontSize: 12)),
            onTap: () => Navigator.of(context).pop('gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('ถ่ายรูป', style: GoogleFonts.kanit()),
            onTap: () => Navigator.of(context).pop('photo'),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text('ถ่ายวิดีโอ', style: GoogleFonts.kanit()),
            onTap: () => Navigator.of(context).pop('video'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return const [];

  final source = choice == 'gallery' ? ImageSource.gallery : ImageSource.camera;
  final permError = await MaintenanceImagePermissions.ensureFor(source);
  if (!context.mounted) return const [];
  if (permError != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(permError, style: GoogleFonts.kanit()),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: 'ตั้งค่า', onPressed: openAppSettings),
    ));
    return const [];
  }

  final picker = ImagePicker();
  try {
    final List<XFile> files;
    switch (choice) {
      case 'gallery':
        files = await picker.pickMultipleMedia();
      case 'photo':
        files = [?await picker.pickImage(source: ImageSource.camera)];
      default:
        files = [?await picker.pickVideo(source: ImageSource.camera)];
    }
    final picked = <PickedPhotoMedia>[];
    for (final f in files) {
      int size;
      try {
        size = await f.length();
      } catch (_) {
        size = 0;
      }
      picked.add(PickedPhotoMedia(f.path, size));
    }
    final ok = picked.where((f) => f.withinLimit).toList();
    final skipped = picked.length - ok.length;
    if (skipped > 0 && context.mounted) {
      photoSnack(
        context,
        'ข้าม $skipped ไฟล์ที่ใหญ่เกินไป (รูปไม่เกิน ${formatPhotoBytes(kPhotoMaxImageBytes)} '
        'วิดีโอไม่เกิน ${formatPhotoBytes(kPhotoMaxVideoBytes)})',
      );
    }
    return ok;
  } catch (e) {
    if (context.mounted) photoSnack(context, maintenanceImagePickErrorMessage(e));
    return const [];
  }
}

final Map<String, Future<Uint8List?>> _videoThumbs = {};

/// First frame of a picked video (cached per path for the session).
Future<Uint8List?> pickedVideoThumbnail(String path) {
  return _videoThumbs.putIfAbsent(path, () async {
    try {
      return await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: path,
        width: 320,
        height: 320,
        format: 'jpeg',
        quality: 70,
      );
    } catch (_) {
      return null;
    }
  });
}

/// Square preview of a picked file (videos show an icon).
class PickedMediaThumb extends StatelessWidget {
  const PickedMediaThumb({super.key, required this.media, this.onRemove});

  final PickedPhotoMedia media;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final placeholder = ColoredBox(
      color: p.hairline,
      child: Center(
        child: Icon(
          media.isVideo ? Icons.movie_outlined : Icons.image_outlined,
          color: Colors.black45,
          size: 28,
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: media.isVideo
              ? FutureBuilder<Uint8List?>(
                  future: pickedVideoThumbnail(media.path),
                  builder: (context, snap) => snap.data == null
                      ? placeholder
                      : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                )
              : Image.file(
                  File(media.path),
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (context, _, _) => placeholder,
                ),
        ),
        if (media.isVideo)
          const Positioned(
            left: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        if (onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// MARK: - Download and share files

/// Downloads the originals from Drive, then opens the share sheet (save to device, LINE, …).
Future<void> sharePhotoMediaFiles(BuildContext context, List<PhotoMediaItem> items) async {
  if (items.isEmpty) return;
  final progress = ValueNotifier<int>(0);
  final cancelled = Completer<void>();
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (_, done, _) => Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'กำลังดาวน์โหลด ${done + 1 > items.length ? items.length : done + 1}/${items.length}',
                style: GoogleFonts.kanit(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!cancelled.isCompleted) cancelled.complete();
            Navigator.of(dialogContext).pop();
          },
          child: const Text('ยกเลิก'),
        ),
      ],
    ),
  ));

  final navigator = Navigator.of(context);
  final client = http.Client();
  final files = <XFile>[];
  String? error;
  try {
    final dir = await getTemporaryDirectory();
    for (final item in items) {
      if (cancelled.isCompleted) break;
      final url = item.directDownloadUrl;
      if (url == null) continue;
      final res = await client.get(url).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) {
        error = 'ดาวน์โหลดไม่สำเร็จ (${res.statusCode})';
        continue;
      }
      final safe = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/${item.id.substring(0, 8)}_$safe');
      await file.writeAsBytes(res.bodyBytes);
      files.add(XFile(file.path, mimeType: item.mime.isEmpty ? null : item.mime));
      progress.value++;
    }
  } catch (_) {
    error = 'ดาวน์โหลดไม่สำเร็จ — ตรวจสอบอินเทอร์เน็ต';
  } finally {
    client.close();
  }
  if (cancelled.isCompleted) return;
  cancelled.complete();
  navigator.pop();
  if (files.isEmpty) {
    if (context.mounted) photoSnack(context, error ?? 'ไม่มีไฟล์ให้แชร์');
    return;
  }
  await SharePlus.instance.share(ShareParams(files: files));
}
