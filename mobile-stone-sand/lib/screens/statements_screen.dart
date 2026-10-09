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

  void _openCreate(String customerId, OrderSource? source) {
    final auth = AuthScope.read(context);
    final summary = summarizeOutstanding(_uncleared.data ?? const []);
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
    final ok = await showClearStatementSheet(context, s);
    if (ok && mounted) showSnack(context, 'เคลียร์บิล ${s.statementNo} แล้ว');
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
        final summary = summarizeOutstanding(_uncleared.data ?? const []);
        final all = _statements.data ?? const <Statement>[];
        final visible = all.where(_filter.matches).toList();
        final openTotal = all.where((s) => !s.isCleared).fold<double>(0, (sum, s) => sum + s.total);
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

class _StatementRow extends StatelessWidget {
  const _StatementRow({
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
  Widget build(BuildContext context) {
    final s = statement;
    final tourRow = s.demo && !s.isCleared;
    final row = _row(context, s, tourRow);
    return tourRow ? TourTarget('st-demo-row', child: row) : row;
  }

  Widget _row(BuildContext context, Statement s, bool tourRow) {
    final clear = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: AppColors.success),
      onPressed: onClear,
      icon: const Icon(Icons.check, size: 18),
      label: const Text('เคลียร์บิล'),
    );
    return Container(
      color: highlight ? AppColors.warningSoft : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
                child: Text(
                  formatMoney(s.total),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ),
            ],
          ),
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
              if (canDelete)
                IconButton(
                  tooltip: 'ลบ ${s.statementNo}',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for cash/transfer and clears the statement; true when it was cleared.
Future<bool> showClearStatementSheet(BuildContext context, Statement s) async {
  final by = AuthScope.read(context).by;
  final ok = await showAppSheet<bool>(
    context,
    title: 'ยืนยันเคลียร์บิล',
    builder: (ctx) => _ClearSheet(statement: s, by: by),
  );
  return ok ?? false;
}

class _ClearSheet extends StatefulWidget {
  const _ClearSheet({required this.statement, required this.by});
  final Statement statement;
  final String by;

  @override
  State<_ClearSheet> createState() => _ClearSheetState();
}

class _ClearSheetState extends State<_ClearSheet> {
  String? _method;
  bool _busy = false;
  String _error = '';

  Future<void> _confirm() async {
    final method = _method;
    if (method == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await clearStatement(widget.statement.id, method, widget.by);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'เคลียร์บิลไม่สำเร็จ');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.statement;
    return TourTarget(
      'st-clear-modal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${s.statementNo} · ${s.customer.name}', style: const TextStyle(fontSize: 14)),
          Text(
            '${formatMoney(s.total)} บาท',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(height: 16),
          PayMethodPicker(value: _method, onChanged: (m) => setState(() => _method = m), hints: _clearHints),
          const SizedBox(height: 12),
          const Text(
            'ทุกออเดอร์ในใบวางบิลนี้จะเปลี่ยนเป็น "จ่ายแล้ว" และออกเลขใบเสร็จให้อัตโนมัติ',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: _busy || _method == null ? null : _confirm,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(_busy ? 'กำลังบันทึก…' : 'ยืนยันเคลียร์บิล'),
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
