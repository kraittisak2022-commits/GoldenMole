import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';

const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.goldenmole.stonesand';
const _snoozeKey = 'stone_sand_update_snooze_v1';
const snoozeFor = Duration(days: 3);

/// A newer build than the one installed.
class SoftUpdate {
  const SoftUpdate({required this.build, this.version = '', this.url, this.fromPlay = false});
  final int build;
  final String version;

  /// Where "อัปเดต" goes when the Play in-app flow is not available.
  final String? url;

  /// Google Play reported it, so the in-app flexible update can install it.
  final bool fromPlay;
}

/// This app's keys in `app_settings.app_defaults` (shared with the other apps, so prefixed).
SoftUpdate? remoteUpdate(Map<dynamic, dynamic> defaults, {required bool android, required int localBuild}) {
  final prefix = android ? 'stoneSandAndroid' : 'stoneSandIos';
  final raw = defaults[android ? '${prefix}LatestVersionCode' : '${prefix}LatestBuild'];
  final build = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'.trim());
  if (build == null || build <= localBuild) return null;
  final url = '${defaults[android ? '${prefix}StoreURL' : '${prefix}TestFlightURL'] ?? ''}'.trim();
  return SoftUpdate(
    build: build,
    version: '${defaults[android ? '${prefix}LatestVersionName' : '${prefix}LatestVersion'] ?? ''}'.trim(),
    url: url.isNotEmpty ? url : (android ? playStoreUrl : null),
  );
}

/// "ใช้งานต่อ" hides the prompt for [snoozeFor], unless an even newer build shows up.
bool shouldPrompt(SoftUpdate u, {DateTime? now}) {
  try {
    final raw = Prefs.instance.getString(_snoozeKey);
    if (raw == null) return true;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final until = (j['until'] as num?)?.toInt() ?? 0;
    final build = (j['build'] as num?)?.toInt() ?? 0;
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return t >= until || u.build > build;
  } catch (_) {
    return true;
  }
}

void snooze(SoftUpdate u, {DateTime? now}) {
  final until = (now ?? DateTime.now()).add(snoozeFor).millisecondsSinceEpoch;
  try {
    Prefs.instance.setString(_snoozeKey, jsonEncode({'until': until, 'build': u.build}));
  } catch (_) {}
}

Future<SoftUpdate?> checkSoftUpdate() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  final android = Platform.isAndroid;
  final candidates = <SoftUpdate>[];
  if (android) {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable && info.flexibleUpdateAllowed) {
        candidates.add(SoftUpdate(build: info.availableVersionCode ?? 0, url: playStoreUrl, fromPlay: true));
      }
    } catch (e) {
      debugPrint('Play update check skipped: $e');
    }
  }
  try {
    final local = int.tryParse((await PackageInfo.fromPlatform()).buildNumber.trim()) ?? 0;
    final row = await db.from('app_settings').select('app_defaults').eq('id', 'default').maybeSingle();
    final defaults = row?['app_defaults'];
    final remote = defaults is Map ? remoteUpdate(defaults, android: android, localBuild: local) : null;
    if (remote != null) candidates.add(remote);
  } catch (e) {
    debugPrint('Remote update check skipped: $e');
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.build.compareTo(a.build));
  return candidates.firstWhere((c) => c.fromPlay, orElse: () => candidates.first);
}

Future<void> _install(SoftUpdate u) async {
  if (u.fromPlay) {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) await InAppUpdate.completeFlexibleUpdate();
      return;
    } catch (e) {
      debugPrint('Flexible update failed: $e');
    }
  }
  final url = u.url;
  if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

bool _checked = false;

/// Once per app run, after sign-in: offer a newer build without blocking work.
Future<void> maybePromptSoftUpdate(BuildContext context) async {
  if (_checked || kDebugMode) return;
  _checked = true;
  final u = await checkSoftUpdate();
  if (u == null || !shouldPrompt(u) || !context.mounted) return;
  final version = [if (u.version.isNotEmpty) 'v${u.version}', if (u.build > 0) '(${u.build})'].join(' ');
  final install = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('มีเวอร์ชันใหม่ของแอป'),
      content: Text(
        '${version.isEmpty ? 'มีเวอร์ชันใหม่' : 'พบเวอร์ชันใหม่ $version'} แนะนำให้อัปเดตเพื่อใช้งานฟีเจอร์ล่าสุด\n\n'
        'ยังใช้งานเวอร์ชันนี้ต่อได้ตามปกติ',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ใช้งานต่อ')),
        if (u.fromPlay || u.url != null)
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: const Text('อัปเดต'),
          ),
      ],
    ),
  );
  if (install == true) {
    await _install(u);
  } else {
    snooze(u);
  }
}
