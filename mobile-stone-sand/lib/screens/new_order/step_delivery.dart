import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calc/delivery_fee.dart';
import '../../calc/pricing.dart';
import '../../calc/trips.dart';
import '../../logic/driver_pay.dart';
import '../../logic/format.dart';
import '../../logic/geo.dart';
import '../../logic/latlng.dart';
import '../../logic/places.dart';
import '../../logic/road_route.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/delivery_map.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

typedef WizardPatch = void Function(WizardState Function(WizardState s) update);

class LoadLine {
  const LoadLine({required this.id, required this.name, required this.load});
  final String id;
  final String name;
  final Load load;
}

/// The suggested fees: the tambon's baht/คิว, plus the per-trip distance surcharge.
WizardState _withFee(Zone z, WizardState st, DeliverySettings settings) => st.copyWith(
      feePerCubic: z.feePerCubic,
      feePerTrip: suggestTripFee(st.roadDistanceKm, settings).toDouble(),
    );

/// Current device position, or an error message.
Future<(LatLngValue?, String)> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return (null, 'เปิด GPS ของเครื่องก่อน');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return (null, 'ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง ลองแตะบนแผนที่แทน');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    return (LatLngValue(pos.latitude, pos.longitude), '');
  } catch (_) {
    return (null, 'ระบุตำแหน่งไม่ได้ ลองแตะบนแผนที่แทน');
  }
}

class StepDelivery extends StatefulWidget {
  const StepDelivery({
    super.key,
    required this.state,
    required this.patch,
    required this.zones,
    required this.drivers,
    required this.settings,
    required this.loadLines,
    required this.onEditProducts,
  });
  final WizardState state;
  final WizardPatch patch;
  final List<Zone> zones;
  final List<Driver> drivers;
  final AppSettings settings;
  final List<LoadLine> loadLines;
  final VoidCallback onEditProducts;

  @override
  State<StepDelivery> createState() => _StepDeliveryState();
}

class _StepDeliveryState extends State<StepDelivery> {
  LatLngValue? _flyTarget;
  bool _locating = false;
  String _geoError = '';
  final _coordText = TextEditingController();
  late final _address = TextEditingController(text: widget.state.deliveryAddress);
  RouteGroup? _group;
  Places? _places = Places.cached;
  String _measuringKey = '';
  String _roadFailedKey = '';
  ({String key, List<LatLngValue> path})? _roadPath;

