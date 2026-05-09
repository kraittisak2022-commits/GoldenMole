class DashboardSummary {
  const DashboardSummary({
    required this.employeeCount,
    required this.transactionCount,
    required this.projectCount,
    required this.totalRevenue,
    required this.totalExpense,
    required this.appName,
  });

  final int employeeCount;
  final int transactionCount;
  final int projectCount;
  final double totalRevenue;
  final double totalExpense;
  final String appName;

  factory DashboardSummary.fromPersistenceMap(Map<String, dynamic> m) {
    return DashboardSummary(
      employeeCount: (m['employeeCount'] as num?)?.toInt() ?? 0,
      transactionCount: (m['transactionCount'] as num?)?.toInt() ?? 0,
      projectCount: (m['projectCount'] as num?)?.toInt() ?? 0,
      totalRevenue: (m['totalRevenue'] as num?)?.toDouble() ?? 0,
      totalExpense: (m['totalExpense'] as num?)?.toDouble() ?? 0,
      appName: (m['appName'] ?? 'Construction Management').toString(),
    );
  }

  Map<String, dynamic> toPersistenceMap() {
    return {
      'employeeCount': employeeCount,
      'transactionCount': transactionCount,
      'projectCount': projectCount,
      'totalRevenue': totalRevenue,
      'totalExpense': totalExpense,
      'appName': appName,
    };
  }
}
