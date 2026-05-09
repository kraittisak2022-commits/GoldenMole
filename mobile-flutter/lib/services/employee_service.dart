import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import 'local_data_cache.dart';

class EmployeeService {
  EmployeeService(this._client);

  final SupabaseClient _client;

  Future<List<Employee>> fetchEmployees({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await LocalDataCache.readEmployees(LocalDataCache.employeeTtl);
      if (cached != null) return cached;
    }

    final rows =
        await _client.from('employees').select().order('created_at');
    final list = rows.map(Employee.fromMap).toList();
    await LocalDataCache.writeEmployees(list);
    return list;
  }

  Future<void> upsertEmployee(Employee employee) async {
    await _client.from('employees').upsert(employee.toInsertMap(), onConflict: 'id');
    await LocalDataCache.invalidateEmployees();
    await LocalDataCache.invalidateDashboard();
  }

  Future<void> deleteEmployee(String id) async {
    await _client.from('employees').delete().eq('id', id);
    await LocalDataCache.invalidateEmployees();
    await LocalDataCache.invalidateDashboard();
  }
}
