import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../data/statements_repo.dart';
import '../logic/format.dart';
import '../logic/order_status.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../tour/tour_controller.dart';
import '../tour/tour_steps.dart';
import '../widgets/loader.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import '../widgets/ui.dart';

enum StatementFilter {
  open('รอเคลียร์'),
  cleared('เคลียร์แล้ว'),
  all('ทั้งหมด');

  const StatementFilter(this.label);
  final String label;

  bool matches(Statement s) => this == all || s.status == name;
}

const _clearHints = (cash: 'รับเป็นเงินสด', transfer: 'โอนเข้าบัญชี / พร้อมเพย์');

class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> with ReloadOnDataChange {
  final _uncleared = Loader<List<Order>>(() => listUnclearedOrders());
  final _statements = Loader<List<Statement>>(() => listStatements());
  StatementFilter _filter = StatementFilter.open;
  String _error = '';

  @override
  List<Loader<dynamic>> get loaders => [_uncleared, _statements];

  @override
  void initState() {
    super.initState();
    reloadAll().then((_) {
      final customer = widget.params['customer'];
      if (!mounted || customer == null) return;
      _openCreate(customer, OrderSource.tryParse(widget.params['source']));
    });
  }

  @override
  void dispose() {
    _uncleared.dispose();
    _statements.dispose();
    super.dispose();
  }

  List<CustomerOutstanding> get _summary =>
      summarizeOutstanding(_uncleared.data ?? const [], statementPaidMap(_statements.data ?? const []));

