import 'package:flutter/material.dart';

import '../../calc/pricing.dart';
import '../../logic/format.dart';
import '../../logic/order_draft.dart';
import '../../logic/wizard_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../tour/tour_controller.dart';
import '../../widgets/ui.dart';
import 'step_fulfillment.dart' show WizardPatch;
import 'wizard_widgets.dart';

Totals wizardTotals(WizardState s, List<OrderItem> items) => draftTotals(
  items: items,
  fulfillment: s.fulfillment ?? Fulfillment.pickup,
  feePerCubic: s.feePerCubic,
  feePerTrip: s.feePerTrip,
  trips: s.trips,
  remoteSurcharge: s.remoteSurcharge,
  deliveryDiscount: s.deliveryDiscount,
  discountType: s.discountType,
  discountValue: s.discountValue,
);

const paymentMethodIcons = {
  PaymentMethod.cash: Icons.payments_outlined,
  PaymentMethod.transfer: Icons.account_balance_outlined,
  PaymentMethod.cod: Icons.account_balance_wallet_outlined,
  PaymentMethod.credit: Icons.event_repeat_outlined,
};

const _methodHints = {
  PaymentMethod.cash: 'รับเงินสดแล้ว',
  PaymentMethod.transfer: 'โอน / พร้อมเพย์',
  PaymentMethod.cod: 'เก็บเงินตอนส่งของ',
  PaymentMethod.credit: 'รวมบิลเคลียร์สิ้นเดือน',
};

class StepSummary extends StatefulWidget {
  const StepSummary({super.key, required this.state, required this.patch, required this.items});
  final WizardState state;
  final WizardPatch patch;
  final List<OrderItem> items;

  @override
  State<StepSummary> createState() => _StepSummaryState();
}

