import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/admin_user.dart';
import '../services/photo_album_service.dart';
import '../theme/daily_palette.dart';
import '../utils/app_haptics.dart';
import '../utils/maintenance_image_permissions.dart';
import '../widgets/app_page_route.dart';

const Color kPhotoAlbumAccent = DailyPalette.moduleAlbum;

const _kThaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// `2026-10-06` → `6 ต.ค. 2569`
String formatPhotoAlbumDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${d.day} ${_kThaiMonthsShort[d.month - 1]} ${d.year + 543}';
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.kanit()),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Calls the Photos API with the admin's session; asks for the password once when no saved one works.
Future<T> _photoCall<T>(
  BuildContext context,
  AdminUser admin,
  Future<T> Function(PhotoAlbumApi api, String token) call,
) async {
  final session = PhotoAlbumSession.instance;
  try {
    return await session.withToken(admin, (t) => call(session.api, t));
  } on PhotoAlbumException catch (e) {
    if (e.code != 'needs_password' || !context.mounted) rethrow;
    final ok = await _promptPassword(context, admin);
    if (!ok) rethrow;
    return session.withToken(admin, (t) => call(session.api, t));
  }
}

Future<bool> _promptPassword(BuildContext context, AdminUser admin) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(admin: admin),
  );
  return result ?? false;
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

String _errorText(Object e, String fallback) =>
    e is PhotoAlbumException ? e.message : fallback;

