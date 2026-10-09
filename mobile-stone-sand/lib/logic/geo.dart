import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

typedef Pt = List<double>; // [lng, lat]
typedef Ring = List<Pt>;
typedef Poly = List<Ring>; // outer ring + holes

/// Map centre used when no pin is set (middle of อ.วังเหนือ).
const districtCenterLat = 19.158;
const districtCenterLng = 99.632;

class TambonMatch {
  const TambonMatch(this.name, this.method);
  final String name;

  /// exact = inside a tambon polygon; nearest = inside the district but between coarse outlines.
  final String method;
}

class RoadDistance {
  const RoadDistance(this.km, this.roadLabel);
  final double km;
  final String roadLabel;
}

class Road {
  const Road({required this.ref, required this.name, required this.points});
  final String ref;
  final String name;
  final List<Pt> points;
}

class _Area {
  const _Area(this.name, this.polys);
  final String name;
  final List<Poly> polys;
}

Pt _pt(Object? p) {
  final l = p as List;
  return [(l[0] as num).toDouble(), (l[1] as num).toDouble()];
}

List<Poly> _polys(Map<String, dynamic> geometry) {
  final type = geometry['type'];
  final coords = geometry['coordinates'] as List;
  Poly poly(List rings) => rings.map((r) => (r as List).map(_pt).toList()).toList();
  if (type == 'Polygon') return [poly(coords)];
  if (type == 'MultiPolygon') return coords.map((p) => poly(p as List)).toList();
  return const [];
}

bool _onSegment(Pt p, Pt a, Pt b) {
  final cross = (p[1] - a[1]) * (b[0] - a[0]) - (p[0] - a[0]) * (b[1] - a[1]);
  if (cross.abs() > 1e-12) return false;
  return p[0] >= math.min(a[0], b[0]) &&
      p[0] <= math.max(a[0], b[0]) &&
      p[1] >= math.min(a[1], b[1]) &&
      p[1] <= math.max(a[1], b[1]);
}

/// Ray casting; points on the boundary count as inside (turf default).
bool _inRing(Pt p, Ring ring) {
  var inside = false;
  final n = ring.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if (_onSegment(p, a, b)) return true;
    final intersect = ((a[1] > p[1]) != (b[1] > p[1])) &&
        (p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]);
    if (intersect) inside = !inside;
  }
  return inside;
}

bool _inPolys(Pt p, List<Poly> polys) {
  for (final poly in polys) {
    if (poly.isEmpty || !_inRing(p, poly.first)) continue;
    var inHole = false;
    for (final hole in poly.skip(1)) {
      if (_inRing(p, hole)) {
        inHole = true;
        break;
      }
    }
    if (!inHole) return true;
  }
  return false;
}

const _earthRadiusKm = 6371.0088;
double _rad(double d) => d * math.pi / 180;

/// turf `rhumbDistance` in kilometres.
double _rhumbKm(Pt from, Pt to) {
  var toLng = to[0];
  toLng += toLng - from[0] > 180 ? -360 : (from[0] - toLng > 180 ? 360 : 0);
  final phi1 = _rad(from[1]);
  final phi2 = _rad(to[1]);
  final dPhi = phi2 - phi1;
  var dLambda = _rad((toLng - from[0]).abs());
  if (dLambda > math.pi) dLambda -= 2 * math.pi;
  final dPsi = math.log(math.tan(phi2 / 2 + math.pi / 4) / math.tan(phi1 / 2 + math.pi / 4));
  final q = dPsi.abs() > 1e-11 ? dPhi / dPsi : math.cos(phi1);
  return math.sqrt(dPhi * dPhi + q * q * dLambda * dLambda) * _earthRadiusKm;
}

/// turf `pointToLineDistance(..., { method: 'planar' })` for one segment.
double _segmentKm(Pt p, Pt a, Pt b) {
  final v = [b[0] - a[0], b[1] - a[1]];
  final w = [p[0] - a[0], p[1] - a[1]];
  final c1 = w[0] * v[0] + w[1] * v[1];
  if (c1 <= 0) return _rhumbKm(p, a);
  final c2 = v[0] * v[0] + v[1] * v[1];
  if (c2 <= c1) return _rhumbKm(p, b);
  final t = c1 / c2;
  return _rhumbKm(p, [a[0] + t * v[0], a[1] + t * v[1]]);
}

