class LatLngValue {
  const LatLngValue(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is LatLngValue && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLngValue($lat, $lng)';
}

bool _valid(double lat, double lng) => lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

final _d34 = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)');
final _patterns = [
  RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
  RegExp(r'[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
  RegExp(r'^(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)$'),
];

/// Reads "19.15, 99.62", Google Maps URLs (…/@19.15,99.62,15z, ?q=19.15,99.62, !3d19.15!4d99.62).
/// Short links (maps.app.goo.gl) cannot be resolved offline and return null.
LatLngValue? parseLatLng(String input) {
  String s;
  try {
    s = Uri.decodeFull(input.trim());
  } catch (_) {
    s = input.trim();
  }
  if (s.isEmpty) return null;
  final d = _d34.firstMatch(s);
  if (d != null) {
    final lat = double.parse(d[1]!);
    final lng = double.parse(d[2]!);
    if (_valid(lat, lng)) return LatLngValue(lat, lng);
  }
  for (final re in _patterns) {
    final m = re.firstMatch(s);
    if (m != null) {
      final lat = double.parse(m[1]!);
      final lng = double.parse(m[2]!);
      if (_valid(lat, lng)) return LatLngValue(lat, lng);
    }
  }
  return null;
}
