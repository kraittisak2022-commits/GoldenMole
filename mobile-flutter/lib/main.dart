import 'dart:async';

// Codemagic Flutter 3.44+ moved CupertinoPageTransitionsBuilder to cupertino.dart
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/app_locale.dart';
import 'models/admin_user.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_update_service.dart';
import 'services/auth_service.dart';
import 'services/count_record_offline_sync.dart';
import 'services/dashboard_service.dart';
import 'services/locale_service.dart';
import 'services/mobile_presence_service.dart';
import 'services/session_service.dart';
import 'services/theme_mode_service.dart';
import 'theme/daily_palette.dart';
import 'widgets/app_locale_scope.dart';
import 'widgets/app_sync_banner.dart';
import 'widgets/app_theme_scope.dart';
import 'utils/app_error_binding.dart';
import 'utils/device_perf.dart';
import 'utils/supabase_function_session.dart';
import 'widgets/app_page_route.dart';
import 'widgets/bootstrap_splash.dart';
import 'utils/touch_profile.dart';

/// Load bundled google_fonts before any widget paints.
///
/// Completing a font load notifies [_SystemFontsNotifier], which asserts if
/// [RenderParagraph] tries to relayout during [SchedulerPhase.midFrameMicrotasks].
/// Awaiting this before [runApp] keeps that notify in an idle phase.
Future<void> _preloadAppFonts() async {
  try {
    // Prime the same families/weights ThemeData + splash/login will request.
    final probe = ThemeData(useMaterial3: true);
    GoogleFonts.kanitTextTheme(probe.textTheme);
    GoogleFonts.kanit(fontWeight: FontWeight.w500);
    GoogleFonts.kanit(fontWeight: FontWeight.w600);
    GoogleFonts.kanit(fontWeight: FontWeight.w700);
    GoogleFonts.kanit(fontWeight: FontWeight.w800);
    GoogleFonts.orbitron(fontWeight: FontWeight.w700);
    await GoogleFonts.pendingFonts();
  } catch (e, st) {
    debugPrint('Font preload skipped: $e\n$st');
  }
}

void _applySystemUiOverlay(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    ),
  );
}