Future<bool> _confirm(
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

/// SuperAdmin: ชื่อ วันที่รายงาน และการเพิ่มรูปผ่านลิงก์ — คืนค่าอัลบั้มที่บันทึกแล้ว
Future<PhotoAlbumDetail?> _editAlbum(
  BuildContext context,
  AdminUser admin,
  PhotoAlbumSummary album,
) {
  return showDialog<PhotoAlbumDetail>(
    context: context,
    builder: (_) => _EditAlbumDialog(admin: admin, album: album),
  );
}

/// SuperAdmin: ย้ายโฟลเดอร์ไปถังขยะ Drive — true เมื่อลบสำเร็จ
Future<bool> _deleteAlbum(
  BuildContext context,
  AdminUser admin,
  PhotoAlbumSummary album,
) async {
  final ok = await _confirm(
    context,
    title: 'ลบอัลบั้ม «${album.title}»?',
    body: 'รูปทั้งหมด ${album.mediaCount} รายการจะถูกย้ายไปถังขยะของ Google Drive และกู้คืนได้ภายใน 30 วัน',
    action: 'ลบอัลบั้ม',
  );
  if (!ok || !context.mounted) return false;
  try {
    await _photoCall(context, admin, (api, t) => api.deleteAlbum(album.id, t));
    if (context.mounted) _snack(context, 'ลบอัลบั้ม «${album.title}» แล้ว');
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, _errorText(e, 'ลบอัลบั้มไม่สำเร็จ'));
    return false;
  }
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'กรุณาใส่ชื่ออัลบั้ม');
      return;
    }
    final a = widget.album;
    final reportDate = _ymd(_date);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await _photoCall(
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
      if (mounted) setState(() => _error = _errorText(e, 'บันทึกไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              decoration: const InputDecoration(
                labelText: 'ชื่ออัลบั้ม / รายงาน',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text('วันที่รายงาน', style: GoogleFonts.kanit(fontSize: 13)),
              subtitle: Text(
                formatPhotoAlbumDate(_ymd(_date)),
                style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _busy ? null : _pickDate,
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
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
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

// MARK: - PIN gate

class PhotoAlbumPinScreen extends StatefulWidget {
  const PhotoAlbumPinScreen({super.key, required this.admin});

  final AdminUser admin;

  @override
  State<PhotoAlbumPinScreen> createState() => _PhotoAlbumPinScreenState();
}

class _PhotoAlbumPinScreenState extends State<PhotoAlbumPinScreen> {
  static const _pinLength = 4;
  String _entered = '';
  bool _wrong = false;

  void _press(String digit) {
    if (_entered.length >= _pinLength) return;
    AppHaptics.tap();
    setState(() {
      _wrong = false;
      _entered += digit;
    });
    if (_entered.length == _pinLength) _check();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    AppHaptics.tap();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _check() {
    if (photoAlbumPinMatches(_entered)) {
      AppHaptics.success();
      Navigator.of(context).pushReplacement(
        AppPageRoute(page: PhotoAlbumsScreen(admin: widget.admin)),
      );
      return;
    }
    AppHaptics.warn();
    setState(() {
      _wrong = true;
      _entered = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 76,
          height: 76,
          child: onTap == null
              ? const SizedBox.shrink()
              : Material(
                  color: p.card,
                  shape: CircleBorder(side: BorderSide(color: p.hairline)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: Center(
                      child: icon != null
                          ? Icon(icon, color: p.ink, size: 26)
                          : Text(
                              label,
                              style: GoogleFonts.kanit(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                color: p.ink,
                              ),
                            ),
                    ),
                  ),
                ),
        ),
      );
    }

    Widget row(List<String> digits) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (final d in digits) key(d, onTap: () => _press(d))],
        );

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        title: Text('อัลบั้มรูป', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 44, color: kPhotoAlbumAccent),
                const SizedBox(height: 12),
                Text(
                  'ใส่รหัส PIN เพื่อเข้าอัลบั้ม',
                  style: GoogleFonts.kanit(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _pinLength; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 9),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _entered.length ? kPhotoAlbumAccent : Colors.transparent,
                          border: Border.all(
                            color: _wrong ? Colors.red : kPhotoAlbumAccent,
                            width: 2,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: _wrong
                        ? Text(
                            'รหัส PIN ไม่ถูกต้อง',
                            style: GoogleFonts.kanit(color: Colors.red, fontWeight: FontWeight.w600),
                          )
                        : null,
                  ),
                ),
                row(['1', '2', '3']),
                row(['4', '5', '6']),
                row(['7', '8', '9']),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    key(''),
                    key('0', onTap: () => _press('0')),
                    key('', onTap: _backspace, icon: Icons.backspace_outlined),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: - Drive image with fallback

class _DriveImage extends StatelessWidget {
  const _DriveImage({required this.url, required this.fallbackUrl, this.fit = BoxFit.cover});

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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = error is PhotoAlbumException
        ? (error as PhotoAlbumException).message
        : 'โหลดไม่สำเร็จ';
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.black38),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: GoogleFonts.kanit(fontSize: 15)),
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

// MARK: - Album list

class PhotoAlbumsScreen extends StatefulWidget {
  const PhotoAlbumsScreen({super.key, required this.admin});

  final AdminUser admin;

  @override
  State<PhotoAlbumsScreen> createState() => _PhotoAlbumsScreenState();
}

class _PhotoAlbumsScreenState extends State<PhotoAlbumsScreen> {
  List<PhotoAlbumSummary>? _albums;
  Object? _error;
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final albums = await _photoCall(context, widget.admin, (api, t) => api.albums(t));
      if (mounted) setState(() => _albums = albums);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await showDialog<PhotoAlbumSummary>(
      context: context,
      builder: (_) => _CreateAlbumDialog(admin: widget.admin),
    );
    if (created == null || !mounted) return;
    setState(() => _albums = [created, ...?_albums]);
    _snack(context, 'สร้างอัลบั้ม «${created.title}» แล้ว');
    await _open(created);
  }

  Future<void> _open(PhotoAlbumSummary album) async {
    await Navigator.of(context).push(
      AppPageRoute(page: PhotoAlbumDetailScreen(admin: widget.admin, album: album)),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _manage(PhotoAlbumSummary album) async {
    AppHaptics.tap();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(album.title, style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
              subtitle: Text(formatPhotoAlbumDate(album.reportDate), style: GoogleFonts.kanit()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('แก้ไขอัลบั้ม', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
              title: Text('ลบอัลบั้ม', style: GoogleFonts.kanit(color: Colors.red.shade700)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      final saved = await _editAlbum(context, widget.admin, album);
      if (saved == null || !mounted) return;
      _snack(context, 'บันทึกแล้ว');
    } else if (!await _deleteAlbum(context, widget.admin, album)) {
      return;
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final q = _query.trim().toLowerCase();
    final albums = (_albums ?? const <PhotoAlbumSummary>[])
        .where((a) => q.isEmpty || a.title.toLowerCase().contains(q))
        .toList();

    Widget body;
    if (_albums == null && _error != null) {
      body = _ErrorView(error: _error!, onRetry: _load);
    } else if (_albums == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (albums.isEmpty) {
      body = ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.photo_library_outlined, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            q.isEmpty ? 'ยังไม่มีอัลบั้ม — กด «สร้างอัลบั้ม»' : 'ไม่พบอัลบั้มที่ค้นหา',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(fontSize: 15, color: p.inkMuted),
          ),
        ],
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, i) => _AlbumCard(
          album: albums[i],
          onTap: () => _open(albums[i]),
          onLongPress: canManagePhotoAlbums(widget.admin) ? () => _manage(albums[i]) : null,
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        title: Text('อัลบั้มรูป', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'ค้นหาอัลบั้ม',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: p.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: p.hairline),
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            if (_loading && _albums != null) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: kPhotoAlbumAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('สร้างอัลบั้ม', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap, this.onLongPress});

  final PhotoAlbumSummary album;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: album.cover == null
                  ? ColoredBox(
                      color: kPhotoAlbumAccent.withValues(alpha: 0.08),
                      child: const Center(
                        child: Icon(Icons.photo_library_outlined, size: 40, color: kPhotoAlbumAccent),
                      ),
                    )
                  : _DriveImage(url: album.cover!.thumb, fallbackUrl: album.cover!.thumbFallback),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 15, color: p.ink),
                  ),
                  Text(
                    '${formatPhotoAlbumDate(album.reportDate)} · ${album.mediaCount} รายการ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(fontSize: 12.5, color: p.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateAlbumDialog extends StatefulWidget {
  const _CreateAlbumDialog({required this.admin});

  final AdminUser admin;

  @override
  State<_CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<_CreateAlbumDialog> {
  final _title = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'กรุณาใส่ชื่ออัลบั้ม');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final album = await _photoCall(
        context,
        widget.admin,
        (api, t) => api.createAlbum(title: title, reportDate: _ymd(_date), token: t),
      );
      if (mounted) Navigator.of(context).pop(album);
    } on PhotoAlbumException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'สร้างอัลบั้มไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('สร้างอัลบั้ม', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            enabled: !_busy,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'ชื่ออัลบั้ม / รายงาน',
              hintText: 'เช่น เทปูนชั้น 2',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text('วันที่รายงาน', style: GoogleFonts.kanit(fontSize: 13)),
            subtitle: Text(
              formatPhotoAlbumDate(_ymd(_date)),
              style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _busy ? null : _pickDate,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: GoogleFonts.kanit(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('สร้าง'),
        ),
      ],
    );
  }
}

// MARK: - Album detail + upload

enum _JobState { waiting, uploading, done, failed }

class _UploadJob {
  _UploadJob(this.path, this.index);

  final String path;
  final int index;
  _JobState state = _JobState.waiting;
  double progress = 0;
  String? error;
}

class PhotoAlbumDetailScreen extends StatefulWidget {
  const PhotoAlbumDetailScreen({super.key, required this.admin, required this.album});

  final AdminUser admin;
  final PhotoAlbumSummary album;

  @override
  State<PhotoAlbumDetailScreen> createState() => _PhotoAlbumDetailScreenState();
}

class _PhotoAlbumDetailScreenState extends State<PhotoAlbumDetailScreen> {
  static const int _maxImageBytes = 50 * 1024 * 1024;

  final ImagePicker _picker = ImagePicker();
  late PhotoAlbumSummary _album = widget.album;
  List<PhotoMediaItem>? _media;
  Object? _error;
  bool _loading = false;

  final List<_UploadJob> _jobs = [];
  bool _uploading = false;

  /// SuperAdmin multi-select (long-press) for delete / cover.
  final Set<String> _selected = {};

  int get _doneCount => _jobs.where((j) => j.state == _JobState.done).length;
  int get _failedCount => _jobs.where((j) => j.state == _JobState.failed).length;

  double get _overallProgress {
    if (_jobs.isEmpty) return 0;
    final sum = _jobs.fold<double>(0, (s, j) {
      if (j.state == _JobState.done) return s + 1;
      if (j.state == _JobState.uploading) return s + j.progress;
      return s;
    });
    return sum / _jobs.length;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _photoCall(context, widget.admin, (api, t) => api.album(_album.id, t));
      if (mounted) {
        setState(() {
          _album = detail.album;
          _media = detail.media;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _album.shareText));
    if (mounted) _snack(context, 'คัดลอกชื่ออัลบั้มและลิงก์แล้ว — วางในกลุ่มไลน์ได้เลย');
  }

  Future<void> _addPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('เลือกจากแกลเลอรี (หลายรูป)', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('ถ่ายรูป', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final permError = await MaintenanceImagePermissions.ensureFor(source);
    if (!mounted) return;
    if (permError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(permError, style: GoogleFonts.kanit()),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'ตั้งค่า', onPressed: openAppSettings),
      ));
      return;
    }

    final List<String> paths;
    try {
      if (source == ImageSource.gallery) {
        paths = (await _picker.pickMultiImage()).map((f) => f.path).toList();
      } else {
        final shot = await _picker.pickImage(source: ImageSource.camera);
        paths = shot == null ? const [] : [shot.path];
      }
    } catch (e) {
      if (mounted) _snack(context, maintenanceImagePickErrorMessage(e));
      return;
    }
    if (paths.isEmpty || !mounted) return;

    setState(() {
      final start = _jobs.length;
      for (var i = 0; i < paths.length; i++) {
        _jobs.add(_UploadJob(paths[i], start + i));
      }
    });
    unawaited(_runQueue());
  }

  Future<void> _runQueue() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    while (mounted) {
      final next = _jobs.where((j) => j.state == _JobState.waiting).firstOrNull;
      if (next == null) break;
      await _upload(next);
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (_failedCount == 0 && _jobs.isNotEmpty) {
      final n = _doneCount;
      setState(_jobs.clear);
      _snack(context, 'อัปโหลดแล้ว $n รูป');
    }
    unawaited(_load());
  }

  Future<void> _upload(_UploadJob job) async {
    setState(() {
      job.state = _JobState.uploading;
      job.progress = 0;
      job.error = null;
    });
    try {
      final file = File(job.path);
      final size = await file.length();
      if (size <= 0) throw const PhotoAlbumException('empty_file');
      if (size > _maxImageBytes) throw const PhotoAlbumException('too_large');
      final mime = photoMimeTypeForPath(job.path);
      final dot = job.path.lastIndexOf('.');
      final ext = dot < 0 ? 'jpg' : job.path.substring(dot + 1).toLowerCase();
      final name = photoUploadFileName(DateTime.now(), job.index, ext);
      if (!mounted) return;

      final sessionUrl = await _photoCall(
        context,
        widget.admin,
        (api, t) => api.startUpload(albumId: _album.id, name: name, mimeType: mime, size: size, token: t),
      );
      final fileId = await PhotoAlbumSession.instance.api.uploadFile(
        file: file,
        size: size,
        sessionUrl: sessionUrl,
        onProgress: (p) {
          if (mounted) setState(() => job.progress = p.clamp(0, 0.99));
        },
      );
      if (!mounted) return;
      final item = await _photoCall(
        context,
        widget.admin,
        (api, t) => api.completeUpload(albumId: _album.id, fileId: fileId, token: t),
      );
      if (!mounted) return;
      setState(() {
        job.state = _JobState.done;
        job.progress = 1;
        _media = [...?_media, item];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        job.state = _JobState.failed;
        job.error = e is PhotoAlbumException ? e.message : 'อัปโหลดไม่สำเร็จ';
      });
    }
  }

  void _retryFailed() {
    setState(() {
      for (final j in _jobs) {
        if (j.state == _JobState.failed) j.state = _JobState.waiting;
      }
    });
    unawaited(_runQueue());
  }

  Future<bool> _confirmLeave() async {
    if (!_uploading) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('กำลังอัปโหลด', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        content: Text(
          'ถ้าออกตอนนี้ รูปที่ยังไม่เสร็จจะไม่ถูกอัปโหลด',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('รอให้เสร็จ')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ออก')),
        ],
      ),
    );
    return leave ?? false;
  }

  bool get _canManage => canManagePhotoAlbums(widget.admin);

  void _openViewer(int index) {
    final media = _media;
    if (media == null) return;
    Navigator.of(context).push(
      AppPageRoute(
        page: _PhotoViewerScreen(
          media: media,
          initialIndex: index,
          onDelete: _canManage ? (m) => _deleteMedia([m.id]) : null,
          onSetCover: _canManage ? _setCover : null,
        ),
      ),
    );
  }

  void _toggleSelected(String id) {
    AppHaptics.tap();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// Returns true when every item was deleted.
  Future<bool> _deleteMedia(List<String> ids) async {
    if (ids.isEmpty) return false;
    final ok = await _confirm(
      context,
      title: ids.length > 1 ? 'ลบ ${ids.length} รายการ?' : 'ลบรายการนี้?',
      body: 'ไฟล์จะถูกย้ายไปถังขยะของ Google Drive และกู้คืนได้ภายใน 30 วัน',
      action: 'ลบ',
    );
    if (!ok || !mounted) return false;
    final failed = <String>[];
    String? lastError;
    for (final id in ids) {
      try {
        await _photoCall(context, widget.admin, (api, t) => api.deleteMedia(id, t));
      } catch (e) {
        failed.add(id);
        lastError = _errorText(e, 'ลบไม่สำเร็จ');
      }
      if (!mounted) return false;
    }
    final gone = ids.where((id) => !failed.contains(id)).toSet();
    setState(() {
      _media = _media?.where((m) => !gone.contains(m.id)).toList();
      _selected.clear();
    });
    _snack(
      context,
      failed.isEmpty ? 'ลบ ${gone.length} รายการแล้ว' : 'ลบไม่สำเร็จ ${failed.length} รายการ · $lastError',
    );
    unawaited(_load());
    return failed.isEmpty;
  }

  Future<void> _setCover(PhotoMediaItem m) async {
    try {
      final detail = await _photoCall(
        context,
        widget.admin,
        (api, t) => api.updateAlbum(_album.id, t, coverMediaId: m.id),
      );
      if (!mounted) return;
      setState(() {
        _album = detail.album;
        _media = detail.media;
        _selected.clear();
      });
      _snack(context, 'ตั้งเป็นภาพปกแล้ว');
    } catch (e) {
      if (mounted) _snack(context, _errorText(e, 'ตั้งภาพปกไม่สำเร็จ'));
    }
  }

  Future<void> _albumMenu(String action) async {
    switch (action) {
      case 'edit':
        final saved = await _editAlbum(context, widget.admin, _album);
        if (saved == null || !mounted) return;
        setState(() {
          _album = saved.album;
          _media = saved.media;
        });
        _snack(context, 'บันทึกแล้ว');
      case 'relink':
        final ok = await _confirm(
          context,
          title: 'สร้างลิงก์แชร์ใหม่?',
          body: 'ลิงก์เดิมที่ส่งในกลุ่มไปแล้วจะเปิดไม่ได้อีก',
          action: 'สร้างลิงก์ใหม่',
        );
        if (!ok || !mounted) return;
        try {
          final detail = await _photoCall(
            context,
            widget.admin,
            (api, t) => api.updateAlbum(_album.id, t, regenerateLink: true),
          );
          if (!mounted) return;
          setState(() => _album = detail.album);
          await Clipboard.setData(ClipboardData(text: _album.shareText));
          if (mounted) _snack(context, 'สร้างลิงก์ใหม่และคัดลอกแล้ว');
        } catch (e) {
          if (mounted) _snack(context, _errorText(e, 'สร้างลิงก์ใหม่ไม่สำเร็จ'));
        }
      case 'delete':
        if (_uploading) {
          _snack(context, 'รอให้อัปโหลดเสร็จก่อนลบอัลบั้ม');
          return;
        }
        if (await _deleteAlbum(context, widget.admin, _album) && mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  Widget _uploadBanner() {
    final p = DailyPalette.of(context);
    final failed = _failedCount;
    final total = _jobs.length;
    final text = _uploading
        ? 'กำลังอัปโหลด ${_doneCount + 1 > total ? total : _doneCount + 1}/$total'
        : failed > 0
            ? 'อัปโหลดไม่สำเร็จ $failed รูป · ${_jobs.firstWhere((j) => j.state == _JobState.failed).error ?? ''}'
            : 'อัปโหลดแล้ว $_doneCount/$total';
    return Material(
      color: p.card,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  failed > 0 && !_uploading ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
                  color: failed > 0 && !_uploading ? Colors.red : kPhotoAlbumAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: p.ink),
                  ),
                ),
                if (!_uploading && failed > 0) ...[
                  TextButton(onPressed: _retryFailed, child: const Text('ลองใหม่')),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => setState(_jobs.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
            if (_uploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _overallProgress, color: kPhotoAlbumAccent),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final media = _media;

    Widget body;
    if (media == null && _error != null) {
      body = _ErrorView(error: _error!, onRetry: _load);
    } else if (media == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (media.isEmpty) {
      body = ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.add_photo_alternate_outlined, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีรูป — กด «เพิ่มรูป»',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(fontSize: 15, color: p.inkMuted),
          ),
        ],
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: media.length,
        itemBuilder: (context, i) {
          final m = media[i];
          final selected = _selected.contains(m.id);
          return GestureDetector(
            onTap: () => _selected.isNotEmpty ? _toggleSelected(m.id) : _openViewer(i),
            onLongPress: _canManage ? () => _toggleSelected(m.id) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedPadding(
                  duration: const Duration(milliseconds: 120),
                  padding: EdgeInsets.all(selected ? 8 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _DriveImage(url: m.src.thumb, fallbackUrl: m.src.thumbFallback),
                  ),
                ),
                if (m.isVideo)
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white70),
                  ),
                if (_selected.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? kPhotoAlbumAccent : Colors.white,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    final selecting = _selected.isNotEmpty;
    final selectionBar = AppBar(
      backgroundColor: kPhotoAlbumAccent.withValues(alpha: 0.12),
      leading: IconButton(
        tooltip: 'ยกเลิกการเลือก',
        onPressed: () => setState(_selected.clear),
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text('เลือกแล้ว ${_selected.length}', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      actions: [
        if (media != null && _selected.length < media.length)
          IconButton(
            tooltip: 'เลือกทั้งหมด',
            onPressed: () => setState(() => _selected.addAll(media.map((m) => m.id))),
            icon: const Icon(Icons.select_all_rounded),
          ),
        if (_selected.length == 1)
          IconButton(
            tooltip: 'ตั้งเป็นภาพปก',
            onPressed: () {
              final m = media?.where((m) => m.id == _selected.first).firstOrNull;
              if (m != null) unawaited(_setCover(m));
            },
            icon: const Icon(Icons.star_outline_rounded),
          ),
        IconButton(
          tooltip: 'ลบที่เลือก',
          onPressed: () => _deleteMedia(_selected.toList()),
          icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
        ),
      ],
    );

    return PopScope(
      canPop: !_uploading && !selecting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_selected.isNotEmpty) {
          setState(_selected.clear);
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: selecting ? selectionBar : AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              Text(
                '${formatPhotoAlbumDate(_album.reportDate)} · ${media?.length ?? _album.mediaCount} รายการ',
                style: GoogleFonts.kanit(fontSize: 12.5, color: p.inkMuted),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'คัดลอกลิงก์',
              onPressed: _album.shareUrl.isEmpty ? null : _copyLink,
              icon: const Icon(Icons.link_rounded),
            ),
            IconButton(
              tooltip: 'รีเฟรช',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (_canManage)
              PopupMenuButton<String>(
                tooltip: 'จัดการอัลบั้ม',
                onSelected: _albumMenu,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text('แก้ไขอัลบั้ม', style: GoogleFonts.kanit()),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'relink',
                    child: ListTile(
                      leading: const Icon(Icons.link_off_rounded),
                      title: Text('สร้างลิงก์แชร์ใหม่', style: GoogleFonts.kanit()),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                      title: Text('ลบอัลบั้ม', style: GoogleFonts.kanit(color: Colors.red.shade700)),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: Column(
            children: [
              if (_jobs.isNotEmpty) _uploadBanner(),
              if (_canManage && !selecting && (media?.length ?? 0) > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: Text(
                    'กดค้างที่รูปเพื่อเลือกหลายรูป แล้วลบหรือตั้งเป็นภาพปก',
                    style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
                  ),
                ),
              Expanded(child: body),
            ],
          ),
        ),
        floatingActionButton: selecting ? null : FloatingActionButton.extended(
          onPressed: _addPhotos,
          backgroundColor: kPhotoAlbumAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text('เพิ่มรูป', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// MARK: - Viewer

class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({
    required this.media,
    required this.initialIndex,
    this.onDelete,
    this.onSetCover,
  });

  final List<PhotoMediaItem> media;
  final int initialIndex;

  /// SuperAdmin only; resolves true when the item was deleted.
  final Future<bool> Function(PhotoMediaItem item)? onDelete;
  final Future<void> Function(PhotoMediaItem item)? onSetCover;

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late final List<PhotoMediaItem> _media = [...widget.media];

  Future<void> _delete(PhotoMediaItem m) async {
    final deleted = await widget.onDelete!(m);
    if (!deleted || !mounted) return;
    setState(() {
      _media.removeWhere((x) => x.id == m.id);
      if (_index >= _media.length) _index = _media.length - 1;
    });
    if (_media.isEmpty) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openExternal(PhotoMediaItem m) async {
    final url = Uri.tryParse(m.src.preview ?? m.src.download);
    if (url == null) return;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack(context, 'เปิดไฟล์ไม่ได้');
  }

  @override
  Widget build(BuildContext context) {
    if (_media.isEmpty) return const ColoredBox(color: Colors.black);
    final current = _media[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${_media.length}',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (widget.onSetCover != null)
            IconButton(
              tooltip: 'ตั้งเป็นภาพปก',
              onPressed: () => widget.onSetCover!(current),
              icon: const Icon(Icons.star_outline_rounded),
            ),
          if (widget.onDelete != null)
            IconButton(
              tooltip: 'ลบ',
              onPressed: () => _delete(current),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          IconButton(
            tooltip: 'เปิดใน Google Drive',
            onPressed: () => _openExternal(current),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: _media.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final m = _media[i];
          if (m.isVideo) {
            return GestureDetector(
              onTap: () => _openExternal(m),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DriveImage(url: m.src.large, fallbackUrl: m.src.thumbFallback, fit: BoxFit.contain),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white70),
                  ),
                ],
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: _DriveImage(url: m.src.large, fallbackUrl: m.src.thumbFallback, fit: BoxFit.contain),
          );
        },
      ),
      bottomNavigationBar: current.uploadedByName == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'อัปโหลดโดย ${current.uploadedByName}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.kanit(color: Colors.white70),
                ),
              ),
            ),
    );
  }
}
