import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/admin_user.dart';
import '../services/photo_album_service.dart';
import '../theme/daily_palette.dart';
import '../utils/app_haptics.dart';
import '../utils/photo_album_format.dart';
import '../widgets/app_page_route.dart';
import '../widgets/photo_album_common.dart';

enum _JobState { waiting, uploading, done, failed }

class _UploadJob {
  _UploadJob(this.media, this.index);

  final PickedPhotoMedia media;
  final int index;
  _JobState state = _JobState.waiting;
  double progress = 0;
  String? error;
}

/// Reads the capture time from the first 128 KB of a JPEG (where EXIF lives).
Future<String?> _captureTimeOf(File file) async {
  final mime = photoMimeTypeForPath(file.path);
  if (mime != 'image/jpeg') return null;
  try {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, 128 * 1024)) {
      builder.add(chunk);
    }
    return readExifDate(builder.takeBytes());
  } catch (_) {
    return null;
  }
}

class PhotoAlbumDetailScreen extends StatefulWidget {
  const PhotoAlbumDetailScreen({
    super.key,
    required this.admin,
    required this.album,
    this.initialUploads = const [],
  });

  final AdminUser admin;
  final PhotoAlbumSummary album;

  /// Files picked on the create page — uploaded as soon as the album opens.
  final List<PickedPhotoMedia> initialUploads;

  @override
  State<PhotoAlbumDetailScreen> createState() => _PhotoAlbumDetailScreenState();
}

class _PhotoAlbumDetailScreenState extends State<PhotoAlbumDetailScreen> {
  late PhotoAlbumSummary _album = widget.album;
  List<PhotoMediaItem>? _media;
  Object? _error;
  bool _loading = false;

  final List<_UploadJob> _jobs = [];
  bool _uploading = false;

  bool _selecting = false;
  final Set<String> _selected = {};

