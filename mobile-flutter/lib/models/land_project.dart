class LandProject {
  const LandProject({
    required this.id,
    required this.name,
    required this.status,
    this.fullPrice,
  });

  final String id;
  final String name;
  final String status;
  final double? fullPrice;

  factory LandProject.fromMap(Map<String, dynamic> row) {
    final priceRaw = row['full_price'];
    return LandProject(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      fullPrice: priceRaw is num ? priceRaw.toDouble() : double.tryParse('$priceRaw'),
    );
  }
}
