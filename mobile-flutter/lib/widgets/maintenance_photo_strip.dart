import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/maintenance_photo_store.dart';
import '../theme/daily_palette.dart';

/// แถว thumbnail รูปบำรุงรักษา — เพิ่ม/ลบได้
class MaintenancePhotoStrip extends StatelessWidget {
  const MaintenancePhotoStrip({
    super.key,
    required this.localPaths,
    required this.remoteUrls,
    required this.onAdd,
    required this.onRemove,
    this.maxPhotos = 10,
    this.enabled = true,
    this.compact = false,
  });

  final List<String> localPaths;
  final List<String> remoteUrls;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int maxPhotos;
  final bool enabled;
  final bool compact;

  int get _count =>
      localPaths.isNotEmpty ? localPaths.length : remoteUrls.length;

  bool get _canAdd => enabled && _count < maxPhotos;

  @override
  Widget build(BuildContext context) {
    final p = DailyPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = p.ink;
    final muted = p.inkMuted;
    final line = p.hairline;
    final accent =
        isDark ? const Color(0xFFFB923C) : const Color(0xFFC2410C);
    final thumb = compact ? 64.0 : 72.0;
    final gap = compact ? 8.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'รูปประกอบ',
              style: GoogleFonts.kanit(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(ไม่บังคับ)',
              style: GoogleFonts.kanit(
                fontSize: compact ? 11 : 12,
                color: muted.withValues(alpha: 0.75),
              ),
            ),
            const Spacer(),
            if (_count > 0)
              Text(
                '$_count/$maxPhotos',
                style: GoogleFonts.kanit(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < _count; i++)
              _ThumbTile(
                size: thumb,
                line: line,
                onRemove: enabled ? () => onRemove(i) : null,
                child: _ThumbImage(
                  localPath: i < localPaths.length ? localPaths[i] : null,
                  remoteUrl: i < remoteUrls.length ? remoteUrls[i] : null,
                ),
              ),
            if (_canAdd)
              Material(
                color: p.chipSurface,
                borderRadius: BorderRadius.circular(compact ? 10 : 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                  onTap: onAdd,
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.45 : 0.35),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          color: accent,
                          size: compact ? 22 : 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'เพิ่ม',
                          style: GoogleFonts.kanit(
                            fontSize: compact ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.size,
    required this.line,
    required this.child,
    this.onRemove,
  });

  final double size;
  final Color line;
  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: size, height: size, child: child),
        ),
        if (onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Colors.black87,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({this.localPath, this.remoteUrl});

  final String? localPath;
  final String? remoteUrl;

  @override
  Widget build(BuildContext context) {
    final colors = DailyPalette.of(context);
    if (localPath != null && localPath!.trim().isNotEmpty) {
      return FutureBuilder<String>(
        future: MaintenancePhotoStore.absolutePathForRelative(localPath!),
        builder: (context, snap) {
          if (!snap.hasData) {
            return ColoredBox(color: colors.chipSurface);
          }
          return Image.file(
            File(snap.data!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallback(colors),
          );
        },
      );
    }
    final url = remoteUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(colors),
      );
    }
    return _fallback(colors);
  }

  Widget _fallback(DailyColors p) {
    return ColoredBox(
      color: p.chipSurface,
      child: Icon(Icons.broken_image_outlined, color: p.inkMuted),
    );
  }
}
