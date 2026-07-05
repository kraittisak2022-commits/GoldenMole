import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_sync_snapshot.dart';
import '../services/count_record_offline_sync.dart';

/// จัดการรายการที่ซิงก์ล้มเหลว — retry / ลบทิ้ง
class SyncFailedQueueSheet extends StatefulWidget {
  const SyncFailedQueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SyncFailedQueueSheet(),
    );
  }

  @override
  State<SyncFailedQueueSheet> createState() => _SyncFailedQueueSheetState();
}

class _SyncFailedQueueSheetState extends State<SyncFailedQueueSheet> {
  List<FailedSyncItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final items = await CountRecordOfflineSync.instance.listFailedItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _retry(String key) async {
    await CountRecordOfflineSync.instance.retryFailedItem(key);
    await _load();
  }

  Future<void> _discard(String key) async {
    await CountRecordOfflineSync.instance.discardFailedItem(key);
    await _load();
  }

  Future<void> _retryAll() async {
    await CountRecordOfflineSync.instance.retryAllFailed();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'รายการซิงก์ไม่สำเร็จ',
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF152535),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ลองซิงค์ใหม่หรือลบออกจากคิว — ข้อมูลในเครื่องยังอยู่',
            style: GoogleFonts.kanit(
              fontSize: 13,
              color: const Color(0xFF6C8899),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'ไม่มีรายการค้าง',
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(color: const Color(0xFF6C8899)),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return _FailedItemTile(
                    item: item,
                    onRetry: () => _retry(item.key),
                    onDiscard: () => _discard(item.key),
                  );
                },
              ),
            ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _retryAll,
              child: Text(
                'ลองซิงค์ทั้งหมด (${_items.length})',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FailedItemTile extends StatelessWidget {
  const _FailedItemTile({
    required this.item,
    required this.onRetry,
    required this.onDiscard,
  });

  final FailedSyncItem item;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3ECF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.isDelete ? Icons.delete_outline : Icons.edit_note_outlined,
              size: 20,
              color: const Color(0xFF78909C),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: const Color(0xFF1A2433),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.date} · ${item.reasonLabel}',
                    style: GoogleFonts.kanit(
                      fontSize: 12,
                      color: const Color(0xFF90A4AE),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'ลองใหม่',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: const Color(0xFF11A8BA),
            ),
            IconButton(
              tooltip: 'ลบจากคิว',
              onPressed: onDiscard,
              icon: const Icon(Icons.close_rounded, size: 20),
              color: const Color(0xFF90A4AE),
            ),
          ],
        ),
      ),
    );
  }
}
