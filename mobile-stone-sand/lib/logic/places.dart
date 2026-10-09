import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'geo.dart';

/// Beyond this the closest village centre says little about where the pin is.
const _villageMaxKm = 4.0;

/// A named road/soi further than this is not "the soi the site is on".
const _roadMaxKm = 0.25;

class PinPlace {
  const PinPlace({this.village, this.road});

  /// Nearest village centre within 4 km, distance rounded to 0.1 km.
  final ({String name, double km})? village;

  /// Nearest named road/soi within 250 m, distance rounded to 10 m.
  final ({String name, double m})? road;

  /// Short text for the address field, e.g. "ใกล้บ้านหม้อ · ซอย 4".
  String get text => [if (village != null) 'ใกล้${village!.name}', if (road != null) road!.name].join(' · ');
}

double _kmBetween(double lat1, double lng1, double lat2, double lng2) {
  final kx = 111.32 * math.cos(((lat1 + lat2) / 2) * (math.pi / 180));
  final dx = (lng2 - lng1) * kx;
  final dy = (lat2 - lat1) * 110.57;
  return math.sqrt(dx * dx + dy * dy);
}

/// Villages and named roads/sois around อ.วังเหนือ, from bundled OpenStreetMap data.
class Places {
  Places._(this._villages, this._roads);

  final List<({String name, double lat, double lng})> _villages;
  final List<({String name, List<Pt> line})> _roads;

  static Places? _cache;

  static Places? get cached => _cache;

  static Future<Places> load() async =>
      _cache ??= Places.parse(await rootBundle.loadString('assets/geo/places.json'));

  factory Places.parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final villages = [
      for (final v in (data['villages'] as List).cast<Map>())
        (name: '${v['name']}', lat: (v['lat'] as num).toDouble(), lng: (v['lng'] as num).toDouble()),
    ];
    final roads = [
      for (final r in (data['roads'] as List).cast<Map>())
        (
          name: '${r['name']}',
          line: [
            for (final c in (r['coords'] as List).cast<List>()) [(c[0] as num).toDouble(), (c[1] as num).toDouble()],
          ],
        ),
    ];
    return Places._(villages, roads);
  }

  /// Nearest village and named road/soi around a pin.
  PinPlace describe(double lat, double lng) {
    ({String name, double km})? village;
    for (final v in _villages) {
      final km = _kmBetween(lat, lng, v.lat, v.lng);
      if (km <= _villageMaxKm && (village == null || km < village.km)) village = (name: v.name, km: km);
    }
    ({String name, double km})? road;
    for (final r in _roads) {
      if (r.line.isEmpty) continue;
      final km = lineDistanceKm([lng, lat], r.line);
      if (km <= _roadMaxKm && (road == null || km < road.km)) road = (name: r.name, km: km);
    }
    return PinPlace(
      village: village == null ? null : (name: village.name, km: (village.km * 10).round() / 10),
      road: road == null ? null : (name: road.name, m: (road.km * 100).round() * 10.0),
    );
  }
}
