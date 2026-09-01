import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../utils/app_haptics.dart';
import 'package:google_fonts/google_fonts.dart';

enum _SavePhase { saving, success, error }

class _SaveDialogSession {
  _SaveDialogSession(this.navigator);

  final NavigatorState navigator;
  final ValueNotifier<_SavePhase> phase = ValueNotifier(_SavePhase.saving);
  final ValueNotifier<String> title = ValueNotifier('');
  final ValueNotifier<String> message = ValueNotifier('');
  final ValueNotifier<String> subtitle = ValueNotifier('');
  final Completer<void> closed = Completer<void>();
  Completer<void>? dismissWait;
  bool popScheduled = false;
  Future<void> Function()? onSendReport;

  void dispose() {
    phase.dispose();
    title.dispose();
    message.dispose();
    subtitle.dispose();
  }

  void dismiss() {
    if (popScheduled) return;
    popScheduled = true;
    if (dismissWait != null && !dismissWait!.isCompleted) {
      dismissWait!.complete();
    }
    if (navigator.canPop()) navigator.pop();
  }
}

/// โอเวอร์เลย์ «กำลังบันทึก» → «สำเร็จ» / «ไม่สำเร็จ» — dialog เดียว morph ต่อเนื่อง
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
        barrierColor: Colors.black.withValues(alpha: 0.42),
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
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
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
    _session?.dismiss();
  }

  static Future<void> showSuccessThenDismiss({
    required BuildContext context,
    required String message,
    Duration holdAfterAnimation = const Duration(milliseconds: 1200),
    required VoidCallback onAfterDismiss,
  }) async {
    await _morphToSuccess(
      context: context,
      message: message,
      holdAfterAnimation: holdAfterAnimation,
    );
    onAfterDismiss();
  }

  /// สำเร็จแต่ยังอยู่หน้าเดิม (เช่น น้ำมัน / นับจำนวน)
  static Future<void> showSuccessStayOnPage({
    required BuildContext context,
    required String message,
    Duration holdAfterAnimation = const Duration(milliseconds: 1300),
    VoidCallback? onAfterDismiss,
  }) async {
    await _morphToSuccess(
      context: context,
      message: message,
      holdAfterAnimation: holdAfterAnimation,
    );
    onAfterDismiss?.call();
  }

  static Future<void> _morphToSuccess({
    required BuildContext context,
    required String message,
    required Duration holdAfterAnimation,
  }) async {
    var session = _session;
    if (session == null) {
      if (!context.mounted) return;
      showSaving(context);
      session = _session;
    }
    if (session == null) return;

    session.message.value = message;
    session.title.value = '';
    session.subtitle.value = '';
    session.phase.value = _SavePhase.success;

    await Future<void>.delayed(
      const Duration(milliseconds: 620) + holdAfterAnimation,
    );

    session.dismiss();
    await session.closed.future;
  }

  /// morph จากกำลังบันทึก → ไม่สำเร็จ (หรือเปิดใหม่ถ้ายังไม่มี dialog)
  static Future<void> showError({
    required BuildContext context,
    required String title,
    required String message,
    String? subtitle,
    Future<void> Function()? onSendReport,
    Duration holdAfterAnimation = const Duration(milliseconds: 3400),
  }) async {
    var session = _session;
    if (session == null || session.popScheduled) {
      if (!context.mounted) return;
      showSaving(context);
      session = _session;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (session == null || !context.mounted) return;

    session.title.value = title;
    session.message.value = message;
    session.subtitle.value = subtitle?.trim() ?? '';
    session.onSendReport = onSendReport;
    session.dismissWait = Completer<void>();
    session.phase.value = _SavePhase.error;

    await Future.any<void>([
      Future<void>.delayed(
        const Duration(milliseconds: 520) + holdAfterAnimation,
      ),
      session.dismissWait!.future,
    ]);

    if (!session.popScheduled) session.dismiss();
    await session.closed.future;
  }
}

class _SaveFeedbackDialog extends StatelessWidget {
  const _SaveFeedbackDialog({required this.session});

  final _SaveDialogSession session;

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 340.0);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ValueListenableBuilder<_SavePhase>(
          valueListenable: session.phase,
          builder: (context, phase, _) {
            final success = phase == _SavePhase.success;
            final error = phase == _SavePhase.error;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              width: width,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: error
                      ? const Color(0xFFEF9A9A).withValues(alpha: 0.7)
                      : success
                          ? const Color(0xFFA5D6A7).withValues(alpha: 0.65)
                          : Colors.white,
                ),
                boxShadow: [
                  BoxShadow(
                    color: error
                        ? const Color(0xFFC62828).withValues(alpha: 0.2)
                        : success
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
                  switchInCurve:
                      const Interval(0.35, 1, curve: Curves.easeOutCubic),
                  switchOutCurve:
                      const Interval(0.65, 1, curve: Curves.easeInCubic),
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        ?currentChild,
                      ],
                    );
                  },
                  child: error
                      ? _ErrorContent(
                          key: const ValueKey('error'),
                          session: session,
                        )
                      : success
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
                  'บันทึกสำเร็จ',
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

class _ErrorContent extends StatefulWidget {
  const _ErrorContent({super.key, required this.session});

  final _SaveDialogSession session;

  @override
  State<_ErrorContent> createState() => _ErrorContentState();
}

class _ErrorContentState extends State<_ErrorContent>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _shake;
  late final Animation<double> _iconScale;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _iconScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.05, 0.75, curve: Curves.elasticOut),
    );
    _textFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
    );
    _entrance.forward();
    _shake.forward();
    AppHaptics.warn();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _shake.dispose();
    super.dispose();
  }

  double _shakeOffset(double t) {
    if (t >= 1) return 0;
    return math.sin(t * math.pi * 6) * 10 * (1 - t);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeOffset(_shake.value), 0),
              child: child,
            );
          },
          child: ScaleTransition(
            scale: Tween<double>(begin: 0, end: 1).animate(_iconScale),
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEF5350), Color(0xFFC62828)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40C62828),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FadeTransition(
          opacity: _textFade,
          child: Column(
            children: [
              ValueListenableBuilder<String>(
                valueListenable: widget.session.title,
                builder: (context, title, _) {
                  return Text(
                    title.trim().isEmpty ? 'บันทึกไม่สำเร็จ' : title.trim(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB71C1C),
                      height: 1.2,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Could not save',
                style: GoogleFonts.kanit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: const Color(0xFFE57373),
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: widget.session.message,
                builder: (context, message, _) {
                  final trimmed = message.trim();
                  if (trimmed.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      trimmed,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF37474F),
                        height: 1.35,
                      ),
                    ),
                  );
                },
              ),
              ValueListenableBuilder<String>(
                valueListenable: widget.session.subtitle,
                builder: (context, subtitle, _) {
                  final trimmed = subtitle.trim();
                  if (trimmed.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      trimmed,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF78909C),
                        height: 1.3,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (widget.session.onSendReport != null)
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final handler = widget.session.onSendReport;
                    if (handler == null) return;
                    try {
                      await handler();
                    } catch (_) {}
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    side: const BorderSide(color: Color(0xFFEF9A9A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'ส่งข้อมูล',
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            if (widget.session.onSendReport != null) const SizedBox(width: 10),
            Expanded(
              flex: widget.session.onSendReport != null ? 1 : 0,
              child: SizedBox(
                width: widget.session.onSendReport == null
                    ? double.infinity
                    : null,
                child: FilledButton(
                  onPressed: widget.session.dismiss,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'ตกลง',
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
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
