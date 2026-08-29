import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Soft update prompt — แนะนำไปอัปเดตที่ Play Store แต่ไม่บังคับ
class SoftAppUpdateInfo {
  const SoftAppUpdateInfo({
    required this.available,
    this.availableVersionCode,
    this.availableVersionName,
    this.source = SoftAppUpdateSource.none,
  });

  final bool available;
  final int? availableVersionCode;
  final String? availableVersionName;
  final SoftAppUpdateSource source;
}

enum SoftAppUpdateSource { none, playStore, remoteConfig }

class AppUpdateService {
  AppUpdateService._();

  static const packageId = 'com.goldenmole.app';
  static const _snoozeUntilKey = 'soft_update_snooze_until_ms';
  static const _snoozeCodeKey = 'soft_update_snooze_code';
  static const snoozeDuration = Duration(days: 3);

  /// ตรวจว่ามีเวอร์ชันใหม่หรือไม่ (Android เท่านั้น)
  static Future<SoftAppUpdateInfo> checkForSoftUpdate({
    SupabaseClient? client,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const SoftAppUpdateInfo(available: false);
    }

    SoftAppUpdateInfo? playHit;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        playHit = SoftAppUpdateInfo(
          available: true,
          availableVersionCode: info.availableVersionCode,
          source: SoftAppUpdateSource.playStore,
        );
      }
    } catch (e, st) {
      debugPrint('InAppUpdate.checkForUpdate skipped: $e\n$st');
    }

    SoftAppUpdateInfo? remoteHit;
    try {
      remoteHit = await _checkRemoteConfig(client ?? Supabase.instance.client);
    } catch (e, st) {
      debugPrint('Remote soft-update check skipped: $e\n$st');
    }

    // เลือกตัวที่เวอร์ชันสูงกว่า (หรืออันแรกที่มี)
    final candidates = <SoftAppUpdateInfo>[
      if (playHit?.available == true) playHit!,
      if (remoteHit?.available == true) remoteHit!,
    ];
    if (candidates.isEmpty) {
      return const SoftAppUpdateInfo(available: false);
    }
    candidates.sort(
      (a, b) => (b.availableVersionCode ?? 0).compareTo(a.availableVersionCode ?? 0),
    );
    return candidates.first;
  }

  static Future<SoftAppUpdateInfo> _checkRemoteConfig(SupabaseClient client) async {
    final pkg = await PackageInfo.fromPlatform();
    final localCode = int.tryParse(pkg.buildNumber.trim()) ?? 0;

    final row = await client
        .from('app_settings')
        .select('app_defaults')
        .limit(1)
        .maybeSingle();
    if (row == null) return const SoftAppUpdateInfo(available: false);

    final defaults = row['app_defaults'];
    if (defaults is! Map) return const SoftAppUpdateInfo(available: false);

    final remoteCodeRaw = defaults['androidLatestVersionCode'];
    final remoteCode = remoteCodeRaw is num
        ? remoteCodeRaw.toInt()
        : int.tryParse('$remoteCodeRaw'.trim());
    if (remoteCode == null || remoteCode <= localCode) {
      return const SoftAppUpdateInfo(available: false);
    }

    final remoteName = '${defaults['androidLatestVersionName'] ?? ''}'.trim();
    return SoftAppUpdateInfo(
      available: true,
      availableVersionCode: remoteCode,
      availableVersionName: remoteName.isEmpty ? null : remoteName,
      source: SoftAppUpdateSource.remoteConfig,
    );
  }

  static Future<bool> shouldPrompt(SoftAppUpdateInfo info) async {
    if (!info.available) return false;
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_snoozeUntilKey) ?? 0;
    final snoozedCode = prefs.getInt(_snoozeCodeKey) ?? 0;
    final code = info.availableVersionCode ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until > now && (code == 0 || code <= snoozedCode)) {
      return false;
    }
    return true;
  }

  static Future<void> snooze(SoftAppUpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(snoozeDuration).millisecondsSinceEpoch;
    await prefs.setInt(_snoozeUntilKey, until);
    if (info.availableVersionCode != null) {
      await prefs.setInt(_snoozeCodeKey, info.availableVersionCode!);
    }
  }

  static Future<bool> openPlayStore() async {
    final market = Uri.parse('market://details?id=$packageId');
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageId',
    );
    try {
      if (await canLaunchUrl(market)) {
        return launchUrl(market, mode: LaunchMode.externalApplication);
      }
      return launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('openPlayStore failed: $e\n$st');
      try {
        return launchUrl(web, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  /// ตรวจแล้วโชว์ไดอะล็อกแบบ soft (ถ้ามีอัปเดตและยังไม่ snooze)
  static Future<void> maybePromptSoftUpdate(BuildContext context) async {
    try {
      final info = await checkForSoftUpdate();
      if (!info.available) return;
      if (!await shouldPrompt(info)) return;
      if (!context.mounted) return;
      await showSoftUpdateDialog(context, info);
    } catch (e, st) {
      debugPrint('maybePromptSoftUpdate: $e\n$st');
    }
  }

  static Future<void> showSoftUpdateDialog(
    BuildContext context,
    SoftAppUpdateInfo info,
  ) async {
    final versionHint = [
      if ((info.availableVersionName ?? '').isNotEmpty)
        'v${info.availableVersionName}',
      if (info.availableVersionCode != null)
        '(${info.availableVersionCode})',
    ].join(' ');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'มีเวอร์ชันใหม่ของแอพ',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
          ),
          content: Text(
            versionHint.trim().isEmpty
                ? 'แนะนำให้อัปเดตจาก Google Play เพื่อใช้งานฟีเจอร์ล่าสุด\n\nยังสามารถใช้งานเวอร์ชันนี้ต่อได้ตามปกติ'
                : 'พบเวอร์ชันใหม่ $versionHint\nแนะนำให้อัปเดตจาก Google Play\n\nยังสามารถใช้งานเวอร์ชันนี้ต่อได้ตามปกติ',
            style: GoogleFonts.kanit(height: 1.4, fontSize: 14.5),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () async {
                await snooze(info);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(
                'ใช้งานต่อ',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                await openPlayStore();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              icon: const Icon(Icons.system_update_alt_rounded, size: 18),
              label: Text(
                'อัปเดตที่ Play Store',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }
}