  bool get _canManage => canManagePhotoAlbums(widget.admin);
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
    if (widget.initialUploads.isNotEmpty) _enqueue(widget.initialUploads);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await photoCall(context, widget.admin, (api, t) => api.album(_album.id, t));
      if (mounted) {
        setState(() {
          _album = detail.album;
          _media = detail.media;
          _selected.retainAll(detail.media.map((m) => m.id));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // MARK: Upload

  Future<void> _addMedia() async {
    final picked = await pickPhotoAlbumMedia(context);
    if (picked.isEmpty || !mounted) return;
    _enqueue(picked);
  }

  void _enqueue(List<PickedPhotoMedia> picked) {
    setState(() {
      if (!_uploading) _jobs.removeWhere((j) => j.state == _JobState.done);
      final start = _jobs.length;
      for (var i = 0; i < picked.length; i++) {
        _jobs.add(_UploadJob(picked[i], start + i));
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
    if (_failedCount == 0 && _doneCount > 0) AppHaptics.success();
    unawaited(_load());
  }

  Future<void> _upload(_UploadJob job) async {
    setState(() {
      job.state = _JobState.uploading;
      job.progress = 0;
      job.error = null;
    });
    try {
      final file = File(job.media.path);
      final video = job.media.isVideo;
      final size = await file.length();
      if (size <= 0) throw const PhotoAlbumException('empty_file');
      if (size > (video ? kPhotoMaxVideoBytes : kPhotoMaxImageBytes)) {
        throw const PhotoAlbumException('too_large');
      }
      final mime = photoMimeTypeForPath(job.media.path);
      final (_, dotExt) = splitPhotoExtension(job.media.path.split(RegExp(r'[\\/]')).last);
      final ext = dotExt.isEmpty ? (video ? 'mp4' : 'jpg') : dotExt.substring(1).toLowerCase();
      final name = photoUploadFileName(DateTime.now(), job.index, ext, video: video);
      final takenAt = await _captureTimeOf(file);
      if (!mounted) return;

      final sessionUrl = await photoCall(
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
      final item = await photoCall(
        context,
        widget.admin,
        (api, t) => api.completeUpload(albumId: _album.id, fileId: fileId, takenAt: takenAt, token: t),
      );
      if (!mounted) return;
      setState(() {
        job.state = _JobState.done;
        job.progress = 1;
        _media = sortPhotoMediaItems([...?_media, item]);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        job.state = _JobState.failed;
        job.error = photoErrorText(e, 'อัปโหลดไม่สำเร็จ');
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
        content: Text('ถ้าออกตอนนี้ ไฟล์ที่ยังไม่เสร็จจะไม่ถูกอัปโหลด', style: GoogleFonts.kanit()),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('รอให้เสร็จ')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ออก')),
        ],
      ),
    );
    return leave ?? false;
  }

  // MARK: Selection, viewer, management

  void _toggleSelected(String id) {
    AppHaptics.tap();
    setState(() {
      _selecting = true;
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _endSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  List<PhotoMediaItem> get _selectedItems =>
      (_media ?? const <PhotoMediaItem>[]).where((m) => _selected.contains(m.id)).toList();

  void _replaceItem(PhotoMediaItem item) {
    setState(() {
      _media = sortPhotoMediaItems((_media ?? const []).map((m) => m.id == item.id ? item : m));
    });
  }

  void _openViewer(int index) {
    final media = _media;
    if (media == null) return;
    Navigator.of(context).push(
      AppPageRoute(
        page: _PhotoViewerScreen(
          admin: widget.admin,
          media: media,
          initialIndex: index,
          onDelete: _canManage ? (m) => _deleteMedia([m.id]) : null,
          onSetCover: _canManage ? _setCover : null,
          onEdited: _replaceItem,
        ),
      ),
    );
  }

  /// Returns true when every item was deleted.
  Future<bool> _deleteMedia(List<String> ids) async {
    if (ids.isEmpty) return false;
    final ok = await photoConfirm(
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
        await photoCall(context, widget.admin, (api, t) => api.deleteMedia(id, t));
      } catch (e) {
        failed.add(id);
        lastError = photoErrorText(e, 'ลบไม่สำเร็จ');
      }
      if (!mounted) return false;
    }
    final gone = ids.where((id) => !failed.contains(id)).toSet();
    setState(() {
      _media = _media?.where((m) => !gone.contains(m.id)).toList();
      _selected.removeAll(gone);
      if (_selected.isEmpty) _selecting = false;
    });
    photoSnack(
      context,
      failed.isEmpty ? 'ลบ ${gone.length} รายการแล้ว' : 'ลบไม่สำเร็จ ${failed.length} รายการ · $lastError',
    );
    unawaited(_load());
    return failed.isEmpty;
  }

  Future<void> _setCover(PhotoMediaItem m) async {
    try {
      final detail = await photoCall(
        context,
        widget.admin,
        (api, t) => api.updateAlbum(_album.id, t, coverMediaId: m.id),
      );
      if (!mounted) return;
      setState(() {
        _album = detail.album;
        _media = detail.media;
        _selecting = false;
        _selected.clear();
      });
      photoSnack(context, 'ตั้งเป็นภาพปกแล้ว');
    } catch (e) {
      if (mounted) photoSnack(context, photoErrorText(e, 'ตั้งภาพปกไม่สำเร็จ'));
    }
  }

  Future<void> _albumMenu(String action) async {
    switch (action) {
      case 'edit':
        final saved = await editPhotoAlbum(context, widget.admin, _album);
        if (saved == null || !mounted) return;
        setState(() {
          _album = saved.album;
          _media = saved.media;
        });
        photoSnack(context, 'บันทึกแล้ว');
      case 'relink':
        final saved = await regeneratePhotoAlbumLink(context, widget.admin, _album);
        if (saved != null && mounted) setState(() => _album = saved.album);
      case 'delete':
        if (_uploading) {
          photoSnack(context, 'รอให้อัปโหลดเสร็จก่อนลบอัลบั้ม');
          return;
        }
        if (await deletePhotoAlbum(context, widget.admin, _album) && mounted) {
          Navigator.of(context).pop();
        }
    }
  }

  // MARK: Build

  Widget _header(DailyColors p, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _album.title,
            style: GoogleFonts.kanit(fontSize: 22, fontWeight: FontWeight.w700, color: p.ink, height: 1.25),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatPhotoAlbumDateLong(_album.reportDate)} · $count รายการ',
            style: GoogleFonts.kanit(fontSize: 13.5, color: p.inkMuted),
          ),
          if (_canManage && !_album.allowLinkUpload)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'ปิดการเพิ่มรูปผ่านลิงก์',
                style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
              ),
            ),
          const SizedBox(height: 12),
          PhotoAlbumShareButtons(album: _album),
        ],
      ),
    );
  }

  Widget _uploadBanner(DailyColors p) {
    final failed = _failedCount;
    final done = _doneCount;
    final total = _jobs.length;
    final finished = !_uploading && failed == 0;
    final String text;
    if (_uploading) {
      text = 'กำลังอัปโหลด ${done + 1 > total ? total : done + 1}/$total';
    } else if (failed > 0) {
      final reason = _jobs.firstWhere((j) => j.state == _JobState.failed).error ?? '';
      text = 'อัปโหลดไม่สำเร็จ $failed รายการ · $reason';
    } else {
      text = 'อัปโหลดแล้ว $done รายการ — ส่งชื่อรายงานและลิงก์เข้ากลุ่มได้เลย';
    }
    final color = failed > 0 && !_uploading
        ? Colors.red
        : finished
            ? Colors.green.shade700
            : kPhotoAlbumAccent;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed > 0 && !_uploading
                    ? Icons.error_outline_rounded
                    : finished
                        ? Icons.check_circle_rounded
                        : Icons.cloud_upload_outlined,
                color: color,
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
              if (!_uploading && failed > 0)
                TextButton(onPressed: _retryFailed, child: const Text('ลองใหม่')),
              if (!_uploading)
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => setState(_jobs.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          if (_uploading) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(value: _overallProgress, color: kPhotoAlbumAccent),
            ),
          ],
          if (finished && done > 0) ...[
            const SizedBox(height: 10),
            PhotoAlbumShareButtons(album: _album, showDrive: false),
          ],
        ],
      ),
    );
  }

  Widget _tile(PhotoMediaItem m, int index) {
    final selected = _selected.contains(m.id);
    return GestureDetector(
      onTap: () => _selecting ? _toggleSelected(m.id) : _openViewer(index),
      onLongPress: () => _toggleSelected(m.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(selected ? 8 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: DriveImage(url: m.src.thumb, fallbackUrl: m.src.thumbFallback),
            ),
          ),
          if (m.isVideo)
            const Center(child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white70)),
          if (_selecting)
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
  }

  List<Widget> _mediaSlivers(DailyColors p, List<PhotoMediaItem> media) {
    final sections = groupPhotosByDay(media, takenAt: (m) => m.takenAt, createdAt: (m) => m.createdAt);
    return [
      for (final section in sections) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          sliver: SliverToBoxAdapter(
            child: Text(
              '${formatPhotoDayHeading(section.at)} · ${section.items.length} รายการ',
              style: GoogleFonts.kanit(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.inkMuted),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: section.items.length,
            itemBuilder: (context, i) {
              final (m, index) = section.items[i];
              return _tile(m, index);
            },
          ),
        ),
      ],
    ];
  }

  AppBar _selectionBar(List<PhotoMediaItem>? media) {
    final count = _selected.length;
    return AppBar(
      backgroundColor: kPhotoAlbumAccent.withValues(alpha: 0.12),
      leading: IconButton(
        tooltip: 'ยกเลิกการเลือก',
        onPressed: _endSelection,
        icon: const Icon(Icons.close_rounded),
      ),
      title: Text(
        count == 0 ? 'เลือกรูป' : 'เลือกแล้ว $count',
        style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
      ),
      actions: [
        if (media != null && count < media.length)
          IconButton(
            tooltip: 'เลือกทั้งหมด',
            onPressed: () => setState(() => _selected.addAll(media.map((m) => m.id))),
            icon: const Icon(Icons.select_all_rounded),
          ),
        if (count > 0)
          IconButton(
            tooltip: 'บันทึก / แชร์ไฟล์',
            onPressed: () => sharePhotoMediaFiles(context, _selectedItems),
            icon: const Icon(Icons.download_rounded),
          ),
        if (_canManage && count == 1)
          IconButton(
            tooltip: 'ตั้งเป็นภาพปก',
            onPressed: () {
              final items = _selectedItems;
              if (items.isNotEmpty) unawaited(_setCover(items.first));
            },
            icon: const Icon(Icons.star_outline_rounded),
          ),
        if (_canManage && count > 0)
          IconButton(
            tooltip: 'ลบที่เลือก',
            onPressed: () => _deleteMedia(_selected.toList()),
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
          ),
      ],
    );
  }

  AppBar _mainBar(List<PhotoMediaItem>? media) {
    return AppBar(
      title: Text(
        _album.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      actions: [
        if ((media?.isNotEmpty ?? false))
          IconButton(
            tooltip: 'เลือกรูป',
            onPressed: () => setState(() => _selecting = true),
            icon: const Icon(Icons.checklist_rounded),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final media = _media;

    final List<Widget> content;
    if (media == null && _error != null) {
      content = [SliverFillRemaining(child: PhotoAlbumErrorView(error: _error!, onRetry: _load))];
    } else if (media == null) {
      content = [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))];
    } else if (media.isEmpty) {
      content = [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                const Icon(Icons.add_photo_alternate_outlined, size: 56, color: Colors.black26),
                const SizedBox(height: 12),
                Text(
                  'ยังไม่มีรูป — กด «เพิ่มรูป/วิดีโอ»',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.kanit(fontSize: 15, color: p.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ];
    } else {
      content = _mediaSlivers(p, media);
    }

    return PopScope(
      canPop: !_uploading && !_selecting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_selecting) {
          _endSelection();
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: _selecting ? _selectionBar(media) : _mainBar(media),
        body: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_loading && media != null)
                const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              SliverToBoxAdapter(child: _header(p, media?.length ?? _album.mediaCount)),
              if (_jobs.isNotEmpty) SliverToBoxAdapter(child: _uploadBanner(p)),
              if (!_selecting && (media?.length ?? 0) > 1)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _canManage
                          ? 'กดค้างที่รูปเพื่อเลือกหลายรูป แล้วบันทึก แชร์ ลบ หรือตั้งเป็นภาพปก'
                          : 'กดค้างที่รูปเพื่อเลือกหลายรูป แล้วบันทึกหรือแชร์',
                      style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
                    ),
                  ),
                ),
              ...content,
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _addMedia,
                backgroundColor: kPhotoAlbumAccent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('เพิ่มรูป/วิดีโอ', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
              ),
      ),
    );
  }
}

