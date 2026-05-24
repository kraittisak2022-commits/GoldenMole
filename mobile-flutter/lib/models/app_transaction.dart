class AppTransaction {
  const AppTransaction({
    required this.id,
    required this.date,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    this.subCategory,
    this.laborStatus,
    this.employeeIds = const [],
    this.note,
    this.eventTime,
    this.eventType,
    this.eventPriority,
    this.sandMorning,
    this.sandAfternoon,
    this.sandMachineType,
    this.sandOperators = const [],
    this.drumsObtained,
    this.drumsWashedAtHome,
    this.sandMorningStart,
    this.sandAfternoonStart,
    this.sandEveningEnd,
    this.vehicleId,
    this.driverId,
    this.driverWage,
    this.vehicleWage,
    this.workDetails,
    this.workType,
    this.workAssignments,
    this.customWorkCategories,
    this.quantity,
    this.unitPrice,
    this.unit,
    this.projectId,
    this.location,
    this.fuelType,
    this.fuelMovement,
    this.tripCount,
    this.tripMorning,
    this.tripAfternoon,
    this.cubicPerTrip,
    this.totalCubic,
    this.perCarTrips,
    this.perCarCubic,
    this.tripBillingMode,
    this.otAmount,
    this.otHours,
    this.otDescription,
    this.advanceAmount,
    this.leaveReason,
    this.leaveDays,
    this.incomePaymentStatus,
    this.createdAt,
  });

  final String id;
  final String date;
  final String type;
  final String category;
  final String description;
  final double amount;
  final String? subCategory;
  final String? laborStatus;
  final List<String> employeeIds;
  final String? note;
  final String? eventTime;
  /// ประเภทเหตุการณ์ (Daily Wizard) — info | warning | problem | success | complaint | request
  final String? eventType;
  /// ความสำคัญ — normal | urgent
  final String? eventPriority;
  final double? sandMorning;
  final double? sandAfternoon;
  final String? sandMachineType;
  final List<String> sandOperators;
  final double? drumsObtained;
  final double? drumsWashedAtHome;
  final String? sandMorningStart;
  final String? sandAfternoonStart;
  final String? sandEveningEnd;
  final String? vehicleId;
  final String? driverId;
  final double? driverWage;
  final double? vehicleWage;
  final String? workDetails;
  final String? workType;
  final Map<String, List<String>>? workAssignments;
  final List<Map<String, String>>? customWorkCategories;
  final double? quantity;
  final double? unitPrice;
  final String? unit;
  /// ชื่อคู่ค้า/ลูกค้า (รายรับ-รายจ่าย)
  final String? projectId;
  /// ที่อยู่ (รายรับ-รายจ่าย)
  final String? location;
  final String? fuelType;
  final String? fuelMovement;
  final double? tripCount;
  final double? tripMorning;
  final double? tripAfternoon;
  final double? cubicPerTrip;
  final double? totalCubic;
  final double? perCarTrips;
  final double? perCarCubic;
  /// DailyLog VehicleTrip: PerTrip | LumpSum
  final String? tripBillingMode;
  final double? otAmount;
  final double? otHours;
  final String? otDescription;
  final double? advanceAmount;
  final String? leaveReason;
  final double? leaveDays;
  /// รายรับ: Unpaid | Paid
  final String? incomePaymentStatus;

  /// จากคอลัมน์ created_at ของฐานข้อมูล (แสดงประวัติ / upsert ให้คงเวลาสร้าง)
  final DateTime? createdAt;

  factory AppTransaction.fromMap(Map<String, dynamic> row) {
    final amountRaw = row['amount'];
    final employeeIdsRaw = row['employee_ids'];
    final sandOperatorsRaw = row['sand_operators'];
    final employeeIds = <String>[
      if (employeeIdsRaw is List)
        ...employeeIdsRaw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
    ];
    if (employeeIds.isEmpty) {
      final legacyId = row['employee_id']?.toString().trim() ?? '';
      if (legacyId.isNotEmpty) employeeIds.add(legacyId);
    }
    return AppTransaction(
      id: (row['id'] ?? '').toString(),
      date: (row['date'] ?? '').toString(),
      type: (row['type'] ?? '').toString(),
      category: (row['category'] ?? '').toString(),
      description: (row['description'] ?? '').toString(),
      amount: amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse('$amountRaw') ?? 0,
      subCategory: row['sub_category']?.toString(),
      laborStatus: row['labor_status']?.toString(),
      employeeIds: employeeIds,
      note: row['note']?.toString(),
      eventTime: row['event_time']?.toString(),
      eventType: row['event_type']?.toString(),
      eventPriority: row['event_priority']?.toString(),
      sandMorning: _toDouble(row['sand_morning']),
      sandAfternoon: _toDouble(row['sand_afternoon']),
      sandMachineType: row['sand_machine_type']?.toString(),
      sandOperators: <String>[
        if (sandOperatorsRaw is List)
          ...sandOperatorsRaw
              .map((e) => '$e')
              .where((e) => e.trim().isNotEmpty),
      ],
      drumsObtained: _toDouble(row['drums_obtained']),
      drumsWashedAtHome: _toDouble(row['drums_washed_at_home']),
      sandMorningStart: row['sand_morning_start']?.toString(),
      sandAfternoonStart: row['sand_afternoon_start']?.toString(),
      sandEveningEnd: row['sand_evening_end']?.toString(),
      vehicleId: row['vehicle_id']?.toString(),
      driverId: row['driver_id']?.toString(),
      driverWage: _toDouble(row['driver_wage']),
      vehicleWage: _toDouble(row['vehicle_wage']),
      workDetails: row['work_details']?.toString(),
      workType: row['work_type']?.toString(),
      workAssignments: _toStringListMap(row['work_assignments']),
      customWorkCategories: _toStringMapList(row['custom_work_categories']),
      quantity: _toDouble(row['quantity']),
      unitPrice: _toDouble(row['unit_price']),
      unit: row['unit']?.toString(),
      projectId: row['project_id']?.toString(),
      location: row['location']?.toString(),
      fuelType: row['fuel_type']?.toString(),
      fuelMovement: row['fuel_movement']?.toString(),
      tripCount: _toDouble(row['trip_count']),
      tripMorning: _toDouble(row['trip_morning']),
      tripAfternoon: _toDouble(row['trip_afternoon']),
      cubicPerTrip: _toDouble(row['cubic_per_trip']),
      totalCubic: _toDouble(row['total_cubic']),
      perCarTrips: _toDouble(row['per_car_trips']),
      perCarCubic: _toDouble(row['per_car_cubic']),
      tripBillingMode: row['trip_billing_mode']?.toString(),
      otAmount: _toDouble(row['ot_amount']),
      otHours: _toDouble(row['ot_hours']),
      otDescription: row['ot_description']?.toString(),
      advanceAmount: _toDouble(row['advance_amount']),
      leaveReason: row['leave_reason']?.toString(),
      leaveDays: _toDouble(row['leave_days']),
      incomePaymentStatus: row['income_payment_status']?.toString(),
      createdAt: _parseDateTime(row['created_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// เก็บแคชเครื่องให้ครบฟิลด์ที่โหลดจาก Supabase
  Map<String, dynamic> toPersistenceMap() {
    return {
      'id': id,
      'date': date,
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
      if (subCategory != null && subCategory!.isNotEmpty)
        'sub_category': subCategory,
      if (laborStatus != null && laborStatus!.isNotEmpty)
        'labor_status': laborStatus,
      if (employeeIds.isNotEmpty) 'employee_ids': employeeIds,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (eventTime != null && eventTime!.isNotEmpty) 'event_time': eventTime,
      if (eventType != null && eventType!.isNotEmpty) 'event_type': eventType,
      if (eventPriority != null && eventPriority!.isNotEmpty)
        'event_priority': eventPriority,
      if (sandMorning != null) 'sand_morning': sandMorning,
      if (sandAfternoon != null) 'sand_afternoon': sandAfternoon,
      if (sandMachineType != null && sandMachineType!.isNotEmpty)
        'sand_machine_type': sandMachineType,
      if (sandOperators.isNotEmpty) 'sand_operators': sandOperators,
      if (drumsObtained != null) 'drums_obtained': drumsObtained,
      if (drumsWashedAtHome != null) 'drums_washed_at_home': drumsWashedAtHome,
      if (sandMorningStart != null && sandMorningStart!.isNotEmpty)
        'sand_morning_start': sandMorningStart,
      if (sandAfternoonStart != null && sandAfternoonStart!.isNotEmpty)
        'sand_afternoon_start': sandAfternoonStart,
      if (sandEveningEnd != null && sandEveningEnd!.isNotEmpty)
        'sand_evening_end': sandEveningEnd,
      if (vehicleId != null && vehicleId!.isNotEmpty) 'vehicle_id': vehicleId,
      if (driverId != null && driverId!.isNotEmpty) 'driver_id': driverId,
      if (driverWage != null) 'driver_wage': driverWage,
      if (vehicleWage != null) 'vehicle_wage': vehicleWage,
      if (workDetails != null)
        'work_details': workDetails!.isEmpty ? null : workDetails,
      if (workType != null && workType!.isNotEmpty) 'work_type': workType,
      if (workAssignments != null && workAssignments!.isNotEmpty)
        'work_assignments': workAssignments,
      if (customWorkCategories != null && customWorkCategories!.isNotEmpty)
        'custom_work_categories': customWorkCategories,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (unit != null && unit!.isNotEmpty) 'unit': unit,
      if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (fuelType != null && fuelType!.isNotEmpty) 'fuel_type': fuelType,
      if (fuelMovement != null && fuelMovement!.isNotEmpty)
        'fuel_movement': fuelMovement,
      if (tripCount != null) 'trip_count': tripCount,
      if (tripMorning != null) 'trip_morning': tripMorning,
      if (tripAfternoon != null) 'trip_afternoon': tripAfternoon,
      if (cubicPerTrip != null) 'cubic_per_trip': cubicPerTrip,
      if (totalCubic != null) 'total_cubic': totalCubic,
      if (perCarTrips != null) 'per_car_trips': perCarTrips,
      if (perCarCubic != null) 'per_car_cubic': perCarCubic,
      if (tripBillingMode != null && tripBillingMode!.isNotEmpty)
        'trip_billing_mode': tripBillingMode,
      if (otAmount != null) 'ot_amount': otAmount,
      if (otHours != null) 'ot_hours': otHours,
      if (otDescription != null && otDescription!.isNotEmpty)
        'ot_description': otDescription,
      if (advanceAmount != null) 'advance_amount': advanceAmount,
      if (leaveReason != null && leaveReason!.isNotEmpty)
        'leave_reason': leaveReason,
      if (leaveDays != null) 'leave_days': leaveDays,
      if (incomePaymentStatus != null && incomePaymentStatus!.isNotEmpty)
        'income_payment_status': incomePaymentStatus,
      if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap({bool omitCreatedAt = false}) {
    return {
      'id': id,
      'date': date,
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
      if (subCategory != null && subCategory!.isNotEmpty)
        'sub_category': subCategory,
      if (laborStatus != null && laborStatus!.isNotEmpty)
        'labor_status': laborStatus,
      if (employeeIds.isNotEmpty) 'employee_ids': employeeIds,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (eventTime != null && eventTime!.isNotEmpty) 'event_time': eventTime,
      if (eventType != null && eventType!.isNotEmpty) 'event_type': eventType,
      if (eventPriority != null && eventPriority!.isNotEmpty)
        'event_priority': eventPriority,
      if (sandMorning != null) 'sand_morning': sandMorning,
      if (sandAfternoon != null) 'sand_afternoon': sandAfternoon,
      if (sandMachineType != null && sandMachineType!.isNotEmpty)
        'sand_machine_type': sandMachineType,
      if (sandOperators.isNotEmpty) 'sand_operators': sandOperators,
      if (drumsObtained != null) 'drums_obtained': drumsObtained,
      if (drumsWashedAtHome != null) 'drums_washed_at_home': drumsWashedAtHome,
      if (sandMorningStart != null && sandMorningStart!.isNotEmpty)
        'sand_morning_start': sandMorningStart,
      if (sandAfternoonStart != null && sandAfternoonStart!.isNotEmpty)
        'sand_afternoon_start': sandAfternoonStart,
      if (sandEveningEnd != null && sandEveningEnd!.isNotEmpty)
        'sand_evening_end': sandEveningEnd,
      if (vehicleId != null && vehicleId!.isNotEmpty) 'vehicle_id': vehicleId,
      if (driverId != null && driverId!.isNotEmpty) 'driver_id': driverId,
      if (driverWage != null) 'driver_wage': driverWage,
      if (vehicleWage != null) 'vehicle_wage': vehicleWage,
      if (workDetails != null)
        'work_details': workDetails!.isEmpty ? null : workDetails,
      if (workType != null && workType!.isNotEmpty) 'work_type': workType,
      if (workAssignments != null && workAssignments!.isNotEmpty)
        'work_assignments': workAssignments,
      if (customWorkCategories != null && customWorkCategories!.isNotEmpty)
        'custom_work_categories': customWorkCategories,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (unit != null && unit!.isNotEmpty) 'unit': unit,
      if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (fuelType != null && fuelType!.isNotEmpty) 'fuel_type': fuelType,
      if (fuelMovement != null && fuelMovement!.isNotEmpty)
        'fuel_movement': fuelMovement,
      if (tripCount != null) 'trip_count': tripCount,
      if (tripMorning != null) 'trip_morning': tripMorning,
      if (tripAfternoon != null) 'trip_afternoon': tripAfternoon,
      if (cubicPerTrip != null) 'cubic_per_trip': cubicPerTrip,
      if (totalCubic != null) 'total_cubic': totalCubic,
      if (perCarTrips != null) 'per_car_trips': perCarTrips,
      if (perCarCubic != null) 'per_car_cubic': perCarCubic,
      if (tripBillingMode != null && tripBillingMode!.isNotEmpty)
        'trip_billing_mode': tripBillingMode,
      if (otAmount != null) 'ot_amount': otAmount,
      if (otHours != null) 'ot_hours': otHours,
      if (otDescription != null && otDescription!.isNotEmpty)
        'ot_description': otDescription,
      if (advanceAmount != null) 'advance_amount': advanceAmount,
      if (leaveReason != null && leaveReason!.isNotEmpty)
        'leave_reason': leaveReason,
      if (leaveDays != null) 'leave_days': leaveDays,
      if (incomePaymentStatus != null && incomePaymentStatus!.isNotEmpty)
        'income_payment_status': incomePaymentStatus,
      if (!omitCreatedAt)
        'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  AppTransaction copyWith({
    String? id,
    String? date,
    String? type,
    String? category,
    String? description,
    double? amount,
    String? subCategory,
    String? laborStatus,
    List<String>? employeeIds,
    String? note,
    String? eventTime,
    String? eventType,
    String? eventPriority,
    double? sandMorning,
    double? sandAfternoon,
    String? sandMachineType,
    List<String>? sandOperators,
    double? drumsObtained,
    double? drumsWashedAtHome,
    String? sandMorningStart,
    String? sandAfternoonStart,
    String? sandEveningEnd,
    String? vehicleId,
    String? driverId,
    double? driverWage,
    double? vehicleWage,
    String? workDetails,
    String? workType,
    Map<String, List<String>>? workAssignments,
    List<Map<String, String>>? customWorkCategories,
    double? quantity,
    double? unitPrice,
    String? unit,
    String? projectId,
    String? location,
    String? fuelType,
    String? fuelMovement,
    double? tripCount,
    double? tripMorning,
    double? tripAfternoon,
    double? cubicPerTrip,
    double? totalCubic,
    double? perCarTrips,
    double? perCarCubic,
    String? tripBillingMode,
    double? otAmount,
    double? otHours,
    String? otDescription,
    double? advanceAmount,
    String? leaveReason,
    double? leaveDays,
    String? incomePaymentStatus,
    DateTime? createdAt,
  }) {
    return AppTransaction(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      subCategory: subCategory ?? this.subCategory,
      laborStatus: laborStatus ?? this.laborStatus,
      employeeIds: employeeIds ?? List<String>.from(this.employeeIds),
      note: note ?? this.note,
      eventTime: eventTime ?? this.eventTime,
      eventType: eventType ?? this.eventType,
      eventPriority: eventPriority ?? this.eventPriority,
      sandMorning: sandMorning ?? this.sandMorning,
      sandAfternoon: sandAfternoon ?? this.sandAfternoon,
      sandMachineType: sandMachineType ?? this.sandMachineType,
      sandOperators: sandOperators ?? List<String>.from(this.sandOperators),
      drumsObtained: drumsObtained ?? this.drumsObtained,
      drumsWashedAtHome: drumsWashedAtHome ?? this.drumsWashedAtHome,
      sandMorningStart: sandMorningStart ?? this.sandMorningStart,
      sandAfternoonStart: sandAfternoonStart ?? this.sandAfternoonStart,
      sandEveningEnd: sandEveningEnd ?? this.sandEveningEnd,
      vehicleId: vehicleId ?? this.vehicleId,
      driverId: driverId ?? this.driverId,
      driverWage: driverWage ?? this.driverWage,
      vehicleWage: vehicleWage ?? this.vehicleWage,
      workDetails: workDetails ?? this.workDetails,
      workType: workType ?? this.workType,
      workAssignments: workAssignments ?? this.workAssignments,
      customWorkCategories: customWorkCategories ?? this.customWorkCategories,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      unit: unit ?? this.unit,
      projectId: projectId ?? this.projectId,
      location: location ?? this.location,
      fuelType: fuelType ?? this.fuelType,
      fuelMovement: fuelMovement ?? this.fuelMovement,
      tripCount: tripCount ?? this.tripCount,
      tripMorning: tripMorning ?? this.tripMorning,
      tripAfternoon: tripAfternoon ?? this.tripAfternoon,
      cubicPerTrip: cubicPerTrip ?? this.cubicPerTrip,
      totalCubic: totalCubic ?? this.totalCubic,
      perCarTrips: perCarTrips ?? this.perCarTrips,
      perCarCubic: perCarCubic ?? this.perCarCubic,
      tripBillingMode: tripBillingMode ?? this.tripBillingMode,
      otAmount: otAmount ?? this.otAmount,
      otHours: otHours ?? this.otHours,
      otDescription: otDescription ?? this.otDescription,
      advanceAmount: advanceAmount ?? this.advanceAmount,
      leaveReason: leaveReason ?? this.leaveReason,
      leaveDays: leaveDays ?? this.leaveDays,
      incomePaymentStatus: incomePaymentStatus ?? this.incomePaymentStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static Map<String, List<String>>? _toStringListMap(dynamic raw) {
    if (raw is! Map) return null;
    final out = <String, List<String>>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      if (key.isEmpty) continue;
      final v = entry.value;
      if (v is! List) continue;
      final items = v
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (items.isNotEmpty) out[key] = items;
    }
    return out.isEmpty ? null : out;
  }

  static List<Map<String, String>>? _toStringMapList(dynamic raw) {
    if (raw is! List) return null;
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = '${item['id'] ?? ''}'.trim();
      final label = '${item['label'] ?? ''}'.trim();
      if (id.isEmpty || label.isEmpty) continue;
      out.add({'id': id, 'label': label});
    }
    return out.isEmpty ? null : out;
  }
}
