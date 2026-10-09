import 'dart:math' as math;

import 'pricing.dart';

class DeliverySettings {
  const DeliverySettings({required this.nearKm, required this.maxKm, required this.roundTo});
  final num nearKm;
  final num maxKm;
  final num roundTo;

  static const defaults = DeliverySettings(nearKm: 3, maxKm: 10, roundTo: 50);

  factory DeliverySettings.fromJson(Map<String, dynamic>? j) => DeliverySettings(
        nearKm: (j?['nearKm'] as num?) ?? defaults.nearKm,
        maxKm: (j?['maxKm'] as num?) ?? defaults.maxKm,
        roundTo: (j?['roundTo'] as num?) ?? defaults.roundTo,
      );

  Map<String, dynamic> toJson() => {'nearKm': nearKm, 'maxKm': maxKm, 'roundTo': roundTo};
}

/// Suggested delivery fee per trip for a tambon fee range, from the straight-line distance
/// between the pin and the nearest main road.
num suggestDeliveryFee(
  num feeMin,
  num feeMax,
  num? distanceKm, [
  DeliverySettings settings = DeliverySettings.defaults,
]) {
  final nearKm = settings.nearKm;
  final maxKm = settings.maxKm;
  final roundTo = settings.roundTo;
  if (distanceKm == null || !distanceKm.isFinite || distanceKm <= nearKm) return feeMin;
  if (distanceKm >= maxKm || maxKm <= nearKm) return feeMax;
  final raw = feeMin + ((feeMax - feeMin) * (distanceKm - nearKm)) / (maxKm - nearKm);
  final rounded = roundTo > 0 ? (raw / roundTo).ceil() * roundTo : jsRound(raw);
  return math.min(feeMax, math.max(feeMin, rounded));
}
