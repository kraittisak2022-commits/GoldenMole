import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calc/pricing.dart';
import '../../calc/trips.dart';
import '../../logic/format.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

const _perTripOptions = [3, 5];

/// The biggest truck carries 5 คิว, so a larger custom load could never be delivered.
const _maxPerTrip = 5;
const _categories = [ProductCategory.sand, ProductCategory.stone];

class StepProducts extends StatefulWidget {
  const StepProducts({super.key, required this.products, required this.loads, required this.onChange});
  final List<Product> products;
  final Map<String, Load> loads;
  final ValueChanged<Map<String, Load>> onChange;

  @override
  State<StepProducts> createState() => _StepProductsState();
}

class _StepProductsState extends State<StepProducts> {
  late final Set<ProductCategory> _open = {
    for (final p in widget.products)
      if (p.active && (quantitiesOf(widget.loads)[p.id] ?? 0) > 0) p.category,
  };

  void _setLoad(String id, Load? load) {
    final next = Map<String, Load>.from(widget.loads);
    if (load != null && load.perTrip > 0) {
      next[id] = load;
    } else {
      next.remove(id);
    }
    widget.onChange(next);
  }

  void _setPerTrip(String id, num? perTrip) {
    final cur = widget.loads[id];
    if (perTrip == null) return _setLoad(id, null);
    final trips = cur?.trips ?? 0;
    _setLoad(id, Load(perTrip: perTrip, trips: trips < 1 ? 1 : trips));
  }

