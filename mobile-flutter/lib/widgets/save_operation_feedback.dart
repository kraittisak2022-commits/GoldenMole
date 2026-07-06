import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../utils/app_haptics.dart';
import 'package:google_fonts/google_fonts.dart';

enum _SavePhase { saving, success }

class _SaveDialogSession {
  _SaveDialogSession(this.navigator);

  final NavigatorState navigator;
  final ValueNotifier<_SavePhase> phase = ValueNotifier(_SavePhase.saving);
  final ValueNotifier<String> message = ValueNotifier('');
  final Completer<void> closed = Completer<void>();
  bool popScheduled = false;

  void dispose() {
    phase.dispose();
    message.dispose();
  }
}

/// โอเวอร์เลย์ «กำลังบันทึก» → «ทำรายการสำเร็จ» — dialog เดียว morph ต่อเนื่อง
/// ไม่ปิดแล้วเปิดใหม่ ฉากหลังไม่กะพริบ และมีอนิเมชันเข้า/ออกนุ่มนวล
class SaveOperationFeedback {
  SaveOperationFeedback._();

  static _SaveDialogSession? _session;

  static void showSaving(BuildContext context) {
    if (_session != null) {
      _session!.phase.value = _SavePhase.saving;
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    final session = _SaveDialogSession(nav);
    _session = session;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'saving',
        barrierColor: Colors.black.withValues(alpha: 0.4),
        useRootNavigator: true,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) => PopScope(
          canPop: false,
          child: _SaveFeedbackDialog(session: session),
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ).whenComplete(() {
        if (identical(_session, session)) _session = null;
        if (!session.closed.isCompleted) session.closed.complete();
        session.dispose();
      }),
    );
  }

  static void dismissSaving(BuildContext context) {
    final session = _session;
    if (session == null || session.popScheduled) return;
    session.popScheduled = true;
    if (session.navigator.canPop()) session.navigator.pop();
  }

  /// morph dialog ที่เปิดอยู่เป็น success (หรือเปิดใหม่ถ้ายังไม่มี) แล้วปิดอัตโนมัติ
  /// [onAfterDismiss] เรียกหลังปิด (เช่น pop กลับหน้าหลัก)
  static Future<void> showSuccessThenDismiss({
    required BuildContext context,
    required String message,
    Duration holdAfterAnimation = const Duration(milliseconds: 1200),
    required VoidCallback onAfterDismiss,
  }) async {
    var session = _session;
    if (session == null) {
      if (!context.mounted) {
        onAfterDismiss();
        return;
      }
      showSaving(context);
      session = _session;
    }
    if (session == null) {
      onAfterDismiss();
      return;
    }
    session.message.value = message;
    session.phase.value = _SavePhase.success;

    // รอ morph + อนิเมชันติ๊กถูก แล้วค้างไว้ให้ผู้ใช้เห็น
    await Future<void>.delayed(
      const Duration(milliseconds: 620) + holdAfterAnimation,
    );

    if (!session.popScheduled) {
      session.popScheduled = true;
      if (session.navigator.canPop()) session.navigator.pop();
    }
    await session.closed.future;
    onAfterDismiss();
  }
}

class _SaveFeedbackDialog extends StatelessWidget {
  const _SaveFeedbackDialog({required this.session});

  final _SaveDialogSession session;

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.84, 330.0);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ValueListenableBuilder<_SavePhase>(
          valueListenable: session.phase,
          builder: (context, phase, _) {
            final success = phase == _SavePhase.success;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              width: width,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: success
                      ? const Color(0xFFA5D6A7).withValues(alpha: 0.65)
                      : Colors.white,
                ),
                boxShadow: [
                  BoxShadow(
                    color: success
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.22)
                        : const Color(0xFF1565C0).withValues(alpha: 0.18),
                    blurRadius: 34,
                    offset: const Offset(0, 13),
                  ),
                ],
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
                  switchOutCurve: const Interval(0.65, 1, curve: Curves.easeInCubic),
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        ?currentChild,
                      ],
                    );
                  },
                  child: success
                      ? _SuccessContent(
                          key: const ValueKey('success'),
                          messageListenable: session.message,
                        )
                      : const _SavingContent(key: ValueKey('saving')),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SavingContent extends StatefulWidget {
  const _SavingContent({super.key});

  @override
  State<_SavingContent> createState() => _SavingContentState();
}

class _SavingContentState extends State<_SavingContent>
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
    return Column(
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

class _SuccessContent extends StatefulWidget {
  const _SuccessContent({super.key, required this.messageListenable});

  final ValueListenable<String> messageListenable;

  @override
  State<_SuccessContent> createState() => _SuccessContentState();
}

class _SuccessContentState extends State<_SuccessContent>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _ripple;
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

    _checkScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.1, 0.7, curve: Curves.elasticOut),
    );
    _textSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
    );

    _entrance.forward();
    _ripple.repeat();
    AppHaptics.success();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    painter: _SuccessRipplePainter(progress: _ripple.value),
                  );
                },
              ),
              ScaleTransition(
                scale: Tween<double>(begin: 0, end: 1).animate(_checkScale),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
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
                ValueListenableBuilder<String>(
                  valueListenable: widget.messageListenable,
                  builder: (context, message, _) {
                    final trimmed = message.trim();
                    if (trimmed.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        trimmed,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.kanit(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF455A64),
                          height: 1.35,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
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
