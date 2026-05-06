import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PageLoadingView extends StatefulWidget {
  const PageLoadingView({
    super.key,
    this.label = 'กำลังโหลดข้อมูล',
  });

  final String label;

  @override
  State<PageLoadingView> createState() => _PageLoadingViewState();
}

class _PageLoadingViewState extends State<PageLoadingView> {
  Timer? _timer;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) return;
      setState(() {
        if (_progress < 90) {
          _progress += 1 + math.Random().nextInt(3);
          if (_progress > 90) _progress = 90;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
              ).createShader(rect),
              child: Text(
                '${_progress.toString().padLeft(2, '0')}%',
                style: GoogleFonts.kanit(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 10,
                backgroundColor: const Color(0xFFE8EEF5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1E88E5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: GoogleFonts.kanit(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
