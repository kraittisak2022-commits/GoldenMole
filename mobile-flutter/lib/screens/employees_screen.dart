import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/employee_service.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../widgets/page_loading_view.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.service});

  final EmployeeService service;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<List<Employee>> _employeesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _typeFilter = 'All';

  @override
  void initState() {
    super.initState();
    MobileErrorScreenTracker.set(
      page: 'พนักงาน',
      pageId: MobileScreenIds.pageEmployees,
      stepId: MobileScreenIds.stepEmployeesList,
    );
    _employeesFuture = widget.service.fetchEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _employeesFuture = widget.service.fetchEmployees(forceRefresh: true);
    });
  }

  Future<void> _openEditor([Employee? existing]) async {
    final draft = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeEditorSheet(existing: existing),
    );
    if (draft == null) return;
    await _saveEmployee(draft);
    _reload();
  }

  Future<void> _saveEmployee(Employee employee) async {
    await widget.service.upsertEmployee(employee);
  }

  Future<void> _deleteEmployee(Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบพนักงาน'),
        content: Text('ยืนยันลบ ${employee.name} ?'),
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
    await widget.service.deleteEmployee(employee.id);
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
            'พนักงาน',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<List<Employee>>(
          future: _employeesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
            return const PageLoadingView(label: 'กำลังโหลดข้อมูลพนักงาน');
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'โหลดพนักงานไม่สำเร็จ\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final all = snapshot.data ?? const [];
            final q = _searchController.text.trim().toLowerCase();
            final employees = all.where((e) {
              final passType = _typeFilter == 'All' || e.type == _typeFilter;
              if (!passType) return false;
              if (q.isEmpty) return true;
              return e.name.toLowerCase().contains(q) ||
                  e.nickname.toLowerCase().contains(q) ||
                  (e.phone ?? '').toLowerCase().contains(q) ||
                  (e.lineUserId ?? '').toLowerCase().contains(q);
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
                          hintText: 'ค้นหาชื่อ / ชื่อเล่น / เบอร์โทร / LINE User ID',
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
                              label: Text('Daily', style: GoogleFonts.kanit()),
                              selected: _typeFilter == 'Daily',
                              onSelected: (_) =>
                                  setState(() => _typeFilter = 'Daily'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'Monthly',
                                style: GoogleFonts.kanit(),
                              ),
                              selected: _typeFilter == 'Monthly',
                              onSelected: (_) =>
                                  setState(() => _typeFilter = 'Monthly'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'ทั้งหมด ${all.length} คน',
                            style: GoogleFonts.kanit(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'แสดง ${employees.length} คน',
                            style: GoogleFonts.kanit(color: Colors.black45),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: employees.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบข้อมูลพนักงาน',
                            style: GoogleFonts.kanit(),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: employees.length,
                          itemBuilder: (context, index) {
                            final employee = employees[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFDBECFF),
                                  child: Text(
                                    employee.name.isEmpty
                                        ? '?'
                                        : employee.name[0].toUpperCase(),
                                    style: GoogleFonts.kanit(
                                      color: const Color(0xFF1565C0),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  employee.name,
                                  style: GoogleFonts.kanit(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${employee.nickname} • ${employee.type}${employee.baseWage != null ? ' • ${employee.baseWage!.toStringAsFixed(0)} บาท' : ''}${employee.lineUserId != null && employee.lineUserId!.trim().isNotEmpty ? ' • LINE ✓' : ''}',
                                  style: GoogleFonts.kanit(),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _openEditor(employee);
                                      return;
                                    }
                                    if (value == 'delete') {
                                      await _deleteEmployee(employee);
                                    }
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
        floatingActionButton: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
            ),
          ),
          child: FloatingActionButton.extended(
            backgroundColor: Colors.transparent,
            elevation: 0,
            onPressed: _openEditor,
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            label: Text(
              'เพิ่มพนักงาน',
              style: GoogleFonts.kanit(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({this.existing});

  final Employee? existing;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _wageController;
  late final TextEditingController _phoneController;
  late final TextEditingController _lineUserIdController;
  String _type = 'Daily';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _nicknameController = TextEditingController(
      text: widget.existing?.nickname ?? '',
    );
    _wageController = TextEditingController(
      text: widget.existing?.baseWage == null
          ? ''
          : widget.existing!.baseWage!.toStringAsFixed(0),
    );
    _phoneController = TextEditingController(
      text: widget.existing?.phone ?? '',
    );
    _lineUserIdController = TextEditingController(
      text: widget.existing?.lineUserId ?? '',
    );
    _type = widget.existing?.type ?? 'Daily';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _wageController.dispose();
    _phoneController.dispose();
    _lineUserIdController.dispose();
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
                widget.existing == null ? 'เพิ่มพนักงาน' : 'แก้ไขพนักงาน',
                style: GoogleFonts.kanit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'ชื่อ'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(labelText: 'ชื่อเล่น'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                items: const [
                  DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'Daily'),
                decoration: const InputDecoration(labelText: 'ประเภท'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _wageController,
                decoration: const InputDecoration(labelText: 'ค่าแรงพื้นฐาน'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'เบอร์โทร'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _lineUserIdController,
                decoration: const InputDecoration(
                  labelText: 'LINE User ID (ไม่บังคับ)',
                  helperText: 'แจ้งเตือนเมื่อมีการเบิกเงิน',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final id =
                      widget.existing?.id ??
                      DateTime.now().millisecondsSinceEpoch.toString();
                  final employee = Employee(
                    id: id,
                    name: _nameController.text.trim(),
                    nickname: _nicknameController.text.trim(),
                    type: _type,
                    baseWage: double.tryParse(_wageController.text.trim()),
                    phone: _phoneController.text.trim().isEmpty
                        ? null
                        : _phoneController.text.trim(),
                    lineUserId: _lineUserIdController.text.trim().isEmpty
                        ? null
                        : _lineUserIdController.text.trim(),
                    startDate:
                        widget.existing?.startDate ??
                        DateTime.now().toIso8601String().substring(0, 10),
                    position: widget.existing?.position,
                    positions: widget.existing?.positions ?? const [],
                    inactive: widget.existing?.inactive ?? false,
                  );
                  Navigator.pop(context, employee);
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