class _StepSummaryState extends State<StepSummary> {
  late final _note = TextEditingController(text: widget.state.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final items = widget.items;
    final patch = widget.patch;
    final totals = wizardTotals(s, items);
    final delivery = s.fulfillment == Fulfillment.delivery;
    const muted = TextStyle(fontSize: 14, color: AppColors.muted);
    const success = TextStyle(fontSize: 14, color: AppColors.success, fontFeatures: tabular);

    Widget discountRow({
      required String label,
      required num value,
      required ValueChanged<double> onChanged,
      required String semantic,
      String? result,
    }) => Row(
      children: [
        Text(label, style: muted),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: NumberField(
            value: value,
            dense: true,
            textAlign: TextAlign.right,
            semanticLabel: semantic,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        const Text('บาท', style: muted),
        if (result != null)
          Expanded(
            child: Text(result, textAlign: TextAlign.right, style: success),
          )
        else
          const Spacer(),
      ],
    );

    Widget amountColumn(double amount, double off) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatMoney(amount),
          style: TextStyle(
            fontSize: 14,
            fontFeatures: tabular,
            color: off != 0 ? AppColors.muted : AppColors.ink,
            decoration: off != 0 ? TextDecoration.lineThrough : null,
          ),
        ),
        if (off != 0)
          Text(
            formatMoney(amount - off),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFeatures: tabular),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle('สรุปยอดและการชำระเงิน', subtitle: s.source == null ? null : 'ออเดอร์${s.source!.label}'),
        const SizedBox(height: 20),
        TourTarget(
          'wiz-totals',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final it = items[i];
                      final load = it.productId == null ? null : s.loads[it.productId];
                      final off = lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                      Text(it.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                      if (load != null)
                                        Text(
                                          '${formatNumber(load.perTrip)} ${it.unit} × ${load.trips} เที่ยว = '
                                          '${formatNumber(it.quantity)} ${it.unit}',
                                          style: muted,
                                        ),
                                      Text(
                                        '${formatNumber(it.quantity)} ${it.unit} × ${formatNumber(it.unitPrice)} บาท',
                                        style: muted,
                                      ),
                                    ],
                                  ),
                                ),
                                amountColumn(it.amount, off),
                              ],
                            ),
                            if (it.productId != null) ...[
                              const SizedBox(height: 8),
                              discountRow(
                                label: 'ลดคิวละ',
                                value: s.unitDiscounts[it.productId] ?? 0,
                                semantic: 'ส่วนลดต่อ${it.unit} ${it.name}',
                                result: off != 0
                                    ? 'เหลือคิวละ ${formatNumber(it.unitPrice - it.discountPerUnit)} · ลด ${formatMoney(off)}'
                                    : null,
                                onChanged: (v) => patch((st) {
                                  final clamped = v < 0 ? 0.0 : (v > it.unitPrice ? it.unitPrice : v);
                                  return st.copyWith(unitDiscounts: {...st.unitDiscounts, it.productId!: clamped});
                                }),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
                if (delivery) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  const Text('ค่าจัดส่ง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                  Text(
                                    '${deliveryFeeFormula(feePerCubic: s.feePerCubic, cubic: totals.totalQuantity, feePerTrip: s.feePerTrip, trips: s.trips, remoteSurcharge: 0)}'
                                    '${s.remoteSurcharge != 0 ? ' + ที่กันดาร ${formatNumber(s.remoteSurcharge)}' : ''}',
                                    style: muted,
                                  ),
                                ],
                              ),
                            ),
                            amountColumn(totals.deliveryTotal, totals.deliveryDiscount),
                          ],
                        ),
                        const SizedBox(height: 8),
                        discountRow(
                          label: 'ลดค่าส่ง',
                          value: s.deliveryDiscount,
                          semantic: 'ส่วนลดค่าส่ง (บาท)',
                          result: totals.deliveryDiscount != 0
                              ? 'เหลือ ${formatMoney(totals.deliveryTotal - totals.deliveryDiscount)}'
                              : null,
                          onChanged: (v) => patch(
                            (st) => st.copyWith(
                              deliveryDiscount: v < 0 ? 0 : (v > totals.deliveryTotal ? totals.deliveryTotal : v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('ส่วนลดท้ายบิล', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 128,
                            child: Segmented<DiscountType>(
                              values: DiscountType.values,
                              selected: s.discountType,
                              labelOf: (t) => t == DiscountType.baht ? 'บาท' : '%',
                              onChanged: (t) {
                                if (t != s.discountType) patch((st) => st.copyWith(discountType: t, discountValue: 0));
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: NumberField(
                              value: s.discountValue,
                              semanticLabel: 'ส่วนลด',
                              onChanged: (v) => patch((st) {
                                final x = v < 0 ? 0.0 : v;
                                return st.copyWith(
                                  discountValue: st.discountType == DiscountType.percent && x > 100 ? 100 : x,
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                      if (s.discountType == DiscountType.percent)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '% คิดจากค่าสินค้าเท่านั้น ไม่รวมค่าส่ง',
                            style: TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TotalsBlock(totals: totals, delivery: delivery),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        TourTarget(
          'wiz-payment',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('วิธีชำระเงิน *', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
              const SizedBox(height: 12),
              for (final row in [
                [PaymentMethod.cash, PaymentMethod.transfer],
                [PaymentMethod.cod, PaymentMethod.credit],
              ]) ...[
                Row(
                  children: [
                    for (final m in row) ...[
                      if (m != row.first) const SizedBox(width: 12),
                      Expanded(child: _methodCard(m, s.paymentMethod == m)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (s.paymentMethod != null && s.paymentMethod != PaymentMethod.credit)
                CheckRow(
                  value: s.paidNow,
                  onChanged: (v) => patch((st) => st.copyWith(paidNow: v)),
                  child: const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'ได้รับเงินแล้ว',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' — ออกใบเสร็จรับเงินทันที'),
                      ],
                    ),
                  ),
                ),
              if (s.paymentMethod == PaymentMethod.credit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(kRadius)),
                  child: const Text(
                    'ออกใบส่งของก่อน แล้วรวมยอดไปเคลียร์ในใบวางบิลรายเดือน',
                    style: TextStyle(fontSize: 14, color: AppColors.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FieldLabel(
          'หมายเหตุ',
          child: TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'เช่น ส่งช่วงเช้า เทกองหน้าบ้าน'),
            onChanged: (v) => patch((st) => st.copyWith(note: v)),
          ),
        ),
      ],
    );
  }

  Widget _methodCard(PaymentMethod m, bool active) {
    return Material(
      color: active ? AppColors.primarySoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: active ? AppColors.primary : AppColors.border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.patch((st) => st.copyWith(paymentMethod: m, paidNow: defaultPaidNow(m))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(paymentMethodIcons[m], size: 22, color: active ? AppColors.primary : AppColors.muted),
                const SizedBox(height: 4),
                Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(_methodHints[m]!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtotal, delivery, discounts and net total.
class TotalsBlock extends StatelessWidget {
  const TotalsBlock({super.key, required this.totals, required this.delivery, this.large = false});
  final Totals totals;
  final bool delivery;
  final bool large;

  @override
  Widget build(BuildContext context) {
    const green = AppColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoRow('ค่าสินค้า', formatMoney(totals.subtotal)),
        if (delivery) InfoRow('ค่าจัดส่ง', formatMoney(totals.deliveryTotal)),
        if (totals.itemDiscount != 0)
          InfoRow('ส่วนลดต่อคิว', '-${formatMoney(totals.itemDiscount)}', valueColor: green),
        if (totals.deliveryDiscount != 0)
          InfoRow('ส่วนลดค่าส่ง', '-${formatMoney(totals.deliveryDiscount)}', valueColor: green),
        if (totals.billDiscount > 0)
          InfoRow('ส่วนลดท้ายบิล', '-${formatMoney(totals.billDiscount)}', valueColor: green),
        if (!large) const Divider(height: 16),
        Padding(
          padding: EdgeInsets.only(top: large ? 8 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text('ยอดสุทธิ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Text(
                large ? '${formatMoney(totals.total)} บาท' : formatMoney(totals.total),
                style: TextStyle(
                  fontSize: large ? 28 : 24,
                  fontWeight: FontWeight.w700,
                  color: large ? AppColors.ink : AppColors.primary,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