class GeoData {
  GeoData._(this._district, this._tambons, this.roads, this.districtOutline);

  final List<Poly> _district;
  final List<_Area> _tambons;
  final List<Road> roads;

  /// Outer ring of the district, for drawing on the map.
  final List<Pt> districtOutline;

  late final List<({String name, Pt c})> _centroids = _tambons.map((t) {
    final pts = t.polys.expand((poly) => poly).expand((ring) => ring).toList();
    final lng = pts.fold<double>(0, (s, p) => s + p[0]) / pts.length;
    final lat = pts.fold<double>(0, (s, p) => s + p[1]) / pts.length;
    return (name: t.name, c: <double>[lng, lat]);
  }).toList();

  static GeoData? _cache;

  static GeoData? get cached => _cache;

  static Future<GeoData> load() async {
    if (_cache != null) return _cache!;
    final results = await Future.wait([
      rootBundle.loadString('assets/geo/district.json'),
      rootBundle.loadString('assets/geo/tambons.json'),
      rootBundle.loadString('assets/geo/main-roads.json'),
    ]);
    return _cache = GeoData.parse(results[0], results[1], results[2]);
  }

  factory GeoData.parse(String districtJson, String tambonsJson, String roadsJson) {
    final district = jsonDecode(districtJson) as Map<String, dynamic>;
    final tambons = jsonDecode(tambonsJson) as Map<String, dynamic>;
    final roadsFc = jsonDecode(roadsJson) as Map<String, dynamic>;
    final dFeatures = district['features'] as List;
    final dPolys = dFeatures.isEmpty
        ? <Poly>[]
        : _polys(Map<String, dynamic>.from((dFeatures.first as Map)['geometry'] as Map));
    final areas = (tambons['features'] as List).map((f) {
      final m = f as Map;
      return _Area(
        '${(m['properties'] as Map)['name']}',
        _polys(Map<String, dynamic>.from(m['geometry'] as Map)),
      );
    }).toList();
    final roads = (roadsFc['features'] as List)
        .map((f) {
          final m = f as Map;
          final g = m['geometry'] as Map;
          if (g['type'] != 'LineString') return null;
          final p = (m['properties'] as Map?) ?? const {};
          return Road(
            ref: '${p['ref'] ?? ''}',
            name: '${p['name'] ?? ''}',
            points: (g['coordinates'] as List).map(_pt).toList(),
          );
        })
        .whereType<Road>()
        .toList();
    return GeoData._(dPolys, areas, roads, dPolys.isEmpty ? const [] : dPolys.first.first);
  }

  bool isInDistrict(double lat, double lng) => _district.isNotEmpty && _inPolys([lng, lat], _district);

  /// Tambon name for a pin, or null when the pin is outside อ.วังเหนือ.
  TambonMatch? findTambon(double lat, double lng) {
    final p = <double>[lng, lat];
    for (final t in _tambons) {
      if (_inPolys(p, t.polys)) return TambonMatch(t.name, 'exact');
    }
    if (!isInDistrict(lat, lng) || _centroids.isEmpty) return null;
    var best = _centroids.first;
    var bestD = double.infinity;
    for (final t in _centroids) {
      final d = math.pow(t.c[0] - lng, 2) + math.pow(t.c[1] - lat, 2);
      if (d < bestD) {
        bestD = d.toDouble();
        best = t;
      }
    }
    return TambonMatch(best.name, 'nearest');
  }

  /// Straight-line distance from a pin to the nearest main road in the district.
  RoadDistance? distanceToMainRoad(double lat, double lng) {
    final p = <double>[lng, lat];
    RoadDistance? best;
    for (final road in roads) {
      var km = double.infinity;
      for (var i = 0; i < road.points.length - 1; i++) {
        km = math.min(km, _segmentKm(p, road.points[i], road.points[i + 1]));
      }
      if (best == null || km < best.km) {
        best = RoadDistance(
          km,
          road.ref.isNotEmpty ? 'ถนน ${road.ref}' : (road.name.isNotEmpty ? road.name : 'ถนนสายหลัก'),
        );
      }
    }
    if (best == null) return null;
    return RoadDistance(((best.km * 100) + 0.5).floorToDouble() / 100, best.roadLabel);
  }
}
