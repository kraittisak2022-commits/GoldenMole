import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/auth_scope.dart';
import 'data/catalog_scope.dart';
import 'data/demo_repo.dart';
import 'routes.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'tour/tour_controller.dart';
import 'tour/tour_overlay.dart';

class StoneSandApp extends StatefulWidget {
  const StoneSandApp({super.key});

  @override
  State<StoneSandApp> createState() => _StoneSandAppState();
}

class _StoneSandAppState extends State<StoneSandApp> {
  final _auth = AuthController();
  final _catalog = CatalogController();
  final _shell = ShellController();
  final _navigator = GlobalKey<NavigatorState>();
  late final _tour = TourController(auth: _auth, catalog: _catalog, shell: _shell, navigatorKey: _navigator);
  String? _userId;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuth);
    _onAuth();
    _auth.recheck().catchError((_) {});
  }

  void _onAuth() {
    final id = _auth.user?.id;
    if (id == _userId) return;
    _userId = id;
    if (id == null) {
      _navigator.currentState?.popUntil((r) => r.isFirst);
      _shell.reset();
      _tour.pause();
      return;
    }
    _catalog.reload();
    deleteStaleDemoSessions().catchError((_) {});
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _auth.dispose();
    _catalog.dispose();
    _shell.dispose();
    _tour.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _auth,
      child: CatalogScope(
        controller: _catalog,
        child: ShellScope(
          controller: _shell,
          child: TourScope(
            controller: _tour,
            child: MaterialApp(
              title: 'ระบบจัดการออเดอร์ หิน-ทราย',
              debugShowCheckedModeBanner: false,
              navigatorKey: _navigator,
              navigatorObservers: [_tour.observer],
              theme: buildAppTheme(),
              locale: const Locale('th', 'TH'),
              supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => TourOverlayHost(child: child ?? const SizedBox.shrink()),
              home: const _AuthGate(),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final signedIn = AuthScope.of(context).isAuthenticated;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: signedIn ? const HomeShell(key: ValueKey('home')) : const LoginScreen(key: ValueKey('login')),
    );
  }
}
