import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_summary.dart';
import 'local_data_cache.dart';

class DashboardService {
  DashboardService(this._client);

  final SupabaseClient _client;

  Future<int> _countRows(String tableName) async {
    return _client.from(tableName).count(CountOption.exact);
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
