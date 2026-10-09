import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc/pricing.dart';
import '../data/catalog_scope.dart';
import '../data/db.dart';
import '../data/orders_repo.dart';
import '../logic/format.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'new_order/wizard_widgets.dart';

class _Item {
  _Item(OrderItem it)
      : id = it.id,
        productId = it.productId,
        unit = it.unit,
        unitPrice = it.unitPrice,
        quantity = it.quantity,
        discountPerUnit = it.discountPerUnit,
        name = TextEditingController(text: it.name);

  final String? id;
  final String? productId;
  final String unit;
  final TextEditingController name;
  double unitPrice;
  double quantity;
  double discountPerUnit;

  /// Stable widget key; new rows have no id yet.
  final Key key = UniqueKey();

  OrderItem toItem() => OrderItem(
        id: id,
        productId: productId,
        name: name.text,
        unit: unit,
        unitPrice: unitPrice,
        quantity: quantity,
        amount: lineAmount(unitPrice, quantity),
        discountPerUnit: discountPerUnit,
      );
}

/// Full-screen editor for a saved order (SuperAdmin or tour orders). Pops the updated [Order].
class OrderEditScreen extends StatefulWidget {
  const OrderEditScreen({super.key, required this.order, required this.by});
  final Order order;
  final String by;

  @override
  State<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends State<OrderEditScreen> {
  late final Order o = widget.order;
  late String _date = o.orderDate;
  late PaymentMethod _payment = o.paymentMethod;
  late final List<_Item> _items = o.items.map(_Item.new).toList();
  late int? _truck = o.truckSize;
  late int _trips = o.trips;
  late double _fee = o.feePerTrip;
  late double _extra = o.remoteSurcharge;
  late double _deliveryDiscount = o.deliveryDiscount;
  late DiscountType _discountType = o.discountType;
  late double _discountValue = o.discountValue;
  late final _address = TextEditingController(text: o.deliveryAddress);
  late final _note = TextEditingController(text: o.note);
  int _addKey = 0;
  bool _saving = false;
  String _error = '';

  bool get _delivery => o.fulfillment == Fulfillment.delivery;

  @override
  void dispose() {
    for (final it in _items) {
      it.name.dispose();
    }
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  OrderEdit get _edit => OrderEdit(
        orderDate: _date,
        items: _items.map((it) => it.toItem()).toList(),
        truckSize: _truck,
        trips: _trips,
        feePerTrip: _fee,
        remoteSurcharge: _extra,
        deliveryDiscount: _deliveryDiscount,
        discountType: _discountType,
        discountValue: _discountValue,
        paymentMethod: _payment,
        deliveryAddress: _address.text,
        note: _note.text,
      );

  void _addProduct(String id) {
    final p = CatalogScope.read(context).products.where((x) => x.id == id).firstOrNull;
    if (p == null) return;
    setState(() {
      _items.add(_Item(OrderItem(
        productId: p.id,
        name: p.name,
        unit: p.unit,
        unitPrice: p.pricePerUnit,
        quantity: 1,
        amount: 0,
      )));
      _addKey++;
    });
  }

  void _removeItem(_Item it) {
    setState(() => _items.remove(it));
    WidgetsBinding.instance.addPostFrameCallback((_) => it.name.dispose());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'วันที่ออเดอร์',
    );
    if (picked != null) setState(() => _date = toIsoDate(picked));
  }

  Future<void> _submit() async {
    if (!_items.any((it) => it.quantity > 0)) return setState(() => _error = 'ต้องมีสินค้าอย่างน้อย 1 รายการ');
    if (_items.any((it) => it.name.text.trim().isEmpty)) return setState(() => _error = 'กรุณาใส่ชื่อสินค้าให้ครบ');
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final next = await updateOrder(o, _edit, widget.by);
      if (mounted) Navigator.of(context).pop(next);
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
    final products = CatalogScope.of(context).products.where((p) => p.active).toList();
    final totals = editTotals(_edit, o.fulfillment);
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(16.0, (width - 768) / 2);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'ยกเลิก',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('แก้ไขออเดอร์ ${o.orderNo}'),
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
                  'วันที่ออเดอร์',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, backgroundColor: AppColors.surface),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(formatDateTh(_date), style: const TextStyle(fontWeight: FontWeight.w400)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldLabel(
                  'วิธีชำระเงิน',
                  child: DropdownButtonFormField<PaymentMethod>(
                    initialValue: _payment,
                    isExpanded: true,
                    items: [
                      for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: (m) => setState(() => _payment = m ?? _payment),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('รายการสินค้า', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          for (final (i, it) in _items.indexed) ...[
            _ItemEditor(
              key: it.key,
              index: i,
              item: it,
              onChanged: () => setState(() {}),
              onRemove: () => _removeItem(it),
            ),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey('add-$_addKey'),
            isExpanded: true,
            hint: const Text('+ เพิ่มสินค้า'),
            items: [
              for (final p in products)
                DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.name} (${formatMoney(p.pricePerUnit)}/${p.unit})', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              if (id != null) _addProduct(id);
            },
          ),
          if (_delivery) ...[
            const SizedBox(height: 20),
            const Text('การจัดส่ง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 560 ? 5 : 2;
              final w = (c.maxWidth - 12 * (cols - 1)) / cols;
              Widget cell(Widget child) => SizedBox(width: w, child: child);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  cell(FieldLabel(
                    'ขนาดรถ',
                    child: DropdownButtonFormField<int>(
                      initialValue: _truck ?? 0,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('—')),
                        DropdownMenuItem(value: 3, child: Text('3 คิว')),
                        DropdownMenuItem(value: 5, child: Text('5 คิว')),
                      ],
                      onChanged: (v) => setState(() => _truck = (v == null || v == 0) ? null : v),
                    ),
                  )),
                  cell(FieldLabel(
                    'จำนวนเที่ยว',
                    child: NumberField(
                      value: _trips,
                      decimal: false,
                      onChanged: (v) => setState(() => _trips = math.max(0, v).floor()),
                    ),
                  )),
                  cell(FieldLabel(
                    'ค่าส่ง/เที่ยว',
                    child: NumberField(value: _fee, onChanged: (v) => setState(() => _fee = math.max(0, v))),
                  )),
                  cell(FieldLabel(
                    'ค่าส่งเพิ่ม',
                    child: NumberField(value: _extra, onChanged: (v) => setState(() => _extra = math.max(0, v))),
                  )),
                  cell(FieldLabel(
                    'ลดค่าส่ง (บาท)',
                    child: NumberField(
                      value: _deliveryDiscount,
                      onChanged: (v) => setState(() => _deliveryDiscount = math.max(0, v)),
                    ),
                  )),
                ],
              );
            }),
            const SizedBox(height: 12),
            FieldLabel(
              'ที่อยู่จัดส่ง',
              child: TextField(controller: _address, minLines: 2, maxLines: 4, onChanged: (_) => setState(() {})),
            ),
          ],
          const SizedBox(height: 20),
          const Text('ส่วนลด', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: Segmented<DiscountType>(
                  values: DiscountType.values,
                  selected: _discountType,
                  labelOf: (t) => t == DiscountType.baht ? 'บาท' : '%',
                  onChanged: (t) {
                    if (t == _discountType) return;
                    setState(() {
                      _discountType = t;
                      _discountValue = 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumberField(
                  value: _discountValue,
                  semanticLabel: 'ส่วนลด',
                  onChanged: (v) => setState(() {
                    final clamped = math.max(0.0, v);
                    _discountValue = _discountType == DiscountType.percent ? math.min(100.0, clamped) : clamped;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'หมายเหตุ',
            child: TextField(controller: _note, minLines: 2, maxLines: 4),
          ),
          const SizedBox(height: 16),
          AppCard(
            color: AppColors.subtle,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow('ค่าสินค้า', formatMoney(totals.subtotal)),
                if (_delivery) InfoRow('ค่าจัดส่ง', formatMoney(totals.deliveryTotal)),
                if (totals.deliveryDiscount != 0) InfoRow('ส่วนลดค่าส่ง', '-${formatMoney(totals.deliveryDiscount)}'),
                if (totals.discountAmount - totals.deliveryDiscount > 0)
                  InfoRow('ส่วนลด', '-${formatMoney(totals.discountAmount - totals.deliveryDiscount)}'),
                const Divider(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Expanded(child: Text('ยอดสุทธิใหม่', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text(
                      formatMoney(totals.total),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
                if (totals.total != o.total)
                  Text(
                    'เดิม ${formatMoney(o.total)} บาท${o.statementId != null ? ' · ยอดในใบวางบิลจะปรับตามให้อัตโนมัติ' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
        ],
      ),
    );
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({super.key, required this.index, required this.item, required this.onChanged, required this.onRemove});
  final int index;
  final _Item item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final net = lineAmount(it.unitPrice, it.quantity) - lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'ชื่อสินค้า ${index + 1}',
                  child: TextField(controller: it.name, onChanged: (_) => onChanged()),
                ),
              ),
              IconButton(
                tooltip: 'ลบ ${it.name.text}',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: FieldLabel(
                    'จำนวน (${it.unit})',
                    child: NumberField(
                      value: it.quantity,
                      dense: true,
                      onChanged: (v) {
                        it.quantity = math.max(0, v);
                        onChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldLabel(
                    'ราคา/หน่วย',
                    child: NumberField(
                      value: it.unitPrice,
                      dense: true,
                      onChanged: (v) {
                        it.unitPrice = math.max(0, v);
                        it.discountPerUnit = math.min(it.unitPrice, it.discountPerUnit);
                        onChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldLabel(
                    'ลด${it.unit}ละ',
                    child: NumberField(
                      value: it.discountPerUnit,
                      dense: true,
                      onChanged: (v) {
                        it.discountPerUnit = math.min(it.unitPrice, math.max(0, v));
                        onChanged();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'รวม ${formatMoney(net)} บาท',
            style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}