// MARK: - Viewer

class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({
    required this.admin,
    required this.media,
    required this.initialIndex,
    required this.onEdited,
    this.onDelete,
    this.onSetCover,
  });

  final AdminUser admin;
  final List<PhotoMediaItem> media;
  final int initialIndex;
  final ValueChanged<PhotoMediaItem> onEdited;

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
  bool _showInfo = true;

  bool get _canManage => canManagePhotoAlbums(widget.admin);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(PhotoMediaItem m) async {
    final deleted = await widget.onDelete!(m);
    if (!deleted || !mounted) return;
    setState(() {
      _media.removeWhere((x) => x.id == m.id);
      if (_index >= _media.length) _index = _media.length - 1;
    });
    if (_media.isEmpty) Navigator.of(context).pop();
  }

  Future<void> _edit(PhotoMediaItem m) async {
    final saved = await showDialog<PhotoMediaItem>(
      context: context,
      builder: (_) => _EditMediaDialog(admin: widget.admin, item: m),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final i = _media.indexWhere((x) => x.id == saved.id);
      if (i >= 0) _media[i] = saved;
    });
    widget.onEdited(saved);
    photoSnack(context, 'บันทึกแล้ว');
  }

  Widget _info(PhotoMediaItem m) {
    final lines = <String>[
      if (m.takenAt != null) 'ถ่ายเมื่อ ${formatPhotoDateTime(m.takenAt!)}',
      [
        'อัปโหลด ${formatPhotoDateTime(m.createdAt)}',
        if (m.uploadedByName != null) 'โดย ${m.uploadedByName}',
      ].join(' '),
      if (m.width > 0 && m.height > 0) '${m.width} × ${m.height}',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          m.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        for (final line in lines)
          Text(line, style: GoogleFonts.kanit(color: Colors.white70, fontSize: 13)),
      ],
    );
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
        title: Text('${_index + 1} / ${_media.length}', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: _showInfo ? 'ซ่อนรายละเอียด' : 'รายละเอียด',
            onPressed: () => setState(() => _showInfo = !_showInfo),
            icon: Icon(_showInfo ? Icons.info_rounded : Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: 'บันทึก / แชร์ไฟล์',
            onPressed: () => sharePhotoMediaFiles(context, [current]),
            icon: const Icon(Icons.download_rounded),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            onSelected: (action) {
              switch (action) {
                case 'drive':
                  unawaited(openPhotoUrl(context, current.src.preview ?? current.src.download));
                case 'edit':
                  unawaited(_edit(current));
                case 'cover':
                  unawaited(widget.onSetCover!(current));
                case 'delete':
                  unawaited(_delete(current));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'drive',
                child: ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text('เปิดใน Google Drive', style: GoogleFonts.kanit()),
                ),
              ),
              if (_canManage)
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text('แก้ไขชื่อ / ผู้ส่ง / วันที่ถ่าย', style: GoogleFonts.kanit()),
                  ),
                ),
              if (widget.onSetCover != null)
                PopupMenuItem(
                  value: 'cover',
                  child: ListTile(
                    leading: const Icon(Icons.star_outline_rounded),
                    title: Text('ตั้งเป็นภาพปก', style: GoogleFonts.kanit()),
                  ),
                ),
              if (widget.onDelete != null)
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                    title: Text('ลบ', style: GoogleFonts.kanit(color: Colors.red.shade700)),
                  ),
                ),
            ],
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
              onTap: () => openPhotoUrl(context, m.src.preview ?? m.src.download),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DriveImage(url: m.src.large, fallbackUrl: m.src.thumbFallback, fit: BoxFit.contain),
                  const Center(child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white70)),
                ],
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: DriveImage(url: m.src.large, fallbackUrl: m.src.thumbFallback, fit: BoxFit.contain),
          );
        },
      ),
      bottomNavigationBar: _showInfo
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _info(current),
              ),
            )
          : null,
    );
  }
}

