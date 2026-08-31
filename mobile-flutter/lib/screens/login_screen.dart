import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/admin_user.dart';
import '../models/saved_login_profile.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../theme/daily_palette.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_version_label.dart';
import '../widgets/soft_press_button.dart';

/// หลังล็อกอินสำเร็จ — [persistSession] คือจะบันทึก session ลงเครื่องหรือไม่
typedef LoginSuccessCallback = Future<void> Function(
  AdminUser admin,
  bool persistSession,
);

/// Native phone-first login — brand hero, short welcome, focused fields, one CTA.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.sessionService,
    required this.onLoginSuccess,
  });

  final AuthService authService;
  final SessionService sessionService;
  final LoginSuccessCallback onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _gold = Color(0xFFC5A55A);
  static const Color _goldDark = Color(0xFF8B7A3E);

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _submitting = false;
  bool _obscurePassword = true;
  bool _rememberSession = true;
  bool _showForm = true;
  bool _prefsLoaded = false;
  String? _errorMessage;
  String? _unlockingProfileId;
  List<SavedLoginProfile> _savedProfiles = const [];
  late AnimationController _entranceController;
  late Animation<double> _logoEntranceScale;

  @override
  void initState() {
    super.initState();
    MobileErrorScreenTracker.set(
      page: 'เข้าสู่ระบบ',
      pageId: MobileScreenIds.pageLogin,
      stepId: MobileScreenIds.stepLoginForm,
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    _logoEntranceScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLoginPrefs());
  }

  Future<void> _loadLoginPrefs() async {
    try {
      final remember =
          await widget.sessionService.getRememberSessionPreference();
      final lastUser = await widget.sessionService.getLastLoginUsername();
      final profiles = await widget.sessionService.getSavedProfiles();
      if (!mounted) return;
      setState(() {
        _rememberSession = remember;
        _savedProfiles = profiles;
        _showForm = profiles.isEmpty;
        _prefsLoaded = true;
        if (lastUser != null && lastUser.isNotEmpty && profiles.isEmpty) {
          _usernameController.text = lastUser;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefsLoaded = true;
        _showForm = true;
      });
    }
  }

  Future<void> _reloadSavedProfiles() async {
    try {
      final profiles = await widget.sessionService.getSavedProfiles();
      if (!mounted) return;
      setState(() {
        _savedProfiles = profiles;
        if (profiles.isEmpty) {
          _showForm = true;
        }
      });
    } catch (_) {
      // ไม่บล็อกหน้าเข้าสู่ระบบ
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit({bool fromSavedProfile = false}) async {
    if (_submitting) return;
    if (!fromSavedProfile && !_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final admin = await widget.authService.login(username, password);
      final remember = fromSavedProfile ? true : _rememberSession;
      await widget.sessionService.setRememberSessionPreference(remember);
      await widget.sessionService.setLastLoginUsername(username);
      if (remember) {
        await widget.sessionService.saveLoginProfile(
          admin: admin,
          password: password,
        );
      }
      await widget.onLoginSuccess(admin, remember);
    } on AdminLoginException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      final raw = e.toString();
      final String detail;
      if (e is SocketException ||
          raw.contains('SocketException') ||
          raw.contains('Failed host lookup')) {
        detail =
            'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ — ตรวจสอบ Wi‑Fi หรือเน็ตมือถือ แล้วลองอีกครั้ง';
      } else if (raw.contains('PostgrestException')) {
        detail =
            'เชื่อมต่อฐานข้อมูล Supabase ไม่สำเร็จ — ตรวจ SUPABASE_URL / key ใน .env และสิทธิ์ RLS ตาราง admin_users';
      } else {
        detail = raw;
      }
      setState(() => _errorMessage = 'เข้าสู่ระบบไม่สำเร็จ: $detail');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _unlockingProfileId = null;
        });
      }
    }
  }

  Future<void> _unlockProfile(SavedLoginProfile profile) async {
    if (_submitting || _unlockingProfileId != null) return;
    setState(() {
      _unlockingProfileId = profile.id;
      _errorMessage = null;
    });

    final password =
        await widget.sessionService.getProfilePassword(profile.id);
    if (!mounted) return;

    if (password == null || password.isEmpty) {
      setState(() {
        _unlockingProfileId = null;
        _errorMessage =
            'ไม่พบรหัสผ่านของโปรไฟล์นี้ — กรุณาเข้าสู่ระบบด้วยชื่อผู้ใช้และรหัสผ่านอีกครั้ง';
        _usernameController.text = profile.username;
        _passwordController.clear();
        _showForm = true;
      });
      await widget.sessionService.removeSavedProfile(profile.id);
      await _reloadSavedProfiles();
      return;
    }

    _usernameController.text = profile.username;
    _passwordController.text = password;
    await widget.sessionService.touchSavedProfile(profile.id);
    await _submit(fromSavedProfile: true);
  }

  Future<void> _confirmRemoveProfile(SavedLoginProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'ลบโปรไฟล์นี้?',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'ลบ «${profile.displayName}» — จะต้องเข้าสู่ระบบด้วยชื่อผู้ใช้และรหัสผ่านอีกครั้ง',
            style: GoogleFonts.kanit(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('ยกเลิก', style: GoogleFonts.kanit()),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(
                'ลบโปรไฟล์',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.sessionService.removeSavedProfile(profile.id);
    await _reloadSavedProfiles();
  }

  void _handleKeyboardSubmit() {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    _submit();
  }

  InputDecoration _fieldDecoration({
    required bool isDark,
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : DailyPalette.card;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.12) : DailyPalette.hairline;
    final focusColor = isDark ? _gold : DailyPalette.brand;
    final iconColor =
        isDark ? Colors.white54 : DailyPalette.inkMuted;
    final labelColor =
        isDark ? Colors.white60 : DailyPalette.inkSubtle;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: iconColor, size: 22),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: focusColor, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.4),
      ),
      labelStyle: GoogleFonts.kanit(color: labelColor, fontSize: 14),
      hintStyle: GoogleFonts.kanit(
        color: isDark
            ? Colors.white.withValues(alpha: 0.32)
            : DailyPalette.inkMuted.withValues(alpha: 0.7),
        fontSize: 14,
      ),
    );
  }

  bool _useSplitLandscapeLayout(Size size) =>
      size.width > size.height && size.width >= 640;

  Widget _buildLandscapeBrandPanel({required bool isDark}) {
    final goldLine = isDark
        ? const [_goldDark, _gold]
        : [DailyPalette.brandDeep, DailyPalette.brandGlow];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF050505),
                  Color(0xFF12110E),
                  Color(0xFF1A160F),
                ]
              : const [
                  Color(0xFF0B1B2B),
                  Color(0xFF0A3D47),
                  Color(0xFF067A87),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!isDark)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.2, -0.35),
                  radius: 1.1,
                  colors: [
                    _gold.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _logoEntranceScale,
                    child: Image.asset(
                      'assets/branding/splash_logo.png',
                      width: 168,
                      height: 168,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'ยินดีต้อนรับ',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'เข้าสู่ระบบเพื่อบันทึกงานประจำวัน',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 48,
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(colors: goldLine),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'GOLDEN MOLE',
                    style: GoogleFonts.kanit(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.4,
                      color: _gold.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSurface({
    required bool isDark,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : DailyPalette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : DailyPalette.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : DailyPalette.brand.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x080F172A),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _buildLoginBody({
    required BoxConstraints constraints,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required double bottomInset,
    required bool splitLandscape,
  }) {
    final formSection = Form(
      key: _formKey,
      child: !_prefsLoaded
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: DailyPalette.brand,
                  ),
                ),
              ),
            )
          : _savedProfiles.isNotEmpty && !_showForm
              ? _buildProfilePicker(
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  hideHeader: splitLandscape,
                )
              : _buildLoginFormFields(
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
    );

    if (splitLandscape) {
      final showProfilePicker =
          _prefsLoaded && _savedProfiles.isNotEmpty && !_showForm;
      final panelTitle = showProfilePicker ? 'เลือกโปรไฟล์' : 'เข้าสู่ระบบ';
      final panelSubtitle = showProfilePicker
          ? 'แตะเพื่อเข้าสู่ระบบ'
          : 'กรอกข้อมูลบัญชีของคุณ';

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 46,
            child: _buildLandscapeBrandPanel(isDark: isDark),
          ),
          Expanded(
            flex: 54,
            child: ColoredBox(
              color: isDark ? const Color(0xFF0A0A0A) : DailyPalette.surface,
              child: SafeArea(
                left: false,
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, formConstraints) {
                          return SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              28,
                              20,
                              28,
                              12 + bottomInset.clamp(0, 120),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: formConstraints.maxHeight - 24,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 400),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        panelTitle,
                                        style: GoogleFonts.kanit(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        panelSubtitle,
                                        style: GoogleFonts.kanit(
                                          fontSize: 14,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      _buildFormSurface(
                                        isDark: isDark,
                                        child: formSection,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppVersionLabel(
                        color: textSecondary.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        16 + bottomInset.clamp(0, 120),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - 28,
            maxWidth: 420,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 1),
                _buildHero(
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
                const SizedBox(height: 28),
                _buildFormSurface(isDark: isDark, child: formSection),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : DailyPalette.ink;
    final textSecondary = isDark ? Colors.white70 : DailyPalette.inkMuted;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    final splitLandscape = _useSplitLandscapeLayout(size);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDark ? const Color(0xFF0A0A0A) : DailyPalette.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : DailyPalette.surface,
      resizeToAvoidBottomInset: true,
      body: splitLandscape
          ? FadeTransition(
              opacity: CurvedAnimation(
                parent: _entranceController,
                curve: const Interval(0.05, 1.0, curve: Curves.easeOutCubic),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _buildLoginBody(
                    constraints: constraints,
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    bottomInset: bottomInset,
                    splitLandscape: true,
                  );
                },
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? const [
                          Color(0xFF0A0A0A),
                          Color(0xFF121212),
                          Color(0xFF0A0A0A),
                        ]
                      : [
                          const Color(0xFFF3FBFC),
                          DailyPalette.surface,
                          Color.lerp(DailyPalette.surface, _gold, 0.04)!,
                        ],
                ),
              ),
              child: SafeArea(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _entranceController,
                    curve:
                        const Interval(0.05, 1.0, curve: Curves.easeOutCubic),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return _buildLoginBody(
                              constraints: constraints,
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                              bottomInset: bottomInset,
                              splitLandscape: false,
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppVersionLabel(
                          color: textSecondary.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHero({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      children: [
        ScaleTransition(
          scale: _logoEntranceScale,
          child: const AppLogo(size: 112),
        ),
        const SizedBox(height: 20),
        Text(
          'ยินดีต้อนรับ',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'เข้าสู่ระบบเพื่อบันทึกงานประจำวัน',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(
            fontSize: 15,
            height: 1.4,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              colors: isDark
                  ? [_goldDark, _gold]
                  : [DailyPalette.brand, DailyPalette.brandDeep],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePicker({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    bool hideHeader = false,
  }) {
    final busy = _submitting || _unlockingProfileId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hideHeader) ...[
          Text(
            'เลือกโปรไฟล์',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'แตะเพื่อเข้าสู่ระบบ',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(fontSize: 14, color: textSecondary),
          ),
          const SizedBox(height: 24),
        ] else
          const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 18,
          children: _savedProfiles
              .map((p) => _profileChip(p, isDark: isDark, busy: busy))
              .toList(),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          _errorBanner(isDark: isDark),
        ],
        const SizedBox(height: 28),
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                    _errorMessage = null;
                    _usernameController.clear();
                    _passwordController.clear();
                    _showForm = true;
                  }),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: isDark ? _gold : DailyPalette.brandDeep,
          ),
          child: Text(
            'ใช้บัญชีอื่น',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileChip(
    SavedLoginProfile profile, {
    required bool isDark,
    required bool busy,
  }) {
    final unlocking = _unlockingProfileId == profile.id;
    final accent = isDark ? _gold : DailyPalette.brand;
    final accentDark = isDark ? _goldDark : DailyPalette.brandDeep;

    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: busy ? null : () => _unlockProfile(profile),
                  onLongPress:
                      busy ? null : () => _confirmRemoveProfile(profile),
                  child: Ink(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent, accentDark],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: unlocking
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              profile.initials,
                              style: GoogleFonts.kanit(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : () => _confirmRemoveProfile(profile),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.7)
                            : DailyPalette.ink.withValues(alpha: 0.55),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: busy ? null : () => _unlockProfile(profile),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                children: [
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : DailyPalette.ink,
                    ),
                  ),
                  Text(
                    profile.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : DailyPalette.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginFormFields({
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _usernameController,
          focusNode: _usernameFocus,
          style: GoogleFonts.kanit(color: textPrimary, fontSize: 16),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          cursorColor: isDark ? _gold : DailyPalette.brand,
          decoration: _fieldDecoration(
            isDark: isDark,
            label: 'ชื่อผู้ใช้',
            hint: 'กรอกชื่อผู้ใช้',
            icon: Icons.person_outline_rounded,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
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
          style: GoogleFonts.kanit(color: textPrimary, fontSize: 16),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleKeyboardSubmit(),
          cursorColor: isDark ? _gold : DailyPalette.brand,
          decoration: _fieldDecoration(
            isDark: isDark,
            label: 'รหัสผ่าน',
            hint: 'กรอกรหัสผ่าน',
            icon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: isDark ? Colors.white54 : DailyPalette.inkMuted,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'กรุณากรอกรหัสผ่าน';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => setState(() => _rememberSession = !_rememberSession),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: _rememberSession,
                    onChanged: (v) =>
                        setState(() => _rememberSession = v ?? false),
                    checkColor: Colors.white,
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return isDark ? _goldDark : DailyPalette.brand;
                      }
                      return isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : DailyPalette.chipSurface;
                    }),
                    side: BorderSide(
                      color: isDark
                          ? Colors.white38
                          : DailyPalette.hairline,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'จำโปรไฟล์นี้ไว้บนเครื่อง',
                    style: GoogleFonts.kanit(
                      fontSize: 14,
                      height: 1.35,
                      color: textPrimary.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _errorBanner(isDark: isDark),
        ],
        const SizedBox(height: 22),
        _primarySubmitButton(isDark: isDark),
        if (_savedProfiles.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _errorMessage = null;
                      _showForm = false;
                    }),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: isDark ? _gold : DailyPalette.brandDeep,
            ),
            child: Text(
              'กลับไปเลือกโปรไฟล์',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'ลืมรหัสผ่าน? ติดต่อผู้ดูแลระบบ',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(
            fontSize: 12,
            color: textSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner({required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: isDark ? Colors.red.shade200 : Colors.red.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.kanit(
                color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primarySubmitButton({required bool isDark}) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [_gold, _goldDark]
          : const [DailyPalette.brand, DailyPalette.brandDeep],
    );
    final shadowColor = isDark ? _gold : DailyPalette.brand;

    return SoftPressButton(
      onTap: _submitting ? null : _submit,
      size: SoftPressSize.large,
      borderRadius: 16,
      useConfirmHaptic: true,
      isDarkSurface: true,
      liftWhenIdle: true,
      depthShadow: SoftPressDepthShadow(
        color: shadowColor.withValues(alpha: 0.32),
        blurRadius: 16,
        offsetY: 8,
        pressedBlurRadius: 6,
        pressedOffsetY: 3,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              const SizedBox(width: 10),
              Text(
                _submitting ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ',
                style: GoogleFonts.kanit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
