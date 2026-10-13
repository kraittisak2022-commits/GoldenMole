import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/photo_upload_manager.dart';
import '../theme/daily_palette.dart';
import '../utils/photo_album_format.dart';
import 'photo_album_common.dart';

/// Upload panel like the web's UploadTray: summary, overall progress, a collapsible per-file list
/// with cancel / retry, and once everything is done the copy button for the album.
/// [albumId] limits it to one album; null shows every upload.
class PhotoUploadTray extends StatefulWidget {
  const PhotoUploadTray({super.key, this.albumId});

  final String? albumId;

  @override
  State<PhotoUploadTray> createState() => _PhotoUploadTrayState();
}

class _PhotoUploadTrayState extends State<PhotoUploadTray> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final manager = PhotoUploadManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final items = manager.itemsFor(widget.albumId);
        if (items.isEmpty) return const SizedBox.shrink();
        return _panel(context, manager, items);
      },
    );
  }

  Widget _panel(BuildContext context, PhotoUploadManager manager, List<PhotoUploadItem> items) {
    final p = DailyPalette.of(context);
    final active = items.where((i) => i.isActive).length;
    final failed = items.where((i) => i.status == PhotoUploadStatus.error).length;
    final done = items.where((i) => i.status == PhotoUploadStatus.done).length;
    final title = active > 0
        ? 'กำลังอัปโหลด $active รายการ'
        : failed > 0
            ? 'อัปโหลดไม่สำเร็จ $failed รายการ'
            : 'อัปโหลดแล้ว $done รายการ';

    final counted = items.where(
      (i) => i.status != PhotoUploadStatus.canceled && i.status != PhotoUploadStatus.error,
    );
    final total = counted.fold<int>(0, (s, i) => s + i.media.size);
    final sent = counted.fold<double>(
      0,
      (s, i) => s + i.media.size * (i.status == PhotoUploadStatus.done ? 1 : i.progress),
    );
    final overall = total > 0 ? sent / total : 0.0;

    final albums = {for (final i in items) i.album.id: i.album};
    final shareAlbum = active == 0 && failed == 0 && done > 0 && albums.length == 1 ? albums.values.first : null;

    return Material(
      color: p.card,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
              child: Row(
                children: [
                  if (failed > 0 && active == 0)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.error_outline_rounded, color: Colors.red),
                    )
                  else if (active == 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: 15, color: p.ink),
                        ),
                        if (active > 0)
                          Text(
                            'เปิดแอปค้างไว้จนกว่าจะเสร็จ · ไปหน้าอื่นในอัลบั้มได้',
                            style: GoogleFonts.kanit(fontSize: 12, color: p.inkMuted),
                          ),
                      ],
                    ),
                  ),
                  if (failed > 0 && active == 0)
                    TextButton(
                      onPressed: () => manager.retryFailed(widget.albumId),
                      child: const Text('ลองใหม่ทั้งหมด'),
                    ),
                  IconButton(
                    tooltip: _collapsed ? 'แสดงรายการ' : 'ย่อรายการ',
                    onPressed: () => setState(() => _collapsed = !_collapsed),
                    icon: Icon(_collapsed ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  ),
                  if (active == 0)
                    IconButton(
                      tooltip: 'ปิด',
                      onPressed: () => manager.clearFinished(widget.albumId),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            if (active > 0) LinearProgressIndicator(value: overall, minHeight: 3, color: kPhotoAlbumAccent),
            if (shareAlbum != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.albumId == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          shareAlbum.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kanit(fontSize: 13, color: p.inkMuted),
                        ),
                      ),
                    PhotoAlbumShareButtons(album: shareAlbum, showDrive: false),
                  ],
                ),
              ),
            if (!_collapsed)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _UploadRow(item: items[i], manager: manager),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.item, required this.manager});

  final PhotoUploadItem item;
  final PhotoUploadManager manager;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final size = formatPhotoBytes(item.media.size);
    final detail = switch (item.status) {
      PhotoUploadStatus.error => item.error ?? 'อัปโหลดไม่สำเร็จ',
      PhotoUploadStatus.canceled => 'ยกเลิกแล้ว',
      PhotoUploadStatus.queued => 'รอคิว · $size',
      PhotoUploadStatus.done => size,
      PhotoUploadStatus.uploading => '${(item.progress * 100).round()}% · $size',
    };

    final Widget trailing = switch (item.status) {
      PhotoUploadStatus.done => Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
        ),
      PhotoUploadStatus.error when item.media.withinLimit => IconButton(
          tooltip: 'ลองใหม่',
          onPressed: () => manager.retry(item.id),
          icon: const Icon(Icons.refresh_rounded),
        ),
      PhotoUploadStatus.queued || PhotoUploadStatus.uploading => IconButton(
          tooltip: 'ยกเลิก',
          onPressed: () => manager.cancel(item.id),
          icon: const Icon(Icons.close_rounded),
        ),
      _ => const SizedBox(width: 48),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: PickedMediaThumb(media: item.media),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(fontSize: 13.5, color: p.ink),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontSize: 12,
                    color: item.status == PhotoUploadStatus.error ? Colors.red.shade700 : p.inkMuted,
                  ),
                ),
                if (item.status == PhotoUploadStatus.uploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 3,
                      color: kPhotoAlbumAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}