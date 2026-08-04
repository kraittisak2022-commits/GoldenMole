import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/services/count_record_work_mode_store.dart';
import 'package:mobile_flutter/utils/count_record_work_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads work mode per day key', () async {
    expect(await CountRecordWorkModeStore.load('2026-08-04'), isNull);
    await CountRecordWorkModeStore.save(
      '2026-08-04',
      CountRecordWorkMode.trip,
    );
    expect(
      await CountRecordWorkModeStore.load('2026-08-04'),
      CountRecordWorkMode.trip,
    );
    await CountRecordWorkModeStore.save(
      '2026-08-04',
      CountRecordWorkMode.both,
    );
    expect(
      await CountRecordWorkModeStore.load('2026-08-04'),
      CountRecordWorkMode.both,
    );
    expect(await CountRecordWorkModeStore.load('2026-08-05'), isNull);
  });
}
