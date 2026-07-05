import 'package:flutter_test/flutter_test.dart';
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
}
