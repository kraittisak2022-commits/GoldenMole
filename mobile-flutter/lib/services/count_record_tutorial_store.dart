import 'package:shared_preferences/shared_preferences.dart';

/// จำว่าผู้ใช้ดูคู่มือ «บันทึกและนับจำนวน» แล้วหรือยัง
class CountRecordTutorialStore {
  CountRecordTutorialStore._();

  static const _keyCompleted = 'count_record_tutorial_completed_v1';

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCompleted) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompleted, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCompleted);
  }
}
