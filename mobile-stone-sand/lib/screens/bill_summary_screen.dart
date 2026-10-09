import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/catalog_scope.dart';
import '../data/orders_repo.dart';
import '../logic/bill_summary.dart';
import '../logic/format.dart';
import '../logic/order_status.dart' show matchesSearch;
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../widgets/loader.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';
import 'orders_screen.dart' show OrderRange;

enum _Sort {
  latest('ล่าสุดก่อน'),
  oldest('เก่าสุดก่อน'),
  netDesc('เหลือมากสุด'),
  netAsc('เหลือน้อยสุด'),
  receivable('ค้างรับมากสุด');

  const _Sort(this.label);
  final String label;
}

/// null = ทั้งหมด, [_openOnly] = ต้องตามงาน, otherwise one stage.
const _openOnly = 'open';

class _Row {
  _Row(this.order, this.summary, this.driverName);
  final Order order;
  final BillSummary summary;
  final String driverName;
}

class BillSummaryScreen extends StatefulWidget {
  const BillSummaryScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<BillSummaryScreen> createState() => _BillSummaryScreenState();
}

class _BillSummaryScreenState extends State<BillSummaryScreen> with ReloadOnDataChange {
  late OrderRange _range = OrderRange.parse(widget.params['r']);
  late OrderSource? _source = OrderSource.tryParse(widget.params['source']);
  late String? _stage = widget.params['stage'];
  _Sort _sort = _Sort.latest;
  final _query = TextEditingController();
  late final _orders = Loader<List<Order>>(() => listOrders(from: _range.from(), limit: 2000));

  @override
  List<Loader<dynamic>> get loaders => [_orders];

  @override
  void initState() {
    super.initState();
    _orders.load();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _orders.dispose();
    _query.dispose();
    super.dispose();
  }

  void _setRange(OrderRange r) {
    if (r == _range) return;
    setState(() => _range = r);
    _orders.load();
  }

  bool _matchesStage(BillStage s) => switch (_stage) {
        null => true,
        _openOnly => s.isOpen,
        final id => s.name == id,
      };

