import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/auth/auth_service.dart';
import 'package:mobile_stone_sand/auth/password_auth.dart';
import 'package:mobile_stone_sand/auth/session.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/data/scope.dart';
import 'package:mobile_stone_sand/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
    endDemoSession();
  });

  group('verifyStoredPassword', () {
    final hex = sha256Hex('secret1');

    test('accepts every stored hash format', () {
      expect(verifyStoredPassword('sha256\$$hex', 'secret1'), true);
      expect(verifyStoredPassword('sha256:$hex', 'secret1'), true);
      expect(verifyStoredPassword(hex.toUpperCase(), 'secret1'), true);
      expect(verifyStoredPassword('sha256\$$hex', 'wrong'), false);
    });

    test('forgives surrounding spaces in the typed password', () {
      expect(verifyStoredPassword('sha256\$$hex', ' secret1 '), true);
    });

    test('still accepts legacy plain-text passwords', () {
      expect(verifyStoredPassword('plain', 'plain'), true);
      expect(verifyStoredPassword('plain', 'other'), false);
      expect(verifyStoredPassword('', ''), false);
    });
  });

  group('canAccessSite', () {
    test('orders are for SuperAdmin and Admin by default', () {
      expect(canAccessSite('SuperAdmin', null, 'order'), true);
      expect(canAccessSite('Admin', null, 'order'), true);
      expect(canAccessSite('Assistant', null, 'order'), false);
    });

    test('allowed_apps overrides the role default', () {
      expect(canAccessSite('Assistant', ['order'], 'order'), true);
      expect(canAccessSite('SuperAdmin', ['main'], 'order'), false);
    });
  });

  group('session', () {
    StoneSandSession make(DateTime loginAt, {bool remember = false}) => StoneSandSession(
      id: 'u1',
      username: 'admin',
      displayName: 'แอดมิน',
      role: 'Admin',
      orderSource: OrderSource.pit,
      loginAt: loginAt.toUtc().toIso8601String(),
      remember: remember,
    );

    test('round-trips and keeps the order source limit', () {
      saveSession(make(DateTime.now()));
      final s = readSession();
      expect(s?.username, 'admin');
      expect(s?.orderSource, OrderSource.pit);
      expect(s?.by, 'แอดมิน');
    });

    test('expires after 12 hours (non-remembered)', () {
      saveSession(make(DateTime.now().subtract(const Duration(hours: 13))));
      expect(readSession(), isNull);
      expect(Prefs.instance.getString('stone_sand_session_v1'), isNull);
    });

    test('non-remembered session still valid at 11 hours', () {
      final s = make(DateTime.now().subtract(const Duration(hours: 11)));
      saveSession(s);
      expect(readSession(), isNotNull);
    });

    test('remembered session valid at 29 days', () {
      final loginAt = DateTime.now().subtract(const Duration(days: 29));
      saveSession(make(loginAt, remember: true));
      expect(readSession(), isNotNull);
    });

    test('remembered session expires at 31 days', () {
      final loginAt = DateTime.now().subtract(const Duration(days: 31));
      saveSession(make(loginAt, remember: true));
      expect(readSession(), isNull);
      expect(Prefs.instance.getString('stone_sand_session_v1'), isNull);
    });

    test('old JSON without remember field parses as remember=false', () {
      // Simulate legacy stored JSON that has no 'remember' key.
      final recentTs = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      final legacyJson =
          '{"id":"u1","username":"admin","displayName":"แอดมิน","role":"Admin","orderSource":null,'
          '"loginAt":"$recentTs"}';
      Prefs.instance.setString('stone_sand_session_v1', legacyJson);
      final s = readSession();
      expect(s, isNotNull);
      expect(s!.remember, isFalse);
    });

    test('slideSession updates loginAt and session stays readable', () {
      final old = make(DateTime.now().subtract(const Duration(days: 25)), remember: true);
      saveSession(old);
      slideSession(readSession()!);
      final fresh = readSession();
      expect(fresh, isNotNull);
      // After sliding, a "29 days ago" offset should still be within TTL.
      final loginAt = DateTime.tryParse(fresh!.loginAt)!;
      expect(DateTime.now().difference(loginAt).inMinutes, lessThan(2));
    });

    test('slideSession is no-op for non-remembered sessions', () {
      final s = make(DateTime.now());
      saveSession(s);
      slideSession(s); // should not throw or change remember flag
      final loaded = readSession();
      expect(loaded?.remember, isFalse);
    });
  });

  group('last username', () {
    test('saves and reads back', () {
      saveLastUsername('สมชาย');
      expect(readLastUsername(), 'สมชาย');
    });

    test('empty string is not saved', () {
      saveLastUsername('');
      expect(readLastUsername(), isNull);
    });

    test('survives multiple overwrites', () {
      saveLastUsername('alice');
      saveLastUsername('bob');
      expect(readLastUsername(), 'bob');
    });

    test('returns null when nothing stored', () {
      expect(readLastUsername(), isNull);
    });
  });

  group('source and demo scope', () {
    test('locks to one source', () {
      setLockedSource(OrderSource.shop);
      expect(canSeeSource(OrderSource.shop), true);
      expect(canSeeSource(OrderSource.pit), false);
      setLockedSource(null);
      expect(canSeeSource(OrderSource.pit), true);
    });

    test('shows demo rows only for the current session', () {
      expect(isVisibleDemo(null), true);
      expect(isVisibleDemo('demo-x'), false);
      final s = startDemoSession();
      expect(s, startsWith('demo-'));
      expect(isVisibleDemo(s), true);
      expect(isVisibleDemo('demo-other'), false);
      expect(Prefs.instance.getString(demoSessionKey), s);
      endDemoSession();
      expect(demoSession(), isNull);
    });
  });
}
