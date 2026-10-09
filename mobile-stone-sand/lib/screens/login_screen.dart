import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_scope.dart';
import '../auth/session.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _showPassword = false;
  bool _busy = false;
  bool _remember = true;
  String _error = '';

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    // Prefill last username.
    final last = readLastUsername();
    if (last != null) {
      _username.text = last;
      // Focus password field when username is already known.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
    }

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _busy = true;
    });
    try {
      await AuthScope.read(context).signIn(_username.text, _password.text, remember: _remember);
      // Let the platform password manager offer to save credentials.
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().isEmpty ? 'เข้าสู่ระบบไม่สำเร็จ' : e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearError() {
    if (_error.isNotEmpty) setState(() => _error = '');
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final year = DateTime.now().year + 543;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: wide ? AppColors.surface : AppColors.subtle,
        body: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: _Hero(wide: true, year: year)),
                  Expanded(
                    flex: 10,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(48),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 384), child: _animatedForm()),
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _Hero(wide: false, year: year),
                    Transform.translate(
                      offset: const Offset(0, -40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 384),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.ink.withValues(alpha: 0.05),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: _animatedForm(),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
                      child: Text(
                        '© $year',
                        style: TextStyle(fontSize: 12, color: AppColors.muted.withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _animatedForm() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: _form()),
    );
  }

  Widget _form() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('กรอกชื่อผู้ใช้และรหัสผ่านเพื่อใช้งาน', style: TextStyle(fontSize: 14, color: AppColors.muted)),
          const SizedBox(height: 24),
          FieldLabel(
            'ชื่อผู้ใช้',
            child: TextField(
              controller: _username,
              focusNode: _usernameFocus,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                errorText: _error.isEmpty ? null : '',
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'รหัสผ่าน',
            child: TextField(
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.go,
              onChanged: (_) => _clearError(),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                errorText: _error.isEmpty ? null : '',
                errorStyle: const TextStyle(height: 0, fontSize: 0),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RememberRow(value: _remember, onChanged: (v) => setState(() => _remember = v)),
          if (_error.isNotEmpty) ...[const SizedBox(height: 16), ErrorBox(_error)],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 10),
                        Text('กำลังเข้าสู่ระบบ…'),
                      ],
                    )
                  : const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Remember-me row ──────────────────────────────────────────────────────────

class _RememberRow extends StatelessWidget {
  const _RememberRow({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? value),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('จดจำการเข้าสู่ระบบ', style: TextStyle(fontSize: 14)),
                  Text(
                    'ไม่ต้องเข้าสู่ระบบใหม่ 30 วัน',
                    style: TextStyle(fontSize: 12, color: AppColors.muted.withValues(alpha: 0.8)),
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

// ─── Hero / decorative sections (unchanged) ───────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.wide, required this.year});
  final bool wide;
  final int year;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final content = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppMark(),
        SizedBox(height: wide ? 32 : 20),
        Text(
          wide ? 'ระบบจัดการออเดอร์\nหิน-ทราย' : 'ระบบจัดการออเดอร์ หิน-ทราย',
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: wide ? 36 : 24, fontWeight: FontWeight.w600, height: 1.25),
        ),
        const SizedBox(height: 8),
        Text(
          'สำหรับเจ้าหน้าที่เท่านั้น',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: wide ? 16 : 14),
        ),
      ],
    );
    return Container(
      color: AppColors.primary,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            top: null,
            child: SizedBox(
              height: wide ? 256 : 112,
              child: CustomPaint(painter: _PilesPainter()),
            ),
          ),
          Padding(
            padding: wide ? const EdgeInsets.all(56) : EdgeInsets.fromLTRB(24, top + 48, 24, 64),
            child: wide
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      content,
                      Text('© $year', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
                    ],
                  )
                : Center(child: content),
          ),
        ],
      ),
    );
  }
}

/// Neutral app mark: two stone piles on a base line (never the company logo).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 4 8 36 34
    final sx = size.width / 36;
    final sy = size.height / 34;
    Offset p(double x, double y) => Offset((x - 4) * sx, (y - 8) * sy);
    final back = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final front = Paint()..color = Colors.white;
    canvas.drawPath(Path()..addPolygon([p(14, 34), p(25.5, 13), p(38, 34)], true), back);
    canvas.drawPath(Path()..addPolygon([p(5, 34), p(17, 10), p(29, 34)], true), front);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(5, 37), p(38, 40)), Radius.circular(1.5 * sx)), front);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PilesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 400;
    final sy = size.height / 120;
    Path poly(List<double> pts) {
      final path = Path()..moveTo(pts[0] * sx, pts[1] * sy);
      for (var i = 2; i < pts.length; i += 2) {
        path.lineTo(pts[i] * sx, pts[i + 1] * sy);
      }
      return path..close();
    }

    canvas.drawPath(
      poly([0, 120, 90, 46, 150, 92, 230, 30, 320, 100, 400, 64, 400, 120]),
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    canvas.drawPath(
      poly([0, 120, 60, 84, 130, 110, 210, 70, 300, 112, 400, 90, 400, 120]),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