  void _openCreate(String customerId, OrderSource? source) {
    final auth = AuthScope.read(context);
    final summary = _summary;
    final picked =
        auth.lockedSource ??
        source ??
        summary.where((r) => r.customerId == customerId && r.unbilledCount > 0).firstOrNull?.source ??
        OrderSource.shop;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateStatementScreen(customerId: customerId, initialSource: picked),
      ),
    );
  }

  Future<void> _clear(Statement s) async {
    final cleared = await showReceivePaymentSheet(context, s);
    if (cleared != null && mounted) {
      showSnack(context, cleared ? 'เคลียร์บิล ${s.statementNo} แล้ว' : 'บันทึกรับชำระ ${s.statementNo} แล้ว');
    }
  }

  Future<void> _remove(Statement s) async {
    final ok = await confirmDialog(
      context,
      title: 'ลบใบวางบิล ${s.statementNo}?',
      message: s.isCleared
          ? 'ใบนี้เคลียร์แล้ว ออเดอร์ในใบนี้จะกลับไปเป็น "ยังไม่จ่าย / ยังไม่เคลียร์"'
          : 'ออเดอร์จะกลับไปเป็นยังไม่วางบิล',
      confirmLabel: 'ลบใบวางบิล',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _error = '');
    try {
      await deleteStatement(s.id, AuthScope.read(context).by);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'ลบไม่สำเร็จ'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    final highlight = widget.params['open'];
    return ListenableBuilder(
      listenable: Listenable.merge(loaders),
      builder: (context, _) {
        final summary = _summary;
        final all = _statements.data ?? const <Statement>[];
        final visible = all.where(_filter.matches).toList();
        final openTotal = all.where((s) => !s.isCleared).fold<double>(0, (sum, s) => sum + s.balance);
        final counts = {for (final f in StatementFilter.values) f: all.where(f.matches).length};
        return TourMarker(
          page: TourPage.statements,
          child: PageScroll(
            onRefresh: reloadAll,
            children: [
              const PageHeader(
                title: 'เคลียร์บิล',
                subtitle: 'รวมออเดอร์ค้างจ่ายของลูกค้าประจำเป็นใบวางบิลรายเดือน แล้วกดเคลียร์เมื่อได้รับเงิน',
              ),
              if (_error.isNotEmpty) ...[ErrorBox(_error), const SizedBox(height: 12)],
              const SectionTitle('ลูกค้าที่ยังไม่เคลียร์บิล'),
              if (_uncleared.error != null) ErrorBox(_uncleared.error!, onRetry: _uncleared.load),
              if (_uncleared.pending)
                const LoadingList()
              else
                AppCard(
                  child: summary.isEmpty
                      ? const EmptyState('ไม่มียอดค้าง ทุกบิลเคลียร์แล้ว')
                      : Column(
                          children: [
                            for (final (i, row) in summary.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _OutstandingRow(row: row, onTap: () => _openCreate(row.customerId, row.source)),
                            ],
                          ],
                        ),
                ),
              const SizedBox(height: 24),
              SectionTitle('ใบวางบิล${openTotal != 0 ? ' · รอเก็บเงิน ${formatMoney(openTotal)} บาท' : ''}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in StatementFilter.values)
                    CountChip(
                      label: f.label,
                      count: counts[f],
                      active: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_statements.error != null) ErrorBox(_statements.error!, onRetry: _statements.load),
              if (_statements.pending)
                const LoadingList()
              else
                AppCard(
                  child: visible.isEmpty
                      ? const EmptyState('ยังไม่มีใบวางบิล')
                      : Column(
                          children: [
                            for (final (i, s) in visible.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _StatementRow(
                                key: ValueKey(s.id),
                                statement: s,
                                highlight: s.id == highlight,
                                canDelete: !s.isCleared || superAdmin,
                                onClear: () => _clear(s),
                                onDelete: () => _remove(s),
                              ),
                            ],
                          ],
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OutstandingRow extends StatelessWidget {
  const _OutstandingRow({required this.row, required this.onTap});
  final CustomerOutstanding row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(row.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                        SourceBadge(row.source),
                      ],
                    ),
                    Text(
                      '${row.count} ออเดอร์ · ตั้งแต่ ${formatDateShort(row.oldestDate)}'
                      '${row.unbilledCount < row.count ? ' · วางบิลแล้ว ${row.count - row.unbilledCount}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(row.total),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                  ),
                  Text(
                    row.unbilledCount > 0 ? 'ยังไม่วางบิล ${formatMoney(row.unbilledTotal)}' : 'รอเคลียร์',
                    style: TextStyle(fontSize: 12, color: row.unbilledCount > 0 ? AppColors.warning : AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementRow extends StatefulWidget {
  const _StatementRow({
    super.key,
    required this.statement,
    required this.highlight,
    required this.canDelete,
    required this.onClear,
    required this.onDelete,
  });
  final Statement statement;
  final bool highlight;
  final bool canDelete;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  @override
  State<_StatementRow> createState() => _StatementRowState();
}

class _StatementRowState extends State<_StatementRow> {
  late bool _expanded = widget.highlight;

  @override
  Widget build(BuildContext context) {
    final s = widget.statement;
    final tourRow = s.demo && !s.isCleared;
    final row = _row(context, s, tourRow);
    return tourRow ? TourTarget('st-demo-row', child: row) : row;
  }

  Widget _row(BuildContext context, Statement s, bool tourRow) {
    final clear = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
      onPressed: widget.onClear,
      icon: const Icon(Icons.check, size: 18),
      label: const Text('เคลียร์บิล'),
    );
    final partial = !s.isCleared && s.paidAmount > 0;
    return Container(
      color: widget.highlight ? AppColors.warningSoft : null,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            s.statementNo,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: tabular),
                          ),
                          SourceBadge(s.source),
                          if (s.demo) const DemoBadge(),
                          if (s.isCleared)
                            AppBadge(
                              'เคลียร์แล้ว${(s.paymentMethod ?? '').isNotEmpty ? ' · ${PaymentMethod.parse(s.paymentMethod).label}' : ''}',
                              tone: BadgeTone.success,
                            )
                          else if (partial)
                            AppBadge('จ่ายบางส่วน · ${s.payments.length} ครั้ง', tone: BadgeTone.info)
                          else
                            const AppBadge('รอเคลียร์', tone: BadgeTone.warning),
                        ],
                      ),
                      Text(s.customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${formatDateShort(s.periodFrom)} – ${formatDateShort(s.periodTo)} · ${s.orderIds.length} ออเดอร์',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: partial
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'ค้าง ${formatMoney(s.balance)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                                fontFeatures: tabular,
                              ),
                            ),
                            Text(
                              'จ่ายแล้ว ${formatMoney(s.paidAmount)} / ${formatMoney(s.total)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                            ),
                          ],
                        )
                      : Text(
                          formatMoney(s.total),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                        ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[const SizedBox(height: 8), _StatementDetails(statement: s)],
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => openStatementBill(context, s.id),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('บิล'),
              ),
              const SizedBox(width: 8),
              if (!s.isCleared)
                Expanded(child: tourRow ? TourTarget('st-clear', child: clear) : clear)
              else
                const Spacer(),
              if (widget.canDelete)
                IconButton(
                  tooltip: 'ลบ ${s.statementNo}',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The statement's orders and payments, loaded when the row is expanded.
class _StatementDetails extends StatefulWidget {
  const _StatementDetails({required this.statement});
  final Statement statement;

  @override
  State<_StatementDetails> createState() => _StatementDetailsState();
}

class _StatementDetailsState extends State<_StatementDetails> {
  late final _orders = Loader<List<Order>>(() => getOrdersByIds(widget.statement.orderIds));

  @override
  void initState() {
    super.initState();
    _orders.load();
  }

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.statement;
    const small = TextStyle(fontSize: 12, color: AppColors.muted);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.subtle.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('รายการในใบวางบิล', style: TextStyle(fontWeight: FontWeight.w500)),
          Text(
            'รอบบิล ${formatDateShort(s.periodFrom)} – ${formatDateShort(s.periodTo)} · ออกเมื่อ ${formatDateTime(s.createdAt)}'
            '${(s.createdBy ?? '').isNotEmpty ? ' · โดย ${s.createdBy}' : ''}',
            style: small,
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _orders,
            builder: (context, _) {
              if (_orders.error != null) return ErrorBox(_orders.error!, onRetry: _orders.load);
              if (_orders.pending) return const LoadingList();
              final rows = [...?_orders.data]
                ..sort(
                  (a, b) =>
                      a.orderDate != b.orderDate ? a.orderDate.compareTo(b.orderDate) : a.orderNo.compareTo(b.orderNo),
                );
              return AppCard(
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('ไม่พบออเดอร์ในใบวางบิลนี้', style: TextStyle(color: AppColors.muted)),
                      )
                    : Column(
                        children: [
                          for (final (i, o) in rows.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            InkWell(
                              onTap: () => openOrder(context, o.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 6,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                o.orderNo,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  color: AppColors.primary,
                                                  fontFeatures: tabular,
                                                ),
                                              ),
                                              Text(formatDateShort(o.orderDate), style: small),
                                              if ((o.receiptNo ?? '').isNotEmpty)
                                                Text('ใบเสร็จ ${o.receiptNo}', style: small),
                                              if (o.cancelled) const AppBadge('ยกเลิก', tone: BadgeTone.danger),
                                            ],
                                          ),
                                          Text(
                                            '${o.items.map((it) => '${it.name} ${formatNumber(it.quantity)} ${it.unit}').join(', ')}'
                                            '${o.fulfillment == Fulfillment.delivery ? ' · ส่ง ${o.trips} เที่ยว' : ' · มารับเอง'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: small,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      formatMoney(o.total),
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: tabular),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              );
            },
          ),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AmountLine(label: 'รวม ${s.orderIds.length} ออเดอร์', value: formatMoney(s.total), bold: true),
                for (final p in s.payments)
                  _AmountLine(
                    label:
                        'รับชำระ ${formatDateTime(p.paidAt)} · ${PaymentMethod.parse(p.method).label}'
                        '${p.note.isNotEmpty ? ' · ${p.note}' : ''}',
                    value: '-${formatMoney(p.amount)}',
                    color: AppColors.success,
                    small: true,
                  ),
                const Divider(height: 12),
                _AmountLine(
                  label: s.isCleared ? 'เคลียร์แล้ว' : 'ค้างชำระ',
                  value: s.isCleared
                      ? (s.clearedAt != null ? formatDateTime(s.clearedAt) : '')
                      : formatMoney(s.balance),
                  color: s.isCleared ? AppColors.success : AppColors.warning,
                  bold: true,
                ),
              ],
            ),
          ),
          if (s.note.isNotEmpty) ...[const SizedBox(height: 6), Text('หมายเหตุ: ${s.note}', style: small)],
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value, this.color, this.bold = false, this.small = false});
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: small ? 12 : 14,
                color: bold ? null : AppColors.muted,
                fontWeight: bold ? FontWeight.w500 : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 12 : 14,
              color: color,
              fontWeight: bold ? FontWeight.w700 : null,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Records a full or partial payment on the statement. Returns true when it cleared,
/// false when a partial payment was saved, null when nothing was saved.
Future<bool?> showReceivePaymentSheet(BuildContext context, Statement s) {
  final by = AuthScope.read(context).by;
  return showAppSheet<bool>(
    context,
    title: 'รับชำระ / เคลียร์บิล',
    builder: (ctx) => _ReceivePaymentSheet(statement: s, by: by),
  );
}

enum _PayMode { full, partial }

class _ReceivePaymentSheet extends StatefulWidget {
  const _ReceivePaymentSheet({required this.statement, required this.by});
  final Statement statement;
  final String by;

  @override
  State<_ReceivePaymentSheet> createState() => _ReceivePaymentSheetState();
}

class _ReceivePaymentSheetState extends State<_ReceivePaymentSheet> {
  late Statement _s = widget.statement;
  _PayMode _mode = _PayMode.full;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _method;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _partialAmount => ((double.tryParse(_amount.text.replaceAll(',', '')) ?? 0) * 100).round() / 100;

  String get _partialProblem {
    if (_mode != _PayMode.partial) return '';
    final a = _partialAmount;
    if (a <= 0) return 'ใส่ยอดที่ลูกค้าจ่ายมา';
    if (a >= _s.balance) return 'ยอดเท่ากับหรือเกินยอดค้าง เลือก "จ่ายครบ" แทน';
    return '';
  }

  Future<void> _submit(double amount) async {
    final method = _method;
    if (method == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final s = await payStatement(id: _s.id, amount: amount, method: method, note: _note.text.trim(), by: widget.by);
      if (mounted) Navigator.of(context).pop(s.isCleared);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'บันทึกรับชำระไม่สำเร็จ');
          _busy = false;
        });
      }
    }
  }

  Future<void> _removePayment(StatementPayment p) async {
    final ok = await confirmDialog(
      context,
      title: 'ลบการรับชำระ ${formatMoney(p.amount)} บาท?',
      message: formatDateTime(p.paidAt),
      confirmLabel: 'ลบ',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await deleteStatementPayment(p.id, widget.by);
      final s = await getStatement(_s.id);
      if (mounted && s != null) setState(() => _s = s);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'ลบไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final balance = s.balance;
    final partialAmount = _partialAmount;
    final amount = _mode == _PayMode.full ? balance : partialAmount;
    final problem = _partialProblem;
    final remaining = math.max(0.0, ((balance - amount) * 100).round() / 100);
    final ready = _method != null && amount > 0 && problem.isEmpty;
    const muted = TextStyle(fontSize: 14, color: AppColors.muted);
    return TourTarget(
      'st-clear-modal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${s.statementNo} · ${s.customer.name}', style: muted),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AmountLine(label: 'ยอดใบวางบิล', value: formatMoney(s.total)),
                if (s.paidAmount > 0)
                  _AmountLine(
                    label: 'รับชำระแล้ว ${s.payments.length} ครั้ง',
                    value: '-${formatMoney(s.paidAmount)}',
                    color: AppColors.success,
                  ),
                const Divider(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Expanded(
                      child: Text('ยอดค้างชำระ', style: TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Text(
                      formatMoney(balance),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (s.payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('ประวัติรับชำระ', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            AppCard(
              child: Column(
                children: [
                  for (final (i, p) in s.payments.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${formatDateTime(p.paidAt)} · ${PaymentMethod.parse(p.method).label}',
                                  style: const TextStyle(fontFeatures: tabular),
                                ),
                                if (p.note.isNotEmpty || (p.createdBy ?? '').isNotEmpty)
                                  Text(
                                    [
                                      p.note,
                                      if ((p.createdBy ?? '').isNotEmpty) 'โดย ${p.createdBy}',
                                    ].where((t) => t.isNotEmpty).join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(p.amount),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                          ),
                          IconButton(
                            tooltip: 'ลบการรับชำระ ${formatMoney(p.amount)}',
                            onPressed: _busy ? null : () => _removePayment(p),
                            icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text('ลูกค้าจ่าย', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Semantics(
            label: 'ลูกค้าจ่าย',
            child: Segmented<_PayMode>(
              values: _PayMode.values,
              selected: _mode,
              labelOf: (m) => m == _PayMode.full ? 'จ่ายครบ' : 'จ่ายบางส่วน',
              trailingOf: (m) => m == _PayMode.full ? formatMoney(balance) : 'ระบุยอดเอง',
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          if (_mode == _PayMode.partial) ...[
            const SizedBox(height: 12),
            FieldLabel(
              'ยอดที่ได้รับ (บาท)',
              child: TextField(
                controller: _amount,
                autofocus: true,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 18, fontFeatures: tabular),
                decoration: InputDecoration(
                  hintText: '0.00',
                  errorText: _amount.text.isNotEmpty && problem.isNotEmpty ? problem : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          const SizedBox(height: 12),
          PayMethodPicker(value: _method, onChanged: (m) => setState(() => _method = m), hints: _clearHints),
          const SizedBox(height: 12),
          FieldLabel(
            'หมายเหตุ (ถ้ามี)',
            child: TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'เช่น โอนงวดแรก'),
            ),
          ),
          const SizedBox(height: 12),
          if (_mode == _PayMode.partial && partialAmount > 0 && problem.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AmountLine(label: 'รับครั้งนี้', value: formatMoney(partialAmount)),
                  _AmountLine(
                    label: 'ค้างชำระหลังรับ',
                    value: formatMoney(remaining),
                    color: AppColors.warning,
                    bold: true,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ใบวางบิลยังเปิดไว้เก็บส่วนที่เหลือ ออเดอร์ยังเป็นค้างจ่ายจนกว่าจะรับครบ',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            )
          else if (_mode == _PayMode.full)
            const Text('ทุกออเดอร์ในใบวางบิลนี้จะเปลี่ยนเป็น "จ่ายแล้ว" และออกเลขใบเสร็จให้อัตโนมัติ', style: muted),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: _busy || !ready ? null : () => _submit(amount),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    _busy
                        ? 'กำลังบันทึก…'
                        : _mode == _PayMode.full
                        ? 'ยืนยันเคลียร์บิล'
                        : 'บันทึกรับ ${formatMoney(partialAmount)}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CreateStatementScreen extends StatefulWidget {
  const CreateStatementScreen({super.key, required this.customerId, required this.initialSource});
  final String customerId;
  final OrderSource initialSource;

  @override
  State<CreateStatementScreen> createState() => _CreateStatementScreenState();
}

class _CreateStatementScreenState extends State<CreateStatementScreen> {
  late final _orders = Loader<List<Order>>(() => listUnclearedOrders(customerId: widget.customerId));
  late OrderSource _source = widget.initialSource;
  String _from = '';
  String _to = toIsoDate();
  Set<String> _selected = {};
  String _rangeKey = '';
  final _note = TextEditingController();
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _orders.load().then((_) => _resetRange());
  }

  @override
  void dispose() {
    _orders.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Order> get _unbilled =>
      (_orders.data ?? const <Order>[]).where((o) => o.statementId == null && o.source == _source).toList();

  void _resetRange() {
    if (!mounted) return;
    final orders = _unbilled;
    setState(() {
      _from = orders.isNotEmpty ? orders.first.orderDate : toIsoDate();
      _to = toIsoDate();
      _syncSelection();
    });
  }

  List<Order> get _inRange =>
      _unbilled.where((o) => o.orderDate.compareTo(_from) >= 0 && o.orderDate.compareTo(_to) <= 0).toList();

  /// Like the web: selecting every order in range again whenever the range changes.
  void _syncSelection() {
    final ids = _inRange.map((o) => o.id).toList();
    final key = ids.join(',');
    if (key != _rangeKey) {
      _rangeKey = key;
      _selected = ids.toSet();
    }
  }

  Future<void> _submit(List<Order> chosen) async {
    if (chosen.isEmpty) return setState(() => _error = 'เลือกออเดอร์อย่างน้อย 1 รายการ');
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final s = await createStatement(
        source: _source,
        customerId: widget.customerId,
        orderIds: chosen.map((o) => o.id).toList(),
        from: _from,
        to: _to,
        note: _note.text,
        by: AuthScope.read(context).by,
      );
      if (mounted) openStatementBill(context, s.id, replace: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'สร้างใบวางบิลไม่สำเร็จ');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = AuthScope.of(context).visibleSources;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 720) / 2);
    return TourMarker(
      page: TourPage.statementCreate,
      id: widget.customerId,
      child: Scaffold(
        appBar: AppBar(title: Text('สร้างใบวางบิล · ${_source.short}')),
        body: ListenableBuilder(
          listenable: _orders,
          builder: (context, _) {
            final all = (_orders.data ?? const <Order>[]).where((o) => o.statementId == null).toList();
            final orders = _unbilled;
            final inRange = _inRange;
            final chosen = inRange.where((o) => _selected.contains(o.id)).toList();
            final total = chosen.fold<double>(0, (s, o) => s + o.total);
            final first = (_orders.data ?? const <Order>[]).firstOrNull;
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 16, side, 32),
              children: [
                if (first != null)
                  Text(
                    '${first.customer.name}${first.customer.phone.isNotEmpty ? ' · ${formatPhone(first.customer.phone)}' : ''}',
                    style: const TextStyle(fontSize: 15, color: AppColors.muted),
                  ),
                const SizedBox(height: 12),
                if (sources.length > 1) ...[
                  Semantics(
                    label: 'ประเภทออเดอร์',
                    child: Segmented<OrderSource>(
                      values: sources,
                      selected: _source,
                      labelOf: (s) => s.short,
                      trailingOf: (s) => '${all.where((o) => o.source == s).length}',
                      onChanged: (s) {
                        if (s == _source) return;
                        setState(() => _source = s);
                        _resetRange();
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ใบวางบิลแยกกันระหว่างออเดอร์ร้านวัสดุก่อสร้างกับออเดอร์ท่าทราย',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_orders.error != null) ErrorBox(_orders.error!, onRetry: _orders.load),
                if (_orders.pending)
                  const LoadingList()
                else if (orders.isEmpty)
                  AppCard(child: EmptyState('ไม่มีออเดอร์${_source.label}ที่ยังไม่วางบิล'))
                else ...[
                  TourTarget(
                    'st-create',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
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
                          ],
                        ),
                        const SizedBox(height: 12),
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
                                        trailing: Text(
                                          formatMoney(o.total),
                                          style: const TextStyle(fontFeatures: tabular),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${formatDateShort(o.orderDate)} · ${o.orderNo}',
                                              style: const TextStyle(fontFeatures: tabular),
                                            ),
                                            Text(
                                              o.items.map((it) => '${it.name} ${formatNumber(it.quantity)}').join(', '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                            ),
                                            if (o.paymentMethod == PaymentMethod.cod && o.driverId != null)
                                              const Text(
                                                'เก็บปลายทาง · ถ้าคนขับเก็บเงินมาแล้ว อย่าใส่ในใบวางบิล ให้รับเงินที่เคลียร์ค่ารถแทน',
                                                style: TextStyle(fontSize: 12, color: AppColors.warning),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FieldLabel('หมายเหตุบนใบวางบิล', child: TextField(controller: _note, minLines: 2, maxLines: 4)),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
                  const SizedBox(height: 16),
                  AppCard(
                    color: AppColors.subtle,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${chosen.length} ออเดอร์', style: const TextStyle(color: AppColors.muted)),
                        ),
                        Text(
                          formatMoney(total),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TourTarget(
                    'st-create-submit',
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving || chosen.isEmpty ? null : () => _submit(chosen),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: Text(_saving ? 'กำลังสร้าง…' : 'สร้างใบวางบิลและพิมพ์'),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
