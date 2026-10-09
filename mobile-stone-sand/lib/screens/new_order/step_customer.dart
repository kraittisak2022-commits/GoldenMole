import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/customers_repo.dart';
import '../../data/db.dart';
import '../../logic/customer_search.dart';
import '../../logic/format.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../tour/tour_controller.dart';
import '../../widgets/ui.dart';
import 'wizard_widgets.dart';

class StepCustomer extends StatefulWidget {
  const StepCustomer({super.key, required this.customer, required this.onSelect});
  final Customer? customer;
  final ValueChanged<Customer?> onSelect;

  @override
  State<StepCustomer> createState() => _StepCustomerState();
}

class _StepCustomerState extends State<StepCustomer> {
  final _query = TextEditingController();
  List<Customer> _results = const [];
  bool _searching = false;
  String _error = '';
  Timer? _debounce;
  int _seq = 0;

  bool _creating = false;
  final _name = TextEditingController();
  final _aliases = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxId = TextEditingController();
  bool _isCredit = false;
  String _formError = '';
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_query, _name, _aliases, _phone, _address, _taxId]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final seq = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await searchCustomers(q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = r;
          _error = '';
        });
      } catch (e) {
        if (!mounted || seq != _seq) return;
        setState(() => _error = errorText(e, 'ค้นหาไม่สำเร็จ'));
      } finally {
        if (mounted && seq == _seq) setState(() => _searching = false);
      }
    });
  }

  void _startCreate() {
    final q = _query.text.trim();
    final digits = digitsOnly(q);
    _name.text = digits.length >= 6 ? '' : q;
    _phone.text = digits.length >= 6 ? digits : '';
    _aliases.clear();
    _address.clear();
    _taxId.clear();
    setState(() {
      _isCredit = false;
      _formError = '';
      _creating = true;
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return setState(() => _formError = 'กรุณาใส่ชื่อลูกค้า');
    final phone = digitsOnly(_phone.text);
    if (phone.isNotEmpty && (phone.length < 9 || phone.length > 10)) {
      return setState(() => _formError = 'เบอร์โทรควรมี 9-10 หลัก');
    }
    setState(() {
      _saving = true;
      _formError = '';
    });
    try {
      final c = await saveCustomer(
        Customer(
          id: '',
          name: _name.text,
          aliases: parseAliases(_aliases.text),
          phone: phone,
          address: _address.text,
          taxId: _taxId.text,
          isCredit: _isCredit,
        ),
        isNew: true,
      );
      if (!mounted) return;
      setState(() => _creating = false);
      _query.clear();
      _results = const [];
      widget.onSelect(c);
    } catch (e) {
      if (mounted) setState(() => _formError = errorText(e, 'บันทึกไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    if (c != null) return _selected(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('ลูกค้า', subtitle: 'ค้นหาจากชื่อ ชื่อเรียก หรือเบอร์โทร หรือเพิ่มลูกค้าใหม่'),
        const SizedBox(height: 16),
        if (!_creating) ..._search() else _form(),
      ],
    );
  }

  Widget _selected(Customer c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle('ลูกค้า', subtitle: 'ข้อมูลนี้จะแสดงบนบิล'),
        const SizedBox(height: 16),
        AppCard(
          color: AppColors.primarySoft.withValues(alpha: 0.5),
          borderColor: AppColors.primary,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        if (c.isCredit) const AppBadge('เครดิตรายเดือน', tone: BadgeTone.info),
                      ],
                    ),
                    if (c.phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: AppColors.muted),
                            const SizedBox(width: 6),
                            Text(formatPhone(c.phone), style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    if (c.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.place_outlined, size: 14, color: AppColors.muted),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(c.address, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.check, color: AppColors.primary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => widget.onSelect(null), child: const Text('เปลี่ยนลูกค้า')),
      ],
    );
  }

  List<Widget> _search() {
    final q = _query.text.trim();
    return [
      TourTarget(
        'wiz-customer-search',
        child: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onQuery,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'ชื่อ ชื่อเรียก หรือ เบอร์โทร',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
      ),
      if (_error.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_error)],
      if (q.isNotEmpty) ...[
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searching && _results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('กำลังค้นหา…', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                ),
              if (!_searching && _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('ไม่พบลูกค้า "$q"', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                ),
              for (var i = 0; i < _results.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _resultRow(_results[i], q),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _startCreate,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
          label: const Text('เพิ่มลูกค้าใหม่'),
        ),
      ),
    ];
  }

  Widget _resultRow(Customer c, String q) {
    final alias = matchedAlias(c.name, c.aliases, q);
    final sub = [if (c.phone.isNotEmpty) formatPhone(c.phone), if (c.address.isNotEmpty) c.address].join(' · ');
    return InkWell(
      onTap: () => widget.onSelect(c),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                    if (alias != null)
                      Text(
                        'ชื่อเรียก: $alias',
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
              if (c.isCredit) const AppBadge('เครดิต', tone: BadgeTone.info),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('ลูกค้าใหม่', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
              ),
              IconButton(
                tooltip: 'ยกเลิก',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _creating = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FieldLabel(
            'ชื่อลูกค้า / ชื่อร้าน *',
            child: TextField(controller: _name, autofocus: true, textInputAction: TextInputAction.next),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'ชื่อเรียก (ถ้ามี · ไว้ค้นหา ไม่แสดงในบิล)',
            hint: 'คั่นหลายชื่อด้วย , เช่น เสี่ยบาส, บาส',
            child: TextField(controller: _aliases, textInputAction: TextInputAction.next),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'เบอร์โทร',
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(hintText: '0xxxxxxxxx'),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'ที่อยู่ (สำหรับออกบิล)',
            child: TextField(
              controller: _address,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'บ้านเลขที่ หมู่ ตำบล'),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'เลขผู้เสียภาษี (ถ้ามี)',
            child: TextField(
              controller: _taxId,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
            ),
          ),
          const SizedBox(height: 8),
          CheckRow(
            boxed: false,
            value: _isCredit,
            onChanged: (v) => setState(() => _isCredit = v),
            child: const Text('ลูกค้าเครดิต (มารับประจำ เคลียร์บิลรายเดือน)'),
          ),
          if (_formError.isNotEmpty) ...[const SizedBox(height: 12), ErrorBox(_formError)],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'กำลังบันทึก…' : 'บันทึกและเลือกลูกค้านี้'),
            ),
          ),
        ],
      ),
    );
  }
}
