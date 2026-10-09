import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../logic/geo.dart';
import '../logic/latlng.dart';
import '../logic/road_route.dart' show pathMidpoint;
import '../theme/app_theme.dart';

const _districtCenter = LatLng(districtCenterLat, districtCenterLng);
const _pinW = 32.0;
const _pinH = 42.0;
const _routeColor = Color(0xFF2563EB);
const _roadStartColor = Color(0xFFD97706);

/// Line from the main road to the pin, with its distance.
class MapRoute {
  const MapRoute({required this.path, required this.label, required this.byRoad});
  final List<LatLngValue> path;
  final String label;

  /// false = straight line (drawn dashed).
  final bool byRoad;
}

/// OpenStreetMap with the district outline, main roads and a draggable delivery pin.
class DeliveryMap extends StatefulWidget {
  const DeliveryMap({
    super.key,
    required this.value,
    this.onChange,
    this.flyTarget,
    this.height = 300,
    this.readOnly = false,
    this.onExpand,
    this.route,
  });

  final LatLngValue? value;
  final MapRoute? route;
  final ValueChanged<LatLngValue>? onChange;

  /// Each new instance recentres the map on it.
  final LatLngValue? flyTarget;
  final double? height;
  final bool readOnly;
  final VoidCallback? onExpand;

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  final _controller = MapController();
  final _mapKey = GlobalKey();
  GeoData? _geo = GeoData.cached;
  LatLng? _dragging;
  Offset _tipOffset = Offset.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (_geo == null) {
      GeoData.load().then((g) {
        if (mounted) setState(() => _geo = g);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DeliveryMap old) {
    super.didUpdateWidget(old);
    final t = widget.flyTarget;
    if (t != null && !identical(t, old.flyTarget) && _ready) {
      final zoom = _controller.camera.zoom < 14 ? 14.0 : _controller.camera.zoom;
      _controller.move(LatLng(t.lat, t.lng), zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit(LatLng p) => widget.onChange?.call(LatLngValue(p.latitude, p.longitude));

  LatLng? _globalToLatLng(Offset global) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _controller.camera.screenOffsetToLatLng(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final pin = _dragging ?? (v == null ? null : LatLng(v.lat, v.lng));
    final interactive = !widget.readOnly && widget.onChange != null;
    final geo = _geo;
    final route = _dragging == null && (widget.route?.path.length ?? 0) > 1 ? widget.route : null;
    final routeMid = route == null ? null : pathMidpoint(route.path);

    final map = FlutterMap(
      key: _mapKey,
      mapController: _controller,
      options: MapOptions(
        initialCenter: v == null ? _districtCenter : LatLng(v.lat, v.lng),
        initialZoom: v == null ? 11 : 14,
        onMapReady: () => _ready = true,
        onTap: interactive ? (_, p) => _emit(p) : null,
        interactionOptions: InteractionOptions(
          flags: widget.readOnly
              ? InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom
              : InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goldenmole.stonesand',
        ),
        if (geo != null && geo.districtOutline.isNotEmpty)
          PolygonLayer(
            polygons: [
              Polygon(
                points: [for (final p in geo.districtOutline) LatLng(p[1], p[0])],
                color: AppColors.primary.withValues(alpha: 0.04),
                borderColor: AppColors.primary,
                borderStrokeWidth: 2,
                pattern: StrokePattern.dashed(segments: const [6, 4]),
              ),
            ],
          ),
        if (geo != null)
          PolylineLayer(
            polylines: [
              for (final r in geo.roads)
                Polyline(
                  points: [for (final p in r.points) LatLng(p[1], p[0])],
                  color: const Color(0xFFD97706).withValues(alpha: 0.7),
                  strokeWidth: 3,
                ),
            ],
          ),
        if (route != null) ...[
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final p in route.path) LatLng(p.lat, p.lng)],
                color: _routeColor.withValues(alpha: 0.85),
                strokeWidth: 5,
                pattern: route.byRoad ? const StrokePattern.solid() : StrokePattern.dashed(segments: const [8, 8]),
              ),
            ],
          ),
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(route.path.first.lat, route.path.first.lng),
                radius: 6,
                color: _roadStartColor,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
          if (routeMid != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(routeMid.lat, routeMid.lng),
                  width: route.label.length * 7.4 + 24,
                  height: 24,
                  child: IgnorePointer(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _routeColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        route.label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
        if (pin != null)
          MarkerLayer(
            markers: [
              Marker(
                point: pin,
                width: _pinW,
                height: _pinH,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: interactive
                      ? (d) => _tipOffset = Offset(_pinW / 2 - d.localPosition.dx, _pinH - 2 - d.localPosition.dy)
                      : null,
                  onPanUpdate: interactive
                      ? (d) {
                          final p = _globalToLatLng(d.globalPosition + _tipOffset);
                          if (p != null) setState(() => _dragging = p);
                        }
                      : null,
                  onPanEnd: interactive
                      ? (_) {
                          final p = _dragging;
                          setState(() => _dragging = null);
                          if (p != null) _emit(p);
                        }
                      : null,
                  child: const CustomPaint(painter: _PinPainter()),
                ),
              ),
            ],
          ),
        RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            ),
          ],
        ),
        if (widget.onExpand != null)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: AppColors.surface,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  tooltip: 'ขยายแผนที่',
                  icon: const Icon(Icons.fullscreen, size: 22),
                  onPressed: widget.onExpand,
                ),
              ),
            ),
          ),
      ],
    );

    final framed = ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: map,
      ),
    );
    if (widget.height == null) return framed;
    final maxH = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(height: widget.height! < maxH ? widget.height : maxH, child: framed);
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 32;
    final sy = size.height / 42;
    final path = Path()
      ..moveTo(16 * sx, 1 * sy)
      ..cubicTo(8 * sx, 1 * sy, 2 * sx, 7 * sy, 2 * sx, 15 * sy)
      ..cubicTo(2 * sx, 25.5 * sy, 16 * sx, 41 * sy, 16 * sx, 41 * sy)
      ..cubicTo(16 * sx, 41 * sy, 30 * sx, 25.5 * sy, 30 * sx, 15 * sy)
      ..cubicTo(30 * sx, 7 * sy, 24 * sx, 1 * sy, 16 * sx, 1 * sy)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = AppColors.primary);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(16 * sx, 15 * sy), 5.5 * sx, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full-screen pin picker; returns the chosen point or null when dismissed.
Future<LatLngValue?> pickPinFullscreen(BuildContext context, LatLngValue? initial) {
  return Navigator.of(context).push<LatLngValue>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PinPickerPage(initial: initial)),
  );
}

class _PinPickerPage extends StatefulWidget {
  const _PinPickerPage({required this.initial});
  final LatLngValue? initial;

  @override
  State<_PinPickerPage> createState() => _PinPickerPageState();
}

class _PinPickerPageState extends State<_PinPickerPage> {
  late LatLngValue? _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ปักหมุดหน้างาน'),
        actions: [
          TextButton(
            onPressed: _value == null ? null : () => Navigator.pop(context, _value),
            child: const Text('ใช้ตำแหน่งนี้'),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'แตะบนแผนที่หรือลากหมุด เส้นสีส้มคือถนนสายหลัก',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, MediaQuery.paddingOf(context).bottom + 8),
              child: DeliveryMap(
                value: _value,
                height: null,
                onChange: (p) => setState(() => _value = p),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
