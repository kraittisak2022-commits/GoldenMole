import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_scope.dart';
import '../data/customers_repo.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../logic/customer_search.dart';
import '../logic/format.dart';
import '../logic/order_status.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../widgets/loader.dart';
import '../widgets/order_row.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';
import 'new_order/wizard_widgets.dart';

/// Outstanding balance per customer id across both order sources.
Map<String, double> customerBalances(List<Order> uncleared) {
  final map = <String, double>{};
  for (final row in summarizeOutstanding(uncleared)) {
    map[row.customerId] = (map[row.customerId] ?? 0) + row.total;
  }
  return map;
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with ReloadOnDataChange {
  final _customers = Loader<List<Customer>>(listCustomers);
  final _uncleared = Loader<List<Order>>(() => listUnclearedOrders());
  final _query = TextEditingController();
  bool _onlyOutstanding = false;

  @override
  List<Loader<dynamic>> get loaders => [_customers, _uncleared];

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    reloadAll().then((_) {
      final id = widget.params['open'];
      if (!mounted || id == null) return;
      final c = _customers.data?.where((c) => c.id == id).firstOrNull;
      if (c != null) _open(c);
    });
  }

  @override
  void dispose() {
    _customers.dispose();
    _uncleared.dispose();
    _query.dispose();
    super.dispose();
  }

  void _open(Customer c) => Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute<void>(builder: (_) => CustomerDetailScreen(customer: c)));

  Future<void> _add() async {
    final saved = await editCustomer(context, null);
    if (saved != null && mounted) _open(saved);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(loaders),
      builder: (context, _) {
        final balances = customerBalances(_uncleared.data ?? const []);
        final total = balances.values.fold<double>(0, (s, v) => s + v);
        final query = _query.text;
        final visible = (_customers.data ?? const <Customer>[])
            .where((c) => (!_onlyOutstanding || (balances[c.id] ?? 0) != 0) && matchesCustomer(c.name, c.aliases, c.phone, query))
            .toList();
        return PageScroll(
          onRefresh: reloadAll,
          children: [
            PageHeader(
              title: 'ลูกค้า',
              subtitle: total != 0 ? 'ยอดค้างรวม ${formatMoney(total)} บาท' : 'ข้อมูลลูกค้าสำหรับออกบิล',
              action: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('เพิ่มลูกค้า'),
              ),
            ),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'ค้นหาชื่อ ชื่อเรียก หรือเบอร์โทร',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 4),
            CheckRow(
              boxed: false,
              value: _onlyOutstanding,
              onChanged: (v) => setState(() => _onlyOutstanding = v),
              child: const Text('เฉพาะที่มียอดค้าง'),
            ),
            const SizedBox(height: 8),
            if (_customers.error != null) ...[
              ErrorBox(_customers.error!, onRetry: _customers.load),
              const SizedBox(height: 12),
            ],
            if (_customers.pending)
              const LoadingList(rows: 5)
            else
              AppCard(
                child: visible.isEmpty
                    ? EmptyState(query.isNotEmpty ? 'ไม่พบลูกค้า' : 'ยังไม่มีลูกค้า')
                    : Column(
                        children: [
                          for (final (i, c) in visible.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _CustomerRow(customer: c, balance: balances[c.id] ?? 0, onTap: () => _open(c)),
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.balance, required this.onTap});
  final Customer customer;
  final double balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final sub = [if (c.phone.isNotEmpty) formatPhone(c.phone), if (c.address.isNotEmpty) c.address].join(' · ');
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
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                        if (c.isCredit) const AppBadge('เครดิต', tone: BadgeTone.info),
                      ],
                    ),
                    if (c.aliases.isNotEmpty)
                      Text(
                        'ชื่อเรียก: ${formatAliases(c.aliases)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.primary),
                      ),
                    Text(
                      sub.isEmpty ? '—' : sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (balance != 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('ค้าง', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    Text(
                      formatMoney(balance),
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning, fontFeatures: tabular),
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

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> with ReloadOnDataChange {
  late Customer _c = widget.customer;
  late final _orders = Loader<List<Order>>(() => listOrders(customerId: _c.id, limit: 100));
  late final _uncleared = Loader<List<Order>>(() => listUnclearedOrders(customerId: _c.id));
  bool _deleting = false;
  String _error = '';

  @override
  List<Loader<dynamic>> get loaders => [_orders, _uncleared];

  @override
  void initState() {
    super.initState();
    reloadAll();
  }

  @override
  void dispose() {
    _orders.dispose();
    _uncleared.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final saved = await editCustomer(context, _c);
    if (saved != null && mounted) setState(() => _c = saved);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'ลบลูกค้า "${_c.name}"?', confirmLabel: 'ลบ', destructive: true);
    if (!ok || !mounted) return;
    setState(() {
      _deleting = true;
      _error = '';
    });
    try {
      await deleteCustomer(_c.id);
      if (!mounted) return;
      showSnack(context, 'ลบลูกค้าแล้ว');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'ลบไม่สำเร็จ');
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 768) / 2);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'แก้ไข', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          if (superAdmin)
            IconButton(
              tooltip: 'ลบลูกค้า ${c.name}',
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(loaders),
        builder: (context, _) {
          final orders = _orders.data ?? const <Order>[];
          final balance = customerBalances(_uncleared.data ?? const [])[c.id] ?? 0;
          final spent = orders.where((o) => !o.cancelled).fold<double>(0, (s, o) => s + o.total);
          return RefreshIndicator(
            onRefresh: reloadAll,
            child: ListView(
              padding: EdgeInsets.fromLTRB(side, 16, side, 32),
              children: [
                if (c.isCredit) ...[
                  const Align(alignment: Alignment.centerLeft, child: AppBadge('ลูกค้าเครดิต', tone: BadgeTone.info)),
                  const SizedBox(height: 6),
                ],
                if (c.aliases.isNotEmpty)
                  Text('ชื่อเรียก: ${formatAliases(c.aliases)}', style: const TextStyle(color: AppColors.primary)),
                if (c.phone.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => launchUrl(Uri(scheme: 'tel', path: digitsOnly(c.phone))),
                      icon: const Icon(Icons.phone_outlined, size: 16),
                      label: Text(formatPhone(c.phone)),
                    ),
                  ),
                if (c.address.isNotEmpty) Text(c.address, style: const TextStyle(color: AppColors.muted)),
                if (c.taxId.isNotEmpty) Text('เลขผู้เสียภาษี ${c.taxId}', style: const TextStyle(color: AppColors.muted)),
                if (c.note.isNotEmpty) Text('หมายเหตุ: ${c.note}', style: const TextStyle(color: AppColors.muted)),
                if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
                const SizedBox(height: 16),
                GridRows(columns: 2, children: [
                  KpiCard(
                    label: 'ยอดค้างเคลียร์',
                    value: formatMoney(balance),
                    warn: balance != 0,
                    pending: _uncleared.pending,
                  ),
                  KpiCard(
                    label: 'ยอดซื้อ (${orders.length} ออเดอร์ล่าสุด)',
                    value: formatMoney(spent),
                    pending: _orders.pending,
                  ),
                ]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => openNewOrder(context, customerId: c.id),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('สร้างออเดอร์'),
                      ),
                    ),
                    if (balance != 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => goTo(context, Dest.statements, {'customer': c.id}),
                          icon: const Icon(Icons.description_outlined, size: 18),
                          label: const Text('ทำใบวางบิล'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                const SectionTitle('ประวัติออเดอร์'),
                if (_orders.error != null) ErrorBox(_orders.error!, onRetry: _orders.load),
                if (_orders.pending)
                  const LoadingList()
                else if (orders.isEmpty)
                  const AppCard(child: EmptyState('ยังไม่มีออเดอร์'))
                else
                  OrderList(orders: orders),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Opens the add/edit customer form; returns the saved customer.
Future<Customer?> editCustomer(BuildContext context, Customer? initial) =>
    Navigator.of(context, rootNavigator: true).push<Customer>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CustomerFormScreen(initial: initial),
    ));

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.initial});
  final Customer? initial;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  late final Customer? _i = widget.initial;
  late final _name = TextEditingController(text: _i?.name ?? '');
  late final _aliases = TextEditingController(text: formatAliases(_i?.aliases ?? const []));
  late final _phone = TextEditingController(text: _i?.phone ?? '');
  late final _address = TextEditingController(text: _i?.address ?? '');
  late final _taxId = TextEditingController(text: _i?.taxId ?? '');
  late final _note = TextEditingController(text: _i?.note ?? '');
  late bool _isCredit = _i?.isCredit ?? false;
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _aliases, _phone, _address, _taxId, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'กรุณาใส่ชื่อลูกค้า');
    final phone = digitsOnly(_phone.text);
    if (phone.isNotEmpty && (phone.length < 9 || phone.length > 10)) {
      return setState(() => _error = 'เบอร์โทรควรมี 9-10 หลัก');
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    final i = _i;
    try {
      final saved = await saveCustomer(Customer(
        id: i?.id ?? '',
        name: _name.text,
        aliases: parseAliases(_aliases.text),
        phone: phone,
        address: _address.text,
        zoneId: i?.zoneId,
        taxId: _taxId.text,
        lat: i?.lat,
        lng: i?.lng,
        isCredit: _isCredit,
        note: _note.text,
      ));
      if (mounted) Navigator.of(context).pop(saved);
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
    final side = math.max(16.0, (width - 640) / 2);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'ยกเลิก', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        title: Text(_i == null ? 'เพิ่มลูกค้า' : 'แก้ไขลูกค้า'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'กำลังบันทึก…' : 'บันทึก'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 32),
        children: [
          FieldLabel(
            'ชื่อลูกค้า / ชื่อร้าน *',
            child: TextField(controller: _name, autofocus: _i == null, textInputAction: TextInputAction.next),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'ชื่อเรียก (ไว้ค้นหา ไม่แสดงในบิล)',
            hint: 'คั่นหลายชื่อด้วย , เช่น เสี่ยบาส, บาส',
            child: TextField(
              controller: _aliases,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'เสี่ยบาส, บาส'),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'เบอร์โทร',
            child: TextField(controller: _phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'ที่อยู่ (สำหรับออกบิล)',
            child: TextField(controller: _address, minLines: 2, maxLines: 4),
          ),
          const SizedBox(height: 16),
          FieldLabel('เลขผู้เสียภาษี', child: TextField(controller: _taxId, keyboardType: TextInputType.number)),
          const SizedBox(height: 16),
          FieldLabel('หมายเหตุ', child: TextField(controller: _note)),
          const SizedBox(height: 8),
          CheckRow(
            boxed: false,
            value: _isCredit,
            onChanged: (v) => setState(() => _isCredit = v),
            child: const Text('ลูกค้าเครดิต (เคลียร์บิลรายเดือน)'),
          ),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
        ],
      ),
    );
  }
}
