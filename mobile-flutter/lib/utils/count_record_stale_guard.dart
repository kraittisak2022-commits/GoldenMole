import '../models/app_transaction.dart';

/// Detects stale count-record payloads that would overwrite a newer higher total.
class CountRecordStaleGuard {
  CountRecordStaleGuard._();

  /// Reject when incoming has meaningfully fewer laps that end earlier than existing.
  /// Allows small intentional undo/edit steps (drop < 5).
  static bool isStaleOverwrite({
    required List<String> incomingLaps,
    required int incomingRounds,
    required List<String> existingLaps,
    required int existingRounds,
  }) {
    final inRounds = incomingRounds > incomingLaps.length
        ? incomingRounds
        : incomingLaps.length;
    final exRounds = existingRounds > existingLaps.length
        ? existingRounds
        : existingLaps.length;
    final drop = exRounds - inRounds;
    if (drop < 5) return false;

    final inLast = incomingLaps.isEmpty ? '' : incomingLaps.last;
    final exLast = existingLaps.isEmpty ? '' : existingLaps.last;
    if (exLast.isEmpty) return false;
    if (inLast.isEmpty) return true;
    return inLast.compareTo(exLast) < 0;
  }

  static List<String> _lapsOf(AppTransaction? tx) {
    if (tx == null) return const [];
    final wa = tx.workAssignments;
    if (wa == null) return const [];
    return List<String>.from(wa['lapTimes'] ?? const []);
  }

  static bool isStaleSandOverwrite({
    required AppTransaction incoming,
    required AppTransaction? existing,
  }) {
    if (existing == null) return false;
    final sub = (incoming.subCategory ?? '').trim().toLowerCase();
    final isSand =
        sub == 'sand' || incoming.description.trim().startsWith('ร่อนทราย:');
    if (!isSand) return false;
    final inLaps = _lapsOf(incoming);
    final exLaps = _lapsOf(existing);
    final inRounds = inLaps.isNotEmpty
        ? inLaps.length
        : (incoming.drumsObtained ?? 0).round();
    final exRounds = exLaps.isNotEmpty
        ? exLaps.length
        : (existing.drumsObtained ?? 0).round();
    return isStaleOverwrite(
      incomingLaps: inLaps,
      incomingRounds: inRounds,
      existingLaps: exLaps,
      existingRounds: exRounds,
    );
  }

  static bool isStaleTripOverwrite({
    required AppTransaction incoming,
    required AppTransaction? existing,
  }) {
    if (existing == null) return false;
    final sub = (incoming.subCategory ?? '').trim().toLowerCase();
    if (sub == 'sand' || sub == 'event') return false;
    final isTrip = sub == 'vehicletrip' ||
        (incoming.vehicleId ?? '').trim().isNotEmpty;
    if (!isTrip) return false;
    final inLaps = _lapsOf(incoming);
    final exLaps = _lapsOf(existing);
    var inRounds = (incoming.perCarTrips ?? incoming.tripCount ?? 0).round();
    if (inLaps.length > inRounds) inRounds = inLaps.length;
    var exRounds = (existing.perCarTrips ?? existing.tripCount ?? 0).round();
    if (exLaps.length > exRounds) exRounds = exLaps.length;
    return isStaleOverwrite(
      incomingLaps: inLaps,
      incomingRounds: inRounds,
      existingLaps: exLaps,
      existingRounds: exRounds,
    );
  }

  static bool isStaleCountRecordOverwrite({
    required AppTransaction incoming,
    required AppTransaction? existing,
  }) {
    return isStaleSandOverwrite(incoming: incoming, existing: existing) ||
        isStaleTripOverwrite(incoming: incoming, existing: existing);
  }
}
