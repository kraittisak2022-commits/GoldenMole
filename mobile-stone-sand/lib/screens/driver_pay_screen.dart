import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../data/payouts_repo.dart';
import '../logic/driver_pay.dart';
import '../logic/format.dart';
import '../models/models.dart';
import '../routes.dart';
import '../screens/new_order/wizard_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/loader.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import '../widgets/ui.dart';

const _payHints = (cash: 'จ่ายเงินสดให้คนขับ', transfer: 'โอนเข้าบัญชีคนขับ');
const _driverPaysHints = (cash: 'คนขับส่งเงินสด', transfer: 'คนขับโอนเข้าบัญชีร้าน');

class DriverPayScreen extends StatefulWidget {
  const DriverPayScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<DriverPayScreen> createState() => _DriverPayScreenState();
}

class _DriverPayScreenState extends State<DriverPayScreen> with ReloadOnDataChange {
  final _unpaid = Loader<List<Order>>(() => listDriverUnpaidOrders());
  final _payouts = Loader<List<DriverPayout>>(() => listDriverPayouts());
  late String? _driver = widget.params['driver'];
  String _error = '';
  String _paidNo = '';

  @override
  List<Loader<dynamic>> get loaders => [_unpaid, _payouts];

  @override
  void initState() {
    super.initState();
    reloadAll().then((_) {
      final id = _driver;
      if (!mounted || id == null) return;
      if ((_unpaid.data ?? const <Order>[]).any((o) => o.driverId == id)) _openPayout(id);
    });
  }

  @override
  void dispose() {
    _unpaid.dispose();
    _payouts.dispose();
    super.dispose();
  }

  String _driverName(String id) => CatalogScope.read(context).driverById(id)?.name ?? 'คนขับ';

