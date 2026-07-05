import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_sync_snapshot.dart';
import '../services/count_record_offline_sync.dart';
import 'sync_failed_queue_sheet.dart';

/// แถบสถานะซิงค์ทั้งแอป — วางทับด้านบนของ [child]
class AppSyncBannerHost extends StatelessWidget {
  const AppSyncBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ValueListenableBuilder<AppSyncSnapshot>(
          valueListenable: CountRecordOfflineSync.instance.syncState,
          builder: (context, snapshot, _) {
            return _AppSyncBanner(snapshot: snapshot);
          },
        ),
      ],
    );
  }
}

class _AppSyncBanner extends StatelessWidget {
  const _AppSyncBanner({required this.snapshot});

  final AppSyncSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final visible = snapshot.showBanner;
    final isSuccess = snapshot.activity == SyncActivity.syncedFlash;
    final isFailure = snapshot.failedCount > 0 &&
        snapshot.activity != SyncActivity.syncing &&
        !AppSyncSnapshot.uploadInFlightHint;

    Color bg;
    Color fg;
    IconData icon;
    if (isSuccess) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      icon = Icons.check_circle_rounded;
    } else if (isFailure) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
      icon = Icons.warning_amber_rounded;
    } else if (snapshot.network == NetworkLinkState.unlink) {
      bg = const Color(0xFFECEFF1);
      fg = const Color(0xFF546E7A);
      icon = Icons.wifi_off_rounded;
    } else if (snapshot.server == ServerReachState.offline) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      icon = Icons.cloud_off_rounded;
    } else if (snapshot.isSyncing) {
      bg = Colors.white.withValues(alpha: 0.96);
      fg = const Color(0xFF3A4A5E);
      icon = Icons.sync_rounded;
    } else {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
      icon = Icons.cloud_upload_outlined;
    }

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.4),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 240),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isFailure
                      ? () => SyncFailedQueueSheet.show(context)
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: fg.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (snapshot.isSyncing && !isSuccess)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: fg,
                              ),
                            )
                          else
                            Icon(icon, size: 16, color: fg),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              snapshot.bannerMessage,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: fg,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (snapshot.pendingCount > 0 &&
                              !isFailure &&
                              !isSuccess &&
                              snapshot.isEffectivelyOnline) ...[
                            const SizedBox(width: 8),
                            _SyncNowChip(
                              onPressed: () => unawaited(
                                CountRecordOfflineSync.instance.syncNow(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncNowChip extends StatelessWidget {
  const _SyncNowChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF11A8BA),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'ซิงค์เลย',
            style: GoogleFonts.kanit(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
