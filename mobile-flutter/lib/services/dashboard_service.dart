import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_summary.dart';
import 'local_data_cache.dart';

class DashboardService {
  DashboardService(this._client);

  final SupabaseClient _client;

  Future<int> _countRows(String tableName) async {
    final response = await _client.from(tableName).select('id');
    return response.length;
  }

  Future<double> _sumTransactionsByType(String type) async {
    final rows = await _client.from('transactions').select('type,amount');
    double sum = 0;
    for (final row in rows) {
      final txType = (row['type'] ?? '').toString().toLowerCase();
      if (txType != type.toLowerCase()) continue;
      final amountRaw = row['amount'];
      final value = amountRaw is num ? amountRaw.toDouble() : double.tryParse('$amountRaw') ?? 0;
      sum += value;
    }
    return sum;
  }

  Future<DashboardSummary> fetchSummary({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached =
          await LocalDataCache.readDashboard(LocalDataCache.dashboardSummaryTtl);
      if (cached != null) return cached;
    }

    final employeeCount = await _countRows('employees');
    final transactionCount = await _countRows('transactions');
    final projectCount = await _countRows('land_projects');
    final totalRevenue = await _sumTransactionsByType('income');
    final totalExpense = await _sumTransactionsByType('expense');

    String appName = 'Construction Management';
    final settingsRows = await _client.from('app_settings').select('app_name').eq('id', 'default').limit(1);
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
  }
}
