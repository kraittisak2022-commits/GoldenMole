import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';

class EmployeeService {
  EmployeeService(this._client);

  final SupabaseClient _client;

  Future<List<Employee>> fetchEmployees() async {
    final rows = await _client.from('employees').select().order('created_at');
    return rows.map(Employee.fromMap).toList();
  }

  Future<void> upsertEmployee(Employee employee) async {
    await _client.from('employees').upsert(employee.toInsertMap(), onConflict: 'id');
  }

  Future<void> deleteEmployee(String id) async {
    await _client.from('employees').delete().eq('id', id);
  }
}
