class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.password,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String username;
  final String password;
  final String displayName;
  final String role;

  factory AdminUser.fromMap(Map<String, dynamic> row) {
    return AdminUser(
      id: (row['id'] ?? '').toString(),
      username: (row['username'] ?? row['user_name'] ?? '').toString(),
      password: (row['password'] ?? '').toString(),
      displayName: (row['display_name'] ?? row['displayName'] ?? '').toString(),
      role: (row['role'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toSessionMap() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'role': role,
    };
  }

  factory AdminUser.fromSessionMap(Map<String, dynamic> row) {
    return AdminUser(
      id: (row['id'] ?? '').toString(),
      username: (row['username'] ?? '').toString(),
      password: '',
      displayName: (row['displayName'] ?? '').toString(),
      role: (row['role'] ?? '').toString(),
    );
  }
}
