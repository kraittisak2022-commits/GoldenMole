import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_summary.dart';
import 'local_data_cache.dart';

class DashboardService {
  DashboardService(this._client);

  final SupabaseClient _client;

  // #region agent log
  static Future<void> _agentLog({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
  }) async {
    final payload = <String, Object?>{
      'sessionId': 'b281b7',
      'runId': 'pre-fix',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    debugPrint('DBG_TX500 ${jsonEncode(payload)}');
    try {
      final client = HttpClient();
      final req = await client
          .postUrl(
            Uri.parse(
              'http://127.0.0.1:7534/ingest/8bc82002-6da6-4937-be9c-d7a33a726939',
            ),
          )
          .timeout(const Duration(milliseconds: 800));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('X-Debug-Session-Id', 'b281b7');
      req.add(utf8.encode(jsonEncode(payload)));
      await req.close().timeout(const Duration(milliseconds: 800));
      client.close(force: true);
    } catch (_) {}
  }
  // #endregion

  Future<int> _countRows(String tableName) async {
    try {
      final n = await _client.from(tableName).count(CountOption.exact);
      // #region agent log
      if (tableName == 'transactions') {
        unawaited(
          _agentLog(
            hypothesisId: 'C',
            location: 'dashboard_service.dart:count',
            message: 'transactions HEAD count ok',
            data: {'count': n},
          ),
        );
      }
      // #endregion
      return n;
    } catch (e) {
      // #region agent log
      if (tableName == 'transactions') {
        unawaited(
          _agentLog(
            hypothesisId: 'C',
            location: 'dashboard_service.dart:count',
            message: 'transactions HEAD count failed',
            data: {
              'type': e.runtimeType.toString(),
              'message': '$e',
              if (e is PostgrestException) ...{
                'code': e.code,
                'pgMessage': e.message,
                'details': '${e.details}',
                'hint': '${e.hint}',
              },
            },
          ),
        );
      }
      // #endregion
      rethrow;
    }
  }

  Future<double> _sumTransactionsByType(String type) async {
    try {
      final raw = await _client.rpc(
        'sum_transactions_amount_by_type',
        params: {'p_type': type},
      );
      if (raw is num) return raw.toDouble();
      return double.tryParse('$raw') ?? 0;
    } catch (_) {
      try {
        final rows = await _client
            .from('transactions')
            .select('amount.sum()')
            .eq('type', type);
        if (rows.isEmpty) return 0;
        final first = rows.first;
        final nested = first['amount'];
        final raw = first['sum'] ??
            (nested is Map ? nested['sum'] : nested) ??
            first['amount'];
        if (raw is num) return raw.toDouble();
        return double.tryParse('$raw') ?? 0;
      } catch (_) {
        final rows = await _client
            .from('transactions')
            .select('amount')
            .eq('type', type);
        var sum = 0.0;
        for (final row in rows) {
          final amountRaw = row['amount'];
          final value = amountRaw is num
              ? amountRaw.toDouble()
              : double.tryParse('$amountRaw') ?? 0;
          sum += value;
        }
        return sum;
      }
    }
  }

  Future<DashboardSummary> fetchSummary({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached =
          await LocalDataCache.readDashboard(LocalDataCache.dashboardSummaryTtl);
      if (cached != null) return cached;
    }

    try {
      final counts = await Future.wait([
        _countRows('employees'),
        _countRows('transactions'),
        _countRows('land_projects'),
        _sumTransactionsByType('Income'),
        _sumTransactionsByType('Expense'),
      ]);
      final employeeCount = counts[0] as int;
      final transactionCount = counts[1] as int;
      final projectCount = counts[2] as int;
      final totalRevenue = counts[3] as double;
      final totalExpense = counts[4] as double;

      var appName = 'Construction Management';
      final settingsRows = await _client
          .from('app_settings')
          .select('app_name')
          .eq('id', 'default')
          .limit(1);
      if (settingsRows.isNotEmpty) {
        final rawName = settingsRows.first['app_name'];
        if (rawName != null && rawName.toString().trim().isNotEmpty) {
          appName = rawName.toString();
        }
      }

      final summary = DashboardSummary(
        employeeCount: employeeCount,
        transactionCount: transactionCount,
        projectCount: projectCount,
        totalRevenue: totalRevenue,
        totalExpense: totalExpense,
        appName: appName,
      );
      await LocalDataCache.writeDashboard(summary);
      return summary;
    } catch (_) {
      final stale = await LocalDataCache.readDashboardAny();
      if (stale != null) return stale;
      rethrow;
    }
  }
}
