import 'dart:math' as math;

/// One product ordered as [trips] deliveries of [perTrip] คิว each.
class Load {
  const Load({required this.perTrip, required this.trips});
  final num perTrip;
  final num trips;

  bool get isActive => perTrip > 0 && trips > 0;
}

num _largestPerTrip(List<Load> loads) =>
    loads.where((l) => l.isActive).fold<num>(0, (m, l) => math.max(m, l.perTrip));

/// Truck sizes are 3 or 5 คิว.
int suggestTruckSize(num totalQuantity) => totalQuantity > 0 && totalQuantity <= 3 ? 3 : 5;

int truckForLoads(List<Load> loads) => suggestTruckSize(_largestPerTrip(loads));

bool truckFits(int size, List<Load> loads) => size >= _largestPerTrip(loads);

int totalTrips(List<Load> loads) =>
    loads.where((l) => l.isActive).fold<int>(0, (s, l) => s + l.trips.floor());
