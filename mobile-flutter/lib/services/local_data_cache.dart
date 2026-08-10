import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../models/employee.dart';
import '../utils/fuel_stock.dart';

/// แคชข้อมูลจาก Supabase ลง SharedPreferences เพื่อโหลดเร็วและลดรอบเน็ตเวิร์ก
///
/// TTL เป็นแบบช่วงแรก—หลังบันทึก/ลบฝั่ง [EmployeeService]/[TransactionService]
/// จะล้างแคชที่เกี่ยวข้องให้เหมาะสม
class LocalDataCache {
  LocalDataCache._();

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _p() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const _kEmpJson = 'v1_cache_employees_json';
  static const _kEmpAt = 'v1_cache_employees_ms';

  static const _kDashJson = 'v1_cache_dashboard_json';
  static const _kDashAt = 'v1_cache_dashboard_ms';

  static const _kTxDayDates = 'v1_cache_tx_day_dates_json';
  static const _kTxAllJson = 'v1_cache_transactions_all_json';
  static const _kTxAllAt = 'v1_cache_transactions_all_ms';

  static const _kFuelStockJson = 'v1_cache_fuel_stock_json';
  static const _kFuelStockAt = 'v1_cache_fuel_stock_ms';

  /// ไม่เขียนข้อมูลธุรกรรมเต็มชุดลง prefs เกินขีดจำกัดนี้ (กันค้างความจำใหญ่)
  static const int maxTransactionsFullJsonChars = 350000;

  static const Duration employeeTtl = Duration(minutes: 25);
  static const Duration dashboardSummaryTtl = Duration(minutes: 8);
  static const Duration transactionsByDayTtl = Duration(minutes: 3);
  /// มี realtime + patch หลังบันทึก — ยืด TTL ลด full-table SELECT ที่กิน Disk IO
  static const Duration transactionsFullTtl = Duration(minutes: 30);
  /// ยอดถังอัปเดตจาก delta หลังเซฟ — TTL ยาวเพื่อไม่บังคับคำนวณ/ดึง DB บ่อย
  static const Duration fuelStockSnapshotTtl = Duration(days: 7);