  WizardState get s => widget.state;
  String get _pinKey => s.hasPin ? '${s.pinLat},${s.pinLng}' : '';
  List<Load> get _loads => [for (final l in widget.loadLines) l.load];
  Zone? _zoneById(String? id) {
    for (final z in widget.zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_places == null) {
      Places.load().then((p) {
        if (mounted) setState(() => _places = p);
      });
    }
    _maybeMeasureRoad();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefillFromCustomer();
    });
  }

  @override
  void didUpdateWidget(covariant StepDelivery old) {
    super.didUpdateWidget(old);
    if (s.deliveryAddress != _address.text) _address.text = s.deliveryAddress;
    _maybeMeasureRoad();
  }

  /// Replaces the straight-line distance with the driving distance from the main road, once per pin.
  void _maybeMeasureRoad() {
    final key = _pinKey;
    if (key.isEmpty || s.roadDistanceByRoad || key == _roadFailedKey || key == _measuringKey) return;
    _measuringKey = key;
    _measureRoad(key, s.pinLat!, s.pinLng!);
  }

  Future<void> _measureRoad(String key, double lat, double lng) async {
    final start = (await GeoData.load()).distanceToMainRoad(lat, lng)?.point;
    final route = start == null ? null : await fetchRoadRoute(LatLngValue(start[1], start[0]), LatLngValue(lat, lng));
    if (!mounted || _pinKey != key) return;
    _measuringKey = '';
    if (route == null) return setState(() => _roadFailedKey = key);
    setState(() => _roadPath = (key: key, path: route.path));
    widget.patch((st) => '${st.pinLat},${st.pinLng}' != key
        ? st
        : _refee(st.copyWith(roadDistanceKm: route.km, roadDistanceByRoad: true)));
  }

  @override
  void dispose() {
    _coordText.dispose();
    _address.dispose();
    super.dispose();
  }

  /// [fillAddress]: put the village/soi near the pin in the address while it is empty or still the
  /// text filled in for the previous pin.
  Future<WizardState Function(WizardState)> _pinUpdate(LatLngValue p, {bool fillAddress = false}) async {
    final geo = await GeoData.load();
    final places = await Places.load();
    final tambon = geo.findTambon(p.lat, p.lng);
    final road = geo.distanceToMainRoad(p.lat, p.lng);
    final delivery = widget.settings.delivery;
    final auto = places.describe(p.lat, p.lng).text;
    return (WizardState st) {
      var next = st.copyWith(
        pinLat: double.parse(p.lat.toStringAsFixed(6)),
        pinLng: double.parse(p.lng.toStringAsFixed(6)),
        outsideDistrict: tambon == null,
        roadDistanceKm: road?.km,
        roadDistanceByRoad: false,
        roadLabel: road?.roadLabel ?? '',
      );
      if (fillAddress && auto.isNotEmpty) {
        final address = st.deliveryAddress.trim();
        final prevAuto = st.hasPin ? places.describe(st.pinLat!, st.pinLng!).text : '';
        if (address.isEmpty || address == prevAuto) next = next.copyWith(deliveryAddress: auto);
      }
      Zone? matched;
      if (tambon != null) {
        for (final z in widget.zones) {
          if (z.name == tambon.name) matched = z;
        }
      }
      var feeZone = _zoneById(st.zoneId);
      if (matched != null && st.tambonMethod != 'manual') {
        next = next.copyWith(zoneId: matched.id, tambonMethod: tambon!.method);
        feeZone = matched;
      }
      if (!st.feeTouched && feeZone != null) next = _withFee(feeZone, next, delivery);
      return next;
    };
  }

  Future<void> _onPin(LatLngValue p) async {
    setState(() => _geoError = '');
    final update = await _pinUpdate(p, fillAddress: true);
    widget.patch(update);
  }

  /// The customer is picked on the step before; start from their saved address and pin.
  Future<void> _prefillFromCustomer() async {
    final c = s.customer;
    if (c == null) return;
    WizardState Function(WizardState)? pin;
    if (!s.hasPin && c.lat != null && c.lng != null) {
      final p = LatLngValue(c.lat!, c.lng!);
      pin = await _pinUpdate(p);
      if (!mounted) return;
      setState(() => _flyTarget = p);
    }
    if (pin == null && (s.deliveryAddress.trim().isNotEmpty || c.address.isEmpty)) return;
    widget.patch((st) {
      var next = st;
      if (st.deliveryAddress.trim().isEmpty && c.address.isNotEmpty) next = next.copyWith(deliveryAddress: c.address);
      return pin == null || next.hasPin ? next : pin(next);
    });
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _geoError = '';
    });
    final (p, err) = await currentPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _geoError = err;
      if (p != null) _flyTarget = p;
    });
    if (p != null) await _onPin(p);
  }

  void _applyCoordText() {
    final p = parseLatLng(_coordText.text);
    if (p == null) {
      setState(() => _geoError =
          'อ่านพิกัดไม่ได้ วางพิกัดแบบ 19.15, 99.62 หรือลิงก์ Google Maps แบบเต็ม (ลิงก์ย่อ maps.app.goo.gl ใช้ไม่ได้)');
      return;
    }
    _coordText.clear();
    setState(() => _flyTarget = p);
    _onPin(p);
  }

  Future<void> _expandMap() async {
    final p = await pickPinFullscreen(context, s.hasPin ? LatLngValue(s.pinLat!, s.pinLng!) : null);
    if (p == null || !mounted) return;
    setState(() => _flyTarget = p);
    await _onPin(p);
  }

  void _chooseZone(String? id) {
    final z = _zoneById(id);
    widget.patch((st) {
      var next = st.copyWith(zoneId: id, tambonMethod: id == null ? null : 'manual');
      if (z != null && !st.feeTouched) next = _withFee(z, next, widget.settings.delivery);
      return next;
    });
  }

  /// The per-km rate depends on the truck size, so an untouched fee follows it.
  WizardState _refee(WizardState st) {
    final z = _zoneById(st.zoneId);
    return z == null || st.feeTouched ? st : _withFee(z, st, widget.settings.delivery);
  }

  void _setTruck(int size) {
    widget.patch((st) {
      final keepDriver = st.driverTruckSize == size;
      final next = st.copyWith(truckSize: size, truckTouched: true);
      return _refee(keepDriver ? next : next.copyWith(driverId: null, driverTruckSize: null, driverConfirmed: false));
    });
  }

  void _chooseDriver(Driver d) {
    widget.patch((st) => st.driverId == d.id
        ? st.copyWith(driverId: null, driverTruckSize: null, driverConfirmed: false)
        : _refee(st.copyWith(
            driverId: d.id,
            driverTruckSize: d.truckSize,
            driverConfirmed: false,
            truckSize: d.truckSize,
            truckTouched: true,
          )));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('การจัดส่ง', subtitle: 'ปักหมุดหน้างาน เลือกตำบล ขนาดรถ และคนขับ'),
        const SizedBox(height: 20),
        ..._pinSection(),
        const SizedBox(height: 20),
        _deliveryCard(),
        const SizedBox(height: 20),
        ..._driverSection(),
      ],
    );
  }

  /// The driving route for this pin, or a straight line from the nearest main-road point.
  MapRoute? _mapRoute(bool measuring) {
    if (!s.hasPin) return null;
    final pin = LatLngValue(s.pinLat!, s.pinLng!);
    final label = measuring ? 'กำลังวัด…' : '${formatNumber(s.roadDistanceKm ?? 0)} กม.';
    final path = _roadPath;
    if (s.roadDistanceByRoad && path != null && path.key == _pinKey) {
      return MapRoute(path: path.path, label: label, byRoad: true);
    }
    final start = GeoData.cached?.distanceToMainRoad(pin.lat, pin.lng)?.point;
    if (start == null) return null;
    return MapRoute(path: [LatLngValue(start[1], start[0]), pin], label: label, byRoad: false);
  }

  List<Widget> _pinSection() {
    final zone = _zoneById(s.zoneId);
    final place = s.hasPin ? _places?.describe(s.pinLat!, s.pinLng!) : null;
    final village = place?.village;
    final soi = place?.road;
    final measuring = s.hasPin && !s.roadDistanceByRoad && _pinKey != _roadFailedKey;
    final km = s.roadDistanceKm;
    final roadHint = [
      if (s.roadLabel.isNotEmpty) s.roadLabel,
      if (s.hasPin && _pinKey == _roadFailedKey) 'วัดตามถนนไม่ได้ ใช้ระยะเส้นตรง',
    ].join(' · ');
    return [
      Row(
        children: [
          const Expanded(child: Text('ปักหมุดหน้างาน', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16))),
          OutlinedButton.icon(
            onPressed: _locating ? null : _locate,
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(_locating ? 'กำลังหา…' : 'ตำแหน่งปัจจุบัน'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'แตะบนแผนที่หรือลากหมุด เส้นสีส้มคือถนนสายหลัก เส้นสีน้ำเงินคือเส้นทางจากถนนใหญ่ถึงหมุด (เส้นประ = ระยะเส้นตรง)',
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
      const SizedBox(height: 12),
      DeliveryMap(
        value: s.hasPin ? LatLngValue(s.pinLat!, s.pinLng!) : null,
        onChange: _onPin,
        flyTarget: _flyTarget,
        onExpand: _expandMap,
        route: _mapRoute(measuring),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _coordText,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyCoordText(),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'วางพิกัด / ลิงก์ Google Maps',
                prefixIcon: Icon(Icons.link, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _coordText.text.trim().isEmpty ? null : _applyCoordText,
            child: const Text('ใช้พิกัด'),
          ),
        ],
      ),
      if (_geoError.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_geoError, style: const TextStyle(fontSize: 14, color: AppColors.destructive)),
        ),
      if (s.hasPin) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                label: 'ตำบล (จากหมุด)',
                value: zone?.name ?? '—',
                hint: switch (s.tambonMethod) {
                  'nearest' => 'ประมาณจากตำบลที่ใกล้ที่สุด',
                  'manual' => 'เลือกเอง',
                  _ => null,
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InfoTile(
                label: s.roadDistanceByRoad ? 'ระยะตามถนนจากถนนใหญ่' : 'ห่างถนนใหญ่ (เส้นตรง)',
                value: measuring ? 'กำลังวัดตามถนน…' : (km != null ? '${formatNumber(km)} กม.' : '—'),
                hint: roadHint.isEmpty ? null : roadHint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InfoTile(
                label: 'หมู่บ้าน (ใกล้หมุดที่สุด)',
                value: village?.name ?? '—',
                hint: village == null
                    ? 'ไม่พบหมู่บ้านในระยะ 4 กม.'
                    : village.km < 0.2
                        ? 'หมุดอยู่กลางหมู่บ้าน'
                        : 'ห่างกลางหมู่บ้าน ~${formatNumber(village.km)} กม.',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InfoTile(
                label: 'ซอย / ถนน',
                value: soi?.name ?? '—',
                hint: soi == null
                    ? 'ไม่มีชื่อซอยในแผนที่ใกล้หมุด'
                    : soi.m <= 20
                        ? 'หมุดอยู่บนเส้นนี้'
                        : 'ห่างจากหมุด ~${formatNumber(soi.m)} ม.',
              ),
            ),
          ],
        ),
      ],
      if (s.hasPin && s.outsideDistrict) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(kRadius)),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'หมุดอยู่นอกเขต อ.วังเหนือ เลือกตำบลที่ใกล้ที่สุดเอง และใส่ค่าส่งเพิ่มตามความเหมาะสม',
                  style: TextStyle(fontSize: 14, color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _deliveryCard() {
    final zone = _zoneById(s.zoneId);
    final delivery = widget.settings.delivery;
    final largestPerTrip = widget.loadLines.fold<num>(0, (m, l) => l.load.perTrip > m ? l.load.perTrip : m);
    final cubic = totalQuantity(quantitiesOf(s.loads));
    final deliveryTotal = round2(s.feePerCubic * cubic + s.feePerTrip * s.trips + s.remoteSurcharge);
    final suggested = zone == null ? null : _withFee(zone, s, delivery);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            'ตำบลที่จัดส่ง *',
            hint: zone == null
                ? null
                : 'ค่าส่ง ${formatNumber(zone.feePerCubic)} บาท/คิว'
                    '${delivery.customerPerKm > 0 ? ' + ${formatNumber(delivery.customerPerKm)} บาท/กม./เที่ยว '
                        'เมื่อห่างถนนใหญ่เกิน ${formatNumber(delivery.nearKm)} กม.' : ''}',
            child: DropdownButtonFormField<String?>(
              key: ValueKey('zone:${s.zoneId}'),
              initialValue: zone?.id,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— เลือกตำบล —')),
                for (final z in widget.zones)
                  DropdownMenuItem<String?>(
                    value: z.id,
                    child: Text('${z.name} (${formatNumber(z.feePerCubic)}/คิว)'),
                  ),
              ],
              onChanged: _chooseZone,
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'ที่อยู่จัดส่ง / จุดสังเกต',
            child: TextField(
              controller: _address,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'บ้านเลขที่ หมู่บ้าน จุดสังเกต'),
              onChanged: (v) => widget.patch((st) => st.copyWith(deliveryAddress: v)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('ขนาดรถ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final size in const [3, 5]) ...[
                if (size == 5) const SizedBox(width: 8),
                Expanded(
                  child: _ToggleButton(
                    label: 'รถ $size คิว',
                    active: s.truckSize == size,
                    onTap: truckFits(size, _loads) ? () => _setTruck(size) : null,
                  ),
                ),
              ],
            ],
          ),
          if (!truckFits(3, _loads))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'สินค้าเที่ยวละ ${formatNumber(largestPerTrip)} คิว ต้องใช้รถ 5 คิว',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
            decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(kRadius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'จำนวนเที่ยว '),
                          TextSpan(
                            text: '${s.trips}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' เที่ยว'),
                        ]),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onEditProducts,
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('แก้ที่สินค้า'),
                    ),
                  ],
                ),
                for (final l in widget.loadLines)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: AppColors.muted),
                          ),
                        ),
                        Text(
                          '${formatNumber(l.load.perTrip)} คิว × ${l.load.trips} เที่ยว',
                          style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabular),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabel(
                  'ค่าส่ง / คิว',
                  hint: s.feeTouched && zone != null ? null : 'ตามตำบล',
                  child: NumberField(
                    decimal: false,
                    value: s.feePerCubic,
                    onChanged: (v) => widget.patch((st) => st.copyWith(feePerCubic: v < 0 ? 0 : v, feeTouched: true)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'เพิ่มตามระยะ / เที่ยว',
                  hint: s.feeTouched && zone != null ? null : 'จากระยะถึงถนนใหญ่',
                  child: NumberField(
                    decimal: false,
                    value: s.feePerTrip,
                    onChanged: (v) => widget.patch((st) => st.copyWith(feePerTrip: v < 0 ? 0 : v, feeTouched: true)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabel(
                  'ที่กันดาร (บวกเพิ่ม)',
                  child: NumberField(
                    decimal: false,
                    value: s.remoteSurcharge,
                    onChanged: (v) => widget.patch((st) => st.copyWith(remoteSurcharge: v < 0 ? 0 : v)),
                  ),
                ),
              ),
            ],
          ),
          if (s.feeTouched && zone != null && suggested != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.patch((st) => _withFee(zone, st, delivery).copyWith(feeTouched: false)),
                child: Text(
                  'ใช้ค่าส่งที่ระบบแนะนำ (${formatNumber(suggested.feePerCubic)}/คิว'
                  '${suggested.feePerTrip != 0 ? ' + ${formatNumber(suggested.feePerTrip)}/เที่ยว' : ''})',
                  style: const TextStyle(decoration: TextDecoration.underline),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(kRadius)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deliveryFeeFormula(
                      feePerCubic: s.feePerCubic,
                      cubic: cubic,
                      feePerTrip: s.feePerTrip,
                      trips: s.trips,
                      remoteSurcharge: s.remoteSurcharge,
                    ),
                    style: const TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                ),
                Text(
                  'ค่าส่ง ${formatMoney(deliveryTotal)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _driverSection() {
    final active = widget.drivers.where((d) => d.active).toList();
    final counts = <RouteGroup?, int>{null: active.length};
    for (final d in active) {
      counts[d.routeGroup] = (counts[d.routeGroup] ?? 0) + 1;
    }
    final shown = active.where((d) => _group == null || d.routeGroup == _group).toList()
      ..sort((a, b) {
        final fa = a.truckSize == s.truckSize ? 1 : 0;
        final fb = b.truckSize == s.truckSize ? 1 : 0;
        return fb != fa ? fb - fa : a.sortOrder.compareTo(b.sortOrder);
      });
    final largestPerTrip = widget.loadLines.fold<num>(0, (m, l) => l.load.perTrip > m ? l.load.perTrip : m);
    Driver? selected;
    for (final d in widget.drivers) {
      if (d.id == s.driverId) selected = d;
    }
    final zone = _zoneById(s.zoneId);

    return [
      const Text('คนขับ', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
      const Text(
        'โทรเช็คคิวก่อน แล้วเลือกคนขับ',
        style: TextStyle(fontSize: 14, color: AppColors.muted),
      ),
      const SizedBox(height: 12),
      DriverPayCard(
        zone: zone,
        truckSize: s.truckSize,
        trips: s.trips,
        roadDistanceKm: s.roadDistanceKm,
        delivery: widget.settings.delivery,
        otherSizeFits: truckFits(s.truckSize == 3 ? 5 : 3, _loads),
        edited: editedDriverFee(s),
        onEdit: (perTrip) => widget.patch(
          (st) => st.copyWith(driverFeeEdit: perTrip == null ? null : (perTrip: perTrip, key: driverFeeKey(st))),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CountChip(label: 'ทั้งหมด', count: counts[null], active: _group == null, onTap: () => setState(() => _group = null)),
          for (final g in RouteGroup.values)
            CountChip(label: g.label, count: counts[g] ?? 0, active: _group == g, onTap: () => setState(() => _group = g)),
        ],
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(
          children: [
            if (shown.isEmpty)
              EmptyState(active.isEmpty ? 'ยังไม่มีคนขับ เพิ่มคนขับที่เมนู "คนขับ" ก่อน' : 'ไม่มีคนขับในสายนี้'),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _driverRow(shown[i], largestPerTrip),
            ],
          ],
        ),
      ),
      if (selected != null) ...[
        const SizedBox(height: 12),
        CheckRow(
          value: s.driverConfirmed,
          onChanged: (v) => widget.patch((st) => st.copyWith(driverConfirmed: v)),
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'ยืนยันว่ารถ '),
            TextSpan(text: selected.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' เข้าหน้างานได้และมีคิวว่าง'),
          ])),
        ),
      ],
    ];
  }

  Widget _driverRow(Driver d, num largestPerTrip) {
    final selected = s.driverId == d.id;
    final fits = truckFits(d.truckSize, _loads);
    final sub = fits
        ? [if (d.village.isNotEmpty) d.village, d.routeGroup.label].join(' · ')
        : 'รถเล็กเกิน (สินค้าเที่ยวละ ${formatNumber(largestPerTrip)} คิว)';
    return Container(
      color: selected ? AppColors.primarySoft.withValues(alpha: 0.6) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: fits ? 1 : 0.5,
              child: InkWell(
                onTap: fits ? () => _chooseDriver(d) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected ? AppColors.primary : AppColors.border,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppBadge(
            '${d.truckSize} คิว${d.truckCount > 1 ? ' ×${d.truckCount}' : ''}',
            tone: d.truckSize == s.truckSize ? BadgeTone.info : BadgeTone.neutral,
          ),
          if (d.contacts.isNotEmpty)
            IconButton(
              tooltip: 'โทรหา ${d.name} ${formatPhone(d.contacts.first.phone)}',
              icon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.primary),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: digitsOnly(d.contacts.first.phone))),
            ),
        ],
      ),
    );
  }
}

