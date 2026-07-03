import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/services/count_record_tutorial_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hasCompleted is false until marked', () async {
    expect(await CountRecordTutorialStore.hasCompleted(), isFalse);
    await CountRecordTutorialStore.markCompleted();
    expect(await CountRecordTutorialStore.hasCompleted(), isTrue);
  });

  test('reset clears completed flag', () async {
    await CountRecordTutorialStore.markCompleted();
    await CountRecordTutorialStore.reset();
    expect(await CountRecordTutorialStore.hasCompleted(), isFalse);
  });
}
