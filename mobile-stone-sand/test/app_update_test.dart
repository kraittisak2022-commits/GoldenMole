import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_stone_sand/data/db.dart';
import 'package:mobile_stone_sand/services/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.setForTest(await SharedPreferences.getInstance());
  });

  group('remoteUpdate', () {
    test('reads this app\'s Android keys and ignores the other apps', () {
      final defaults = {
        'androidLatestVersionCode': 99,
        'stoneSandAndroidLatestVersionCode': '7',
        'stoneSandAndroidLatestVersionName': '1.2.0',
      };
      final u = remoteUpdate(defaults, android: true, localBuild: 5)!;
      expect(u.build, 7);
      expect(u.version, '1.2.0');
      expect(u.url, playStoreUrl);
      expect(u.fromPlay, isFalse);
      expect(remoteUpdate(defaults, android: true, localBuild: 7), isNull);
      expect(remoteUpdate({'androidLatestVersionCode': 99}, android: true, localBuild: 1), isNull);
    });

    test('iOS needs a TestFlight link to offer an update button', () {
      final u = remoteUpdate(
        {'stoneSandIosLatestBuild': 4, 'stoneSandIosLatestVersion': '1.0.1'},
        android: false,
        localBuild: 3,
      )!;
      expect(u.version, '1.0.1');
      expect(u.url, isNull);
      final withLink = remoteUpdate(
        {'stoneSandIosLatestBuild': 4, 'stoneSandIosTestFlightURL': 'https://testflight.apple.com/join/x'},
        android: false,
        localBuild: 3,
      )!;
      expect(withLink.url, 'https://testflight.apple.com/join/x');
    });
  });

  test('snooze hides the same build for three days but not a newer one', () {
    final now = DateTime(2026, 10, 9, 12);
    const u = SoftUpdate(build: 7);
    expect(shouldPrompt(u, now: now), isTrue);
    snooze(u, now: now);
    expect(shouldPrompt(u, now: now.add(const Duration(days: 2))), isFalse);
    expect(shouldPrompt(const SoftUpdate(build: 8), now: now), isTrue);
    expect(shouldPrompt(u, now: now.add(snoozeFor)), isTrue);
  });
}