/// What the driver earns for this job, for the admin to tell him on the phone. Never shown on the customer's bill.
/// The admin can raise or lower the pay per trip; [edited] is that pay, null = the tambon rate.
class DriverPayCard extends StatefulWidget {
  const DriverPayCard({
    super.key,
    required this.zone,
    required this.truckSize,
    required this.trips,
    required this.roadDistanceKm,
    required this.delivery,
    required this.otherSizeFits,
    this.edited,
    this.onEdit,
  });

  final Zone? zone;
  final int truckSize;
  final int trips;
  final double? roadDistanceKm;
  final DeliverySettings delivery;
  final bool otherSizeFits;
  final double? edited;
  final ValueChanged<double?>? onEdit;

  @override
  State<DriverPayCard> createState() => _DriverPayCardState();
}

class _DriverPayCardState extends State<DriverPayCard> {
  bool _editing = false;
  double _typed = 0;

  void _startEdit(double perTrip) {
    _typed = widget.edited ?? perTrip;
    if (widget.edited == null) widget.onEdit?.call(perTrip);
    setState(() => _editing = true);
  }

  void _type(double v) {
    _typed = v < 0 ? 0 : v;
    widget.onEdit?.call(_typed);
  }

  void _finishEdit() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  void _reset() {
    widget.onEdit?.call(null);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.zone;
    final truckSize = widget.truckSize;
    final delivery = widget.delivery;
    final edited = widget.edited;
    final canEdit = widget.onEdit != null;
    if (z == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'เลือกตำบลก่อน ระบบจะคำนวณค่ารถคนขับให้',
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
    }
    final rate = driverTripRate(z, truckSize, widget.roadDistanceKm, delivery);
    final pay = edited ?? rate.perTrip;
    if (edited == null && rate.perTrip <= 0 && !_editing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(kRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ยังไม่ได้ตั้งค่ารถคนขับ ต.${z.name} สำหรับรถ $truckSize คิว ตั้งได้ที่ ตั้งค่า › ค่าส่งตามตำบล',
                    style: const TextStyle(fontSize: 14, color: AppColors.warning),
                  ),
                ),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _startEdit(rate.perTrip),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('ใส่ค่ารถเอง'),
              ),
            ],
          ],
        ),
      );
    }
    final km = chargedKm(widget.roadDistanceKm, delivery.nearKm);
    final otherSize = truckSize == 3 ? 5 : 3;
    final other = widget.otherSizeFits && edited == null
        ? driverTripRate(z, otherSize, widget.roadDistanceKm, delivery).perTrip
        : 0.0;
    final adjusted = edited != null && edited != rate.perTrip;
    final diff = pay - rate.perTrip;
    const label = TextStyle(fontSize: 14, color: AppColors.muted);
    const value = TextStyle(fontSize: 14, fontFeatures: tabular);
    const unit = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted);

    Widget line(String l, String v, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(l, style: style ?? label)),
          Text(v, style: style ?? value),
        ],
      ),
    );

    final amount = _editing
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 128),
                    child: Focus(
                      onFocusChange: (focused) {
                        if (!focused) _finishEdit();
                      },
                      child: NumberField(
                        key: const ValueKey('driver-fee-field'),
                        decimal: false,
                        autofocus: true,
                        dense: true,
                        semanticLabel: 'ค่ารถคนขับต่อเที่ยว (บาท)',
                        value: pay,
                        onChanged: _type,
                        onSubmitted: _finishEdit,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('บาท/เที่ยว', style: unit),
                  ),
                ),
                IconButton(
                  tooltip: 'เสร็จ',
                  onPressed: _finishEdit,
                  icon: const Icon(Icons.check_circle, color: AppColors.primary),
                ),
              ],
            ),
          )
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatNumber(pay),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const TextSpan(text: ' บาท/เที่ยว', style: unit),
                  ],
                ),
                style: const TextStyle(fontFeatures: tabular),
              ),
              if (canEdit)
                TextButton.icon(
                  key: const ValueKey('driver-fee-edit'),
                  onPressed: () => _startEdit(rate.perTrip),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('ปรับ'),
                ),
            ],
          );

    return Container(
      key: const ValueKey('driver-pay'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.4),
        border: Border.all(
          color: adjusted ? AppColors.warning.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          const Text(
                            'ค่ารถคนขับเที่ยวนี้ · บอกคนขับตอนโทร',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary),
                          ),
                          if (adjusted) const AppBadge('ปรับเอง', tone: BadgeTone.warning),
                        ],
                      ),
                      amount,
                      if (widget.trips > 1)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: 'รวม ${widget.trips} เที่ยว '),
                              TextSpan(
                                text: formatNumber(pay * widget.trips),
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                              ),
                              const TextSpan(text: ' บาท'),
                            ],
                          ),
                          style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabular),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              border: Border(top: BorderSide(color: AppColors.primary.withValues(alpha: 0.2))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rate.perTrip > 0) ...[
                  line('ค่ารถ ต.${z.name} (รถ $truckSize คิว)', formatNumber(rate.base)),
                  line(
                    rate.extra > 0
                        ? 'ตามระยะ เกิน ${formatNumber(delivery.nearKm)} กม. คิด $km กม. × ${formatNumber(perKmFor(truckSize, delivery))}'
                        : 'ตามระยะ (ไม่เกิน ${formatNumber(delivery.nearKm)} กม. ไม่คิดเพิ่ม)',
                    rate.extra > 0 ? '+${formatNumber(rate.extra)}' : '0',
                  ),
                ] else
                  Text(
                    'ต.${z.name} ยังไม่ได้ตั้งค่ารถ ใช้ค่ารถที่ใส่เอง',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                if (adjusted && rate.perTrip > 0)
                  line(
                    '${diff > 0 ? 'ปรับเพิ่ม' : 'ปรับลด'} (ระบบคำนวณ ${formatNumber(rate.perTrip)})',
                    '${diff > 0 ? '+' : '−'}${formatNumber(diff.abs())}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.warning,
                      fontFeatures: tabular,
                    ),
                  ),
                if (edited != null && rate.perTrip > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('driver-fee-reset'),
                      onPressed: _reset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'ใช้ค่ารถตามระบบ (${formatNumber(rate.perTrip)} บาท/เที่ยว)',
                        style: const TextStyle(fontSize: 14, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                if (other > 0)
                  Text(
                    'ถ้าใช้รถ $otherSize คิว: ${formatNumber(other)} บาท/เที่ยว',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (hint != null)
            Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: active ? AppColors.primary : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: BorderSide(color: active ? AppColors.primary : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadius),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
