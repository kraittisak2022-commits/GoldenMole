import 'package:flutter/widgets.dart';

import '../data/scope.dart';
import '../models/models.dart';
import 'auth_service.dart';
import 'session.dart';

class AuthController extends ChangeNotifier {
  AuthController() : _user = readSession() {
    setLockedSource(_user?.orderSource);
  }

  StoneSandSession? _user;

  StoneSandSession? get user => _user;
  bool get isAuthenticated => _user != null;

  /// Hides edit/delete actions only; the database itself does not enforce roles.
  bool get isSuperAdmin => _user?.role == 'SuperAdmin';

  /// The only order source this account may see, or null for both.
  OrderSource? get lockedSource => _user?.orderSource;

  /// Order sources the signed-in account may see and create.
  List<OrderSource> get visibleSources => lockedSource != null ? [lockedSource!] : OrderSource.values;

  String get by => _user?.by ?? '';

  Future<void> signIn(String username, String password, {bool remember = false}) async {
    final session = await signInWithAdminUsers(username, password);
    final remembered = session.copyWith(remember: remember);
    saveSession(remembered);
    saveLastUsername(username.trim());
    _set(remembered);
  }

  void signOut() {
    clearSession();
    _set(null);
  }

  void _set(StoneSandSession? s) {
    _user = s;
    setLockedSource(s?.orderSource);
    notifyListeners();
  }

  /// Re-checks the account on start; signs out when it was removed or lost access.
  /// For remembered sessions, slides the TTL so active users never get logged out.
  Future<void> recheck() async {
    final u = _user;
    if (u == null) return;
    final res = await checkSession(u.id);
    if (_user?.id != u.id) return;
    if (!res.allowed) return signOut();

    final roleChanged = res.role != null && (res.role != u.role || res.orderSource != u.orderSource);
    if (roleChanged) {
      final next = u.copyWith(role: res.role, orderSource: res.orderSource, clearSource: res.orderSource == null);
      saveSession(next);
      _set(slideSession(next));
      return;
    }
    // Role and source are unchanged, so listeners need no rebuild.
    _user = slideSession(u);
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({super.key, required AuthController controller, required super.child}) : super(notifier: controller);

  static AuthController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AuthScope>()!.notifier!;

  static AuthController read(BuildContext context) => context.getInheritedWidgetOfExactType<AuthScope>()!.notifier!;
}
