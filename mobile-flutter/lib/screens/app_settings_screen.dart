import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_user.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    super.key,
    required this.onOpenEmployees,
    required this.onOpenTransactions,
    required this.onOpenProjects,
    required this.currentAdmin,
  });

  final VoidCallback onOpenEmployees;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenProjects;
  final AdminUser currentAdmin;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _notifications = true;
  bool _smoothAnimations = true;
  bool _compactTiles = true;
  bool _saving = false;

  static const _kNotifications = 'app_notifications_enabled';
  static const _kAnimations = 'app_smooth_animations';
  static const _kCompactTiles = 'app_compact_tiles';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifications = prefs.getBool(_kNotifications) ?? true;
      _smoothAnimations = prefs.getBool(_kAnimations) ?? true;
      _compactTiles = prefs.getBool(_kCompactTiles) ?? true;
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
              style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

