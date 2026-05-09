import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/admin_user.dart';
import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

/// โทนสีและเลย์เอาต์อ้างอิงจาก `src/modules/Auth/LoginPage.tsx` (เว็บ)
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoginSuccess,
  });

  final AuthService authService;
  final ValueChanged<AdminUser> onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const Color _gold = Color(0xFFC5A55A);
  static const Color _goldDark = Color(0xFF8B7A3E);

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _submitting = false;
  bool _darkMode = true;
  bool _obscurePassword = true;
  String? _errorMessage;
  late AnimationController _shimmerController;
  late AnimationController _entranceController;
  late AnimationController _ambientController;
  late Animation<double> _logoEntranceScale;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _logoEntranceScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _ambientController.dispose();
    _shimmerController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final admin = await widget.authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      widget.onLoginSuccess(admin);
    } on AdminLoginException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      final raw = e.toString();
      final detail = raw.contains('PostgrestException')
          ? 'เชื่อมต่อฐานข้อมูล Supabase ไม่สำเร็จ — ตรวจ SUPABASE_URL / key ใน .env และสิทธิ์ RLS ตาราง admin_users'
          : raw;
      setState(() => _errorMessage = 'เข้าสู่ระบบไม่สำเร็จ: $detail');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _handleKeyboardSubmit() {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    _submit();
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    if (_darkMode) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white54),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x6600C8FF), width: 1.2),
        ),
        labelStyle: GoogleFonts.kanit(color: Colors.white60, fontSize: 13),
        hintStyle: GoogleFonts.kanit(
          color: Colors.white.withValues(alpha: 0.35),
        ),
      );
    }
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.brown.shade300),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.72),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.brown.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.9), width: 1.4),
      ),
      labelStyle: GoogleFonts.kanit(color: Colors.brown.shade700, fontSize: 13),
      hintStyle: GoogleFonts.kanit(color: Colors.black.withValues(alpha: 0.38)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = _darkMode ? Colors.white : Colors.black87;
    final textSecondary = _darkMode ? Colors.white70 : Colors.black54;

    return Theme(
      data: Theme.of(context).copyWith(
        brightness: _darkMode ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: _buildBackground()),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ambientController,
                builder: (context, _) {
                  final t = _ambientController.value * 2 * math.pi;
                  return Stack(
                    children: [
                      Positioned(
                        top: -80 + 14 * math.sin(t * 0.8),
                        left: -40 + 10 * math.cos(t * 0.6),
                        child: _glowOrb(
                          size: 260,
                          colors: _darkMode
                              ? [const Color(0x330096FF), Colors.transparent]
                              : [
                                  _gold.withValues(alpha: 0.14),
                                  Colors.transparent,
                                ],
                        ),
                      ),
                      Positioned(
                        bottom: -60 + 12 * math.cos(t * 0.9),
                        right: -30 + 8 * math.sin(t * 0.5),
                        child: _glowOrb(
                          size: 220,
                          colors: _darkMode
                              ? [const Color(0x287850FF), Colors.transparent]
                              : [
                                  _goldDark.withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Material(
                    color: _darkMode
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _darkMode = !_darkMode),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _darkMode
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: _darkMode
                              ? const Color(0xFF00D4FF)
                              : Colors.brown.shade600,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _entranceController,
                  curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
                ),
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 0.1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _entranceController,
                          curve: const Interval(
                            0.08,
                            1.0,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 28,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              color: _darkMode
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.72),
                              border: Border.all(
                                color: _darkMode
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.brown.shade100.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _darkMode
                                      ? const Color(0x3300C8FF)
                                      : _gold.withValues(alpha: 0.18),
                                  blurRadius: 32,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _topGlowBar(),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    22,
                                    22,
                                    26,
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildLogo(),
                                        const SizedBox(height: 18),
                                        Text(
                                          'ระบบจัดการโครงการก่อสร้าง',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.kanit(
                                            fontSize: 13,
                                            color: _darkMode
                                                ? const Color(0x99B8F4FF)
                                                : textSecondary,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Construction Management',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.kanit(
                                            fontSize: 12,
                                            color: textSecondary.withValues(
                                              alpha: 0.85,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        _featureBadges(),
                                        const SizedBox(height: 22),
                                        TextFormField(
                                          controller: _usernameController,
                                          focusNode: _usernameFocus,
                                          style: GoogleFonts.kanit(
                                            color: textPrimary,
                                            fontSize: 15,
                                          ),
                                          textInputAction: TextInputAction.next,
                                          onFieldSubmitted: (_) {
                                            _passwordFocus.requestFocus();
                                          },
                                          cursorColor: _darkMode
                                              ? const Color(0xFF00C8FF)
                                              : _goldDark,
                                          decoration: _fieldDecoration(
                                            label: 'ชื่อผู้ใช้ (Username)',
                                            hint: 'กรอกชื่อผู้ใช้',
                                            icon: Icons.person_outline_rounded,
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'กรุณากรอกชื่อผู้ใช้';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _passwordController,
                                          focusNode: _passwordFocus,
                                          obscureText: _obscurePassword,
                                          style: GoogleFonts.kanit(
                                            color: textPrimary,
                                            fontSize: 15,
                                          ),
                                          textInputAction: TextInputAction.done,
                                          onFieldSubmitted: (_) =>
                                              _handleKeyboardSubmit(),
                                          cursorColor: _darkMode
                                              ? const Color(0xFF00C8FF)
                                              : _goldDark,
                                          decoration: _fieldDecoration(
                                            label: 'รหัสผ่าน (Password)',
                                            hint: 'กรอกรหัสผ่าน',
                                            icon: Icons.lock_outline_rounded,
                                            suffixIcon: IconButton(
                                              onPressed: () => setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              ),
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                          .visibility_off_outlined,
                                                color: _darkMode
                                                    ? Colors.white54
                                                    : Colors.brown.shade400,
                                              ),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'กรุณากรอกรหัสผ่าน';
                                            }
                                            return null;
                                          },
                                        ),
                                        if (_errorMessage != null) ...[
                                          const SizedBox(height: 14),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(
                                                alpha: _darkMode ? 0.14 : 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Colors.red.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.shield_outlined,
                                                  size: 20,
                                                  color: Colors.red.shade300,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    _errorMessage!,
                                                    style: GoogleFonts.kanit(
                                                      color:
                                                          Colors.red.shade200,
                                                      fontSize: 13,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 18),
                                        _gradientSubmitButton(),
                                        const SizedBox(height: 18),
                                        Text(
                                          'ติดต่อผู้ดูแลระบบหากลืมรหัสผ่าน',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.kanit(
                                            fontSize: 11,
                                            color: textSecondary.withValues(
                                              alpha: 0.75,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _darkMode
                                          ? [
                                              Colors.transparent,
                                              const Color(0x5500C8FF),
                                              const Color(0x557850FF),
                                              Colors.transparent,
                                            ]
                                          : [
                                              Colors.transparent,
                                              _gold.withValues(alpha: 0.45),
                                              Colors.transparent,
                                            ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (_darkMode) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050510), Color(0xFF0A0A1A), Color(0xFF101028)],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF8F4EB),
            Color.lerp(const Color(0xFFF0E8D8), Colors.white, 0.35)!,
          ],
        ),
      ),
    );
  }

  Widget _glowOrb({required double size, required List<Color> colors}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  Widget _topGlowBar() {
    return SizedBox(
      height: 3,
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final t = _shimmerController.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.2 + t * 2.4, 0),
                end: Alignment(0.2 + t * 2.4, 0),
                colors: _darkMode
                    ? [
                        Colors.transparent,
                        const Color(0xFF00C8FF),
                        const Color(0xFF7850FF),
                        Colors.transparent,
                      ]
                    : [
                        Colors.transparent,
                        _gold,
                        _goldDark,
                        Colors.transparent,
                      ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_logoEntranceScale, _ambientController]),
          builder: (context, _) {
            final pulse =
                1.0 + 0.04 * math.sin(_ambientController.value * 2 * math.pi);
            final scale = (_logoEntranceScale.value * pulse).clamp(0.85, 1.12);
            return Transform.scale(
              scale: scale,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _darkMode
                        ? const [Color(0xFF0A0A20), Color(0xFF111130)]
                        : const [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                  ),
                  border: Border.all(
                    color: _darkMode
                        ? const Color(0x4400C8FF)
                        : _gold.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _darkMode
                          ? const Color(0x5500C8FF)
                          : _gold.withValues(alpha: 0.28),
                      blurRadius: 26,
                      spreadRadius: 0,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: AppLogo(size: _darkMode ? 76 : 72),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            if (_darkMode) {
              return const LinearGradient(
                colors: [
                  Color(0xFF5ED4FF),
                  Color(0xFF7AA8FF),
                  Color(0xFFB794FF),
                ],
              ).createShader(bounds);
            }
            return LinearGradient(
              colors: [Colors.black87, Colors.brown.shade800],
            ).createShader(bounds);
          },
          child: Text(
            'เข้าสู่ระบบ',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _featureBadges() {
    final chips = ['วิเคราะห์', 'จัดการงาน', 'รายรับ-จ่าย'];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: chips.map((label) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: _darkMode
                ? const Color(0x1400C8FF)
                : Colors.black.withValues(alpha: 0.05),
            border: Border.all(
              color: _darkMode
                  ? const Color(0x2200C8FF)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.kanit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _darkMode
                  ? const Color(0xCC7ADFFF)
                  : Colors.black.withValues(alpha: 0.72),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _gradientSubmitButton() {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _darkMode
          ? const [Color(0xFF0080FF), Color(0xFF6020C0)]
          : [_gold, _goldDark],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _submitting ? null : _submit,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (_darkMode ? const Color(0xFF0080FF) : _gold).withValues(
                  alpha: 0.35,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_submitting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Text(
                  _submitting ? 'กำลังตรวจสอบ...' : 'เข้าสู่ระบบ',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