ThemeData _buildAppTheme(Brightness brightness) {
  final daily =
      brightness == Brightness.dark ? DailyColors.dark : DailyColors.light;
  final brand = daily.brandDeep;
  final ink = daily.ink;
  final scaffoldBg = daily.surface;
  final cardColor = daily.card;
  final hairline = daily.hairline;
  final muted = daily.inkMuted;
  final outlineSide = brightness == Brightness.dark
      ? const Color(0xFF3A4F5E)
      : const Color(0xFFC8DDE7);
  final inputFill = brightness == Brightness.dark
      ? const Color(0xFF121C26)
      : const Color(0xFFFAFCFF);
  final chipSelected = brightness == Brightness.dark
      ? const Color(0xFF1A3A42)
      : const Color(0xFFDDF6F9);
  final navIndicator = brightness == Brightness.dark
      ? const Color(0xFF1A3A42)
      : const Color(0xFFD5F2F5);
  final progressTrack = brightness == Brightness.dark
      ? const Color(0xFF1A2E38)
      : const Color(0xFFDDF0F3);

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: scaffoldBg,
    extensions: <ThemeExtension<dynamic>>[daily],
  );
  // ripple แบบ M3 ใหม่ — เครื่องรุ่นเล็กใช้ ripple เดิม (InkSparkle ใช้ shader)
  final splash = DevicePerf.isConstrainedDevice
      ? InkRipple.splashFactory
      : InkSparkle.splashFactory;
  return base.copyWith(
    textTheme: GoogleFonts.kanitTextTheme(base.textTheme).apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    splashFactory: splash,
    visualDensity: VisualDensity.standard,
    // ทรานสิชันเปลี่ยนหน้าแบบ M3 ใหม่ + predictive back บน Android
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(),
        TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cardColor,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness,
      ),
      titleTextStyle: GoogleFonts.kanit(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: daily.shadowCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(64, 46),
        side: BorderSide(color: outlineSide),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: GoogleFonts.kanit(color: muted),
      labelStyle: GoogleFonts.kanit(color: daily.inkSubtle),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: brand, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE05B5B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE05B5B), width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF1E3A4C)
          : const Color(0xFF1E3A4C),
      contentTextStyle: GoogleFonts.kanit(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 4,
      actionTextColor: const Color(0xFF6FE3F0),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: GoogleFonts.kanit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      contentTextStyle: GoogleFonts.kanit(
        fontSize: 14.5,
        color: muted,
        height: 1.45,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: daily.grabber,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: hairline),
      labelStyle: GoogleFonts.kanit(fontSize: 13, color: ink),
      backgroundColor: cardColor,
      selectedColor: chipSelected,
    ),
    dividerTheme: DividerThemeData(
      color: hairline,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      titleTextStyle: GoogleFonts.kanit(fontSize: 15, color: ink),
      subtitleTextStyle: GoogleFonts.kanit(
        fontSize: 12.5,
        color: muted,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: brand,
      linearTrackColor: progressTrack,
      circularTrackColor: progressTrack,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: daily.shadowLift,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: GoogleFonts.kanit(fontSize: 14.5, color: ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xE61E3A4C),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: GoogleFonts.kanit(fontSize: 12, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      indicatorColor: navIndicator,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? brand : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.kanit(
          fontSize: 11.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? brand : muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: outlineSide, width: 1.6),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : outlineSide,
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      headerHeadlineStyle: GoogleFonts.kanit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ใช้ฟอนต์ที่ bundle ในแอพ — ไม่ดาวน์โหลดจากเน็ตตอนเปิด
  GoogleFonts.config.allowRuntimeFetching = false;

  // แสดงผลเต็มจอแบบแอพยุคใหม่ — เนื้อหาลอดใต้ status bar / gesture bar
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  _applySystemUiOverlay(Brightness.light);

  final appRootNavigatorKey = GlobalKey<NavigatorState>();

  try {
    // Fonts must finish before runApp — see [_preloadAppFonts].
    await Future.wait([
      DevicePerf.init(),
      dotenv.load(fileName: '.env'),
      _preloadAppFonts(),
    ]);

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env file');
    }

    // Initialize Supabase
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);

    AppErrorBinding.install(appRootNavigatorKey);

    runApp(MobileApp(navigatorKey: appRootNavigatorKey));
  } catch (e) {
    debugPrint('Error during initialization: $e');
    runApp(
      MaterialApp(
        title: 'GoldenMole for User',
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'เกิดข้อผิดพลาดในการเริ่มต้นแอพ:\n$e\n\nกรุณาตรวจสอบไฟล์ .env และการเชื่อมต่ออินเทอร์เน็ต',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileApp extends StatefulWidget {
  const MobileApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  AdminUser? _currentAdmin;
  bool _bootstrapping = true;
  AppLocale _locale = AppLocale.th;
  ThemeMode _themeMode = ThemeMode.light;
  final SessionService _sessionService = SessionService();
  final LocaleService _localeService = LocaleService();
  final ThemeModeService _themeModeService = ThemeModeService();
  late final ThemeData _lightTheme = _buildAppTheme(Brightness.light);
  late final ThemeData _darkTheme = _buildAppTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
    _loadSavedLocale();
    _loadSavedThemeMode();
  }

  Future<void> _loadSavedLocale() async {
    final saved = await _localeService.load();
    if (!mounted) return;
    setState(() => _locale = saved);
  }

  Future<void> _loadSavedThemeMode() async {
    final saved = await _themeModeService.load();
    if (!mounted) return;
    setState(() => _themeMode = saved);
    _applySystemUiOverlay(
      saved == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );
  }

  Future<void> _setLocale(AppLocale next) async {
    if (_locale == next) return;
    await _localeService.save(next);
    if (!mounted) return;
    setState(() => _locale = next);
  }

  Future<void> _setThemeMode(ThemeMode next) async {
    if (_themeMode == next) return;
    await _themeModeService.save(next);
    if (!mounted) return;
    setState(() => _themeMode = next);
    _applySystemUiOverlay(
      next == ThemeMode.dark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_currentAdmin == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        CountRecordOfflineSync.instance.onAppResumed();
        unawaited(MobilePresenceService.instance.resume());
        ensureSupabaseSessionForEdgeFunctions(Supabase.instance.client).catchError(
          (Object e, StackTrace st) {
            debugPrint('ensureSupabaseSession on resume: $e\n$st');
          },
        );
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(MobilePresenceService.instance.pause());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _restoreSession() async {
    // Hold branded launch splash long enough for the reveal sequence.
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final minSplashMs = reduceMotion
        ? 520
        : (DevicePerf.isConstrainedDevice ? 1100 : 2000);
    final minSplash = Future<void>.delayed(Duration(milliseconds: minSplashMs));
    try {
      final results = await Future.wait([
        _sessionService.getSavedAdmin(),
        minSplash,
      ]);
      final admin = results[0] as AdminUser?;
      if (admin != null) {
        unawaited(
          ensureSupabaseSessionForEdgeFunctions(Supabase.instance.client)
              .catchError((Object e, StackTrace st) {
            debugPrint('ensureSupabaseSessionForEdgeFunctions: $e\n$st');
          }),
        );
        unawaited(MobilePresenceService.instance.start(admin.username));
      }
      if (!mounted) return;
      setState(() {
        _currentAdmin = admin;
        _bootstrapping = false;
      });
      _scheduleSoftUpdateCheck();
    } catch (e) {
      debugPrint('Error restoring session: $e');
      await minSplash;
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
      });
      _scheduleSoftUpdateCheck();
    }
  }

  void _scheduleSoftUpdateCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        final ctx = widget.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        unawaited(AppUpdateService.maybePromptSoftUpdate(ctx));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'GoldenMole for User',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      scrollBehavior: DevicePerf.isConstrainedDevice
          ? const _AppScrollBehaviorConstrained()
          : const _AppScrollBehavior(),
      theme: _lightTheme,
      darkTheme: _darkTheme,
      locale: _locale.materialLocale,
      supportedLocales: const [
        Locale('th', 'TH'),
        Locale('zh', 'CN'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        DevicePerf.updateScreenClass(context);
        final profile = TouchProfile.of(context);
        final themed = Theme.of(context).copyWith(
          visualDensity: profile.isTablet
              ? VisualDensity.comfortable
              : VisualDensity.standard,
        );
        return Theme(
          data: themed,
          child: AppThemeScope(
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
            child: AppLocaleScope(
              locale: _locale,
              onLocaleChanged: _setLocale,
              child: AppSyncBannerHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          );
        },
        child: _bootstrapping
            ? const BootstrapSplash(key: ValueKey('bootstrap'))
            : _currentAdmin == null
            ? LoginScreen(
                key: const ValueKey('login'),
                authService: AuthService(client),
                sessionService: _sessionService,
                onLoginSuccess: (admin, persistSession) async {
                  if (persistSession) {
                    await _sessionService.saveAdmin(admin);
                  } else {
                    await _sessionService.clear();
                  }
                  try {
                    await ensureSupabaseSessionForEdgeFunctions(
                      Supabase.instance.client,
                    );
                  } catch (e, st) {
                    debugPrint('ensureSupabaseSession after login: $e\n$st');
                  }
                  if (!mounted) return;
                  setState(() => _currentAdmin = admin);
                  unawaited(MobilePresenceService.instance.start(admin.username));
                },
              )
            : DashboardScreen(
                key: ValueKey('dashboard_${_currentAdmin!.id}'),
                currentAdmin: _currentAdmin!,
                dashboardService: DashboardService(client),
                onLogout: () async {
                  await MobilePresenceService.instance.stop();
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (e, st) {
                    debugPrint('Supabase signOut: $e\n$st');
                  }
                  await _sessionService.clear();
                  if (!mounted) return;
                  setState(() => _currentAdmin = null);
                },
              ),
      ),
    );
  }
}

/// เลื่อนนิ่มบนมือถือเหมือน iOS และลด “กระด้าง” เวลา overscroll บน Android
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        );
      default:
        return super.getScrollPhysics(context);
    }
  }
}

/// เครื่อง RAM/CPU จำกัด: บน Android ใช้ Clamping ลดงาน physics ขณะเลื่อน
class _AppScrollBehaviorConstrained extends MaterialScrollBehavior {
  const _AppScrollBehaviorConstrained();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >=
        TouchProfile.tabletBreakpoint;
    if (isTablet) {
      return const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      );
    }
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        );
      case TargetPlatform.iOS:
        return const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        );
      default:
        return super.getScrollPhysics(context);
    }
  }
}
