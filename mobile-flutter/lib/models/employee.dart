class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.nickname,
    required this.type,
    this.baseWage,
    this.phone,
    this.lineUserId,
    this.startDate,
    this.position,
    this.positions = const [],
    this.inactive = false,
  });

  final String id;
  final String name;
  final String nickname;
  final String type;
  final double? baseWage;
  final String? phone;
  /// LINE User ID สำหรับแจ้งเตือนเบิกเงิน (Messaging API)
  final String? lineUserId;
  final String? startDate;
  final String? position;
  final List<String> positions;
  final bool inactive;

  factory Employee.fromMap(Map<String, dynamic> row) {
    final baseWageRaw = row['base_wage'];
    final positionsRaw = row['positions'];
    return Employee(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      nickname: (row['nickname'] ?? '').toString(),
      type: (row['type'] ?? 'Daily').toString(),
      baseWage: baseWageRaw is num ? baseWageRaw.toDouble() : double.tryParse('$baseWageRaw'),
      phone: row['phone']?.toString(),
      lineUserId: row['line_user_id']?.toString(),
      startDate: row['start_date']?.toString(),
      position: row['position']?.toString(),
      positions: <String>[
        if (positionsRaw is List)
          ...positionsRaw
              .map((e) => '$e')
              .where((e) => e.trim().isNotEmpty),
      ],
      inactive: row['inactive'] == true,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'name': name,
      'nickname': nickname,
      'type': type,
      'base_wage': baseWage,
      'phone': phone,
      'line_user_id': (lineUserId == null || lineUserId!.trim().isEmpty)
          ? null
          : lineUserId!.trim(),
      'start_date': startDate,
      'position': position,
      if (positions.isNotEmpty) 'positions': positions,
      'inactive': inactive,
    };
  }

  /// เก็บลงแคชเครื่องให้ครบเหมือนแถวที่ `fromMap` อ่านได้
  Map<String, dynamic> toPersistenceMap() {
    return {
      'id': id,
      'name': name,
      'nickname': nickname,
      'type': type,
      if (baseWage != null) 'base_wage': baseWage,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      if (lineUserId != null && lineUserId!.trim().isNotEmpty)
        'line_user_id': lineUserId!.trim(),
      if (startDate != null && startDate!.isNotEmpty)
        'start_date': startDate,
      if (position != null && position!.isNotEmpty) 'position': position,
      if (positions.isNotEmpty) 'positions': positions,
      'inactive': inactive,
    };
  }
}