// MARK: - Edit media (SuperAdmin)

class _EditMediaDialog extends StatefulWidget {
  const _EditMediaDialog({required this.admin, required this.item});

  final AdminUser admin;
  final PhotoMediaItem item;

  @override
  State<_EditMediaDialog> createState() => _EditMediaDialogState();
}

class _EditMediaDialogState extends State<_EditMediaDialog> {
  late final (String, String) _parts = splitPhotoExtension(widget.item.name);
  late final _name = TextEditingController(text: _parts.$1);
  late final _uploader = TextEditingController(text: widget.item.uploadedByName ?? '');

  /// Capture time as Bangkok wall time; null clears it.
  late DateTime? _takenAt = widget.item.takenAt == null ? null : bangkokTime(widget.item.takenAt!);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _uploader.dispose();
    super.dispose();
  }

  Future<void> _pickTakenAt() async {
    final base = _takenAt ?? bangkokTime(widget.item.createdAt) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (time == null || !mounted) return;
    setState(() => _takenAt = DateTime.utc(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'ใส่ชื่อไฟล์');
      return;
    }
    final uploader = _uploader.text.trim();
    final takenAt = _takenAt?.subtract(const Duration(hours: 7)).toIso8601String();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await photoCall(
        context,
        widget.admin,
        (api, t) => api.updateMedia(
          widget.item.id,
          t,
          name: name,
          uploadedByName: uploader.isEmpty ? null : uploader,
          takenAt: takenAt,
        ),
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = photoErrorText(e, 'บันทึกไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taken = _takenAt;
    final takenLabel = taken == null
        ? 'ไม่ระบุ'
        : formatPhotoDateTime(taken.subtract(const Duration(hours: 7)).toIso8601String());
    return AlertDialog(
      title: Text('แก้ไขไฟล์', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'ชื่อไฟล์',
                suffixText: _parts.$2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _uploader,
              enabled: !_busy,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'ผู้ส่ง', border: OutlineInputBorder()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text('วันที่ถ่าย', style: GoogleFonts.kanit(fontSize: 13)),
              subtitle: Text(takenLabel, style: GoogleFonts.kanit(fontSize: 15, fontWeight: FontWeight.w600)),
              trailing: taken == null
                  ? null
                  : IconButton(
                      tooltip: 'ล้างวันที่ถ่าย',
                      onPressed: _busy ? null : () => setState(() => _takenAt = null),
                      icon: const Icon(Icons.clear_rounded),
                    ),
              onTap: _busy ? null : _pickTakenAt,
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
