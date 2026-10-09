import 'package:flutter/material.dart';

import '../../calc/pricing.dart';
import '../../logic/format.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'step_summary.dart';
import 'wizard_widgets.dart';

class StepConfirm extends StatelessWidget {
  const StepConfirm({
    super.key,
    required this.state,
    required this.items,
    required this.zone,
    required this.driver,
    required this.onEdit,
  });
  final WizardState state;
  final List<OrderItem> items;
  final Zone? zone;
  final Driver? driver;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = s.customer;
    final totals = wizardTotals(s, items);
    final delivery = s.fulfillment == Fulfillment.delivery;
    final paidLabel = s.paymentMethod == PaymentMethod.credit
        ? 'ค้างเครดิต (เคลียร์รายเดือน)'
        : s.paidNow
            ? 'จ่ายแล้ว — ออกใบเสร็จ'
            : 'ยังไม่จ่าย';
    const muted = TextStyle(fontSize: 14, color: AppColors.muted);
    const strong = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);
    final customerLine =
        [if ((c?.phone ?? '').isNotEmpty) formatPhone(c!.phone), if ((c?.address ?? '').isNotEmpty) c!.address].join(' · ');

    final blocks = <Widget>[
      _Block(
        title: 'ประเภทและวันที่',
        onEdit: () => onEdit(stepIndex(StepKey.source)),
        children: [
          Text(s.source == null ? '—' : 'ออเดอร์${s.source!.label}', style: strong),
          Text('เลขที่ใบส่งของขึ้นต้นด้วย ${s.source == OrderSource.pit ? 'TS' : 'DO'}', style: muted),
          Text(
            'วันที่ออเดอร์ ${formatDateLongTh(s.orderDate.isEmpty ? toIsoDate() : s.orderDate)}'
            '${s.orderDate.isEmpty ? ' (วันนี้)' : ''}',
            style: s.orderDate.isEmpty
                ? muted
                : const TextStyle(fontSize: 14, color: AppColors.warning, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      _Block(
        title: 'สินค้า',
        onEdit: () => onEdit(stepIndex(StepKey.products)),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(text: it.name),
                          TextSpan(
                            text: ' × ${formatNumber(it.quantity)} ${it.unit}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ])),
                        if (it.discountPerUnit != 0)
                          Text(
                            'ลดคิวละ ${formatNumber(it.discountPerUnit)} บาท',
                            style: const TextStyle(fontSize: 12, color: AppColors.success),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (it.discountPerUnit != 0)
                        Text(
                          formatMoney(it.amount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      Text(
                        formatMoney(it.amount - lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit)),
                        style: const TextStyle(fontFeatures: tabular),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      _Block(
        title: 'ลูกค้า',
        onEdit: () => onEdit(stepIndex(StepKey.customer)),
        children: [
          Text(c?.name ?? '—', style: strong),
          Text(customerLine.isEmpty ? '—' : customerLine, style: muted),
        ],
      ),
      _Block(
        title: 'การรับสินค้า',
        onEdit: () => onEdit(stepIndex(StepKey.fulfillment)),
        children: delivery
            ? [
                Text('จัดส่ง · ต.${zone?.name ?? '—'} · รถ ${s.truckSize} คิว × ${s.trips} เที่ยว', style: strong),
                if (s.deliveryAddress.isNotEmpty) Text(s.deliveryAddress, style: muted),
                Text(
                  'ค่าส่ง ${deliveryFeeFormula(feePerCubic: s.feePerCubic, cubic: totals.totalQuantity, feePerTrip: s.feePerTrip, trips: s.trips, remoteSurcharge: s.remoteSurcharge)}'
                  ' = ${formatMoney(totals.deliveryTotal)}'
                  '${s.roadDistanceKm != null ? ' · ${s.roadDistanceByRoad ? 'ระยะตามถนนจากถนนใหญ่' : 'ห่างถนนใหญ่ (เส้นตรง)'}'
                      ' ${formatNumber(s.roadDistanceKm)} กม.' : ''}',
                  style: muted,
                ),
                Text('คนขับ: ${driver?.name ?? 'ยังไม่ระบุ'}', style: muted),
              ]
            : const [Text('มารับเองที่ท่าทราย', style: strong)],
      ),
      _Block(
        title: 'ชำระเงิน',
        onEdit: () => onEdit(stepIndex(StepKey.summary)),
        children: [
          Text(s.paymentMethod?.label ?? '—', style: strong),
          Text(paidLabel, style: muted),
          if (s.note.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('หมายเหตุ: ${s.note}', style: muted)),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('ตรวจสอบก่อนออกบิล', subtitle: "แตะ 'แก้ไข' เพื่อกลับไปแก้ขั้นตอนนั้น"),
        const SizedBox(height: 16),
        const Divider(height: 1),
        for (final b in blocks) ...[b, const Divider(height: 1)],
        const SizedBox(height: 20),
        TotalsBlock(totals: totals, delivery: delivery, large: true),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.onEdit, required this.children});
  final String title;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
              TextButton(onPressed: onEdit, child: const Text('แก้ไข')),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}
