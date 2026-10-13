import 'dart:async';

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
import 'photo_viewer_screen.dart';

const double _gridGap = 4;
const double _gridPadding = 4;

double _aspectOf(PhotoMediaItem m) =>
    m.width > 0 && m.height > 0 ? m.width / m.height : (m.isVideo ? 16 / 9 : 4 / 3);

class PhotoAlbumDetailScreen extends StatefulWidget {
  const PhotoAlbumDetailScreen({super.key, required this.admin, required this.album});

  final AdminUser admin;
  final PhotoAlbumSummary album;

  @override
  State<PhotoAlbumDetailScreen> createState() => _PhotoAlbumDetailScreenState();
}

class _PhotoAlbumDetailScreenState extends State<PhotoAlbumDetailScreen> {
  final PhotoUploadManager _uploads = PhotoUploadManager.instance;
  late PhotoAlbumSummary _album = widget.album;
  List<PhotoMediaItem>? _media;
  Object? _error;
  bool _loading = false;

  /// Uploads that finish before the album has loaded; merged in once it does.
  final List<PhotoMediaItem> _arrived = [];
  StreamSubscription<PhotoUploaded>? _uploadedSub;

  bool _selecting = false;
  final Set<String> _selected = {};

  bool get _canManage => canManagePhotoAlbums(widget.admin);

  @override
  void initState() {
    super.initState();
    _uploadedSub = _uploads.uploaded.listen(_onUploaded);
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_uploadedSub?.cancel());
    super.dispose();
  }

  List<PhotoMediaItem> _withArrived(List<PhotoMediaItem> media) {
    final known = media.map((m) => m.id).toSet();
    final fresh = _arrived.where((m) => known.add(m.id)).toList();
    return fresh.isEmpty ? media : sortPhotoMediaItems([...media, ...fresh]);
  }

  void _onUploaded(PhotoUploaded event) {
    if (event.albumId != _album.id || !mounted) return;
    _arrived.add(event.media);
    final media = _media;
    if (media != null) setState(() => _media = _withArrived(media));
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
          _media = _withArrived(detail.media);
          _selected.retainAll(_media!.map((m) => m.id));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMedia() async {
    final picked = await pickPhotoAlbumMedia(context);
    if (picked.isEmpty || !mounted) return;
    _uploads.enqueue(widget.admin, _album, picked);
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
    final i = _arrived.indexWhere((m) => m.id == item.id);
    if (i >= 0) _arrived[i] = item;
    setState(() {
      _media = sortPhotoMediaItems((_media ?? const []).map((m) => m.id == item.id ? item : m));
    });
  }

  void _openViewer(int index) {
    final media = _media;
    if (media == null) return;
    Navigator.of(context).push(
      AppPageRoute(
        page: PhotoViewerScreen(
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
    _arrived.removeWhere((m) => gone.contains(m.id));
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
        _media = _withArrived(detail.media);
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
          _media = _withArrived(saved.media);
        });
        photoSnack(context, 'บันทึกแล้ว');
      case 'relink':
        final saved = await regeneratePhotoAlbumLink(context, widget.admin, _album);
        if (saved != null && mounted) setState(() => _album = saved.album);
      case 'delete':
        if (_uploads.isBusy(_album.id)) {
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
              child: Text('ปิดการเพิ่มรูปผ่านลิงก์', style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted)),
            ),
          const SizedBox(height: 12),
          PhotoAlbumShareButtons(album: _album),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _addMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text('เพิ่มรูป/วิดีโอ', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
          ),
          if ((_media?.length ?? 0) > 1 && !_selecting)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _canManage
                    ? 'แตะค้างที่รูปเพื่อเลือกหลายรูป แล้วบันทึก แชร์ ลบ หรือตั้งเป็นภาพปก'
                    : 'แตะค้างที่รูปเพื่อเลือกหลายรูป แล้วบันทึกหรือแชร์พร้อมกัน',
                style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(PhotoMediaItem m, int index, double width, double height) {
    final selected = _selected.contains(m.id);
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () => _selecting ? _toggleSelected(m.id) : _openViewer(index),
        onLongPress: () => _toggleSelected(m.id),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.all(selected ? width * 0.07 : 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 10 : 0),
                child: DriveImage(url: m.src.thumb, fallbackUrl: m.src.thumbFallback),
              ),
            ),
            if (m.isVideo)
              const Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
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
      ),
    );
  }

  /// Day headings, then justified rows that keep each photo's shape (like Google Photos / the web grid).
  List<Widget> _mediaSlivers(DailyColors p, List<PhotoMediaItem> media, double width) {
    final inner = width - _gridPadding * 2;
    final target = photoTargetRowHeight(inner);
    final sections = groupPhotosByDay(media, takenAt: (m) => m.takenAt, createdAt: (m) => m.createdAt);
    return [
      for (final section in sections) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              formatPhotoDayHeading(section.at),
              style: GoogleFonts.kanit(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
        ),
        Builder(builder: (context) {
          final rows = justifiedPhotoRows(
            [for (final (m, _) in section.items) _aspectOf(m)],
            inner,
            target,
            _gridGap,
          );
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, r) {
                final row = rows[r];
                final h = row.height.floorToDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: _gridGap),
                  child: Row(
                    children: [
                      for (var k = 0; k < row.items.length; k++) ...[
                        if (k > 0) const SizedBox(width: _gridGap),
                        () {
                          final (m, index) = section.items[row.items[k].index];
                          return _tile(m, index, row.items[k].width.floorToDouble(), h);
                        }(),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        }),
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
        if (media?.isNotEmpty ?? false)
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
            tooltip: 'ตั้งค่าอัลบั้ม',
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

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _endSelection();
      },
      child: Scaffold(
        backgroundColor: p.surface,
        appBar: _selecting ? _selectionBar(media) : _mainBar(media),
        bottomNavigationBar: PhotoUploadTray(albumId: _album.id),
        body: RefreshIndicator(
          onRefresh: _load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final List<Widget> content;
              if (media == null && _error != null) {
                content = [SliverFillRemaining(child: PhotoAlbumErrorView(error: _error!, onRetry: _load))];
              } else if (media == null) {
                content = [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))];
              } else if (media.isEmpty) {
                content = [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined, size: 56, color: Colors.black26),
                          const SizedBox(height: 12),
                          Text(
                            'ยังไม่มีรูปในอัลบั้มนี้',
                            style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
                          ),
                          Text(
                            'กด «เพิ่มรูป/วิดีโอ» เพื่อเลือกจากเครื่องหรือถ่ายใหม่',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.kanit(fontSize: 14, color: p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
              } else {
                content = _mediaSlivers(p, media, constraints.maxWidth);
              }
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_loading && media != null)
                    const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                  SliverToBoxAdapter(child: _header(p, media?.length ?? _album.mediaCount)),
                  ...content,
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
