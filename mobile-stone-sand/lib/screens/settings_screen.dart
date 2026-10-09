import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../calc/delivery_fee.dart';
import '../data/catalog_repo.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../logic/format.dart';
import '../logic/promptpay.dart';
import '../models/models.dart';
import '../screens/new_order/wizard_widgets.dart';
import '../theme/app_theme.dart';
import '../tour/tour_menu_card.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    if (catalog.loading && catalog.products.isEmpty) {
      return const PageScroll(children: [LoadingList()]);
    }
    return PageScroll(
      maxWidth: 768,
      onRefresh: catalog.reload,
      children: [
        const PageHeader(title: 'ตั้งค่า', subtitle: 'ราคาสินค้า ค่าส่ง หัวบิล ช่องทางรับเงิน และสอนใช้งาน'),
        if (catalog.error.isNotEmpty) ...[ErrorBox(catalog.error), const SizedBox(height: 12)],
        ProductsSection(products: catalog.products),
        const SizedBox(height: 20),
        ZonesSection(zones: catalog.zones, delivery: catalog.settings.delivery),
        const SizedBox(height: 20),
        DeliverySection(settings: catalog.settings.delivery, zones: catalog.zones),
        const SizedBox(height: 20),
        CompanySection(company: catalog.settings.company),
        const SizedBox(height: 20),
        PaymentSection(payment: catalog.settings.payment),
        const SizedBox(height: 20),
        const TourMenuCard(),
      ],
    );
  }
}

/// Saving state for one settings card; reloads the catalog after a successful save.
mixin _Saver<T extends StatefulWidget> on State<T> {
  bool saving = false;
  String saveError = '';
  bool saved = false;
  Timer? _doneTimer;

  Future<void> runSave(Future<void> Function() fn) async {
    _doneTimer?.cancel();
    setState(() {
      saving = true;
      saveError = '';
      saved = false;
    });
    try {
      await fn();
      if (!mounted) return;
      await CatalogScope.read(context).reload();
      if (!mounted) return;
      setState(() => saved = true);
      _doneTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => saved = false);
      });
    } catch (e) {
      if (mounted) setState(() => saveError = errorText(e, 'บันทึกไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    this.subtitle,
    required this.child,
    required this.saving,
    required this.error,
    required this.saved,
    required this.onSave,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final bool saving;
  final String error;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ),
          const SizedBox(height: 16),
          child,
          if (error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(error)],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (saved) ...[
                const Icon(Icons.check, size: 16, color: AppColors.success),
                const SizedBox(width: 4),
                const Text('บันทึกแล้ว', style: TextStyle(fontSize: 14, color: AppColors.success)),
                const SizedBox(width: 12),
              ],
              FilledButton(onPressed: saving ? null : onSave, child: Text(saving ? 'กำลังบันทึก…' : 'บันทึก')),
            ],
          ),
        ],
      ),
    );
  }
}

const _newPrefix = 'new-';
bool _isNew(String id) => id.startsWith(_newPrefix);
int _nextSort(Iterable<int> sorts) => sorts.fold(0, math.max) + 10;

class _ProductRow {
  _ProductRow(Product p)
      : id = p.id,
        name = TextEditingController(text: p.name),
        category = p.category,
        price = p.pricePerUnit,
        active = p.active,
        sortOrder = p.sortOrder;
  _ProductRow.blank(this.sortOrder)
      : id = '$_newPrefix${DateTime.now().microsecondsSinceEpoch}',
        name = TextEditingController(),
        category = ProductCategory.stone,
        price = 0,
        active = true;
  final String id;
  final TextEditingController name;
  ProductCategory category;
  double price;
  bool active;
  final int sortOrder;
}

class ProductsSection extends StatefulWidget {
  const ProductsSection({super.key, required this.products});
  final List<Product> products;

