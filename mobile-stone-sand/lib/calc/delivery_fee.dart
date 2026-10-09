class DeliverySettings {
  const DeliverySettings({
    required this.nearKm,
    required this.driverPerKm5,
    required this.driverPerKm3,
    this.extra = const {},
  });

  /// Distance from the main road with no surcharge.
  final num nearKm;

  /// Baht per started km beyond nearKm, per trip, by truck size (5 คิว is also used when the size is unknown).
  /// Charged to the customer and paid to the driver alike.
  final num driverPerKm5;
  final num driverPerKm3;

  /// Other keys stored with the setting; kept so saving here does not drop them.
  final Map<String, dynamic> extra;

  static const defaults = DeliverySettings(nearKm: 1, driverPerKm5: 0, driverPerKm3: 0);

  static const _known = {'nearKm', 'driverPerKm5', 'driverPerKm3', 'maxKm', 'roundTo'};

  factory DeliverySettings.fromJson(Map<String, dynamic>? j) => DeliverySettings(
        nearKm: (j?['nearKm'] as num?) ?? defaults.nearKm,
        driverPerKm5: (j?['driverPerKm5'] as num?) ?? defaults.driverPerKm5,
        driverPerKm3: (j?['driverPerKm3'] as num?) ?? defaults.driverPerKm3,
        extra: {...?j}..removeWhere((k, _) => _known.contains(k)),
      );

  DeliverySettings copyWith({num? nearKm, num? driverPerKm5, num? driverPerKm3}) => DeliverySettings(
        nearKm: nearKm ?? this.nearKm,
        driverPerKm5: driverPerKm5 ?? this.driverPerKm5,
        driverPerKm3: driverPerKm3 ?? this.driverPerKm3,
        extra: extra,
      );

  Map<String, dynamic> toJson() =>
      {...extra, 'nearKm': nearKm, 'driverPerKm5': driverPerKm5, 'driverPerKm3': driverPerKm3};
}

/// Baht per km for the truck size; trucks of unknown size use the normal 5-คิว rate.
num perKmFor(int? truckSize, DeliverySettings settings) =>
    truckSize == 3 ? settings.driverPerKm3 : settings.driverPerKm5;

/// Whole km beyond nearKm, any part of a km counting as a full km (1.4 km past → 2 km).
int chargedKm(num? distanceKm, num nearKm) {
  if (distanceKm == null || !distanceKm.isFinite || distanceKm <= nearKm) return 0;
  // Rounded to metres first so 2.0 − 1 stays 1 km despite floating-point error
  return (((distanceKm - nearKm) * 1000).round() / 1000).ceil();
}

/// Per-trip surcharge: the baht/km for each started km beyond nearKm; 0 without a distance.
num distanceSurcharge(num? distanceKm, {required num nearKm, required num perKm}) =>
    perKm <= 0 ? 0 : chargedKm(distanceKm, nearKm) * perKm;

/// Suggested delivery fee per trip: the tambon fee, plus the truck size's baht/km for every started km
/// beyond nearKm between the main road and the pin.
num suggestDeliveryFee(
  num feeMin,
  num? distanceKm,
  int? truckSize, [
  DeliverySettings settings = DeliverySettings.defaults,
]) =>
    feeMin + distanceSurcharge(distanceKm, nearKm: settings.nearKm, perKm: perKmFor(truckSize, settings));
