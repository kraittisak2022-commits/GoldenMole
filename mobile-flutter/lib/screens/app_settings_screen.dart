import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_user.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    super.key,
    required this.onOpenEmployees,
    required this.onOpenTransactions,
    required this.onOpenProjects,
    required this.onOpenMobileAndroidHub,
    required this.currentAdmin,
  });

  final VoidCallback onOpenEmployees;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenMobileAndroidHub;
  final AdminUser currentAdmin;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _notifications = true;
  bool _smoothAnimations = true;
  bool _compactTiles = true;
  bool _saving = false;
  bool _cacheLoading = false;
  bool _cacheClearing = false;
  int? _cacheBytes;
  DateTime? _cacheNewestFileAt;
  DateTime? _cacheMeasuredAt;
  DateTime? _lastCacheClearedAt;

  static const _kNotifications = 'app_notifications_enabled';
  static const _kAnimations = 'app_smooth_animations';
  static const _kCompactTiles = 'app_compact_tiles';
  static const _kLastCacheClearMillis = 'app_last_cache_clear_millis';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _refreshCacheInfo();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes ไบต์';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _formatDateTimeThai(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final be = d.year + 543;
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$be $hh:$min น.';
  }

  Future<({int bytes, DateTime? newest})> _measureCacheDir(Directory dir) async {
    if (!dir.existsSync()) return (bytes: 0, newest: null);
    var total = 0;
    DateTime? newest;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final len = await entity.length();
        total += len;
        final lm = await entity.lastModified();
        if (newest == null || lm.isAfter(newest)) newest = lm;
      }
    } catch (_) {
      return (bytes: total, newest: newest);
    }
    return (bytes: total, newest: newest);
  }

  Future<void> _refreshCacheInfo() async {
    setState(() => _cacheLoading = true);
    try {
      final cacheRoot = await getApplicationCacheDirectory();
      final measured = await _measureCacheDir(Directory(cacheRoot.path));
      if (!mounted) return;
      setState(() {
        _cacheBytes = measured.bytes;
        _cacheNewestFileAt = measured.newest;
        _cacheMeasuredAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cacheBytes = null;
        _cacheNewestFileAt = null;
        _cacheMeasuredAt = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _cacheLoading = false);
    }
  }

  Future<void> _clearApplicationCache() async {
    setState(() => _cacheClearing = true);
    try {
      final dir = await getApplicationCacheDirectory();
      if (dir.existsSync()) {
        for (final e in dir.listSync()) {
          if (e is File) {
            await e.delete();
          } else if (e is Directory) {
            await e.delete(recursive: true);
          }
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastCacheClearMillis, DateTime.now().millisecondsSinceEpoch);
      if (!mounted) return;
      setState(() {
        _lastCacheClearedAt = DateTime.now();
      });
      await _refreshCacheInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ล้างแคชของแอปแล้ว',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ล้างแคชไม่สำเร็จ: $e',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cacheClearing = false);
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final clearMs = prefs.getInt(_kLastCacheClearMillis);
    if (!mounted) return;
    setState(() {
      _notifications = prefs.getBool(_kNotifications) ?? true;
      _smoothAnimations = prefs.getBool(_kAnimations) ?? true;
      _compactTiles = prefs.getBool(_kCompactTiles) ?? true;
      _lastCacheClearedAt =
          clearMs != null ? DateTime.fromMillisecondsSinceEpoch(clearMs) : null;
    });
  }

  Future<void> _savePrefs() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifications, _notifications);
    await prefs.setBool(_kAnimations, _smoothAnimations);
    await prefs.setBool(_kCompactTiles, _compactTiles);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('บันทึกการตั้งค่าสำเร็จ', style: GoogleFonts.kanit()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FA),
        appBar: AppBar(
          title: Text(
            'ตั้งค่าแอพ',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SectionCard(
              title: 'การตั้งค่าแอพ',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('เปิดการแจ้งเตือน', style: GoogleFonts.kanit()),
                    subtitle: Text(
                      'แจ้งเตือนสถานะงานและข้อมูลสำคัญ',
                      style: GoogleFonts.kanit(fontSize: 12),
                    ),
                    value: _notifications,
                    onChanged: (v) => setState(() => _notifications = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('อนิเมชันลื่นไหล', style: GoogleFonts.kanit()),
                    subtitle: Text(
                      'เปิดเอฟเฟกต์การเปลี่ยนหน้าและปุ่ม',
                      style: GoogleFonts.kanit(fontSize: 12),
                    ),
                    value: _smoothAnimations,
                    onChanged: (v) => setState(() => _smoothAnimations = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('โหมดเมนูกระชับ', style: GoogleFonts.kanit()),
                    subtitle: Text(
                      'ย่อขนาดการ์ดเมนูให้พอดีหน้าจอเดียว',
                      style: GoogleFonts.kanit(fontSize: 12),
                    ),
                    value: _compactTiles,
                    onChanged: (v) => setState(() => _compactTiles = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _savePrefs,
                    icon: _saving
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'กำลังบันทึก...' : 'บันทึกการตั้งค่า',
                      style: GoogleFonts.kanit(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SectionCard(
              title: 'แคชในเครื่อง',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'นับจากโฟลเดอร์แคชระบบของแอป (ภาพ/ไฟล์ชั่วคราวที่ระบบจัดเก็บ)',
                    style: GoogleFonts.kanit(
                      fontSize: 12.5,
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'ขนาดประมาณ',
                    value: _cacheLoading
                        ? 'กำลังคำนวณ...'
                        : (_cacheBytes != null ? _formatBytes(_cacheBytes!) : 'ไม่ทราบ'),
                  ),
                  _InfoRow(
                    label: 'ไฟล์ล่าสุด',
                    value: _cacheLoading
                        ? '—'
                        : _formatDateTimeThai(_cacheNewestFileAt),
                  ),
                  _InfoRow(
                    label: 'วัดครั้งล่าสุด',
                    value: _formatDateTimeThai(_cacheMeasuredAt),
                  ),
                  _InfoRow(
                    label: 'ล้างล่าสุด',
                    value: _formatDateTimeThai(_lastCacheClearedAt),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _cacheLoading ? null : _refreshCacheInfo,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(
                            'คำนวณใหม่',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_cacheLoading || _cacheClearing)
                              ? null
                              : _clearApplicationCache,
                          icon: _cacheClearing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: Text(
                            _cacheClearing ? 'กำลังล้าง...' : 'ล้างแคช',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SectionCard(
              title: 'แอป Android',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    isThreeLine: true,
                    leading: const Icon(Icons.smartphone_outlined, color: Color(0xFF00897B)),
                    title: Text(
                      'รายงานข้อผิดพลาด / บั๊ค',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'ส่งเข้าเว็บ ดูประวัติ และแจ้งปัญหาด้วยตนเอง',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onOpenMobileAndroidHub,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SectionCard(
              title: 'บัญชีผู้ใช้',
              child: Column(
                children: [
                  _InfoRow(
                    label: 'ชื่อผู้ใช้',
                    value: widget.currentAdmin.username,
                  ),
                  _InfoRow(
                    label: 'ชื่อแสดงผล',
                    value: widget.currentAdmin.displayName,
                  ),
                  _InfoRow(label: 'สิทธิ์', value: widget.currentAdmin.role),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'การเปลี่ยนรหัสผ่าน/โปรไฟล์ขั้นสูง สามารถทำผ่านเว็บแอพได้',
                      style: GoogleFonts.kanit(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.kanit(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: GoogleFonts.kanit(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

