import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/admin_user.dart';
import '../services/photo_album_service.dart';
import '../utils/photo_album_format.dart';
import '../widgets/photo_album_common.dart';

String _largeFallback(PhotoMediaItem m) => m.src.thumbFallback.replaceAll(RegExp(r'sz=w\d+'), 'sz=w2048');

double _aspectOf(PhotoMediaItem m) =>
    m.width > 0 && m.height > 0 ? m.width / m.height : (m.isVideo ? 16 / 9 : 4 / 3);

enum _Drag { none, pending, vertical, other }

/// Full-screen viewer (apps/photo/src/components/Lightbox.tsx): swipe sideways to move, down to close,
/// up for info, tap to hide the bars, pinch or double tap to zoom. Videos play in Drive's player.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
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
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late final List<PhotoMediaItem> _media = [...widget.media];

  final TransformationController _zoom = TransformationController();
  late final AnimationController _zoomAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _zoomTween;
  bool _zoomed = false;
  Offset _doubleTapAt = Offset.zero;

  bool _chrome = true;
  bool _showInfo = false;

  String? _playingId;
  WebViewController? _player;

  int _pointers = 0;
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _dragT0 = Duration.zero;
  double _dragDy = 0;

  bool get _canManage => canManagePhotoAlbums(widget.admin);

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _zoom.value = tween.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _precache());
  }

  @override
  void dispose() {
    _zoom.dispose();
    _zoomAnim.dispose();
    _pages.dispose();
    super.dispose();
  }

  // MARK: Zoom

  void _onZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _animateZoom(Matrix4 to) {
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: to)
        .animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim.forward(from: 0);
  }

  void _toggleZoom() {
    if (_zoomed) {
      _animateZoom(Matrix4.identity());
      return;
    }
    const s = 2.5;
    final p = _doubleTapAt;
    _animateZoom(Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-p.dx * (s - 1), -p.dy * (s - 1), 0));
  }

  // MARK: Paging

  /// Neighbours two steps either way, so swiping shows the full-size photo straight away.
  void _precache() {
    if (!mounted) return;
    for (var i = _index - 2; i <= _index + 2; i++) {
      if (i < 0 || i >= _media.length || i == _index) continue;
      final url = _media[i].src.large;
      if (url.isEmpty) continue;
      unawaited(precacheImage(NetworkImage(url), context, onError: (_, _) {}));
    }
  }

  void _onPage(int i) {
    _zoomAnim.stop();
    _zoom.value = Matrix4.identity();
    setState(() {
      _index = i;
      _playingId = null;
      _player = null;
    });
    _precache();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= _media.length) return;
    _pages.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  void _onTap() {
    setState(() {
      if (_showInfo) {
        _showInfo = false;
      } else {
        _chrome = !_chrome;
      }
    });
  }

  // MARK: Swipe down to close / up for info (raw pointers so pinch, paging and taps keep working)

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _drag = _Drag.pending;
      _dragStart = e.position;
      _dragT0 = e.timeStamp;
    } else {
      _drag = _Drag.other;
      if (_dragDy != 0) setState(() => _dragDy = 0);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_pointers != 1 || _zoomed || _playingId != null) return;
    final d = e.position - _dragStart;
    if (_drag == _Drag.pending) {
      if (d.distance < 12) return;
      _drag = d.dy.abs() > d.dx.abs() ? _Drag.vertical : _Drag.other;
    }
    if (_drag == _Drag.vertical) setState(() => _dragDy = d.dy);
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_drag == _Drag.vertical && e is PointerUpEvent) {
      final ms = math.max(1, (e.timeStamp - _dragT0).inMilliseconds);
      final speed = _dragDy / ms;
      if (_dragDy > 0 && (_dragDy > 140 || speed > 0.8)) {
        Navigator.of(context).pop();
        return;
      }
      if (_dragDy < -60) _showInfo = true;
    }
    if (_pointers == 0) {
      _drag = _Drag.none;
      setState(() => _dragDy = 0);
    }
  }

  // MARK: Actions

  void _play(PhotoMediaItem m) {
    final preview = m.src.preview;
    if (preview == null || preview.isEmpty) {
      unawaited(openPhotoUrl(context, m.src.download));
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame || request.url.contains('/preview')) return NavigationDecision.navigate;
          unawaited(openPhotoUrl(context, request.url));
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(preview));
    setState(() {
      _player = controller;
      _playingId = m.id;
      _chrome = true;
    });
  }

  Future<void> _delete(PhotoMediaItem m) async {
    final deleted = await widget.onDelete!(m);
    if (!deleted || !mounted) return;
    setState(() {
      _media.removeWhere((x) => x.id == m.id);
      if (_index >= _media.length) _index = _media.length - 1;
      _playingId = null;
      _player = null;
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

  // MARK: Build

  Widget _page(int i) {
    final m = _media[i];
    final current = i == _index;
    if (m.isVideo) {
      final player = _player;
      if (current && _playingId == m.id && player != null) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: Center(
              child: AspectRatio(aspectRatio: _aspectOf(m), child: WebViewWidget(controller: player)),
            ),
          ),
        );
      }
      return GestureDetector(
        onTap: _onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DriveImage(url: m.src.large, fallbackUrl: _largeFallback(m), fit: BoxFit.contain),
            Center(
              child: IconButton(
                tooltip: 'เล่นวิดีโอ',
                iconSize: 76,
                onPressed: () => _play(m),
                icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: current ? _zoom : null,
        panEnabled: current && _zoomed,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: DriveImage(url: m.src.large, fallbackUrl: _largeFallback(m), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _topBar(PhotoMediaItem current) {
    const white = Colors.white;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
          child: Row(
            children: [
              IconButton(
                tooltip: 'ปิด',
                color: white,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  '${_index + 1} / ${_media.length}',
                  style: GoogleFonts.kanit(color: Colors.white70, fontSize: 14),
                ),
              ),
              IconButton(
                tooltip: 'ข้อมูล',
                color: white,
                isSelected: _showInfo,
                onPressed: () => setState(() => _showInfo = !_showInfo),
                icon: const Icon(Icons.info_outline_rounded),
                selectedIcon: const Icon(Icons.info_rounded),
              ),
              IconButton(
                tooltip: 'บันทึก / แชร์ไฟล์',
                color: white,
                onPressed: () => sharePhotoMediaFiles(context, [current]),
                icon: const Icon(Icons.download_rounded),
              ),
              if (_canManage)
                IconButton(
                  tooltip: 'แก้ไข',
                  color: white,
                  onPressed: () => _edit(current),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (widget.onDelete != null)
                IconButton(
                  tooltip: 'ลบ',
                  color: white,
                  onPressed: () => _delete(current),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              PopupMenuButton<String>(
                iconColor: white,
                onSelected: (action) {
                  if (action == 'drive') {
                    unawaited(openPhotoUrl(context, current.src.preview ?? current.src.download));
                  } else if (action == 'cover') {
                    unawaited(widget.onSetCover!(current));
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
                  if (widget.onSetCover != null)
                    PopupMenuItem(
                      value: 'cover',
                      child: ListTile(
                        leading: const Icon(Icons.star_outline_rounded),
                        title: Text('ตั้งเป็นภาพปก', style: GoogleFonts.kanit()),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(PhotoMediaItem m) {
    final muted = GoogleFonts.kanit(color: Colors.white70, fontSize: 13.5);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: Text(label, style: muted)),
              Expanded(child: Text(value, style: muted)),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F20),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      m.name,
                      style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
                if (_canManage)
                  IconButton(
                    tooltip: 'แก้ไขชื่อ ผู้ส่ง และวันที่ถ่าย',
                    color: Colors.white,
                    onPressed: () => _edit(m),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
              ],
            ),
            if (m.takenAt != null) row('ถ่ายเมื่อ', formatPhotoDateTime(m.takenAt!)),
            row(
              'อัปโหลด',
              '${formatPhotoDateTime(m.createdAt)}${m.uploadedByName != null ? ' โดย ${m.uploadedByName}' : ''}',
            ),
            if (m.width > 0 && m.height > 0) row('ขนาด', '${m.width} × ${m.height}'),
          ],
        ),
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap, String label) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(tooltip: label, color: Colors.white, iconSize: 30, onPressed: onTap, icon: Icon(icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_media.isEmpty) return const ColoredBox(color: Colors.black);
    final current = _media[_index];
    final height = MediaQuery.sizeOf(context).height;
    final pulled = _dragDy > 0 ? _dragDy : 0.0;
    final progress = (pulled / height).clamp(0.0, 1.0);
    final scale = 1 - progress * 0.25;
    final playing = _playingId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 1 - progress)),
          ),
          Positioned.fill(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: AnimatedContainer(
                duration: _pointers > 0 ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transformAlignment: Alignment.center,
                transform: Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(0, pulled, 0),
                child: PageView.builder(
                  controller: _pages,
                  physics: _zoomed || playing ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                  dragStartBehavior: DragStartBehavior.down,
                  itemCount: _media.length,
                  onPageChanged: _onPage,
                  itemBuilder: (context, i) => _page(i),
                ),
              ),
            ),
          ),
          if (playing && _chrome) ...[
            if (_index > 0)
              Positioned(
                left: 8,
                top: height / 2 - 28,
                child: _navButton(Icons.chevron_left_rounded, () => _go(-1), 'ก่อนหน้า'),
              ),
            if (_index < _media.length - 1)
              Positioned(
                right: 8,
                top: height / 2 - 28,
                child: _navButton(Icons.chevron_right_rounded, () => _go(1), 'ถัดไป'),
              ),
          ],
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !_chrome || pulled > 0,
              child: AnimatedOpacity(
                opacity: _chrome && pulled == 0 ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: _topBar(current),
              ),
            ),
          ),
          if (_showInfo)
            Positioned(left: 0, right: 0, bottom: 0, child: _info(current)),
        ],
      ),
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
