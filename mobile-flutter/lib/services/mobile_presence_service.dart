import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks mobile app presence on Supabase Realtime channel `mobile-presence`.
class MobilePresenceService {
  MobilePresenceService._();
  static final MobilePresenceService instance = MobilePresenceService._();

  RealtimeChannel? _channel;
  String? _username;
  bool _subscribed = false;

  Future<void> start(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;
    await stop();
    _username = trimmed;

    final client = Supabase.instance.client;
    final device = await _resolveDeviceLabel();
    final platform = Platform.operatingSystem;
    final presenceKey = 'mobile-$trimmed-${device.hashCode}';

    final channel = client.channel(
      'mobile-presence',
      opts: RealtimeChannelConfig(
        key: presenceKey,
        enabled: true,
      ),
    );

    channel.onPresenceSync((_) {
      // web dashboard reads presence state
    });

    channel.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        await _track(trimmed, device, platform);
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        _subscribed = false;
        if (error != null) {
          debugPrint('mobile-presence subscribe error: $error');
        }
      }
    });

    _channel = channel;
  }

  Future<void> pause() async {
    if (_channel == null || !_subscribed) return;
    try {
      await _channel!.untrack();
    } catch (e, st) {
      debugPrint('mobile-presence untrack: $e\n$st');
    }
  }

  Future<void> resume() async {
    final username = _username;
    if (username == null || username.isEmpty) return;
    if (_channel == null || !_subscribed) {
      await start(username);
      return;
    }
    final device = await _resolveDeviceLabel();
    await _track(username, device, Platform.operatingSystem);
  }

  Future<void> stop() async {
    final ch = _channel;
    _channel = null;
    _username = null;
    _subscribed = false;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (_) {}
    try {
      await Supabase.instance.client.removeChannel(ch);
    } catch (e, st) {
      debugPrint('mobile-presence removeChannel: $e\n$st');
    }
  }

  Future<void> _track(String username, String device, String platform) async {
    if (_channel == null || !_subscribed) return;
    try {
      await _channel!.track({
        'username': username,
        'device': device,
        'platform': platform,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e, st) {
      debugPrint('mobile-presence track: $e\n$st');
    }
  }

  Future<String> _resolveDeviceLabel() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return '${info.brand} ${info.model}'.trim();
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.utsname.machine;
      }
    } catch (e) {
      debugPrint('device info: $e');
    }
    return 'Mobile';
  }
}
