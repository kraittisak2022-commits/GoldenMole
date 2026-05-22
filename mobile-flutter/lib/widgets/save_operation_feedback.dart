import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// โอเวอร์เลย์ «กำลังบันทึก» / «ทำรายการสำเร็จ» สำหรับฟอร์มบันทึกประจำวัน
class SaveOperationFeedback {
  SaveOperationFeedback._();

  static void showSaving(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: _SavingFeedbackDialog(),
      ),
    );
  }

  static void dismissSaving(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  /// แสดง success แล้วปิด dialog — [onAfterDismiss] เรียกหลังปิด (เช่น pop กลับหน้าหลัก)
  static Future<void> showSuccessThenDismiss({
    required BuildContext context,
    required String message,
    Duration holdAfterAnimation = const Duration(milliseconds: 1200),
    required VoidCallback onAfterDismiss,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: _SuccessFeedbackDialog(
          message: message,
          holdAfterAnimation: holdAfterAnimation,
        ),
      ),
    );
    onAfterDismiss();
  }
}

class _SavingFeedbackDialog extends StatefulWidget {
  const _SavingFeedbackDialog();

  @override
  State<_SavingFeedbackDialog> createState() => _SavingFeedbackDialogState();
}

class _SavingFeedbackDialogState extends State<_SavingFeedbackDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            return Transform.scale(
              scale: 0.98 + math.sin(t * math.pi * 2) * 0.02,
              child: child,
            );
          },
          child: Container(
            width: math.min(MediaQuery.sizeOf(context).width * 0.82, 320),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _SavingRingPainter(progress: _ctrl.value),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'กำลังบันทึกข้อมูล',
                  style: GoogleFonts.kanit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'กรุณารอสักครู่…',
                  style: GoogleFonts.kanit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                _SavingDots(animation: _ctrl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavingDots extends StatelessWidget {
  const _SavingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (animation.value * 3 + i * 0.33) % 1.0;
            final lift = math.sin(phase * math.pi) * 6;
            final opacity = 0.35 + math.sin(phase * math.pi) * 0.65;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              transform: Matrix4.translationValues(0, -lift, 0),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF42A5F5).withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _SavingRingPainter extends CustomPainter {
  _SavingRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final track = Paint()
      ..color = const Color(0xFFE3F2FD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final sweep = progress * math.pi * 1.6 + 0.8;
    final arc = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFF1565C0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _SavingRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SuccessFeedbackDialog extends StatefulWidget {
  const _SuccessFeedbackDialog({
    required this.message,
    required this.holdAfterAnimation,
  });

  final String message;
  final Duration holdAfterAnimation;

  @override
  State<_SuccessFeedbackDialog> createState() => _SuccessFeedbackDialogState();
}

class _SuccessFeedbackDialogState extends State<_SuccessFeedbackDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _ripple;
  late final Animation<double> _cardScale;
  late final Animation<double> _cardOpacity;
  late final Animation<double> _checkScale;
  late final Animation<double> _textSlide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _cardScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0, 0.55, curve: Curves.elasticOut),
    );
    _cardOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );
    _checkScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.2, 0.75, curve: Curves.elasticOut),
    );
    _textSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
    );

    _entrance.forward();
    _ripple.repeat();
    _scheduleClose();
  }

  Future<void> _scheduleClose() async {
    await Future<void>.delayed(
      const Duration(milliseconds: 650) + widget.holdAfterAnimation,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 340.0);
    return Center(
      child: FadeTransition(
        opacity: _cardOpacity,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(_cardScale),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFFA5D6A7).withValues(alpha: 0.65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.22),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _ripple,
                          builder: (context, _) {
                            return CustomPaint(
                              size: const Size(88, 88),
                              painter: _SuccessRipplePainter(
                                progress: _ripple.value,
                              ),
                            );
                          },
                        ),
                        ScaleTransition(
                          scale: Tween<double>(begin: 0, end: 1)
                              .animate(_checkScale),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF43A047),
                                  Color(0xFF2E7D32),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x402E7D32),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(_textSlide),
                    child: FadeTransition(
                      opacity: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            'ทำรายการสำเร็จ',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.kanit(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1B5E20),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Saved successfully',
                            style: GoogleFonts.kanit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: const Color(0xFF66BB6A),
                            ),
                          ),
                          if (widget.message.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              widget.message.trim(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.kanit(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF455A64),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessRipplePainter extends CustomPainter {
  _SuccessRipplePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final p = ((progress + i * 0.28) % 1.0);
      final radius = 20 + p * 34;
      final opacity = (1 - p) * 0.35;
      final paint = Paint()
        ..color = const Color(0xFF66BB6A).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessRipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
