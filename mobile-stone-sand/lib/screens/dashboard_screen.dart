import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/orders_repo.dart';
import '../logic/format.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../tour/tour_controller.dart';
import '../tour/tour_steps.dart';
import '../widgets/calendar_picker.dart';
import '../widgets/loader.dart';
import '../widgets/order_row.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with ReloadOnDataChange {
  late String _date;
  late final Loader<List<Order>> _month;
  final _open = Loader<List<Order>>(listUnclearedOrders);
  final _waiting = Loader<List<Order>>(
    () => listOrders(deliveryStatuses: [DeliveryStatus.waiting, DeliveryStatus.dispatched], limit: 200),
  );

  @override
  List<Loader<dynamic>> get loaders => [_month, _open, _waiting];

  @override
  void initState() {
    super.initState();
    final d = widget.params['d'] ?? '';
    _date = _isoDate.hasMatch(d) ? d : toIsoDate();
    _month = Loader(_fetchMonth);
    reloadAll();
  }

  Future<List<Order>> _fetchMonth() {
    final r = monthRange(_date);
    return listOrders(from: r.from, to: r.to, limit: 3000);
  }

  @override
  void dispose() {
    for (final l in loaders) {
      l.dispose();
    }
    super.dispose();
  }

  void _setDate(String next) {
    final sameMonth = monthRange(next).from == monthRange(_date).from;
    setState(() => _date = next);
    if (!sameMonth) _month.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(loaders),
      builder: (context, _) {
        final today = toIsoDate();
        final isToday = _date == today;
        final monthOrders = _month.data ?? const <Order>[];
        final dayOrders = monthOrders.where((o) => o.orderDate == _date).toList();
        final dayCounts = <String, int>{};
        for (final o in monthOrders) {
          if (!o.cancelled) dayCounts[o.orderDate] = (dayCounts[o.orderDate] ?? 0) + 1;
        }
        final day = periodStats(dayOrders);
        final monthStats = periodStats(monthOrders);
        final openOrders = _open.data ?? const <Order>[];
        final waitingAll = _waiting.data ?? const <Order>[];
        final unpaidTotal = openOrders
            .where((o) => o.paymentStatus == PaymentStatus.unpaid)
            .fold<double>(0, (s, o) => s + o.total);
        final creditTotal = openOrders
            .where((o) => o.paymentStatus == PaymentStatus.credit)
            .fold<double>(0, (s, o) => s + o.total);
        final error = _month.error ?? _open.error ?? _waiting.error;
        final monthPending = _month.pending;
        final width = MediaQuery.sizeOf(context).width;
        final twoCol = width >= 1024;
        final ymd = _date.split('-').map(int.parse).toList();

        final daySection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              'ออเดอร์${isToday ? 'วันนี้' : 'วันที่เลือก'} ${dayOrders.isNotEmpty ? '(${dayOrders.length})' : ''}',
            ),
            Reveal(
              pending: monthPending,
              placeholder: const LoadingList(),
              child: dayOrders.isEmpty
                  ? AppCard(child: EmptyState(isToday ? 'ยังไม่มีออเดอร์วันนี้' : 'ไม่มีออเดอร์ในวันที่เลือก'))
                  : OrderList(orders: dayOrders),
            ),
          ],
        );
        final summarySection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('สรุปวัน'),
            Reveal(pending: monthPending, placeholder: const LoadingList(rows: 2), child: SummaryCard(stats: day)),
          ],
        );

        return TourMarker(
          page: TourPage.home,
          child: PageScroll(
            onRefresh: reloadAll,
            children: [
              if (isWide(context)) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TourTarget(
                    'new-order',
                    child: FilledButton.icon(
                      onPressed: () => openNewOrder(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('สร้างออเดอร์'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _DateBar(date: _date, today: today, counts: dayCounts, onChange: _setDate),
              if (error != null) ...[const SizedBox(height: 16), ErrorBox(error, onRetry: reloadAll)],
              const SizedBox(height: 16),
              TourTarget(
                'dash-kpis',
                child: GridRows(
                  columns: width >= 1024 ? 4 : 2,
                  children: [
                    KpiCard(
                      label: 'ออเดอร์',
                      value: formatNumber(day.orderCount),
                      hint: '${formatMoney(day.net)} บาท',
                      pending: monthPending,
                    ),
                    KpiCard(
                      label: 'สินค้า',
                      value: '${formatNumber(day.quantity)} คิว',
                      hint: '${formatNumber(day.trips)} เที่ยว',
                      pending: monthPending,
                    ),
                    KpiCard(label: 'รับเงินแล้ว', value: formatMoney(day.paid), hint: 'บาท', pending: monthPending),
                    KpiCard(
                      label: 'ค้างรับ',
                      value: formatMoney(day.outstanding),
                      hint: 'ยังไม่จ่าย + เครดิต',
                      warn: day.outstanding > 0,
                      pending: monthPending,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (twoCol)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: daySection),
                    const SizedBox(width: 24),
                    SizedBox(width: 352, child: summarySection),
                  ],
                )
              else ...[
                daySection,
                const SizedBox(height: 24),
                summarySection,
              ],
              const SizedBox(height: 24),
              SectionTitle(
                'งานค้าง (ทุกวัน)',
                action: TextButton(
                  onPressed: () => goTo(context, Dest.orders, {'f': 'waiting', 'r': 'all'}),
                  child: const Text('ดูทั้งหมด'),
                ),
              ),
              TourTarget(
                'dash-pending',
                child: GridRows(
                  columns: width >= 600 ? 3 : 1,
                  children: [
                    KpiCard(
                      label: 'กำลังจัดส่ง',
                      value: '${formatNumber(waitingAll.length)} ออเดอร์',
                      warn: waitingAll.isNotEmpty,
                      pending: _waiting.pending,
                      onTap: () => goTo(context, Dest.orders, {'f': 'waiting', 'r': 'all'}),
                    ),
                    KpiCard(
                      label: 'ยังไม่จ่าย',
                      value: formatMoney(unpaidTotal),
                      warn: unpaidTotal > 0,
                      pending: _open.pending,
                      onTap: () => goTo(context, Dest.orders, {'f': 'unpaid', 'r': 'all'}),
                    ),
                    KpiCard(
                      label: 'ค้างเครดิต',
                      value: formatMoney(creditTotal),
                      pending: _open.pending,
                      onTap: () => goTo(context, Dest.statements),
                    ),
                  ],
                ),
              ),
              if (waitingAll.isNotEmpty) ...[
                const SizedBox(height: 12),
                OrderList(orders: waitingAll.take(6).toList()),
              ],
              const SizedBox(height: 24),
              SectionTitle('สรุปเดือน${thMonths[ymd[1] - 1]} ${ymd[0] + 543}'),
              Reveal(pending: monthPending, placeholder: const LoadingList(rows: 2), child: SummaryCard(stats: monthStats)),
            ],
          ),
        );
      },
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.date, required this.today, required this.counts, required this.onChange});
  final String date;
  final String today;

  /// Orders per ISO day in the month of [date].
  final Map<String, int> counts;
  final ValueChanged<String> onChange;

  bool get isToday => date == today;

  Future<void> _pick(BuildContext context) async {
    final picked = await showCalendarPicker(context, value: date, today: today, counts: counts);
    if (picked != null) onChange(picked);
  }

  @override
  Widget build(BuildContext context) {
    final long = formatDateLongTh(date);
    final parts = long.split(' ');
    final showWeekday = MediaQuery.sizeOf(context).width >= 400;
    final label = showWeekday ? long : parts.skip(1).join(' ');
    Widget step(IconData icon, String tip, int delta) => Tooltip(
      message: tip,
      child: Material(
        color: AppColors.subtle,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChange(shiftIsoDate(date, delta)),
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 24)),
        ),
      ),
    );
    return Row(
      children: [
        step(Icons.chevron_left, 'วันก่อนหน้า', -1),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: AppColors.surface,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _pick(context),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        step(Icons.chevron_right, 'วันถัดไป', 1),
        if (!isToday) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => onChange(toIsoDate()),
              child: const Text('วันนี้'),
            ),
          ),
        ],
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.stats});
  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final locked = AuthScope.of(context).lockedSource;
    const small = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('จำนวนออเดอร์', formatNumber(stats.orderCount)),
          InfoRow('ค่าสินค้า', formatMoney(stats.productSales)),
          InfoRow('ค่าจัดส่ง', formatMoney(stats.deliveryFees)),
          if (stats.discounts != 0) InfoRow('ส่วนลด', '-${formatMoney(stats.discounts)}'),
          const Divider(height: 16),
          InfoRow('ยอดขายสุทธิ', formatMoney(stats.net), bold: true),
          InfoRow('รับเงินแล้ว', formatMoney(stats.paid)),
          InfoRow('ค้างรับ', formatMoney(stats.outstanding)),
          InfoRow('ค่าจ้างคนขับ', formatMoney(stats.driverWages)),
          if (locked == null) ...[
            const Divider(height: 24),
            const Text('แยกตามประเภทออเดอร์', style: small),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in OrderSource.values) ...[
                  if (s != OrderSource.values.first) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kRadius),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SourceBadge(s),
                          const SizedBox(height: 6),
                          Text(
                            formatMoney(stats.bySource[s]!.net),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: tabular),
                          ),
                          Text(
                            '${formatNumber(stats.bySource[s]!.orderCount)} ออเดอร์ · '
                            '${formatNumber(stats.bySource[s]!.quantity)} คิว',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (stats.quantityByProduct.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('ขายตามสินค้า', style: small),
            const SizedBox(height: 8),
            for (final p in stats.quantityByProduct)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${formatNumber(p.quantity)} ${p.unit} · ${formatMoney(p.amount)}',
                      style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
