import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/land_project.dart';

class ProjectService {
  ProjectService(this._client);

  final SupabaseClient _client;

  Future<List<LandProject>> fetchProjects() async {
    final rows = await _client.from('land_projects').select().order('created_at', ascending: false);
    return rows.map(LandProject.fromMap).toList();
  }
}