  void _setTrips(String id, num trips) {
    final cur = widget.loads[id];
    if (cur == null) return;
    _setLoad(id, Load(perTrip: cur.perTrip, trips: trips < 0 ? 0 : trips.floor()));
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.products.where((p) => p.active).toList();
    final quantities = quantitiesOf(widget.loads);
    final loads = widget.loads.values.toList();
    final sum = active.fold<double>(0, (s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id] ?? 0));
    final count = totalQuantity(quantities);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('เลือกสินค้า', subtitle: 'เลือกหมวด ทราย หรือ หิน แล้วเลือกคิวต่อเที่ยวและจำนวนเที่ยว'),
        const SizedBox(height: 24),
        if (active.isEmpty) const AppCard(child: EmptyState('ยังไม่มีสินค้า เพิ่มได้ที่หน้าตั้งค่า')),
        for (final c in _categories)
          if (active.any((p) => p.category == c)) ...[
            _category(c, active.where((p) => p.category == c).toList(), quantities),
            const SizedBox(height: 12),
          ],
        if (count > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'รวม ${formatNumber(count)} คิว · ${totalTrips(loads)} เที่ยว · รถ ${truckForLoads(loads)} คิว',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                Text(
                  '${formatMoney(sum)} บาท',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _category(ProductCategory c, List<Product> list, Map<String, double> quantities) {
    final isOpen = _open.contains(c);
    final picked = list.where((p) => (quantities[p.id] ?? 0) > 0).toList();
    final pickedQty = picked.fold<double>(0, (s, p) => s + quantities[p.id]!);
    final pickedSum = picked.fold<double>(0, (s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id]!));
    return AppCard(
      borderColor: picked.isNotEmpty ? AppColors.ink : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => isOpen ? _open.remove(c) : _open.add(c)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          Text(
                            picked.isNotEmpty
                                ? 'เลือก ${picked.length} รายการ · ${formatNumber(pickedQty)} คิว'
                                : list.map((p) => p.name).join(' · '),
                            style: const TextStyle(fontSize: 14, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (picked.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          formatMoney(pickedSum),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                        ),
                      ),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isOpen)
            for (final p in list) ...[
              const Divider(height: 1),
              _ProductCard(
                product: p,
                load: widget.loads[p.id],
                qty: quantities[p.id] ?? 0,
                onPerTrip: (n) => _setPerTrip(p.id, n),
                onTrips: (n) => _setTrips(p.id, n),
              ),
            ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.load,
    required this.qty,
    required this.onPerTrip,
    required this.onTrips,
  });
  final Product product;
  final Load? load;
  final double qty;

  /// null clears the product.
  final ValueChanged<num?> onPerTrip;
  final ValueChanged<num> onTrips;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  late bool _custom;
  late final TextEditingController _customText;

  @override
  void initState() {
    super.initState();
    final l = widget.load;
    _custom = l != null && !_perTripOptions.contains(l.perTrip);
    _customText = TextEditingController(text: _custom ? formatNumber(l!.perTrip) : '');
  }

  @override
  void dispose() {
    _customText.dispose();
    super.dispose();
  }

  bool get _customInvalid {
    final t = _customText.text.trim();
    final n = double.tryParse(t) ?? 0;
    return t.isNotEmpty && !(n > 0 && n <= _maxPerTrip);
  }

  void _pickQuick(int n) {
    final picked = !_custom && widget.load?.perTrip == n;
    setState(() {
      _custom = false;
      _customText.clear();
    });
    widget.onPerTrip(picked ? null : n);
  }

  void _toggleCustom() {
    final l = widget.load;
    if (_custom) {
      setState(() {
        _custom = false;
        _customText.clear();
      });
      if (l != null && !_perTripOptions.contains(l.perTrip)) widget.onPerTrip(null);
      return;
    }
    setState(() => _custom = true);
    if (l != null) widget.onPerTrip(null);
  }

  void _typeCustom(String text) {
    setState(() {});
    final n = double.tryParse(text.trim()) ?? 0;
    widget.onPerTrip(n > 0 && n <= _maxPerTrip ? n : null);
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: active,
          child: Material(
            color: active ? AppColors.ink : AppColors.subtle,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: active ? Colors.white : AppColors.ink,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final l = widget.load;
    final qty = widget.qty;
    final onTrips = widget.onTrips;
    Widget round(IconData icon, String tip, VoidCallback? onTap, {bool dark = false}) => Tooltip(
          message: tip,
          child: Material(
            color: onTap == null
                ? (dark ? AppColors.ink : AppColors.subtle).withValues(alpha: 0.3)
                : (dark ? AppColors.ink : AppColors.subtle),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon, size: 20, color: dark ? Colors.white : AppColors.ink),
              ),
            ),
          ),
        );
    return Container(
      color: qty > 0 ? AppColors.primarySoft.withValues(alpha: 0.4) : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    Text(
                      '${formatNumber(p.pricePerUnit)} บาท / ${p.unit}',
                      style: const TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    if (l != null)
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'รวม ${formatNumber(qty)} คิว'),
                          if (qty > 0)
                            TextSpan(
                              text: ' · ${formatMoney(lineAmount(p.pricePerUnit, qty))}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                        ]),
                        style: const TextStyle(fontSize: 14, fontFeatures: tabular),
                      )
                    else
                      const Text('เลือกคิวต่อเที่ยวก่อน', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('จำนวนเที่ยว', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      round(
                        Icons.remove,
                        'ลดเที่ยว ${p.name}',
                        l == null || l.trips <= 0 ? null : () => onTrips(l.trips - 1),
                      ),
                      SizedBox(
                        width: 52,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            inputDecorationTheme: const InputDecorationTheme(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: UnderlineInputBorder(),
                              disabledBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                          child: NumberField(
                            value: l?.trips ?? 0,
                            decimal: false,
                            enabled: l != null,
                            dense: true,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                            semanticLabel: 'จำนวนเที่ยว ${p.name}',
                            onChanged: onTrips,
                          ),
                        ),
                      ),
                      round(
                        Icons.add,
                        'เพิ่มเที่ยว ${p.name}',
                        l == null ? null : () => onTrips(l.trips + 1),
                        dark: true,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('คิวต่อเที่ยว', style: TextStyle(fontSize: 14, color: AppColors.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final n in _perTripOptions) ...[
                _chip('$n คิว', !_custom && l?.perTrip == n, () => _pickQuick(n)),
                const SizedBox(width: 8),
              ],
              _chip('อื่นๆ', _custom, _toggleCustom),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customText,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    style: const TextStyle(fontFeatures: tabular),
                    decoration: InputDecoration(
                      hintText: 'เช่น 2 หรือ 2.5',
                      isDense: true,
                      errorText: _customInvalid ? 'ใส่ได้ไม่เกิน $_maxPerTrip คิวต่อเที่ยว (รถใหญ่สุด 5 คิว)' : null,
                    ),
                    onChanged: _typeCustom,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('คิว / เที่ยว', style: TextStyle(fontSize: 14, color: AppColors.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
