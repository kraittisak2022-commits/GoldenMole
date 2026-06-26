import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_transaction.dart';
import '../services/transaction_service.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../widgets/page_loading_view.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.service});

  final TransactionService service;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late Future<List<AppTransaction>> _transactionsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _typeFilter = 'All';

  @override
  void initState() {
    super.initState();
    MobileErrorScreenTracker.set(
      page: 'รายการธุรกรรม',
      pageId: MobileScreenIds.pageTransactions,
      stepId: MobileScreenIds.stepTransactionsList,
    );
    _transactionsFuture = widget.service.fetchTransactions();
  }

  void _reload() {
    setState(() {
      _transactionsFuture = widget.service.fetchTransactions(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor([AppTransaction? existing]) async {
    final draft = await showModalBottomSheet<AppTransaction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransactionEditorSheet(existing: existing),
    );
    if (draft == null) return;
    await widget.service.upsertTransaction(draft);
    _reload();
  }

  Future<void> _delete(AppTransaction item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบรายการ'),
        content: Text('ยืนยันลบ "${item.description}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.deleteTransaction(item.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FA),
        appBar: AppBar(
          title: Text(
            'ธุรกรรม',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<List<AppTransaction>>(
          future: _transactionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
            return const PageLoadingView(label: 'กำลังโหลดข้อมูลธุรกรรม');
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'โหลดธุรกรรมไม่สำเร็จ\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final all = snapshot.data ?? const [];
            final q = _searchController.text.trim().toLowerCase();
            final items = all.where((t) {
              final passType = _typeFilter == 'All' || t.type == _typeFilter;
              if (!passType) return false;
              if (q.isEmpty) return true;
              return t.description.toLowerCase().contains(q) ||
                  t.category.toLowerCase().contains(q) ||
                  t.date.toLowerCase().contains(q);
            }).toList();

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.kanit(),
                        decoration: InputDecoration(
                          hintText: 'ค้นหาธุรกรรม',
                          hintStyle: GoogleFonts.kanit(),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFFF7FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'ทั้งหมด',
                                style: GoogleFonts.kanit(),
                              ),
                              selected: _typeFilter == 'All',
                              onSelected: (_) =>
                                  setState(() => _typeFilter = 'All'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text('รายรับ', style: GoogleFonts.kanit()),
                              selected: _typeFilter == 'Income',
                              onSelected: (_) =>
                                  setState(() => _typeFilter = 'Income'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'รายจ่าย',
                                style: GoogleFonts.kanit(),
                              ),
                              selected: _typeFilter == 'Expense',
                              onSelected: (_) =>
                                  setState(() => _typeFilter = 'Expense'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบรายการธุรกรรม',
                            style: GoogleFonts.kanit(),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final tx = items[index];
                            final income = tx.type.toLowerCase() == 'income';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      (income ? Colors.green : Colors.red)
                                          .withValues(alpha: 0.15),
                                  child: Icon(
                                    income
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: income ? Colors.green : Colors.red,
                                  ),
                                ),
                                title: Text(
                                  tx.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.kanit(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${tx.date} • ${tx.category}',
                                  style: GoogleFonts.kanit(),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') await _openEditor(tx);
                                    if (value == 'delete') await _delete(tx);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('แก้ไข'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('ลบ'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openEditor,
          backgroundColor: const Color(0xFF1565C0),
          icon: const Icon(Icons.add_chart, color: Colors.white),
          label: Text(
            'เพิ่มรายการ',
            style: GoogleFonts.kanit(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _TransactionEditorSheet extends StatefulWidget {
  const _TransactionEditorSheet({this.existing});

  final AppTransaction? existing;

  @override
  State<_TransactionEditorSheet> createState() =>
      _TransactionEditorSheetState();
}

class _TransactionEditorSheetState extends State<_TransactionEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _dateController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  String _type = 'Income';

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController(
      text: widget.existing?.date.isNotEmpty == true
          ? widget.existing!.date
          : DateTime.now().toIso8601String().substring(0, 10),
    );
    _categoryController = TextEditingController(
      text: widget.existing?.category ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _amountController = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.amount.toStringAsFixed(2),
    );
    _type = widget.existing?.type.isNotEmpty == true
        ? widget.existing!.type
        : 'Income';
  }

  @override
  void dispose() {
    _dateController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, bottom + 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'เพิ่มธุรกรรม' : 'แก้ไขธุรกรรม',
                style: GoogleFonts.kanit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: 'วันที่ (YYYY-MM-DD)',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกวันที่' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                items: const [
                  DropdownMenuItem(value: 'Income', child: Text('Income')),
                  DropdownMenuItem(value: 'Expense', child: Text('Expense')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'Income'),
                decoration: const InputDecoration(labelText: 'ประเภท'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกหมวดหมู่' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'รายละเอียด'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกรายละเอียด' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'จำนวนเงิน'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'กรอกจำนวนเงิน';
                  }
                  if (double.tryParse(v.trim()) == null) {
                    return 'จำนวนเงินไม่ถูกต้อง';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final item = AppTransaction(
                    id:
                        widget.existing?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    date: _dateController.text.trim(),
                    type: _type,
                    category: _categoryController.text.trim(),
                    description: _descriptionController.text.trim(),
                    amount: double.parse(_amountController.text.trim()),
                  );
                  Navigator.pop(context, item);
                },
                child: Text('บันทึก', style: GoogleFonts.kanit()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