  List<_Row> _sorted(List<_Row> rows) {
    int byDate(_Row a, _Row b) {
      final d = a.order.orderDate.compareTo(b.order.orderDate);
      return d != 0 ? d : a.order.createdAt.compareTo(b.order.createdAt);
    }

    final list = [...rows];
    switch (_sort) {
      case _Sort.latest:
        list.sort((a, b) => byDate(b, a));
      case _Sort.oldest:
        list.sort(byDate);
      case _Sort.netDesc:
        list.sort((a, b) => b.summary.net.compareTo(a.summary.net));
      case _Sort.netAsc:
        list.sort((a, b) => a.summary.net.compareTo(b.summary.net));
      case _Sort.receivable:
        list.sort((a, b) => b.summary.receivable.compareTo(a.summary.receivable));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final locked = AuthScope.of(context).lockedSource;
    final catalog = CatalogScope.of(context);
    final source = locked != null ? null : _source;
    final width = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: _orders,
      builder: (context, _) {
        final orders = _orders.data ?? const <Order>[];
        final rows = [
          for (final o in orders)
            _Row(
              o,
              summarizeBill(o, zone: catalog.zoneById(o.zoneId), delivery: catalog.settings.delivery),
              catalog.driverById(o.driverId)?.name ?? '',
            ),
        ];
        final query = _query.text;
        final sourceCounts = {for (final s in OrderSource.values) s: rows.where((r) => r.order.source == s).length};
        final searched =
            rows.where((r) => (source == null || r.order.source == source) && matchesSearch(r.order, query)).toList();
        final stageCounts = {for (final s in BillStage.values) s: searched.where((r) => r.summary.stage == s).length};
        final openCount = searched.where((r) => r.summary.stage.isOpen).length;
        final visible = _sorted(searched.where((r) => _matchesStage(r.summary.stage)).toList());
        final totals = totalBills(searched.map((r) => r.summary));
        final visibleTotals = totalBills(visible.map((r) => r.summary));
        final margin = netMargin(totals.net, totals.revenue);
        final losses = searched
            .where((r) => r.summary.deliveryMargin < 0 && r.summary.stage != BillStage.cancelled)
            .length;

        final search = TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'ค้นหาชื่อ ชื่อเรียก เบอร์โทร หรือเลขที่บิล',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(tooltip: 'ล้างคำค้น', icon: const Icon(Icons.close, size: 18), onPressed: _query.clear),
          ),
        );
        final rangeSelect = DropdownButtonFormField<OrderRange>(
          initialValue: _range,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.date_range_outlined, size: 20)),
          items: [for (final r in OrderRange.values) DropdownMenuItem(value: r, child: Text(r.label))],
          onChanged: (r) => r == null ? null : _setRange(r),
        );
        final sortSelect = DropdownButtonFormField<_Sort>(
          initialValue: _sort,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.sort, size: 20)),
          items: [for (final s in _Sort.values) DropdownMenuItem(value: s, child: Text(s.label))],
          onChanged: (s) => s == null ? null : setState(() => _sort = s),
        );

        Widget chip(String label, int count, String? id) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CountChip(label: label, count: count, active: _stage == id, onTap: () => setState(() => _stage = id)),
            );

        return PageScroll(
          onRefresh: _orders.load,
          children: [
            const PageHeader(
              title: 'สรุปบิล',
              subtitle: 'แต่ละบิลได้ค่าของเท่าไร หักค่ารถเท่าไร เหลือเข้าร้านเท่าไร และติดขั้นตอนไหน',
            ),
            if (width >= 600)
              Row(children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                SizedBox(width: 180, child: rangeSelect),
                const SizedBox(width: 8),
                SizedBox(width: 190, child: sortSelect),
              ])
            else ...[
              search,
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: rangeSelect),
                const SizedBox(width: 8),
                Expanded(child: sortSelect),
              ]),
            ],
            const SizedBox(height: 12),
            if (locked == null) ...[
              Segmented<OrderSource?>(
                values: const [null, OrderSource.shop, OrderSource.pit],
                selected: source,
                labelOf: (s) => s?.short ?? 'ทั้งหมด',
                trailingOf: (s) => '${s == null ? rows.length : sourceCounts[s]}',
                onChanged: (s) => setState(() => _source = s),
              ),
              const SizedBox(height: 12),
            ],
            if (_orders.error != null) ...[ErrorBox(_orders.error!, onRetry: _orders.load), const SizedBox(height: 12)],
            GridRows(
              columns: width >= 1024 ? 3 : 2,
              children: [
                KpiCard(
                  label: 'ยอดบิลรวม',
                  value: formatMoney(totals.revenue),
                  hint: '${totals.count} บิล',
                  pending: _orders.pending,
                ),
                KpiCard(label: 'ค่าสินค้า', value: formatMoney(totals.goods), hint: 'หลังหักส่วนลด', pending: _orders.pending),
                KpiCard(
                  label: 'ค่าส่งเก็บลูกค้า',
                  value: formatMoney(totals.deliveryFee),
                  hint: 'หลังหักส่วนลดค่าส่ง',
                  pending: _orders.pending,
                ),
                KpiCard(
                  label: 'หักค่ารถคนขับ',
                  value: formatMoney(totals.driverCost),
                  hint: totals.driverCostPending > 0 ? 'ยังไม่จ่าย ${formatMoney(totals.driverCostPending)}' : 'จ่ายครบแล้ว',
                  pending: _orders.pending,
                ),
                KpiCard(
                  label: 'คงเหลือเข้าร้าน',
                  value: formatMoney(totals.net),
                  hint: margin != null ? '$margin% ของยอดบิล' : null,
                  valueColor: AppColors.success,
                  pending: _orders.pending,
                ),
                KpiCard(
                  label: 'ค้างรับ',
                  value: formatMoney(totals.receivable),
                  hint: 'รับแล้ว ${formatMoney(totals.received)}',
                  warn: totals.receivable > 0,
                  pending: _orders.pending,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (losses > 0) ...[
              AppCard(
                color: AppColors.warningSoft,
                borderColor: AppColors.warning.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'มี $losses บิลที่ค่ารถคนขับสูงกว่าค่าส่งที่เก็บลูกค้า (ขาดทุนค่าส่ง) เรียง "เหลือน้อยสุด" เพื่อดู',
                        style: const TextStyle(fontSize: 14, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  chip('ทั้งหมด', searched.length, null),
                  chip('ต้องตามงาน', openCount, _openOnly),
                  for (final s in BillStage.values)
                    if ((stageCounts[s] ?? 0) > 0 || _stage == s.name) chip(s.label, stageCounts[s] ?? 0, s.name),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_orders.pending)
              const LoadingList()
            else if (visible.isEmpty)
              AppCard(child: EmptyState(query.isNotEmpty ? 'ไม่พบบิลที่ค้นหา' : 'ยังไม่มีบิลในช่วงนี้'))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      BillTile(order: visible[i].order, summary: visible[i].summary, driverName: visible[i].driverName),
                    ],
                    Container(
                      color: AppColors.subtle.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Text('${visible.length} รายการ', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                          const Spacer(),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'ยอดบิล ${formatMoney(visibleTotals.revenue)} · เหลือ '),
                              TextSpan(
                                text: formatMoney(visibleTotals.net),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                              ),
                            ]),
                            style: const TextStyle(fontSize: 13, fontFeatures: tabular),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'ค่ารถที่มีเครื่องหมาย ≈ คือค่ารถที่ยังไม่ได้จ่ายคนขับ ยอดจริงจะใช้ตามที่บันทึกตอนเคลียร์ค่ารถ · บิลที่ยกเลิกไม่นับรวมยอด',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class BillTile extends StatelessWidget {
  const BillTile({super.key, required this.order, required this.summary, this.driverName = ''});
  final Order order;
  final BillSummary summary;
  final String driverName;

  ({String label, VoidCallback onTap})? _action(BuildContext context) {
    final o = order;
    return switch (summary.stage) {
      BillStage.needDriver || BillStage.waitDelivery || BillStage.onTheWay || BillStage.awaitPayment => (
          label: 'เปิดออเดอร์',
          onTap: () => openOrder(context, o.id),
        ),
      BillStage.driverCash || BillStage.payDriver => (
          label: 'ไปเคลียร์ค่ารถ',
          onTap: () => goTo(context, Dest.driverPay, {'driver': o.driverId!}),
        ),
      BillStage.unbilled => (
          label: 'ไปออกใบวางบิล',
          onTap: () => goTo(context, Dest.statements, {'customer': o.customerId, 'source': o.source.name}),
        ),
      BillStage.billed => (
          label: 'ดูใบวางบิล',
          onTap: () => goTo(context, Dest.statements, {'open': o.statementId!}),
        ),
      BillStage.done || BillStage.cancelled => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final s = summary;
    final cancelled = s.stage == BillStage.cancelled;
    final action = _action(context);
    const numStyle = TextStyle(fontSize: 14, fontFeatures: tabular);
    const labelStyle = TextStyle(fontSize: 14, color: AppColors.muted);

    Widget line(String label, Widget value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: style ?? labelStyle, overflow: TextOverflow.ellipsis)),
            value,
          ]),
        );

    final driverCost = s.driverCost == 0 && !s.driverCostEstimated
        ? const Text('—', style: labelStyle)
        : Text(
            '${s.driverCostEstimated ? '≈ ' : ''}−${formatMoney(s.driverCost)}',
            style: numStyle.copyWith(color: s.driverCostEstimated ? AppColors.muted : AppColors.ink),
          );

    return Opacity(
      opacity: cancelled ? 0.6 : 1,
      child: InkWell(
        onTap: () => openOrder(context, o.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                o.customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${o.orderNo} · ${formatDateShort(o.orderDate)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                  ),
                  SourceBadge(o.source),
                  if (o.demo) const DemoBadge(),
                  AppBadge(s.stage.label, tone: s.stage.tone),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    line('ยอดบิล', Text(formatMoney(s.revenue), style: numStyle.copyWith(fontWeight: FontWeight.w500))),
                    line('ค่าสินค้า', Text(formatMoney(s.goods), style: numStyle)),
                    if (o.fulfillment == Fulfillment.delivery) ...[
                      line('ค่าส่งเก็บลูกค้า', Text(formatMoney(s.deliveryFee), style: numStyle)),
                      line(driverName.isEmpty ? 'ค่ารถ' : 'ค่ารถ ($driverName)', driverCost),
                    ],
                    const Divider(height: 12),
                    line(
                      'คงเหลือเข้าร้าน',
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (s.deliveryMargin < 0 && !cancelled) ...[
                          const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          formatMoney(s.net),
                          style: numStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cancelled ? AppColors.muted : AppColors.success,
                          ),
                        ),
                      ]),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    if (s.receivable > 0)
                      line(
                        'ค้างรับ',
                        Text(formatMoney(s.receivable), style: numStyle.copyWith(color: AppColors.warning)),
                        style: const TextStyle(fontSize: 14, color: AppColors.warning),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Steps(steps: s.steps, cancelled: cancelled),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  if (action != null)
                    TextButton.icon(
                      onPressed: action.onTap,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(action.label),
                    ),
                  TextButton.icon(
                    onPressed: () => openOrderBill(context, o.id),
                    style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('ใบส่งของ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.cancelled});
  final List<BillStep> steps;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final shown = steps.where((s) => s.state != BillStepState.skip).toList();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _step(shown[i])),
        ],
      ],
    );
  }

  Widget _step(BillStep step) {
    final color = cancelled
        ? AppColors.border
        : switch (step.state) {
            BillStepState.done => AppColors.success,
            BillStepState.current => AppColors.warning,
            _ => AppColors.border,
          };
    final current = step.state == BillStepState.current && !cancelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(height: 4),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: current ? AppColors.ink : AppColors.muted,
            fontWeight: current ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
