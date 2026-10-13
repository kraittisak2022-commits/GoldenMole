import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/admin_user.dart';
import '../services/photo_album_service.dart';
import '../services/photo_upload_manager.dart';
import '../theme/daily_palette.dart';
import '../utils/app_haptics.dart';
import '../utils/photo_album_format.dart';
import '../widgets/app_page_route.dart';
import '../widgets/photo_album_common.dart';
import '../widgets/photo_upload_tray.dart';
import 'photo_album_detail_screen.dart';

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
      final albums = await photoCall(context, widget.admin, (api, t) => api.albums(t));
      if (mounted) setState(() => _albums = albums);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<_CreatedAlbum>(
      AppPageRoute(page: _CreateAlbumScreen(admin: widget.admin)),
    );
    if (result == null || !mounted) return;
    setState(() => _albums = [result.album, ...?_albums?.where((a) => a.id != result.album.id)]);
    if (result.uploads.isNotEmpty) {
      PhotoUploadManager.instance.enqueue(widget.admin, result.album, result.uploads);
      photoSnack(context, 'สร้างอัลบั้มแล้ว กำลังอัปโหลด ${result.uploads.length} รายการ');
    }
    if (result.open) {
      await _open(result.album);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _open(PhotoAlbumSummary album) async {
    await Navigator.of(context).push(
      AppPageRoute(page: PhotoAlbumDetailScreen(admin: widget.admin, album: album)),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _albumActions(PhotoAlbumSummary album) async {
    AppHaptics.tap();
    final canManage = canManagePhotoAlbums(widget.admin);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(album.title, style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${formatPhotoAlbumDate(album.reportDate)} · ${album.mediaCount} รายการ',
                style: GoogleFonts.kanit(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text('คัดลอกชื่อรายงาน + ลิงก์', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text('แชร์', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop('share'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text('เปิดใน Google Drive', style: GoogleFonts.kanit()),
              onTap: () => Navigator.of(context).pop('drive'),
            ),
            if (canManage) ...[
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
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await copyPhotoAlbumShareText(context, album);
      case 'share':
        await sharePhotoAlbumText(album);
      case 'drive':
        await openPhotoUrl(context, album.driveFolderUrl);
      case 'edit':
        final saved = await editPhotoAlbum(context, widget.admin, album);
        if (saved == null || !mounted) return;
        photoSnack(context, 'บันทึกแล้ว');
        unawaited(_load());
      case 'delete':
        if (await deletePhotoAlbum(context, widget.admin, album) && mounted) unawaited(_load());
    }
  }

  bool _matches(PhotoAlbumSummary a, String q) {
    if (q.isEmpty) return true;
    return a.title.toLowerCase().contains(q) ||
        a.reportDate.contains(q) ||
        formatPhotoAlbumDate(a.reportDate).contains(q) ||
        formatPhotoAlbumDateLong(a.reportDate).contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final q = _query.trim().toLowerCase();
    final albums = (_albums ?? const <PhotoAlbumSummary>[]).where((a) => _matches(a, q)).toList();

    Widget body;
    if (_albums == null && _error != null) {
      body = PhotoAlbumErrorView(error: _error!, onRetry: _load);
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
          onMore: () => _albumActions(albums[i]),
        ),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && PhotoUploadManager.instance.isBusy()) {
          photoSnack(context, 'ยังอัปโหลดต่อเบื้องหลัง — เปิดแอปค้างไว้จนกว่าจะเสร็จ');
        }
      },
      child: _scaffold(p, body),
    );
  }

  Widget _scaffold(DailyColors p, Widget body) {
    return Scaffold(
      backgroundColor: p.surface,
      bottomNavigationBar: const PhotoUploadTray(),
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
                hintText: 'ค้นหาชื่อรายงานหรือวันที่',
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
  const _AlbumCard({required this.album, required this.onTap, required this.onMore});

  final PhotoAlbumSummary album;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMore,
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
                  : DriveImage(url: album.cover!.thumb, fallbackUrl: album.cover!.thumbFallback),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
              child: Row(
                children: [
                  Expanded(
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
                  IconButton(
                    tooltip: 'คัดลอก / แชร์',
                    visualDensity: VisualDensity.compact,
                    onPressed: onMore,
                    icon: const Icon(Icons.more_vert_rounded),
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

// MARK: - Create album

class _CreatedAlbum {
  const _CreatedAlbum(this.album, {this.open = false, this.uploads = const []});

  final PhotoAlbumSummary album;
  final bool open;
  final List<PickedPhotoMedia> uploads;
}

/// Name, photos/videos and report date in one page (like the web dialog).
/// With files it opens the album and uploads; without, it shows the link to share.
class _CreateAlbumScreen extends StatefulWidget {
  const _CreateAlbumScreen({required this.admin});

  final AdminUser admin;

  @override
  State<_CreateAlbumScreen> createState() => _CreateAlbumScreenState();
}

class _CreateAlbumScreenState extends State<_CreateAlbumScreen> {
  /// Rendering every full-size photo would exhaust memory; the rest are counted in a "+N" tile.
  static const _maxPreviews = 30;

  final _title = TextEditingController();
  final List<PickedPhotoMedia> _files = [];
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;
  PhotoAlbumSummary? _created;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickPhotoAlbumMedia(context);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      final known = _files.map((f) => f.path).toSet();
      _files.addAll(picked.where((f) => known.add(f.path)));
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'ตั้งชื่อรายงาน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final album = await photoCall(
        context,
        widget.admin,
        (api, t) => api.createAlbum(title: title, reportDate: photoYmd(_date), token: t),
      );
      if (!mounted) return;
      AppHaptics.success();
      if (_files.isNotEmpty) {
        Navigator.of(context).pop(_CreatedAlbum(album, open: true, uploads: [..._files]));
      } else {
        setState(() => _created = album);
      }
    } catch (e) {
      if (mounted) setState(() => _error = photoErrorText(e, 'สร้างอัลบั้มไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _form(DailyColors p) {
    final ymd = photoYmd(_date);
    final count = _files.length;
    final shown = math.min(count, _maxPreviews);
    final hidden = count - shown;
    final totalBytes = _files.fold<int>(0, (s, f) => s + f.size);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TextField(
          controller: _title,
          enabled: !_busy,
          autofocus: true,
          maxLength: 200,
          textInputAction: TextInputAction.done,
          style: GoogleFonts.kanit(fontSize: 16),
          decoration: InputDecoration(
            labelText: 'ชื่อรายงาน',
            hintText: 'เช่น เทปูนชั้น 2 อาคาร A',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'รูปและวิดีโอ',
                style: GoogleFonts.kanit(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
              ),
            ),
            if (count > 0)
              Text(
                '$count รายการ · ${formatPhotoBytes(totalBytes)}',
                style: GoogleFonts.kanit(fontSize: 12.5, color: p.inkMuted),
              ),
            if (count > 0)
              TextButton(
                onPressed: _busy ? null : () => setState(_files.clear),
                child: const Text('ล้างทั้งหมด'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: shown + 1 + (hidden > 0 ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == shown + 1) {
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.hairline, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '+$hidden',
                  style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w600, color: p.inkMuted),
                ),
              );
            }
            if (i == 0) {
              return Material(
                color: kPhotoAlbumAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _busy ? null : _pick,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, color: kPhotoAlbumAccent, size: 30),
                      const SizedBox(height: 4),
                      Text(
                        count == 0 ? 'เลือก' : 'เพิ่มอีก',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.kanit(fontSize: 12, color: kPhotoAlbumAccent),
                      ),
                    ],
                  ),
                ),
              );
            }
            final file = _files[i - 1];
            return PickedMediaThumb(
              media: file,
              onRemove: _busy ? null : () => setState(() => _files.remove(file)),
            );
          },
        ),
        if (count == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'เลือกไว้ก่อนได้เลย ระบบจะอัปโหลดให้ทันทีหลังสร้างอัลบั้ม',
              style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
            ),
          ),
        const SizedBox(height: 8),
        PhotoReportDateTile(
          ymd: ymd,
          enabled: !_busy,
          onTap: () async {
            final picked = await pickPhotoReportDate(context, _date);
            if (picked != null && mounted) setState(() => _date = picked);
          },
        ),
        Text(
          'คนที่มีลิงก์ดูรูปและเพิ่มรูปได้ โดยไม่ต้องเข้าสู่ระบบ',
          style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kPhotoAlbumAccent,
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  count == 0 ? 'สร้าง' : 'สร้างและอัปโหลด $count รายการ',
                  style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }

  Widget _done(DailyColors p, PhotoAlbumSummary album) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Icon(Icons.check_circle_rounded, size: 52, color: Colors.green),
        const SizedBox(height: 8),
        Text(
          'สร้างอัลบั้มแล้ว',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(fontSize: 20, fontWeight: FontWeight.w700, color: p.ink),
        ),
        Text(
          '${formatPhotoAlbumDateLong(album.reportDate)} · เก็บใน ${photoDrivePathLabel(album.reportDate)}',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(fontSize: 12.5, color: p.inkMuted),
        ),
        const SizedBox(height: 16),
        PhotoShareCard(album: album),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kPhotoAlbumAccent,
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: () => Navigator.of(context).pop(_CreatedAlbum(album, open: true)),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text('เปิดอัลบั้มและเพิ่มรูป', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          onPressed: () => Navigator.of(context).pop(_CreatedAlbum(album)),
          child: Text('ปิด', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final created = _created;
    return PopScope(
      canPop: created == null && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && created != null) Navigator.of(context).pop(_CreatedAlbum(created));
      },
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: AppBar(
          title: Text(
            created == null ? 'สร้างอัลบั้ม' : created.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(child: created == null ? _form(p) : _done(p, created)),
      ),
    );
  }
}
