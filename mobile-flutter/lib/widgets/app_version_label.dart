import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// ป้ายเวอร์ชันแอพ — โหลดจาก package_info ครั้งเดียว
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({
    super.key,
    this.color = const Color(0xFF9AAFBF),
    this.fontSize = 11,
    this.prefix = 'v',
  });

  final Color color;
  final double fontSize;
  final String prefix;

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final v = _version;
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    return Text(
      '${widget.prefix}$v',
      // Bundled pubspec font — safe when this label appears on splash/login
      // while GoogleFonts may still be resolving elsewhere.
      style: TextStyle(
        fontFamily: 'Kanit',
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w500,
        color: widget.color,
        letterSpacing: 0.2,
      ),
    );
  }
}
