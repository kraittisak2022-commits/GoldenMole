import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'format.dart' show publicAppUrl;
import 'latlng.dart';

class RoadRoute {
  const RoadRoute({required this.km, required this.path});
  final double km;

  /// Driving path from the main road to the pin; empty when Google returned no line.
  final List<LatLngValue> path;
}

/// Driving route from the web app's `/api/road-distance`, or null when it cannot be measured
/// (no key on the server, offline, no route).
Future<RoadRoute?> fetchRoadRoute(LatLngValue from, LatLngValue to) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.postUrl(Uri.parse('$publicAppUrl/api/road-distance'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'from': {'lat': from.lat, 'lng': from.lng},
      'to': {'lat': to.lat, 'lng': to.lng},
    }));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) return null;
    final data = jsonDecode(body);
    if (data is! Map) return null;
    final km = data['km'];
    if (km is! num || !km.isFinite) return null;
    var path = <LatLngValue>[];
    final line = data['polyline'];
    if (line is String && line.isNotEmpty) {
      try {
        path = decodePolyline(line);
      } on FormatException {
        path = [];
      }
    }
    return RoadRoute(km: km.toDouble(), path: path);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Google encoded polyline (precision 5) to points.
List<LatLngValue> decodePolyline(String encoded) {
  final points = <LatLngValue>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  int next() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) throw const FormatException('Truncated polyline');
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return result & 1 == 1 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    points.add(LatLngValue(lat / 1e5, lng / 1e5));
  }
  return points;
}

/// Point halfway along the path (by distance), for placing the distance label.
LatLngValue? pathMidpoint(List<LatLngValue> path) {
  if (path.isEmpty) return null;
  if (path.length == 1) return path.first;
  double segLen(LatLngValue a, LatLngValue b) {
    final dx = (b.lng - a.lng) * math.cos(((a.lat + b.lat) / 2) * (math.pi / 180));
    final dy = b.lat - a.lat;
    return math.sqrt(dx * dx + dy * dy);
  }

  final lengths = [for (var i = 1; i < path.length; i++) segLen(path[i - 1], path[i])];
  var remaining = lengths.fold<double>(0, (s, l) => s + l) / 2;
  for (var i = 0; i < lengths.length; i++) {
    if (remaining <= lengths[i] && lengths[i] > 0) {
      final t = remaining / lengths[i];
      return LatLngValue(
        path[i].lat + (path[i + 1].lat - path[i].lat) * t,
        path[i].lng + (path[i + 1].lng - path[i].lng) * t,
      );
    }
    remaining -= lengths[i];
  }
  return path.last;
}