  static bool _withinTtl(Duration ttl, int? cachedAtMs) {
    if (cachedAtMs == null) return false;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
    );
    return elapsed <= ttl;
  }

  static Future<List<Employee>?> readEmployees(Duration ttl) async {
    final p = await _p();
    if (!_withinTtl(ttl, p.getInt(_kEmpAt))) return null;
    return _decodeEmployees(p.getString(_kEmpJson));
  }

  /// อ่านแคชพนักงานแม้ TTL หมด — ใช้ตอนออฟไลน์
  static Future<List<Employee>?> readEmployeesAny() async {
    final p = await _p();
    return _decodeEmployees(p.getString(_kEmpJson));
  }

  static List<Employee>? _decodeEmployees(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Employee.fromMap)
          .toList();
    } catch (e, st) {
      debugPrint('LocalDataCache.readEmployees decode error: $e\n$st');
      return null;
    }
  }

  static Future<void> writeEmployees(List<Employee> list) async {
    final p = await _p();
    final blob = jsonEncode(list.map((e) => e.toPersistenceMap()).toList());
    await p.setString(_kEmpJson, blob);
    await p.setInt(_kEmpAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> invalidateEmployees() async {
    final p = await _p();
    await p.remove(_kEmpJson);
    await p.remove(_kEmpAt);
  }

  static Future<DashboardSummary?> readDashboard(Duration ttl) async {
    final p = await _p();
    if (!_withinTtl(ttl, p.getInt(_kDashAt))) return null;
    return _decodeDashboard(p.getString(_kDashJson));
  }

  /// อ่านแคชสรุปแดชบอร์ดแม้ TTL หมด — ใช้ตอนออฟไลน์
  static Future<DashboardSummary?> readDashboardAny() async {
    final p = await _p();
    return _decodeDashboard(p.getString(_kDashJson));
  }

  static DashboardSummary? _decodeDashboard(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DashboardSummary.fromPersistenceMap(decoded);
    } catch (e, st) {
      debugPrint('LocalDataCache.readDashboard decode error: $e\n$st');
      return null;
    }
  }

  static Future<void> writeDashboard(DashboardSummary s) async {
    final p = await _p();
    await p.setString(_kDashJson, jsonEncode(s.toPersistenceMap()));
    await p.setInt(_kDashAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> invalidateDashboard() async {
    final p = await _p();
    await p.remove(_kDashJson);
    await p.remove(_kDashAt);
  }

  static String _txDayJsonKey(String ymd) => 'v1_cache_tx_day_$ymd';
  static String _txDayAtKey(String ymd) => 'v1_cache_tx_day_${ymd}_at';

  static Future<List<String>> _trackedTxDates() async {
    final p = await _p();
    final raw = p.getString(_kTxDayDates);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _setTrackedTxDates(List<String> dates) async {
    final p = await _p();
    if (dates.isEmpty) {
      await p.remove(_kTxDayDates);
      return;
    }
    await p.setString(_kTxDayDates, jsonEncode(dates.toSet().toList()));
  }

  static Future<void> writeTransactionsForDay(String ymd, List<AppTransaction> list) async {
    final p = await _p();
    final blob =
        jsonEncode(list.map((e) => e.toPersistenceMap()).toList());
    await p.setString(_txDayJsonKey(ymd), blob);
    await p.setInt(_txDayAtKey(ymd), DateTime.now().millisecondsSinceEpoch);
    final track = {...await _trackedTxDates(), ymd}.toList();
    await _setTrackedTxDates(track);
  }

  static Future<List<AppTransaction>?> readTransactionsForDay(String ymd, Duration ttl) async {
    final p = await _p();
    final atKey = _txDayAtKey(ymd);
    if (!_withinTtl(ttl, p.getInt(atKey))) return null;
    return _decodeTransactionsForDay(p.getString(_txDayJsonKey(ymd)), ymd);
  }

  /// อ่านธุรกรรมรายวันแม้ TTL หมด — ใช้ตอนออฟไลน์
  static Future<List<AppTransaction>?> readTransactionsForDayAny(String ymd) async {
    final p = await _p();
    return _decodeTransactionsForDay(p.getString(_txDayJsonKey(ymd)), ymd);
  }

  static List<AppTransaction>? _decodeTransactionsForDay(String? raw, String ymd) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppTransaction.fromMap)
          .toList();
    } catch (e, st) {
      debugPrint('LocalDataCache.readTransactionsForDay $ymd error: $e\n$st');
      return null;
    }
  }

  static Future<void> invalidateTransactionsForDay(String ymd) async {
    final p = await _p();
    await p.remove(_txDayJsonKey(ymd));
    await p.remove(_txDayAtKey(ymd));
    final rest = [...await _trackedTxDates()];
    rest.removeWhere((s) => s == ymd);
    await _setTrackedTxDates(rest);
  }

  static Future<void> invalidateAllTransactionsByDay() async {
    final p = await _p();
    for (final ymd in await _trackedTxDates()) {
      await p.remove(_txDayJsonKey(ymd));
      await p.remove(_txDayAtKey(ymd));
    }
    await p.remove(_kTxDayDates);
  }

  static Future<List<AppTransaction>?> readTransactionsFull(Duration ttl) async {
    final p = await _p();
    if (!_withinTtl(ttl, p.getInt(_kTxAllAt))) return null;
    return _decodeTransactionsFull(p.getString(_kTxAllJson));
  }

  /// อ่านธุรกรรมทั้งหมดแม้ TTL หมด — ใช้ตอนออฟไลน์
  static Future<List<AppTransaction>?> readTransactionsFullAny() async {
    final p = await _p();
    return _decodeTransactionsFull(p.getString(_kTxAllJson));
  }

  static List<AppTransaction>? _decodeTransactionsFull(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppTransaction.fromMap)
          .toList();
    } catch (e, st) {
      debugPrint('LocalDataCache.readTransactionsFull error: $e\n$st');
      return null;
    }
  }

  static Future<void> writeTransactionsFull(List<AppTransaction> list) async {
    final blob =
        jsonEncode(list.map((e) => e.toPersistenceMap()).toList());
    if (blob.length > maxTransactionsFullJsonChars) return;
    final p = await _p();
    await p.setString(_kTxAllJson, blob);
    await p.setInt(_kTxAllAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// อัปเดต/เพิ่มรายการเดียวในแคชธุรกรรมเต็มชุด (ใช้หลังบันทึกออฟไลน์)
  static Future<void> patchTransactionInFull(AppTransaction tx) async {
    final existing = await readTransactionsFullAny() ?? const <AppTransaction>[];
    final next = <AppTransaction>[
      tx,
      ...existing.where((t) => t.id != tx.id),
    ];
    await writeTransactionsFull(next);
  }

  /// ลบรายการจากแคชธุรกรรมเต็มชุด
  static Future<void> removeTransactionFromFull(String id) async {
    if (id.trim().isEmpty) return;
    final existing = await readTransactionsFullAny();
    if (existing == null) return;
    final next = existing.where((t) => t.id != id).toList();
    if (next.length == existing.length) return;
    await writeTransactionsFull(next);
  }

  static Future<void> invalidateTransactionsFull() async {
    final p = await _p();
    await p.remove(_kTxAllJson);
    await p.remove(_kTxAllAt);
  }

  static Future<void> writeFuelStockSnapshot(FuelStockBalance balance) async {
    final p = await _p();
    await p.setString(
      _kFuelStockJson,
      jsonEncode({
        'mainDiesel': balance.mainDiesel,
        'reserveDiesel': balance.reserveDiesel,
        'mainBenzine': balance.mainBenzine,
        'reserveBenzine': balance.reserveBenzine,
      }),
    );
    await p.setInt(_kFuelStockAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// อ่าน snapshot คงเหลือน้ำมัน (TTL) — ใช้โชว์เกจทันทีก่อนคำนวณจากแคชธุรกรรม
  static Future<FuelStockBalance?> readFuelStockSnapshot(Duration ttl) async {
    final p = await _p();
    if (!_withinTtl(ttl, p.getInt(_kFuelStockAt))) return null;
    return _decodeFuelStock(p.getString(_kFuelStockJson));
  }

  static Future<FuelStockBalance?> readFuelStockSnapshotAny() async {
    final p = await _p();
    return _decodeFuelStock(p.getString(_kFuelStockJson));
  }

  static FuelStockBalance? _decodeFuelStock(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return FuelStockBalance(
        mainDiesel: (decoded['mainDiesel'] as num?)?.toDouble() ?? 0,
        reserveDiesel: (decoded['reserveDiesel'] as num?)?.toDouble() ?? 0,
        mainBenzine: (decoded['mainBenzine'] as num?)?.toDouble() ?? 0,
        reserveBenzine: (decoded['reserveBenzine'] as num?)?.toDouble() ?? 0,
      );
    } catch (e, st) {
      debugPrint('LocalDataCache.readFuelStockSnapshot error: $e\n$st');
      return null;
    }
  }

  static Future<void> invalidateFuelStockSnapshot() async {
    final p = await _p();
    await p.remove(_kFuelStockJson);
    await p.remove(_kFuelStockAt);
  }
}
