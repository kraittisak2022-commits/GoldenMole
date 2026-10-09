import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_scope.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../data/drivers_repo.dart';
import '../logic/format.dart';
import '../models/models.dart';
import '../screens/new_order/wizard_widgets.dart';
import '../theme/app_theme.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({super.key});

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  String _error = '';

  Future<void> _edit(Driver? d) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DriverFormScreen(initial: d),
    ));
    if (saved == true && mounted) await CatalogScope.read(context).reload();
  }

  Future<void> _toggleActive(Driver d) async {
    setState(() => _error = '');
    try {
      await saveDriverFrom(d, active: !d.active);
      if (mounted) await CatalogScope.read(context).reload();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e, 'บันทึกไม่สำเร็จ'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    final drivers = catalog.drivers;
    final error = catalog.error.isNotEmpty ? catalog.error : _error;
    return PageScroll(
      onRefresh: catalog.reload,
      children: [
        PageHeader(
          title: 'รถ / คนขับ',
          subtitle: '${drivers.where((d) => d.active).length} คันพร้อมรับงาน · แบ่ง ${RouteGroup.values.length} สาย',
          action: FilledButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('เพิ่มคนขับ'),
          ),
        ),
        if (error.isNotEmpty) ...[ErrorBox(error), const SizedBox(height: 12)],
        if (catalog.loading && drivers.isEmpty)
          const LoadingList()
        else
          for (final g in RouteGroup.values) ...[
            SectionTitle('${g.label} · ${drivers.where((d) => d.routeGroup == g).length}'),
            AppCard(
              child: Builder(builder: (context) {
                final list = drivers.where((d) => d.routeGroup == g).toList();
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('ยังไม่มีคนขับในสายนี้', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                  );
                }
                return Column(
                  children: [
                    for (final (i, d) in list.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _DriverRow(driver: d, onEdit: () => _edit(d), onToggle: () => _toggleActive(d)),
                    ],
                  ],
                );
              }),
            ),
            const SizedBox(height: 20),
          ],
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.driver, required this.onEdit, required this.onToggle});
  final Driver driver;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final d = driver;
    final info = d.village;
    return Container(
      color: d.active ? null : AppColors.subtle.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        color: d.active ? null : AppColors.muted,
                        decoration: d.active ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    Text(info.isEmpty ? '—' : info, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              AppBadge('${d.truckSize} คิว${d.truckCount > 1 ? ' ×${d.truckCount}' : ''}', tone: BadgeTone.info),
              IconButton(
                tooltip: 'แก้ไข ${d.name}',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.muted),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in d.contacts)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: digitsOnly(c.phone))),
                  icon: const Icon(Icons.phone_outlined, size: 16),
                  label: Text('${c.label.isNotEmpty ? '${c.label} ' : ''}${formatPhone(c.phone)}'),
                ),
              if (d.contactNote.isNotEmpty)
                Text(d.contactNote, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(value: d.active, onChanged: (_) => onToggle()),
                    const Text('รับงาน', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> saveDriverFrom(Driver d, {bool? active}) => saveDriver(
      id: d.id,
      name: d.name,
      village: d.village,
      routeGroup: d.routeGroup,
      truckSize: d.truckSize,
      truckCount: d.truckCount,
      contacts: d.contacts,
      contactNote: d.contactNote,
      wagePerTrip: d.wagePerTrip,
      active: active ?? d.active,
    );

class _ContactInput {
  _ContactInput(String label, String phone)
      : label = TextEditingController(text: label),
        phone = TextEditingController(text: phone);
  final TextEditingController label;
  final TextEditingController phone;

  void dispose() {
    label.dispose();
    phone.dispose();
  }
}

/// Add/edit a driver; pops true after saving or deleting.
class DriverFormScreen extends StatefulWidget {
  const DriverFormScreen({super.key, this.initial});
  final Driver? initial;

  @override
  State<DriverFormScreen> createState() => _DriverFormScreenState();
}

class _DriverFormScreenState extends State<DriverFormScreen> {
  late final Driver? _i = widget.initial;
  late final _name = TextEditingController(text: _i?.name ?? '');
  late final _village = TextEditingController(text: _i?.village ?? '');
  late final _contactNote = TextEditingController(text: _i?.contactNote ?? '');
  late RouteGroup _group = _i?.routeGroup ?? RouteGroup.north;
  late int _truckSize = _i?.truckSize ?? 5;
  late int _truckCount = _i?.truckCount ?? 1;
  late bool _active = _i?.active ?? true;
  late final List<_ContactInput> _contacts = [
    for (final c in _i?.contacts ?? const <DriverContact>[]) _ContactInput(c.label, c.phone),
  ];
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (_contacts.isEmpty) _contacts.add(_ContactInput('', ''));
  }

  @override
  void dispose() {
    _name.dispose();
    _village.dispose();
    _contactNote.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'กรุณาใส่ชื่อคนขับ');
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await saveDriver(
        id: _i?.id,
        name: _name.text,
        village: _village.text,
        routeGroup: _group,
        truckSize: _truckSize,
        truckCount: _truckCount,
        contacts: [
          for (final c in _contacts) DriverContact(label: c.label.text.trim(), phone: digitsOnly(c.phone.text)),
        ],
        contactNote: _contactNote.text,
        wagePerTrip: _i?.wagePerTrip ?? 0,
        active: _active,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'บันทึกไม่สำเร็จ');
          _saving = false;
        });
      }
    }
  }

  Future<void> _remove() async {
    final i = _i;
    if (i == null) return;
    final ok = await confirmDialog(context, title: 'ลบคนขับ "${i.name}"?', confirmLabel: 'ลบคนขับ', destructive: true);
    if (!ok || !mounted) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await deleteDriver(i.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, 'ลบไม่สำเร็จ');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 640) / 2);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'ยกเลิก', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        title: Text(_i == null ? 'เพิ่มคนขับ' : 'แก้ไขคนขับ'),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabel(
                  'ชื่อ *',
                  child: TextField(controller: _name, autofocus: _i == null, textInputAction: TextInputAction.next),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'บ้าน / หมู่บ้าน',
                  child: TextField(controller: _village, textInputAction: TextInputAction.next),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'สาย',
            child: DropdownButtonFormField<RouteGroup>(
              initialValue: _group,
              items: [for (final g in RouteGroup.values) DropdownMenuItem(value: g, child: Text(g.label))],
              onChanged: (g) => setState(() => _group = g ?? _group),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabel(
                  'ขนาดรถ',
                  child: DropdownButtonFormField<int>(
                    initialValue: _truckSize,
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3 คิว')),
                      DropdownMenuItem(value: 5, child: Text('5 คิว')),
                    ],
                    onChanged: (v) => setState(() => _truckSize = v ?? _truckSize),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'จำนวนคัน',
                  child: NumberField(
                    value: _truckCount,
                    decimal: false,
                    hintText: '1',
                    onChanged: (v) => setState(() => _truckCount = math.max(1, v.round())),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('เบอร์โทร', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          for (final (i, c) in _contacts.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Semantics(
                      label: 'ชื่อผู้ติดต่อ ${i + 1}',
                      child: TextField(controller: c.label, decoration: const InputDecoration(hintText: 'เช่น ภรรยา')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: 'เบอร์โทร ${i + 1}',
                      child: TextField(
                        controller: c.phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(hintText: '0xx-xxx-xxxx'),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'ลบเบอร์',
                    onPressed: () => setState(() => _contacts.removeAt(i).dispose()),
                    icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _contacts.add(_ContactInput('', ''))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('เพิ่มเบอร์'),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel('หมายเหตุการติดต่อ', child: TextField(controller: _contactNote)),
          const SizedBox(height: 8),
          CheckRow(
            boxed: false,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            child: const Text('พร้อมรับงาน'),
          ),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
          if (superAdmin && _i != null) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                onPressed: _saving ? null : _remove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบคนขับ'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
