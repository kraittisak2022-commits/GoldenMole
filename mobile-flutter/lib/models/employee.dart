class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.nickname,
    required this.type,
    this.baseWage,
    this.phone,
    this.startDate,
    this.position,
    this.inactive = false,
  });

  final String id;
  final String name;
  final String nickname;
  final String type;
  final double? baseWage;
  final String? phone;
  final String? startDate;
  final String? position;
  final bool inactive;

  factory Employee.fromMap(Map<String, dynamic> row) {
    final baseWageRaw = row['base_wage'];
    return Employee(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      nickname: (row['nickname'] ?? '').toString(),
      type: (row['type'] ?? 'Daily').toString(),
      baseWage: baseWageRaw is num ? baseWageRaw.toDouble() : double.tryParse('$baseWageRaw'),
      phone: row['phone']?.toString(),
      startDate: row['start_date']?.toString(),
      position: row['position']?.toString(),
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
      'start_date': startDate,
      'position': position,
      'inactive': inactive,
    };
  }
}
