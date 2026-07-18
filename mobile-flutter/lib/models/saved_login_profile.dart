/// โปรไฟล์ล็อกอินที่บันทึกไว้ (metadata เท่านั้น — รหัสผ่านอยู่ secure storage)
class SavedLoginProfile {
  const SavedLoginProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.lastUsedAt,
  });

  final String id;
  final String username;
  final String displayName;
  final DateTime lastUsedAt;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) {
      final u = username.trim();
      return u.isEmpty ? '?' : u.substring(0, 1).toUpperCase();
    }
    return parts.map((p) => p.substring(0, 1).toUpperCase()).join();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory SavedLoginProfile.fromJson(Map<String, dynamic> json) {
    final rawDate = json['lastUsedAt']?.toString();
    return SavedLoginProfile(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['username'] ?? '').toString(),
      lastUsedAt: DateTime.tryParse(rawDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  SavedLoginProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    DateTime? lastUsedAt,
  }) {
    return SavedLoginProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}
