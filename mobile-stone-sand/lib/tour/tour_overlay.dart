import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart' show tabular;
import 'tour_controller.dart';
import 'tour_steps.dart';

const violet600 = Color(0xFF7C3AED);
const violet700 = Color(0xFF6D28D9);
const violet50 = Color(0xFFF5F3FF);
const violet100 = Color(0xFFEDE9FE);
const violet200 = Color(0xFFDDD6FE);

const _pad = 8.0;
const _edge = 12.0;
const _cardWidth = 380.0;
const _advanceDelay = Duration(milliseconds: 650);

/// Puts the coach card over the whole app while a tour runs. The app underneath stays usable.
class TourOverlayHost extends StatelessWidget {
  const TourOverlayHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tour = TourScope.maybeOf(context);
    final signedIn = AuthScope.of(context).isAuthenticated;
    return Stack(
      children: [
        child,
        if (tour != null && tour.active && signedIn) Positioned.fill(child: TourOverlay(tour: tour)),
      ],
    );
  }
}

class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.tour});
  final TourController tour;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  Timer? _ticker;
  Timer? _advanceTimer;
  Rect? _rect;
  TourEnv _env = const TourEnv(page: null);
  int _index = -1;
  int _advancedFor = -1;
  int _scrolledFor = -1;
  bool _minimized = false;
  bool _confirmExit = false;

  TourController get _tour => widget.tour;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _advance([TourVars? captured]) {
    final index = _tour.state?.step ?? -1;
    if (_advancedFor == index) return;
    _advancedFor = index;
    _tour.advance(captured);
  }

  void _tick() {
    if (!mounted) return;
    final index = _tour.state?.step ?? -1;
    final step = _tour.step;
    if (step == null) return;
    if (index != _index) {
      _index = index;
      _advancedFor = -1;
      _scrolledFor = -1;
      _advanceTimer?.cancel();
      _advanceTimer = null;
      _minimized = false;
      _confirmExit = false;
    }
    final env = _tour.env();
    if (step.skip?.call(env) ?? false) return _advance();

    final ctx = step.target != null && step.isOn(env.page) ? _tour.targetContext(step.target!) : null;
    Rect? rect;
    if (ctx != null) {
      final box = ctx.findRenderObject()! as RenderBox;
      rect = box.localToGlobal(Offset.zero) & box.size;
      final h = MediaQuery.sizeOf(context).height;
      if (_scrolledFor != index) {
        _scrolledFor = index;
        if (rect.top < 72 || rect.bottom > h - 180) {
          Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 300));
        }
      }
    }

    if (step.done != null && _advanceTimer == null && _advancedFor != index && step.done!(env)) {
      final captured = step.capture?.call(env);
      _advanceTimer = Timer(_advanceDelay, () {
        _advanceTimer = null;
        if (mounted && _tour.state?.step == index) _advance(captured);
      });
    }

    if (!_sameRect(rect, _rect) || env.page != _env.page) {
      setState(() {
        _rect = rect;
        _env = env;
      });
    } else {
      _env = env;
    }
  }

  static bool _sameRect(Rect? a, Rect? b) =>
      a == b ||
      (a != null &&
          b != null &&
          (a.left - b.left).abs() < 1 &&
          (a.top - b.top).abs() < 1 &&
          (a.width - b.width).abs() < 1 &&
          (a.height - b.height).abs() < 1);

  @override
  Widget build(BuildContext context) {
    final step = _tour.step;
    final s = _tour.state;
    if (step == null || s == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final total = tourSteps.length;

    if (_minimized) {
      return Stack(
        children: [
          Positioned(
            top: padding.top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: violet600,
                shape: const StadiumBorder(),
                elevation: 6,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _minimized = false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_outlined, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'สอนใช้งาน · ขั้น ${s.step + 1}/$total',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final spot = _rect;
    final wide = size.width >= 768;
    final placeTop = step.placeTop ?? (spot != null && spot.center.dy > size.height / 2);
    final cardMaxHeight = math.min(size.height * 0.7, 544.0);
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: cardMaxHeight),
      child: _TourCard(
        tour: _tour,
        step: step,
        state: s,
        offPage: !step.isOn(_env.page),
        confirmExit: _confirmExit,
        onConfirmExit: (v) => setState(() => _confirmExit = v),
        onMinimize: () => setState(() => _minimized = true),
        onAdvance: _advance,
      ),
    );

    final Widget positioned;
    if (!wide) {
      positioned = Positioned(
        left: _edge,
        right: _edge,
        top: placeTop ? padding.top + _edge : null,
        bottom: placeTop ? null : padding.bottom + _edge,
        child: card,
      );
    } else {
      final leftSide = spot != null && spot.center.dx > size.width / 2;
      positioned = Positioned(
        width: _cardWidth,
        left: leftSide ? 24 : null,
        right: leftSide ? null : 24,
        top: placeTop ? padding.top + 24 : null,
        bottom: placeTop ? null : padding.bottom + 24,
        child: card,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _SpotPainter(spot?.inflate(_pad)))),
        ),
        positioned,
      ],
    );
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter(this.spot);
  final Rect? spot;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0x8C0F172A);
    final full = Offset.zero & size;
    final s = spot;
    if (s == null) {
      canvas.drawRect(full, dim);
      return;
    }
    final hole = RRect.fromRectAndRadius(s, const Radius.circular(14));
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(full), Path()..addRRect(hole)), dim);
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = violet600.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) => old.spot != spot;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.tour,
    required this.step,
    required this.state,
    required this.offPage,
    required this.confirmExit,
    required this.onConfirmExit,
    required this.onMinimize,
    required this.onAdvance,
  });
  final TourController tour;
  final TourStep step;
  final TourState state;
  final bool offPage;
  final bool confirmExit;
  final ValueChanged<bool> onConfirmExit;
  final VoidCallback onMinimize;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final index = state.step;
    final total = tourSteps.length;
    final progress = chapterProgress(tourSteps, index);
    final interactive = step.done != null;
    final busy = tour.busy;
    final offRoute = offPage ? step.route?.call(state.vars) : null;

    return Material(
      color: AppColors.surface,
      elevation: 12,
      shadowColor: const Color(0x55000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: violet200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (index + 1) / total,
            minHeight: 4,
            color: violet600,
            backgroundColor: violet100,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: violet50, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_outlined, size: 14, color: violet700),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'บทที่ ${progress.chapter + 1}/${tourChapters.length} · ${tourChapters[progress.chapter]}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: violet700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${progress.chapterStep}/${progress.chapterSize}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                ),
                _IconAction(label: 'ย่อหน้าต่างสอนใช้งาน', icon: Icons.remove, onPressed: onMinimize),
                _IconAction(label: 'ออกจากโหมดสอนใช้งาน', icon: Icons.close, onPressed: () => onConfirmExit(true)),
              ],
            ),
          ),
          if (confirmExit)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ออกจากโหมดสอนใช้งาน?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'ลบข้อมูลสาธิตทั้งหมดตอนนี้ หรือพักไว้แล้วกลับมาสอนต่อจากหน้าเมนูก็ได้',
                      style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.muted),
                    ),
                    if (tour.error.isNotEmpty) ...[const SizedBox(height: 8), _ErrorText(tour.error)],
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
                        onPressed: busy ? null : tour.end,
                        child: Text(busy ? 'กำลังลบ…' : 'ลบข้อมูลสาธิตและออก'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: busy ? null : tour.pause, child: const Text('พักไว้ก่อน')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: busy ? null : () => onConfirmExit(false),
                            child: const Text('สอนต่อ'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3)),
                    const SizedBox(height: 6),
                    Text(step.body, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xCC0F172A))),
                    if (offPage) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'ขั้นนี้อยู่อีกหน้าหนึ่ง',
                              style: TextStyle(fontSize: 14, color: Color(0xFF92400E)),
                            ),
                            if (offRoute != null) ...[
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => tour.navigate(offRoute),
                                child: const Text('ไปที่หน้านั้น'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else if (interactive) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(color: violet50, borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.touch_app_outlined, size: 18, color: violet700),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ทำตามจุดที่ไฮไลต์ไว้ ระบบจะพาไปขั้นต่อไปให้เอง',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF5B21B6)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (tour.error.isNotEmpty) ...[const SizedBox(height: 8), _ErrorText(tour.error)],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Text(
                    'ขั้น ${index + 1}/$total',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                  ),
                  const Spacer(),
                  if (canGoBack(tourSteps, index))
                    _IconAction(label: 'ย้อนกลับ', icon: Icons.arrow_back, onPressed: busy ? null : tour.back),
                  if (step.action != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: step.action == TourAction.finish ? AppColors.success : AppColors.primary,
                      ),
                      onPressed: busy ? null : () => tour.runAction(step.action!),
                      child: Text(busy ? 'กำลังทำรายการ…' : step.actionLabel ?? ''),
                    )
                  else if (interactive)
                    (step.required
                        ? const SizedBox.shrink()
                        : TextButton(onPressed: busy ? null : onAdvance, child: const Text('ข้ามขั้นนี้')))
                  else
                    FilledButton(
                      onPressed: busy ? null : onAdvance,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('ถัดไป'), SizedBox(width: 6), Icon(Icons.arrow_forward, size: 18)],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card sits above the navigator, where there is no Overlay for tooltips.
class _IconAction extends StatelessWidget {
  const _IconAction({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: AppColors.muted),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: AppColors.destructiveSoft, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.destructive)),
  );
}
