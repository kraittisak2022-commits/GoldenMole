import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../models/employee.dart';
import '../utils/fuel_stock.dart';

/// jsonDecode ใน isolate — อย่าเรียกตรงจาก UI
List<Map<String, dynamic>> decodeTxPersistenceMaps(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// jsonEncode ใน isolate — อย่าเรียกตรงจาก UI
String encodeTxPersistenceMaps(List<Map<String, dynamic>> maps) {
  return jsonEncode(maps);
}

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
  static const _txFullFileName = 'tx_full_v1.json';

  static const _kFuelStockJson = 'v1_cache_fuel_stock_json';
  static const _kFuelStockAt = 'v1_cache_fuel_stock_ms';

  /// เพดานไฟล์แคชเต็มชุด (~8 MB) — กันบวมผิดปกติ ไม่ใช่ SharedPreferences
  static const int maxTransactionsFullJsonChars = 8 * 1024 * 1024;

  static File? _txFullFile;
  static bool _legacyTxPrefsCleared = false;
  /// แคชใน RAM หลังถอดรหัสครั้งแรก — กัน decode ไฟล์ ~4MB ซ้ำตอนเปิดเมนู
  static List<AppTransaction>? _txFullMemory;
  static Future<List<AppTransaction>?>? _txFullInFlight;

  static void _clearTxFullMemory() {
    _txFullMemory = null;
    _txFullInFlight = null;
  }

  /// อ่านแคชเต็มชุดจาก RAM ทันที (ไม่แตะดิสก์) — null ถ้ายังไม่เคยโหลด
  static List<AppTransaction>? peekTransactionsFull() => _txFullMemory;

  static const Duration employeeTtl = Duration(minutes: 25);
  static const Duration dashboardSummaryTtl = Duration(minutes: 30);
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

  static Future<File?> _transactionsFullFile() async {
    if (kIsWeb) return null;
    if (_txFullFile != null) return _txFullFile;
    try {
      final dir = await getApplicationSupportDirectory();
      _txFullFile = File('${dir.path}/$_txFullFileName');
      return _txFullFile;
    } catch (e, st) {
      debugPrint('LocalDataCache._transactionsFullFile: $e\n$st');
      return null;
    }
  }

  static Future<void> _clearLegacyTxPrefsOnce() async {
    if (_legacyTxPrefsCleared) return;
    _legacyTxPrefsCleared = true;
    try {
      final p = await _p();
      if (p.containsKey(_kTxAllJson)) {
        await p.remove(_kTxAllJson);
      }
    } catch (_) {}
  }

  static Future<String?> _readTransactionsFullBlob() async {
    await _clearLegacyTxPrefsOnce();
    try {
      final file = await _transactionsFullFile();
      if (file == null || !await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      return raw;
    } catch (e, st) {
      debugPrint('LocalDataCache.readTransactionsFull file error: $e\n$st');
      return null;
    }
  }

  static Future<List<AppTransaction>?> _decodeTransactionsFullAsync(
    String? raw,
  ) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final maps = await compute(decodeTxPersistenceMaps, raw);
      if (maps.isEmpty) return null;
      return maps.map(AppTransaction.fromMap).toList();
    } catch (e, st) {
      debugPrint('LocalDataCache.readTransactionsFull error: $e\n$st');
      return null;
    }
  }

  static Future<List<AppTransaction>?> readTransactionsFull(Duration ttl) async {
    final p = await _p();
    if (!_withinTtl(ttl, p.getInt(_kTxAllAt))) return null;
    return readTransactionsFullAny();
  }

  /// อ่านธุรกรรมทั้งหมดแม้ TTL หมด — ใช้ตอนออฟไลน์
  static Future<List<AppTransaction>?> readTransactionsFullAny() async {
    final mem = _txFullMemory;
    if (mem != null) return mem;
    final existing = _txFullInFlight;
    if (existing != null) return existing;
    final future = () async {
      final raw = await _readTransactionsFullBlob();
      final decoded = await _decodeTransactionsFullAsync(raw);
      if (decoded != null) _txFullMemory = decoded;
      return decoded;
    }();
    _txFullInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_txFullInFlight, future)) _txFullInFlight = null;
    }
  }

  static Future<void> writeTransactionsFull(List<AppTransaction> list) async {
    final maps = list.map((e) => e.toPersistenceMap()).toList();
    final blob = await compute(encodeTxPersistenceMaps, maps);
    if (blob.length > maxTransactionsFullJsonChars) {
      debugPrint(
        'LocalDataCache.writeTransactionsFull skipped: ${blob.length} chars',
      );
      return;
    }
    await _clearLegacyTxPrefsOnce();
    try {
      final file = await _transactionsFullFile();
      if (file == null) return;
      await file.writeAsString(blob, flush: true);
      final p = await _p();
      await p.setInt(_kTxAllAt, DateTime.now().millisecondsSinceEpoch);
      _txFullMemory = List<AppTransaction>.from(list);
    } catch (e, st) {
      debugPrint('LocalDataCache.writeTransactionsFull error: $e\n$st');
    }
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
    _clearTxFullMemory();
    await _clearLegacyTxPrefsOnce();
    final p = await _p();
    await p.remove(_kTxAllAt);
    try {
      final file = await _transactionsFullFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
        'reserveAnchorYmd': kFuelReserveAnchorYmd,
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
      final anchor = decoded['reserveAnchorYmd'];
      if (anchor is String && anchor != kFuelReserveAnchorYmd) {
        return null;
      }
      if (anchor == null && kFuelReserveAnchorYmd.isNotEmpty) {
        return null;
      }
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
