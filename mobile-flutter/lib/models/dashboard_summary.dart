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
}
