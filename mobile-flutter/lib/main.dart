import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/admin_user.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/dashboard_service.dart';
import 'services/session_service.dart';
import 'widgets/bootstrap_splash.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Load environment variables
    await dotenv.load(fileName: '.env');

    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env file');
    }

    // Initialize Supabase
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

    runApp(const MobileApp());
  } catch (e) {
    debugPrint('Error during initialization: $e');
    runApp(
      MaterialApp(
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
  const MobileApp({super.key});

  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> {
  AdminUser? _currentAdmin;
  bool _bootstrapping = true;
  final SessionService _sessionService = SessionService();

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final admin = await _sessionService.getSavedAdmin();
      if (!mounted) return;
      setState(() {
        _currentAdmin = admin;
        _bootstrapping = false;
      });
    } catch (e) {
      debugPrint('Error restoring session: $e');
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    final baseLight = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF11A8BA),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF3FBFC),
    );
    final appTheme = baseLight.copyWith(
      textTheme: GoogleFonts.kanitTextTheme(baseLight.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF17374C),
        elevation: 0,
        titleTextStyle: GoogleFonts.kanit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF17374C),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF11A8BA),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFCFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDEAF1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDEAF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF11A8BA), width: 1.4),
        ),
      ),
    );

    return MaterialApp(
      title: 'Construction Management Mobile',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: appTheme,
      darkTheme: appTheme,
      home: _bootstrapping
          ? const BootstrapSplash()
          : _currentAdmin == null
          ? LoginScreen(
              authService: AuthService(client),
              onLoginSuccess: (admin) async {
                await _sessionService.saveAdmin(admin);
                if (!mounted) return;
                setState(() => _currentAdmin = admin);
              },
            )
          : DashboardScreen(
              currentAdmin: _currentAdmin!,
              dashboardService: DashboardService(client),
              onLogout: () async {
                await _sessionService.clear();
                if (!mounted) return;
                setState(() => _currentAdmin = null);
              },
            ),
    );
  }
}
