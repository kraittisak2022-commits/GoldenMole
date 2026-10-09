import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/orders_repo.dart';
import '../logic/format.dart';
import '../logic/order_status.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../widgets/loader.dart';
import '../widgets/order_row.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';

enum OrderRange {
  today('วันนี้'),
  d7('7 วันล่าสุด'),
  month('เดือนนี้'),
  m3('3 เดือน'),
  all('ทั้งหมด');

  const OrderRange(this.label);
  final String label;

  /// Web query value (`7d`, `3m`, …).
  String get param => switch (this) {
        OrderRange.d7 => '7d',
        OrderRange.m3 => '3m',
        _ => name,
      };

  static OrderRange parse(String? v) =>
      OrderRange.values.firstWhere((r) => r.param == v, orElse: () => OrderRange.month);

  String? from([DateTime? now]) {
    final d = now ?? DateTime.now();
    return switch (this) {
      OrderRange.today => toIsoDate(d),
      OrderRange.d7 => toIsoDate(DateTime(d.year, d.month, d.day - 6)),
      OrderRange.month => toIsoDate(DateTime(d.year, d.month, 1)),
      OrderRange.m3 => toIsoDate(DateTime(d.year, d.month - 2, 1)),
      OrderRange.all => null,
    };
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with ReloadOnDataChange {
  late OrderFilter _filter = OrderFilter.parse(widget.params['f']);
  late OrderRange _range = OrderRange.parse(widget.params['r']);
  late OrderSource? _source = OrderSource.tryParse(widget.params['source']);
  final _query = TextEditingController();
  late final _orders = Loader<List<Order>>(() => listOrders(from: _range.from(), limit: 1000));

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

  @override
  Widget build(BuildContext context) {
    final locked = AuthScope.of(context).lockedSource;
    final source = locked != null ? null : _source;
    final wide = isWide(context);
    return ListenableBuilder(
      listenable: _orders,
      builder: (context, _) {
        final orders = _orders.data ?? const <Order>[];
        final query = _query.text;
        final sourceCounts = {for (final s in OrderSource.values) s: orders.where((o) => o.source == s).length};
        final searched =
            orders.where((o) => (source == null || o.source == source) && matchesSearch(o, query)).toList();
        final counts = {for (final f in OrderFilter.values) f: searched.where((o) => matchesFilter(o, f)).length};
        final visible = searched.where((o) => matchesFilter(o, _filter)).toList();
        final visibleTotal = visible.fold<double>(0, (s, o) => s + (o.cancelled ? 0 : o.total));
        final visibleOutstanding = visible.fold<double>(0, (s, o) => s + outstanding(o));

        final search = TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'ค้นหาชื่อ ชื่อเรียก เบอร์โทร หรือเลขที่บิล',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'ล้างคำค้น',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _query.clear,
                  ),
          ),
        );
        final rangeSelect = DropdownButtonFormField<OrderRange>(
          initialValue: _range,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.date_range_outlined, size: 20)),
          items: [
            for (final r in OrderRange.values) DropdownMenuItem(value: r, child: Text(r.label)),
          ],
          onChanged: (r) => r == null ? null : _setRange(r),
        );

        return PageScroll(
          onRefresh: _orders.load,
          children: [
            PageHeader(
              title: 'ออเดอร์',
              subtitle: 'ติดตามสถานะจ่ายเงิน จัดส่ง และเคลียร์บิล',
              action: wide
                  ? FilledButton.icon(
                      onPressed: () => openNewOrder(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('สร้างออเดอร์'),
                    )
                  : null,
            ),
            if (MediaQuery.sizeOf(context).width >= 600)
              Row(children: [Expanded(child: search), const SizedBox(width: 8), SizedBox(width: 200, child: rangeSelect)])
            else ...[
              search,
              const SizedBox(height: 8),
              rangeSelect,
            ],
            const SizedBox(height: 12),
            if (locked == null) ...[
              Segmented<OrderSource?>(
                values: const [null, OrderSource.shop, OrderSource.pit],
                selected: source,
                labelOf: (s) => s?.short ?? 'ทั้งหมด',
                trailingOf: (s) => '${s == null ? orders.length : sourceCounts[s]}',
                onChanged: (s) => setState(() => _source = s),
              ),
              const SizedBox(height: 12),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final f in OrderFilter.values) ...[
                    if (f != OrderFilter.values.first) const SizedBox(width: 8),
                    CountChip(
                      label: f.label,
                      count: counts[f],
                      active: f == _filter,
                      onTap: () => setState(() => _filter = f),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_orders.error != null) ...[ErrorBox(_orders.error!, onRetry: _orders.load), const SizedBox(height: 12)],
            if (_orders.pending)
              const LoadingList()
            else if (visible.isEmpty)
              AppCard(
                child: EmptyState(
                  query.isNotEmpty ? 'ไม่พบออเดอร์ที่ค้นหา' : 'ยังไม่มีออเดอร์ในช่วงนี้',
                  action: TextButton(
                    onPressed: () => openNewOrder(context),
                    child: const Text('สร้างออเดอร์ใหม่'),
                  ),
                ),
              )
            else
              OrderList(
                orders: visible,
                header: Container(
                  color: AppColors.subtle.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('${visible.length} รายการ', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      const Spacer(),
                      Text(
                        'รวม ${formatMoney(visibleTotal)}'
                        '${visibleOutstanding != 0 ? ' · ค้าง ${formatMoney(visibleOutstanding)}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
