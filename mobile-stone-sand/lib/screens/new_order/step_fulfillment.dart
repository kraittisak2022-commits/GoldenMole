import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calc/delivery_fee.dart';
import '../../calc/trips.dart';
import '../../logic/format.dart';
import '../../logic/geo.dart';
import '../../logic/latlng.dart';
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

double _fee(Zone z, WizardState st, DeliverySettings settings) =>
    suggestDeliveryFee(z.feeMin, st.roadDistanceKm, st.truckSize, settings).toDouble();

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

class StepFulfillment extends StatefulWidget {
  const StepFulfillment({
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
  State<StepFulfillment> createState() => _StepFulfillmentState();
}

class _StepFulfillmentState extends State<StepFulfillment> {
  LatLngValue? _flyTarget;
  bool _locating = false;
  String _geoError = '';
  final _coordText = TextEditingController();
  late final _address = TextEditingController(text: widget.state.deliveryAddress);
  RouteGroup? _group;

  WizardState get s => widget.state;
  List<Load> get _loads => [for (final l in widget.loadLines) l.load];
  Zone? _zoneById(String? id) {
    for (final z in widget.zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant StepFulfillment old) {
    super.didUpdateWidget(old);
    if (s.deliveryAddress != _address.text) _address.text = s.deliveryAddress;
  }

  @override
  void dispose() {
    _coordText.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<WizardState Function(WizardState)> _pinUpdate(LatLngValue p) async {
    final geo = await GeoData.load();
    final tambon = geo.findTambon(p.lat, p.lng);
    final road = geo.distanceToMainRoad(p.lat, p.lng);
    final delivery = widget.settings.delivery;
    return (WizardState st) {
      var next = st.copyWith(
        pinLat: double.parse(p.lat.toStringAsFixed(6)),
        pinLng: double.parse(p.lng.toStringAsFixed(6)),
        outsideDistrict: tambon == null,
        roadDistanceKm: road?.km,
        roadLabel: road?.roadLabel ?? '',
      );
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
      if (!st.feeTouched && feeZone != null) next = next.copyWith(feePerTrip: _fee(feeZone, next, delivery));
      return next;
    };
  }

  Future<void> _onPin(LatLngValue p) async {
    setState(() => _geoError = '');
    final update = await _pinUpdate(p);
    widget.patch(update);
  }

  Future<void> _chooseFulfillment(Fulfillment f, Customer? customer) async {
    WizardState Function(WizardState)? pin;
    if (f == Fulfillment.delivery && !s.hasPin && customer?.lat != null && customer?.lng != null) {
      final p = LatLngValue(customer!.lat!, customer.lng!);
      pin = await _pinUpdate(p);
      setState(() => _flyTarget = p);
    }
    widget.patch((st) {
      var next = st.copyWith(fulfillment: f);
      if (f == Fulfillment.delivery && st.deliveryAddress.trim().isEmpty && (customer?.address ?? '').isNotEmpty) {
        next = next.copyWith(deliveryAddress: customer!.address);
      }
      return pin == null ? next : pin(next);
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
      if (z != null && !st.feeTouched) {
        next = next.copyWith(feePerTrip: _fee(z, st, widget.settings.delivery));
      }
      return next;
    });
  }

  /// The per-km rate depends on the truck size, so an untouched fee follows it.
  WizardState _refee(WizardState st) {
    final z = _zoneById(st.zoneId);
    return z == null || st.feeTouched ? st : st.copyWith(feePerTrip: _fee(z, st, widget.settings.delivery));
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
    final customer = s.customer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('การรับสินค้า', subtitle: 'ลูกค้ามารับเองที่ท่าทราย หรือให้รถไปส่ง'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ChoiceCard(
                active: s.fulfillment == Fulfillment.pickup,
                onTap: () => _chooseFulfillment(Fulfillment.pickup, customer),
                icon: Icons.storefront_outlined,
                title: 'มารับเอง',
                hint: 'ไม่มีค่าส่ง',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceCard(
                active: s.fulfillment == Fulfillment.delivery,
                onTap: () => _chooseFulfillment(Fulfillment.delivery, customer),
                icon: Icons.local_shipping_outlined,
                title: 'จัดส่ง',
                hint: 'ในเขต อ.วังเหนือ',
              ),
            ),
          ],
        ),
        if (s.fulfillment == Fulfillment.delivery) ...[
          const SizedBox(height: 20),
          ..._pinSection(),
          const SizedBox(height: 20),
          _deliveryCard(),
          const SizedBox(height: 20),
          ..._driverSection(),
        ],
        if (s.fulfillment == Fulfillment.pickup) ...[
          const SizedBox(height: 20),
          const AppCard(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ลูกค้ามารับที่ท่าทราย ไม่มีค่าส่ง ระบบจะบันทึกสถานะการส่งเป็น "มารับเอง"',
                    style: TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _pinSection() {
    final zone = _zoneById(s.zoneId);
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
      const Text('แตะบนแผนที่หรือลากหมุด เส้นสีส้มคือถนนสายหลัก', style: TextStyle(fontSize: 14, color: AppColors.muted)),
      const SizedBox(height: 12),
      DeliveryMap(
        value: s.hasPin ? LatLngValue(s.pinLat!, s.pinLng!) : null,
        onChange: _onPin,
        flyTarget: _flyTarget,
        onExpand: _expandMap,
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
                label: 'ห่างถนนใหญ่',
                value: s.roadDistanceKm != null ? '${formatNumber(s.roadDistanceKm)} กม.' : '—',
                hint: s.roadLabel.isEmpty ? null : s.roadLabel,
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
    final deliveryTotal = s.feePerTrip * s.trips + s.remoteSurcharge;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            'ตำบลที่จัดส่ง *',
            hint: zone == null
                ? null
                : 'ค่าส่ง ${formatNumber(zone.feeMin)} บาท/เที่ยว'
                    '${perKmFor(s.truckSize, delivery) > 0 ? ' + ${formatNumber(perKmFor(s.truckSize, delivery))} บาท/กม. '
                        '(รถ ${s.truckSize == 3 ? 3 : 5} คิว) เมื่อห่างถนนใหญ่เกิน ${formatNumber(delivery.nearKm)} กม.' : ''}',
            child: DropdownButtonFormField<String?>(
              key: ValueKey('zone:${s.zoneId}'),
              initialValue: zone?.id,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— เลือกตำบล —')),
                for (final z in widget.zones)
                  DropdownMenuItem<String?>(
                    value: z.id,
                    child: Text('${z.name} (${formatNumber(z.feeMin)})'),
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
                  'ค่าส่ง / เที่ยว',
                  hint: s.feeTouched && zone != null ? null : 'คำนวณจากระยะถึงถนนใหญ่',
                  child: NumberField(
                    value: s.feePerTrip,
                    onChanged: (v) => widget.patch((st) => st.copyWith(feePerTrip: v < 0 ? 0 : v, feeTouched: true)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'ที่กันดาร (บวกเพิ่ม)',
                  child: NumberField(
                    value: s.remoteSurcharge,
                    onChanged: (v) => widget.patch((st) => st.copyWith(remoteSurcharge: v < 0 ? 0 : v)),
                  ),
                ),
              ),
            ],
          ),
          if (s.feeTouched && zone != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.patch(
                  (st) => st.copyWith(feePerTrip: _fee(zone, st, delivery), feeTouched: false),
                ),
                child: Text(
                  'ใช้ค่าส่งที่ระบบแนะนำ (${formatNumber(_fee(zone, s, delivery))})',
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
                    '${formatNumber(s.feePerTrip)} × ${s.trips} เที่ยว'
                    '${s.remoteSurcharge != 0 ? ' + ${formatNumber(s.remoteSurcharge)}' : ''}',
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

    return [
      const Text('คนขับ (ไม่บังคับ)', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
      const Text(
        'โทรเช็คคิวก่อน แล้วเลือกคนขับ ระบุภายหลังในหน้าออเดอร์ได้',
        style: TextStyle(fontSize: 14, color: AppColors.muted),
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
            if (shown.isEmpty) const EmptyState('ไม่มีคนขับในสายนี้'),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'ยืนยันว่ารถ '),
                TextSpan(text: selected.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' เข้าหน้างานได้และมีคิวว่าง'),
              ])),
              if (selected.wagePerTrip != 0)
                Text(
                  'ค่าจ้างคนขับ ${formatNumber(selected.wagePerTrip)} × ${s.trips} = '
                  '${formatMoney(selected.wagePerTrip * s.trips)} บาท',
                  style: const TextStyle(color: AppColors.muted),
                ),
            ],
          ),
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