  Future<void> _openPayout(String driverId) async {
    setState(() {
      _driver = driverId;
      _paidNo = '';
    });
    final orders = (_unpaid.data ?? const <Order>[]).where((o) => o.driverId == driverId).toList();
    final no = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(
      builder: (_) => PayoutScreen(driverId: driverId, driverName: _driverName(driverId), orders: orders),
    ));
    if (no != null && mounted) {
      setState(() {
        _error = '';
        _paidNo = no;
      });
    }
  }

  Future<void> _remove(DriverPayout p) async {
    final ok = await confirmDialog(
      context,
      title: 'ลบรายการจ่ายค่ารถ ${p.payoutNo}?',
      message: '${p.driverName} · ออเดอร์ในรายการนี้จะกลับเป็น "ค่ารถยังไม่จ่าย"',
      confirmLabel: 'ลบรายการ',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _error = '';
      _paidNo = '';
    });
    try {
      await deleteDriverPayout(p.id, AuthScope.read(context).by);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'ลบไม่สำเร็จ'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    CatalogScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(loaders),
      builder: (context, _) {
        final dues = summarizeDriverDues(_unpaid.data ?? const []);
        final dueTotal = dues.fold<double>(0, (s, d) => s + d.total);
        final driver = _driver;
        final payouts =
            (_payouts.data ?? const <DriverPayout>[]).where((p) => driver == null || p.driverId == driver).toList();
        return PageScroll(
          onRefresh: reloadAll,
          children: [
            const PageHeader(title: 'เคลียร์ค่ารถ', subtitle: 'จ่ายค่ารถให้คนขับตามออเดอร์ที่วิ่งส่ง แล้วบันทึกว่าจ่ายแล้ว'),
            if (_error.isNotEmpty) ...[ErrorBox(_error), const SizedBox(height: 12)],
            if (_paidNo.isNotEmpty) ...[
              Notice(icon: Icons.check_circle_outline, tone: BadgeTone.success, text: _paidNo),
              const SizedBox(height: 12),
            ],
            SectionTitle('คนขับที่ยังไม่ได้รับค่ารถ${dueTotal != 0 ? ' · รวม ${formatMoney(dueTotal)} บาท' : ''}'),
            if (_unpaid.error != null) ErrorBox(_unpaid.error!, onRetry: _unpaid.load),
            if (_unpaid.pending)
              const LoadingList()
            else
              AppCard(
                child: dues.isEmpty
                    ? const EmptyState('ไม่มีค่ารถค้างจ่าย')
                    : Column(
                        children: [
                          for (final (i, row) in dues.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _DueRow(
                              row: row,
                              name: _driverName(row.driverId),
                              selected: row.driverId == driver,
                              onTap: () => _openPayout(row.driverId),
                            ),
                          ],
                        ],
                      ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: SectionTitle('ประวัติจ่ายค่ารถ${driver != null ? ' · ${_driverName(driver)}' : ''}')),
                if (driver != null)
                  TextButton(onPressed: () => setState(() => _driver = null), child: const Text('ดูทุกคน')),
              ],
            ),
            if (_payouts.error != null) ErrorBox(_payouts.error!, onRetry: _payouts.load),
            if (_payouts.pending)
              const LoadingList()
            else
              AppCard(
                child: payouts.isEmpty
                    ? const EmptyState('ยังไม่มีประวัติจ่ายค่ารถ')
                    : Column(
                        children: [
                          for (final (i, p) in payouts.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _PayoutRow(payout: p, onDelete: superAdmin ? () => _remove(p) : null),
                          ],
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.row, required this.name, required this.selected, required this.onTap});
  final DriverDue row;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft.withValues(alpha: 0.6) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                      Text(
                        '${row.count} ออเดอร์ · ${formatNumber(row.trips)} เที่ยว · ตั้งแต่ ${formatDateShort(row.oldestDate)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(row.total), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    Text(
                      row.cash != 0 ? 'เก็บปลายทาง ${formatMoney(row.cash)}' : 'ค่ารถ',
                      style: TextStyle(fontSize: 12, color: row.cash != 0 ? AppColors.warning : AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout, this.onDelete});
  final DriverPayout payout;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = payout;
    final trips = p.orders.fold<int>(0, (s, o) => s + o.trips);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.payoutNo, style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: tabular)),
                    AppBadge('จ่ายแล้ว · ${PaymentMethod.parse(p.method).label}', tone: BadgeTone.success),
                  ],
                ),
                Text(p.driverName, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${formatDateTime(p.createdAt)}${(p.createdBy ?? '').isNotEmpty ? ' · โดย ${p.createdBy}' : ''}'
                  ' · ${p.orders.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final o in p.orders)
                      InkWell(
                        onTap: () => openOrder(context, o.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                          child: Text(
                            o.orderNo,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (p.note.isNotEmpty)
                  Text('หมายเหตุ: ${p.note}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('ค่ารถ ${formatMoney(p.total)}', style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
              if (p.cashCollected != 0) ...[
                Text(
                  'รับเงินสดจากคนขับ ${formatMoney(p.cashCollected)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                ),
                Text(
                  p.total >= p.cashCollected
                      ? 'ร้านจ่ายคนขับ ${formatMoney(p.total - p.cashCollected)}'
                      : 'คนขับส่งร้าน ${formatMoney(p.cashCollected - p.total)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFeatures: tabular),
                ),
              ],
            ],
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'ลบ ${p.payoutNo}',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// Pays one driver for the chosen orders; pops with a message describing what was saved.
class PayoutScreen extends StatefulWidget {
  const PayoutScreen({super.key, required this.driverId, required this.driverName, required this.orders});
  final String driverId;
  final String driverName;
  final List<Order> orders;

  @override
  State<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends State<PayoutScreen> {
  late String _from = widget.orders.isNotEmpty ? widget.orders.first.orderDate : toIsoDate();
  late String _to = toIsoDate().compareTo(_from) < 0 ? _from : toIsoDate();
  late final Map<String, double> _amounts = {for (final o in widget.orders) o.id: suggestedDriverPay(o)};
  Set<String> _selected = {};
  String _rangeKey = '';
  String? _method;
  final _note = TextEditingController();
  /// net = fee deducted from the COD cash now; later = driver hands over all the cash, fee waits for the monthly clearing
  _CashMode? _cashMode;
  (double, double) _modeKey = (0, 0);
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _syncSelection();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<Order> get _inRange => widget.orders
      .where((o) => o.orderDate.compareTo(_from) >= 0 && o.orderDate.compareTo(_to) <= 0)
      .toList();

  void _syncSelection() {
    final ids = _inRange.map((o) => o.id).toList();
    final key = ids.join(',');
    if (key != _rangeKey) {
      _rangeKey = key;
      _selected = ids.toSet();
    }
  }

  Future<void> _submit({required List<Order> chosen, required double cash, required bool needsMethod}) async {
    if (chosen.isEmpty) return setState(() => _error = 'เลือกออเดอร์อย่างน้อย 1 รายการ');
    if (cash > 0 && _cashMode == null) {
      return setState(() => _error = 'เลือกว่าหักค่ารถให้คนขับแล้ว หรือรับเงินเต็มจำนวน');
    }
    if (needsMethod && _method == null) return setState(() => _error = 'เลือกช่องทางการจ่ายเงิน');
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      if (cash > 0 && _cashMode == _CashMode.later) {
        final received = await receiveDriverCod(
          driverId: widget.driverId,
          orderIds: [for (final o in chosen) o.id],
          note: _note.text,
          by: AuthScope.read(context).by,
          cashExpected: cash,
        );
        if (mounted) {
          Navigator.of(context).pop('รับเงินปลายทาง ${formatMoney(received)} บาท จากคนขับแล้ว · ค่ารถรอเคลียร์รอบเดือน');
        }
        return;
      }
      final no = await createDriverPayout(
        driverId: widget.driverId,
        lines: [for (final o in chosen) (orderId: o.id, amount: _amounts[o.id] ?? 0)],
        method: _method ?? 'cash',
        note: _note.text,
        by: AuthScope.read(context).by,
        cashExpected: cash,
      );
      if (mounted) Navigator.of(context).pop('บันทึกเคลียร์ค่ารถ $no แล้ว');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'บันทึกไม่สำเร็จ');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 720) / 2);
    final inRange = _inRange;
    final chosen = inRange.where((o) => _selected.contains(o.id)).toList();
    final total = chosen.fold<double>(0, (s, o) => s + (_amounts[o.id] ?? 0));
    final trips = chosen.fold<int>(0, (s, o) => s + o.trips);
    final cash = chosen.fold<double>(0, (s, o) => s + codToCollect(o));
    final codCount = chosen.where((o) => codToCollect(o) > 0).length;
    if (_modeKey != (cash, total)) {
      _modeKey = (cash, total);
      _cashMode = null;
    }
    final later = cash > 0 && _cashMode == _CashMode.later;
    final net = later ? -cash : total - cash;
    final needsMethod = !later && net != 0;
    const big = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular);

    return Scaffold(
      appBar: AppBar(title: Text('จ่ายค่ารถ · ${widget.driverName}')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 32),
        children: [
          if (widget.orders.isEmpty)
            const AppCard(child: EmptyState('คนขับคนนี้ไม่มีค่ารถค้างจ่าย'))
          else ...[
            Row(children: [
              Expanded(
                child: DateField(
                  label: 'ตั้งแต่วันที่',
                  value: _from,
                  last: _to,
                  onChanged: (v) => setState(() {
                    _from = v;
                    _syncSelection();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DateField(
                  label: 'ถึงวันที่',
                  value: _to,
                  first: _from,
                  onChanged: (v) => setState(() {
                    _to = v;
                    _syncSelection();
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(children: [
                Expanded(child: Text('ออเดอร์', style: TextStyle(fontSize: 12, color: AppColors.muted))),
                Text('ค่ารถ (บาท)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            AppCard(
              child: inRange.isEmpty
                  ? const EmptyState('ไม่มีออเดอร์ในช่วงวันที่นี้')
                  : Column(
                      children: [
                        for (final (i, o) in inRange.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          PickRow(
                            selected: _selected.contains(o.id),
                            onToggle: () => setState(() {
                              if (!_selected.remove(o.id)) _selected.add(o.id);
                            }),
                            trailing: SizedBox(
                              width: 104,
                              child: NumberField(
                                value: _amounts[o.id] ?? 0,
                                decimal: false,
                                dense: true,
                                textAlign: TextAlign.end,
                                semanticLabel: 'ค่ารถ ${o.orderNo}',
                                onChanged: (v) => setState(() => _amounts[o.id] = math.max(0, v)),
                              ),
                            ),
                            child: _PayoutOrderInfo(order: o),
                          ),
                        ],
                      ],
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'ตั้งต้นจากค่าจ้างคนขับในออเดอร์ ถ้ายังไม่ได้ใส่จะใช้ค่าส่งที่เก็บจากลูกค้า แก้ตัวเลขได้ก่อนยืนยัน',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              color: AppColors.subtle,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: cash != 0
                  ? Column(
                      children: [
                        if (later) ...[
                          _SumLine(label: 'เงินเก็บปลายทาง ($codCount ออเดอร์)', value: formatMoney(cash)),
                          const SizedBox(height: 6),
                          _SumLine(
                            label: 'ค่ารถ · ${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว — รอเคลียร์รอบเดือน',
                            value: formatMoney(total),
                          ),
                        ] else ...[
                          _SumLine(
                            label: 'ค่ารถ · ${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว',
                            value: formatMoney(total),
                          ),
                          const SizedBox(height: 6),
                          _SumLine(
                            label: 'หัก เงินเก็บปลายทาง ($codCount ออเดอร์)',
                            value: '-${formatMoney(cash)}',
                            valueColor: AppColors.destructive,
                          ),
                        ],
                        const Divider(height: 20),
                        Row(children: [
                          Expanded(
                            child: Text(
                              net >= 0 ? 'ร้านจ่ายคนขับ' : 'คนขับต้องส่งเงินให้ร้าน',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            formatMoney(net.abs()),
                            style: big.copyWith(color: net >= 0 ? AppColors.primary : AppColors.warning),
                          ),
                        ]),
                      ],
                    )
                  : Row(children: [
                      Expanded(
                        child: Text(
                          '${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      Text(formatMoney(total), style: big.copyWith(color: AppColors.primary)),
                    ]),
            ),
            if (cash != 0) ...[
              const SizedBox(height: 12),
              _CashModeTile(
                selected: _cashMode == _CashMode.net,
                onTap: () => setState(() => _cashMode = _CashMode.net),
                title: total < cash
                    ? 'หักค่ารถให้คนขับแล้ว · รับเงิน ${formatMoney(cash - total)} บาท'
                    : total > cash
                        ? 'หักค่ารถให้คนขับแล้ว · ร้านจ่ายเพิ่ม ${formatMoney(total - cash)} บาท'
                        : 'หักค่ารถให้คนขับแล้ว · หักกันพอดี',
                detail: 'เก็บปลายทาง ${formatMoney(cash)} − ค่ารถ ${formatMoney(total)} · เคลียร์ค่ารถรอบนี้เลย',
              ),
              const SizedBox(height: 8),
              _CashModeTile(
                selected: _cashMode == _CashMode.later,
                onTap: () => setState(() => _cashMode = _CashMode.later),
                title: 'ได้รับเงินสด ${formatMoney(cash)} บาท จากคนขับแล้ว',
                detail: 'ค่ารถ ${formatMoney(total)} ยังไม่จ่าย รอเคลียร์ค่ารถทีเดียวในรอบเดือน',
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  'ออเดอร์เก็บปลายทางจะเปลี่ยนเป็น "จ่ายแล้ว" และออกใบเสร็จให้อัตโนมัติ',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
            if (needsMethod) ...[
              const SizedBox(height: 16),
              PayMethodPicker(
                value: _method,
                onChanged: (m) => setState(() => _method = m),
                hints: net > 0 ? _payHints : _driverPaysHints,
                label: net < 0
                    ? 'คนขับส่งเงินส่วนต่างด้วย'
                    : cash != 0
                        ? 'จ่ายส่วนต่างให้คนขับด้วย'
                        : 'จ่ายค่ารถด้วย',
              ),
            ],
            const SizedBox(height: 16),
            FieldLabel(
              'หมายเหตุ',
              child: TextField(controller: _note, decoration: const InputDecoration(hintText: 'เช่น โอนเข้าบัญชีภรรยา')),
            ),
            if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: _saving || chosen.isEmpty || (cash > 0 && _cashMode == null) || (needsMethod && _method == null)
                    ? null
                    : () => _submit(chosen: chosen, cash: cash, needsMethod: needsMethod),
                icon: const Icon(Icons.check, size: 18),
                label: Text(_saving
                    ? 'กำลังบันทึก…'
                    : later
                        ? 'ยืนยันรับเงิน ${formatMoney(cash)} (ค่ารถรอเคลียร์รอบเดือน)'
                        : cash != 0
                            ? 'ยืนยันเคลียร์ค่ารถ'
                            : 'ยืนยันจ่ายค่ารถ'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CashMode { net, later }

class _CashModeTile extends StatelessWidget {
  const _CashModeTile({required this.selected, required this.onTap, required this.title, required this.detail});
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.warningSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? const Color(0xFFFBBF24) : AppColors.border, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected ? AppColors.warning : AppColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFeatures: tabular)),
                      const SizedBox(height: 2),
                      Text(detail, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontFeatures: tabular)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayoutOrderInfo extends StatelessWidget {
  const _PayoutOrderInfo({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final cod = codToCollect(o);
    const small = TextStyle(fontSize: 12, color: AppColors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(o.orderNo, style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: tabular)),
            SourceBadge(o.source),
            if (o.deliveryStatus != DeliveryStatus.delivered) const AppBadge('ยังไม่ส่ง', tone: BadgeTone.warning),
          ],
        ),
        if (cod != 0)
          Text(
            'เก็บเงินปลายทาง ${formatNumber(cod)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary),
          )
        else if (o.statementId != null && o.paymentStatus != PaymentStatus.paid)
          const Text(
            'อยู่ในใบวางบิล · ลูกค้าจ่ายที่เคลียร์บิล',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary),
          ),
        Text('${formatDateShort(o.orderDate)} · ${o.customer.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
        Text(
          '${o.truckSize != 0 ? '${o.truckSize} คิว × ' : ''}${o.trips} เที่ยว'
          ' · เก็บลูกค้า ${formatNumber(o.deliveryTotal - o.deliveryDiscount)}',
          style: small,
        ),
      ],
    );
  }
}

class _SumLine extends StatelessWidget {
  const _SumLine({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted))),
      Text(value, style: TextStyle(fontSize: 14, color: valueColor, fontFeatures: tabular)),
    ]);
  }
}