  @override
  State<ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<ProductsSection> with _Saver {
  List<_ProductRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant ProductsSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.products, widget.products)) _reset();
  }

  void _reset() {
    _disposeRows();
    _rows = [for (final p in widget.products) _ProductRow(p)];
  }

  void _disposeRows() {
    for (final r in _rows) {
      r.name.dispose();
    }
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }

  Future<void> _remove(_ProductRow r) async {
    if (!_isNew(r.id)) {
      final ok = await confirmDialog(
        context,
        title: 'ลบสินค้า "${r.name.text}"?',
        message: 'ออเดอร์เก่ายังแสดงชื่อเดิม กดบันทึกเพื่อยืนยัน',
        confirmLabel: 'ลบ',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _rows.remove(r);
      r.name.dispose();
    });
  }

  Future<void> _save() => runSave(() async {
        if (_rows.any((r) => r.name.text.trim().isEmpty)) throw const AppException('กรุณาใส่ชื่อสินค้าให้ครบ');
        final before = {for (final p in widget.products) p.id: p};
        for (final p in widget.products) {
          if (!_rows.any((r) => r.id == p.id)) await deleteProduct(p.id);
        }
        for (final r in _rows) {
          if (_isNew(r.id)) {
            await createProduct(
              name: r.name.text,
              category: r.category,
              unit: 'คิว',
              pricePerUnit: r.price,
              sortOrder: r.sortOrder,
            );
            continue;
          }
          final b = before[r.id];
          if (b != null &&
              (b.pricePerUnit != r.price || b.name != r.name.text || b.category != r.category || b.active != r.active)) {
            await saveProduct(id: r.id, name: r.name.text, category: r.category, pricePerUnit: r.price, active: r.active);
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    return _SettingsCard(
      title: 'ราคาสินค้า (ต่อคิว)',
      subtitle: 'ราคา 3 คิว / 5 คิว คิดจากราคาต่อคิว × จำนวน',
      saving: saving,
      error: saveError,
      saved: saved,
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, r) in _rows.indexed) ...[
            if (i > 0) const Divider(height: 24),
            Column(
              key: ValueKey(r.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel('ชื่อสินค้า', child: TextField(controller: r.name)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FieldLabel(
                        'หมวด',
                        child: DropdownButtonFormField<ProductCategory>(
                          initialValue: r.category,
                          items: [
                            for (final c in ProductCategory.values) DropdownMenuItem(value: c, child: Text(c.label)),
                          ],
                          onChanged: (c) => setState(() => r.category = c ?? r.category),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FieldLabel(
                        'บาท/คิว',
                        child: NumberField(
                          value: r.price,
                          decimal: false,
                          onChanged: (v) => setState(() => r.price = math.max(0, v)),
                        ),
                      ),
                    ),
                    if (superAdmin)
                      IconButton(
                        tooltip: 'ลบสินค้า ${r.name.text}',
                        onPressed: () => _remove(r),
                        icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                CheckRow(
                  boxed: false,
                  value: r.active,
                  onChanged: (v) => setState(() => r.active = v),
                  child: const Text('ขายอยู่'),
                ),
              ],
            ),
          ],
          if (superAdmin) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _rows.add(_ProductRow.blank(_nextSort(_rows.map((r) => r.sortOrder))))),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('เพิ่มสินค้า'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneRow {
  _ZoneRow(Zone z)
      : id = z.id,
        name = TextEditingController(text: z.name),
        feeMin = z.feeMin,
        feeMax = z.feeMax,
        sortOrder = z.sortOrder;
  _ZoneRow.blank(this.sortOrder)
      : id = '$_newPrefix${DateTime.now().microsecondsSinceEpoch}',
        name = TextEditingController(),
        feeMin = 0,
        feeMax = 0;
  final String id;
  final TextEditingController name;
  double feeMin;
  double feeMax;
  final int sortOrder;
}

class ZonesSection extends StatefulWidget {
  const ZonesSection({super.key, required this.zones, required this.delivery});
  final List<Zone> zones;
  final DeliverySettings delivery;

  @override
  State<ZonesSection> createState() => _ZonesSectionState();
}

class _ZonesSectionState extends State<ZonesSection> with _Saver {
  List<_ZoneRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant ZonesSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.zones, widget.zones)) _reset();
  }

  void _reset() {
    _disposeRows();
    _rows = [for (final z in widget.zones) _ZoneRow(z)];
  }

  void _disposeRows() {
    for (final r in _rows) {
      r.name.dispose();
    }
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }

  Future<void> _remove(_ZoneRow r) async {
    if (!_isNew(r.id)) {
      final ok = await confirmDialog(
        context,
        title: 'ลบ ต.${r.name.text}?',
        message: 'กดบันทึกเพื่อยืนยัน',
        confirmLabel: 'ลบ',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _rows.remove(r);
      r.name.dispose();
    });
  }

  Future<void> _save() => runSave(() async {
        if (_rows.any((r) => r.name.text.trim().isEmpty)) throw const AppException('กรุณาใส่ชื่อตำบลให้ครบ');
        final invalid = _rows.where((r) => r.feeMax < r.feeMin).firstOrNull;
        if (invalid != null) throw AppException('ต.${invalid.name.text}: ราคาสูงสุดต้องไม่น้อยกว่าราคาต่ำสุด');
        final before = {for (final z in widget.zones) z.id: z};
        for (final z in widget.zones) {
          if (!_rows.any((r) => r.id == z.id)) await deleteZone(z.id);
        }
        for (final r in _rows) {
          if (_isNew(r.id)) {
            await createZone(name: r.name.text, feeMin: r.feeMin, feeMax: r.feeMax, sortOrder: r.sortOrder);
            continue;
          }
          final b = before[r.id];
          if (b != null && (b.feeMin != r.feeMin || b.feeMax != r.feeMax || b.name != r.name.text)) {
            await saveZone(id: r.id, name: r.name.text, feeMin: r.feeMin, feeMax: r.feeMax);
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final superAdmin = AuthScope.of(context).isSuperAdmin;
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted);
    return _SettingsCard(
      title: 'ค่าส่งตามตำบล (บาท/เที่ยว)',
      subtitle: 'ใกล้ถนนใหญ่ไม่เกิน ${formatNumber(widget.delivery.nearKm)} กม. คิดราคาต่ำสุด '
          'ไกลขึ้นคิดเพิ่มตามระยะจนถึงราคาสูงสุด',
      saving: saving,
      error: saveError,
      saved: saved,
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadius),
              child: Column(
                children: [
                  Container(
                    color: AppColors.subtle,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      const Expanded(child: Text('ตำบล', style: head)),
                      const SizedBox(width: 92, child: Text('ต่ำสุด', style: head)),
                      const SizedBox(width: 8),
                      const SizedBox(width: 92, child: Text('สูงสุด', style: head)),
                      if (superAdmin) const SizedBox(width: 48),
                    ]),
                  ),
                  for (final r in _rows) ...[
                    const Divider(height: 1),
                    Padding(
                      key: ValueKey(r.id),
                      padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
                      child: Row(children: [
                        Expanded(
                          child: superAdmin
                              ? Semantics(
                                  label: 'ชื่อตำบล',
                                  child: TextField(
                                    controller: r.name,
                                    decoration: const InputDecoration(
                                      hintText: 'ชื่อตำบล',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                )
                              : Text(r.name.text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: NumberField(
                            value: r.feeMin,
                            decimal: false,
                            dense: true,
                            semanticLabel: 'ค่าส่งต่ำสุด ${r.name.text}',
                            onChanged: (v) => setState(() => r.feeMin = math.max(0, v)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: NumberField(
                            value: r.feeMax,
                            decimal: false,
                            dense: true,
                            semanticLabel: 'ค่าส่งสูงสุด ${r.name.text}',
                            style: r.feeMax < r.feeMin ? const TextStyle(color: AppColors.destructive) : null,
                            onChanged: (v) => setState(() => r.feeMax = math.max(0, v)),
                          ),
                        ),
                        if (superAdmin)
                          IconButton(
                            tooltip: 'ลบ ต.${r.name.text}',
                            onPressed: () => _remove(r),
                            icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                          )
                        else
                          const SizedBox(width: 12),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (superAdmin) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _rows.add(_ZoneRow.blank(_nextSort(_rows.map((r) => r.sortOrder))))),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('เพิ่มตำบล'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ชื่อตำบลต้องตรงกับชื่อในแผนที่ ระบบจึงจะเลือกตำบลให้อัตโนมัติจากหมุดหน้างาน',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class DeliverySection extends StatefulWidget {
  const DeliverySection({super.key, required this.settings, required this.zones});
  final DeliverySettings settings;
  final List<Zone> zones;

  @override
  State<DeliverySection> createState() => _DeliverySectionState();
}

class _DeliverySectionState extends State<DeliverySection> with _Saver {
  late num _near = widget.settings.nearKm;
  late num _max = widget.settings.maxKm;
  late num _round = widget.settings.roundTo;

  @override
  void didUpdateWidget(covariant DeliverySection old) {
    super.didUpdateWidget(old);
    if (!identical(old.settings, widget.settings)) {
      _near = widget.settings.nearKm;
      _max = widget.settings.maxKm;
      _round = widget.settings.roundTo;
    }
  }

  DeliverySettings get _form => DeliverySettings(nearKm: _near, maxKm: _max, roundTo: _round);

  @override
  Widget build(BuildContext context) {
    final sample = widget.zones.firstOrNull;
    return _SettingsCard(
      title: 'การคำนวณค่าส่งจากระยะ',
      subtitle: 'ระยะวัดจากหมุดหน้างานถึงถนนสายหลักที่ใกล้ที่สุด (เส้นตรง)',
      saving: saving,
      error: saveError,
      saved: saved,
      onSave: () => runSave(() async {
        if (_max <= _near) throw const AppException('ระยะไกลสุดต้องมากกว่าระยะใกล้');
        await saveSetting('delivery', _form.toJson());
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FieldLabel(
                  'ระยะใกล้ (กม.)',
                  hint: 'ไม่เกินนี้ = ราคาต่ำสุด',
                  child: NumberField(value: _near, onChanged: (v) => setState(() => _near = math.max(0, v))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'ระยะไกลสุด (กม.)',
                  hint: 'ตั้งแต่นี้ = ราคาสูงสุด',
                  child: NumberField(value: _max, onChanged: (v) => setState(() => _max = math.max(0, v))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'ปัดขึ้นทีละ (บาท)',
                  child: NumberField(
                    value: _round,
                    decimal: false,
                    onChanged: (v) => setState(() => _round = math.max(0, v)),
                  ),
                ),
              ),
            ],
          ),
          if (sample != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.subtle, borderRadius: BorderRadius.circular(kRadius)),
              child: Text(
                'ตัวอย่าง ต.${sample.name}: ${[1, 5, 8, 12].map((km) => '$km กม. = '
                    '${formatNumber(suggestDeliveryFee(sample.feeMin, sample.feeMax, km, _form))}').join(' · ')}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CompanySection extends StatefulWidget {
  const CompanySection({super.key, required this.company});
  final CompanySettings company;

  @override
  State<CompanySection> createState() => _CompanySectionState();
}

class _CompanySectionState extends State<CompanySection> with _Saver {
  final _nameTh = TextEditingController();
  final _nameEn = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(covariant CompanySection old) {
    super.didUpdateWidget(old);
    if (!identical(old.company, widget.company)) _fill();
  }

  void _fill() {
    final c = widget.company;
    _nameTh.text = c.nameTh;
    _nameEn.text = c.nameEn;
    _address.text = c.address;
    _taxId.text = c.taxId;
    _phone.text = c.phone;
  }

  @override
  void dispose() {
    for (final c in [_nameTh, _nameEn, _address, _taxId, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'หัวบิล',
      subtitle: 'แสดงบนใบส่งของ ใบเสร็จ และใบวางบิล',
      saving: saving,
      error: saveError,
      saved: saved,
      onSave: () => runSave(() => saveSetting(
            'company',
            CompanySettings(
              nameTh: _nameTh.text,
              nameEn: _nameEn.text,
              address: _address.text,
              taxId: _taxId.text,
              phone: _phone.text,
            ).toJson(),
          )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel('ชื่อ (ไทย)', child: TextField(controller: _nameTh)),
          const SizedBox(height: 12),
          FieldLabel('ชื่อ (อังกฤษ)', child: TextField(controller: _nameEn)),
          const SizedBox(height: 12),
          FieldLabel('ที่อยู่', child: TextField(controller: _address, minLines: 2, maxLines: 4)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FieldLabel(
                  'เลขประจำตัวผู้เสียภาษี',
                  child: TextField(controller: _taxId, keyboardType: TextInputType.number),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel('โทร', child: TextField(controller: _phone, keyboardType: TextInputType.phone)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PaymentSection extends StatefulWidget {
  const PaymentSection({super.key, required this.payment});
  final PaymentSettings payment;

  @override
  State<PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<PaymentSection> with _Saver {
  late final _promptPay = TextEditingController(text: widget.payment.promptPayId);
  late final _bank = TextEditingController(text: widget.payment.bankText);

  @override
  void didUpdateWidget(covariant PaymentSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.payment, widget.payment)) {
      _promptPay.text = widget.payment.promptPayId;
      _bank.text = widget.payment.bankText;
    }
  }

  @override
  void dispose() {
    _promptPay.dispose();
    _bank.dispose();
    super.dispose();
  }

  bool get _ppValid => _promptPay.text.isEmpty || promptPayTarget(_promptPay.text) != null;

  @override
  Widget build(BuildContext context) {
    final valid = _ppValid;
    return _SettingsCard(
      title: 'ช่องทางรับเงิน',
      subtitle: 'ถ้าใส่พร้อมเพย์ บิลที่ยังไม่จ่ายจะมี QR ให้ลูกค้าสแกนจ่ายพร้อมยอดเงิน',
      saving: saving,
      error: saveError,
      saved: saved,
      onSave: () => runSave(() async {
        if (!_ppValid) {
          throw const AppException('หมายเลขพร้อมเพย์ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขผู้เสียภาษี 13 หลัก');
        }
        await saveSetting(
          'payment',
          PaymentSettings(promptPayId: _promptPay.text.trim(), bankText: _bank.text.trim()).toJson(),
        );
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(
            'หมายเลขพร้อมเพย์',
            hint: 'เบอร์มือถือ หรือ เลขผู้เสียภาษีของ หจก.',
            child: TextField(
              controller: _promptPay,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(errorText: valid ? null : 'รูปแบบไม่ถูกต้อง'),
            ),
          ),
          const SizedBox(height: 12),
          FieldLabel(
            'ข้อความบัญชีธนาคาร',
            hint: 'เช่น กสิกรไทย 123-4-56789-0 หจก. พีรสิทธิ์ วัสดุก่อสร้าง',
            child: TextField(controller: _bank),
          ),
        ],
      ),
    );
  }
}
