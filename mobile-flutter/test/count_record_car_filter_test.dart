import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/daily_module_transactions.dart';

void main() {
  test('count-record picker keeps drum and ten-wheel only', () {
    expect(isCountRecordDrumOrTenWheelCarName('รถดรัมโอเว่น'), isTrue);
    expect(isCountRecordDrumOrTenWheelCarName('รถสิบล้อ A'), isTrue);
    expect(isCountRecordDrumOrTenWheelCarName('10ล้อ-B'), isTrue);
    expect(isCountRecordDrumOrTenWheelCarName('รถหกล้อ 01'), isFalse);
    expect(isCountRecordDrumOrTenWheelCarName('รถแม็คโคร SK200'), isFalse);
  });
}
