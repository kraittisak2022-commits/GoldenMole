import 'package:flutter/material.dart';

import '../../calc/pricing.dart';
import '../../calc/trips.dart';
import '../../logic/format.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

const _perTripOptions = [1, 2, 3, 4, 5];

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

  void _pickPerTrip(String id, int perTrip) {
    final cur = widget.loads[id];
    if (cur?.perTrip == perTrip) return _setLoad(id, null);
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
        const StepTitle('เลือกสินค้า', subtitle: 'เลือกหมวด หิน หรือ ทราย แล้วเลือกคิวต่อเที่ยวและจำนวนเที่ยว'),
        const SizedBox(height: 24),
        if (active.isEmpty) const AppCard(child: EmptyState('ยังไม่มีสินค้า เพิ่มได้ที่หน้าตั้งค่า')),
        for (final c in ProductCategory.values)
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
                onPerTrip: (n) => _pickPerTrip(p.id, n),
                onTrips: (n) => _setTrips(p.id, n),
              ),
            ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
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
  final ValueChanged<int> onPerTrip;
  final ValueChanged<num> onTrips;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final l = load;
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
                if (n != _perTripOptions.first) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: l?.perTrip == n ? AppColors.ink : AppColors.subtle,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => onPerTrip(n),
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Text(
                            '$n คิว',
                            style: TextStyle(
                              fontSize: 14,
                              color: l?.perTrip == n ? Colors.white : AppColors.ink,
                              fontWeight: l?.perTrip == n ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
