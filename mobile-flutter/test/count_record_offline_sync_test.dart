import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/app_sync_snapshot.dart';
import 'package:mobile_flutter/services/count_record_offline_sync.dart';

void main() {
  group('CountRecordOfflineSync.retryDelayForCount', () {
    test('starts at 2 seconds', () {
      expect(
        CountRecordOfflineSync.retryDelayForCount(0).inSeconds,
        2,
      );
    });

    test('doubles up to 30 seconds cap', () {
      expect(CountRecordOfflineSync.retryDelayForCount(1).inSeconds, 4);
      expect(CountRecordOfflineSync.retryDelayForCount(2).inSeconds, 8);
      expect(CountRecordOfflineSync.retryDelayForCount(5).inSeconds, 30);
    });
  });

  group('AppSyncSnapshot', () {
    test('distinguishes no network vs server offline messages', () {
      const noNet = AppSyncSnapshot(network: NetworkLinkState.unlink);
      expect(noNet.bannerMessage, contains('ไม่มีสัญญาณ'));

      const serverDown = AppSyncSnapshot(
        network: NetworkLinkState.linked,
        server: ServerReachState.offline,
      );
      expect(serverDown.bannerMessage, contains('เซิร์ฟเวอร์'));
    });
  });
}
