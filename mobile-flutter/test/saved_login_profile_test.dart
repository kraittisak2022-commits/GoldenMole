import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/admin_user.dart';
import 'package:mobile_flutter/models/saved_login_profile.dart';
import 'package:mobile_flutter/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements SecureCredentialStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

AdminUser _admin(String id, String username, String displayName) {
  return AdminUser(
    id: id,
    username: username,
    password: '',
    displayName: displayName,
    role: 'admin',
  );
}

void main() {
  group('SavedLoginProfile', () {
    test('initials from two-word display name', () {
      final p = SavedLoginProfile(
        id: '1',
        username: 'admin',
        displayName: 'Somchai Jaidee',
        lastUsedAt: DateTime(2026, 1, 1),
      );
      expect(p.initials, 'SJ');
    });

    test('initials fall back to username', () {
      final p = SavedLoginProfile(
        id: '1',
        username: 'boss',
        displayName: '   ',
        lastUsedAt: DateTime(2026, 1, 1),
      );
      expect(p.initials, 'B');
    });

    test('round-trips JSON', () {
      final original = SavedLoginProfile(
        id: 'abc',
        username: 'u1',
        displayName: 'User One',
        lastUsedAt: DateTime.utc(2026, 7, 18, 10, 30),
      );
      final restored = SavedLoginProfile.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.displayName, original.displayName);
      expect(restored.lastUsedAt.toUtc(), original.lastUsedAt.toUtc());
    });
  });

  group('SessionService saved profiles', () {
    late SessionService service;
    late _MemorySecureStore storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = _MemorySecureStore();
      service = SessionService(secureStore: storage);
    });

    test('saves, lists, and caps at max profiles', () async {
      for (var i = 0; i < SessionService.maxSavedProfiles + 2; i++) {
        await service.saveLoginProfile(
          admin: _admin('id-$i', 'user$i', 'User $i'),
          password: 'pass-$i',
        );
      }
      final profiles = await service.getSavedProfiles();
      expect(profiles.length, SessionService.maxSavedProfiles);
      // ล่าสุดอยู่หน้าสุด; เก่าสุดถูกตัดออก (id-0, id-1)
      expect(profiles.first.username, 'user${SessionService.maxSavedProfiles + 1}');
      expect(
        profiles.map((p) => p.username),
        isNot(contains('user0')),
      );
      expect(
        profiles.map((p) => p.username),
        isNot(contains('user1')),
      );
    });

    test('stores password in secure storage and removes with profile', () async {
      await service.saveLoginProfile(
        admin: _admin('a1', 'alice', 'Alice'),
        password: 'secret',
      );
      expect(await service.getProfilePassword('a1'), 'secret');
      await service.removeSavedProfile('a1');
      expect(await service.getSavedProfiles(), isEmpty);
      expect(await service.getProfilePassword('a1'), isNull);
    });

    test('migrates legacy single password into a profile', () async {
      SharedPreferences.setMockInitialValues({
        'mobile_last_login_username': 'legacy_user',
      });
      final legacyStore = _MemorySecureStore();
      await legacyStore.write(
        'mobile_saved_login_password',
        'legacy-pass',
      );
      final migrating = SessionService(secureStore: legacyStore);
      final profiles = await migrating.getSavedProfiles();
      expect(profiles.length, 1);
      expect(profiles.first.username, 'legacy_user');
      expect(
        await migrating.getProfilePassword(profiles.first.id),
        'legacy-pass',
      );
      expect(await legacyStore.read('mobile_saved_login_password'), isNull);
    });
  });
}
