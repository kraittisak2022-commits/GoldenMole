import 'dart:math' as math;

import 'pricing.dart';

class DeliverySettings {
  const DeliverySettings({required this.nearKm, required this.maxKm, required this.roundTo, this.extra = const {}});
  final num nearKm;
  final num maxKm;
  final num roundTo;

  /// Keys the web app also stores (baht/km by truck size); kept so saving here does not drop them.
  final Map<String, dynamic> extra;

  static const defaults = DeliverySettings(nearKm: 3, maxKm: 10, roundTo: 50);

  factory DeliverySettings.fromJson(Map<String, dynamic>? j) => DeliverySettings(
        nearKm: (j?['nearKm'] as num?) ?? defaults.nearKm,
        maxKm: (j?['maxKm'] as num?) ?? defaults.maxKm,
        roundTo: (j?['roundTo'] as num?) ?? defaults.roundTo,
        extra: {...?j}..removeWhere((k, _) => k == 'nearKm' || k == 'maxKm' || k == 'roundTo'),
      );

  DeliverySettings copyWith({num? nearKm, num? maxKm, num? roundTo}) => DeliverySettings(
        nearKm: nearKm ?? this.nearKm,
        maxKm: maxKm ?? this.maxKm,
        roundTo: roundTo ?? this.roundTo,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {...extra, 'nearKm': nearKm, 'maxKm': maxKm, 'roundTo': roundTo};
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
  final extra = ((feeMax - feeMin) * (distanceKm - nearKm)) / (maxKm - nearKm);
  final rounded = roundTo > 0 ? (extra / roundTo).ceil() * roundTo : jsRound(extra);
  return math.min(feeMax, feeMin + rounded);
}
