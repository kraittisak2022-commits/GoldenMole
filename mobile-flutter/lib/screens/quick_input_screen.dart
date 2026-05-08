import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../utils/daily_module_transactions.dart';

class QuickInputScreen extends StatefulWidget {
  const QuickInputScreen({
    super.key,
    required this.service,
    required this.employeeService,
    this.initialCategory,
    this.appBarTitle,
    /// วันที่ตามที่เลือกบนแดชบอร์ด (ให้โหลดธุรกรรมเดิมของวันนั้นได้)
    this.selectedDateForModule,
  });

  final TransactionService service;
  final EmployeeService employeeService;

  /// ตั้งหมวดหมู่เริ่มต้นเมื่อเปิดจากการ์ดหน้าแรก
  final String? initialCategory;
  final String? appBarTitle;
  final DateTime? selectedDateForModule;

  @override
  State<QuickInputScreen> createState() => _QuickInputScreenState();
}

class _QuickInputScreenState extends State<QuickInputScreen> {
  static const Color _bg = Color(0xFFFDFEFF);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final TextEditingController _categoryController;
  final _sand1MorningController = TextEditingController();
  final _sand1AfternoonController = TextEditingController();
  final _sand2MorningController = TextEditingController();
  final _sand2AfternoonController = TextEditingController();
  final _sandDrumsObtainedController = TextEditingController();
  final _drumsWashedAtHomeController = TextEditingController();
  final _sandMorningStartController = TextEditingController();
  final _sandAfternoonStartController = TextEditingController();
  final _sandEveningEndController = TextEditingController();
  final _vehicleIdController = TextEditingController();
  final _driverIdController = TextEditingController();
  final _vehicleWageController = TextEditingController();
  final _driverWageController = TextEditingController();
  final _vehicleWorkDetailsController = TextEditingController();
  final _tripMorningController = TextEditingController();
  final _tripAfternoonController = TextEditingController();
  final _cubicPerTripController = TextEditingController();
  final _fuelLitersController = TextEditingController();
  final _fuelUnitController = TextEditingController(text: 'ลิตร');
  final _fuelAmountController = TextEditingController();
  final _fuelDetailsController = TextEditingController();
  final _fuelVehicleController = TextEditingController();
  final _fuelVehicleLitersController = TextEditingController();
  final _fuelVehicleTimeController = TextEditingController();
  final _laborDailyWageController = TextEditingController();
  final _laborWorkDetailsController = TextEditingController();
  final _otRateController = TextEditingController();
  final _otHoursController = TextEditingController();
  final _otDescController = TextEditingController();
  List<Employee> _employees = const [];
  List<Employee> _driverEmployees = const [];
  List<String> _cars = const [];

  late DateTime _selectedDate;
  bool _saving = false;
  String? _activeSignatureNote;
  List<String> _otDescSuggestions = const [];
  List<AppTransaction> _moduleDayTransactions = const [];
  bool _moduleDayLoading = false;
  /// แสดงรายการประวัติเฉพาะเมื่อผู้ใช้กด (ค่าเริ่มต้นซ่อน)
  bool _moduleHistoryVisible = false;

  /// แถวที่โหลดจากระบบ (คงค่า created_at เดิมเมื่ออัปเดตซ้ำ)
  final Set<String> _persistOmitCreatedForIds = {};
  /// แถวที่บันทึกในวงจรนี้แล้ว — อย่ายิง created_at ซ้ำ
  final Set<String> _persistOmitCreatedSessionIds = {};
  final Map<String, String> _sandRowIdsByKey = {};
  List<String> _sand1OperatorNames = const [];
  List<String> _sand2OperatorNames = const [];
  String? _vehicleMainTxId;
  String? _vehicleTripTxId;
  String? _fuelStockInTxId;
  String? _fuelVehicleUseTxId;
  String? _laborTxId;
  String? _otTxId;
  String? _homeSandTxId;
  String? _genericTxId;
  bool get _isSandWashMode =>
      (widget.initialCategory ?? '').contains('ร่อนทราย');
  bool get _isVehicleTripMode =>
      (widget.initialCategory ?? '').contains('เที่ยวรถ');
  bool get _isFuelMode => (widget.initialCategory ?? '').contains('น้ำมัน');
  bool get _isHomeSandMode =>
      (widget.initialCategory ?? '').contains('ทรายที่ล้างที่บ้าน');
  String _vehicleWorkType = 'FullDay';
  String _fuelType = 'Diesel';
  String _fuelVehicleType = 'Diesel';
  String _laborWorkType = 'FullDay';
  final Set<String> _selectedLaborEmpIds = {};
  bool get _isLaborMode =>
      widget.initialCategory == 'ค่าแรง' ||
      (widget.initialCategory ?? '').contains('บันทึกการทำงาน');
  bool get _isOtMode => (widget.initialCategory ?? '').contains('OT');

  @override
  void initState() {
    super.initState();
    final d = widget.selectedDateForModule ?? DateTime.now();
    _selectedDate = DateTime(d.year, d.month, d.day);
    _categoryController = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory!.trim()
          : 'ค่าแรง',
    );
    _loadEmployees();
    _loadAppCars();
    _loadOtSuggestions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadModuleTransactions());
  }

  String _quickYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _persist(AppTransaction t) async {
    final omitCreated = _persistOmitCreatedForIds.contains(t.id) ||
        _persistOmitCreatedSessionIds.contains(t.id);
    await widget.service.upsertTransaction(t, omitCreatedAt: omitCreated);
    _persistOmitCreatedSessionIds.add(t.id);
  }

  void _clearHydrationSlots() {
    _persistOmitCreatedForIds.clear();
    _persistOmitCreatedSessionIds.clear();
    _sandRowIdsByKey.clear();
    _vehicleMainTxId = null;
    _vehicleTripTxId = null;
    _fuelStockInTxId = null;
    _fuelVehicleUseTxId = null;
    _laborTxId = null;
    _otTxId = null;
    _homeSandTxId = null;
    _genericTxId = null;
  }

  /// ล้างฟอร์มก่อนโหลดวันใหม่ เพื่อไม่ให้เหลือค่าจากวันก่อนหน้า
  void _clearModuleFormFields() {
    if (_isSandWashMode) {
      _sand1MorningController.clear();
      _sand1AfternoonController.clear();
      _sand2MorningController.clear();
      _sand2AfternoonController.clear();
      _sandDrumsObtainedController.clear();
      _sandMorningStartController.clear();
      _sandAfternoonStartController.clear();
      _sandEveningEndController.clear();
      _sand1OperatorNames = const [];
      _sand2OperatorNames = const [];
    } else if (_isHomeSandMode) {
      _sandDrumsObtainedController.clear();
      _drumsWashedAtHomeController.clear();
    } else if (_isVehicleTripMode) {
      _vehicleIdController.clear();
      _driverIdController.clear();
      _vehicleWageController.clear();
      _driverWageController.clear();
      _vehicleWorkDetailsController.clear();
      _tripMorningController.clear();
      _tripAfternoonController.clear();
      _cubicPerTripController.clear();
    } else if (_isFuelMode) {
      _fuelLitersController.clear();
      _fuelAmountController.clear();
      _fuelDetailsController.clear();
      _fuelVehicleController.clear();
      _fuelVehicleLitersController.clear();
      _fuelVehicleTimeController.clear();
    } else if (_isLaborMode) {
      _selectedLaborEmpIds.clear();
      _laborDailyWageController.clear();
      _laborWorkDetailsController.clear();
    } else if (_isOtMode) {
      _selectedLaborEmpIds.clear();
      _otRateController.clear();
      _otHoursController.clear();
      _otDescController.clear();
    } else {
      _amountController.clear();
      _descriptionController.clear();
    }
  }

  Future<void> _loadModuleTransactions() async {
    final cat = widget.initialCategory?.trim();
    if (!mounted || cat == null || cat.isEmpty) return;
    setState(() {
      _moduleDayLoading = true;
      _moduleHistoryVisible = false;
    });
    _clearHydrationSlots();
    _clearModuleFormFields();
    try {
      final ymd = _quickYmd(_selectedDate);
      final rows = await widget.service.fetchTransactionsForDate(ymd);
      final matched = rows
          .where((t) => transactionMatchesDailyModule(t, ymd, cat))
          .toList();
      matched.sort((a, b) {
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      if (!mounted) return;
      for (final t in matched) {
        _persistOmitCreatedForIds.add(t.id);
      }
      setState(() {
        _moduleDayTransactions = matched;
        _moduleDayLoading = false;
        _moduleHistoryVisible = false;
      });
      _hydrateFormsFromTransactions(matched);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _moduleDayTransactions = const [];
        _moduleDayLoading = false;
        _moduleHistoryVisible = false;
      });
    }
  }

  static String _strNum(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return '${v.round()}';
    final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }

  String _stripRecorderSuffix(String raw) =>
      raw.replaceAll(RegExp(r'\s*\(ผู้กรอก:[^)]+\)\s*$'), '').trim();

  String _employeeLabelFromIdOrName(String raw) {
    final token = raw.trim();
    if (token.isEmpty) return '';
    for (final e in _employees) {
      if (e.id == token) {
        return (e.nickname.isNotEmpty ? e.nickname : e.name).trim();
      }
    }
    return token;
  }

  List<String> _extractNamesFromDescription(String description) {
    final plain = _stripRecorderSuffix(description);
    final m = RegExp(r'\[([^\]]+)\]').firstMatch(plain);
    if (m == null) return const [];
    return m.group(1)!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _operatorNamesFromTransaction(AppTransaction t) {
    final fromIds = t.sandOperators
        .map(_employeeLabelFromIdOrName)
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (fromIds.isNotEmpty) return fromIds;
    return _extractNamesFromDescription(t.description);
  }

  void _hydrateFormsFromTransactions(List<AppTransaction> txs) {
    if (txs.isEmpty) return;
    void setIfEmpty(TextEditingController c, String val) {
      if (val.isEmpty) return;
      if (c.text.trim().isEmpty) c.text = val;
    }

    if (_isSandWashMode) {
      var inferredMaxDrums = 0.0;
      List<String> oldMachineNames = const [];
      List<String> newMachineNames = const [];
      for (final t in txs) {
        final rowDrums = t.drumsObtained ?? 0;
        if (rowDrums > inferredMaxDrums) {
          inferredMaxDrums = rowDrums;
        }
        final mt = (t.sandMachineType ?? '').toLowerCase();
        if (mt == 'old' ||
            (t.description).contains('เครื่องร่อน 1')) {
          _sandRowIdsByKey.putIfAbsent('Old', () => t.id);
          _sand1MorningController.text =
              _strNum(t.sandMorning);
          _sand1AfternoonController.text =
              _strNum(t.sandAfternoon);
          final names = _operatorNamesFromTransaction(t);
          if (oldMachineNames.isEmpty && names.isNotEmpty) {
            oldMachineNames = names;
          }
        } else if (mt == 'new' ||
            (t.description).contains('เครื่องร่อน 2')) {
          _sandRowIdsByKey.putIfAbsent('New', () => t.id);
          _sand2MorningController.text =
              _strNum(t.sandMorning);
          _sand2AfternoonController.text =
              _strNum(t.sandAfternoon);
          final names = _operatorNamesFromTransaction(t);
          if (newMachineNames.isEmpty && names.isNotEmpty) {
            newMachineNames = names;
          }
        } else if (t.description.contains('จำนวนถัง')) {
          _sandRowIdsByKey.putIfAbsent('drums', () => t.id);
          _sandDrumsObtainedController.text = _strNum(t.drumsObtained);
        }
        if (t.sandMorningStart?.isNotEmpty == true) {
          _sandMorningStartController.text = t.sandMorningStart!;
        }
        if (t.sandAfternoonStart?.isNotEmpty == true) {
          _sandAfternoonStartController.text = t.sandAfternoonStart!;
        }
        if (t.sandEveningEnd?.isNotEmpty == true) {
          _sandEveningEndController.text = t.sandEveningEnd!;
        }
      }
      // Fallback: if no dedicated "จำนวนถัง" row exists, use max drums from Sand rows.
      if (_sandDrumsObtainedController.text.trim().isEmpty && inferredMaxDrums > 0) {
        _sandDrumsObtainedController.text = _strNum(inferredMaxDrums);
      }
      _sand1OperatorNames = oldMachineNames;
      _sand2OperatorNames = newMachineNames;
      return;
    }

    if (_isHomeSandMode) {
      final t = txs.first;
      _homeSandTxId = t.id;
      _sandDrumsObtainedController.text =
          _strNum(t.drumsObtained);
      _drumsWashedAtHomeController.text =
          _strNum(t.drumsWashedAtHome);
      return;
    }

    if (_isVehicleTripMode) {
      for (final t in txs) {
        if (t.category == 'Vehicle') {
          _vehicleMainTxId = t.id;
          _vehicleIdController.text = t.vehicleId ?? '';
          _driverIdController.text = t.driverId ?? '';
          _vehicleWageController.text = _strNum(t.vehicleWage);
          _driverWageController.text = _strNum(t.driverWage);
          _vehicleWorkDetailsController.text =
              _stripRecorderSuffix(t.workDetails ?? '');
          _vehicleWorkType = (t.workType == 'HalfDay') ? 'HalfDay' : 'FullDay';
        } else if (t.subCategory == 'VehicleTrip' ||
            (t.category == 'DailyLog' && (t.perCarTrips ?? t.tripCount ?? 0) > 0)) {
          _vehicleTripTxId = t.id;
          _tripMorningController.text =
              _strNum(t.tripMorning);
          _tripAfternoonController.text =
              _strNum(t.tripAfternoon);
          _cubicPerTripController.text =
              _strNum(t.cubicPerTrip);
        }
      }
      return;
    }

    if (_isFuelMode) {
      for (final t in txs) {
        if (t.fuelMovement == 'stock_out') {
          _fuelVehicleUseTxId = t.id;
          _fuelVehicleController.text = t.vehicleId ?? '';
          _fuelVehicleLitersController.text = _strNum(t.quantity);
          _fuelVehicleTimeController.text =
              _stripRecorderSuffix(t.workDetails ?? '');
          if ((t.fuelType ?? '').isNotEmpty) {
            _fuelVehicleType =
                t.fuelType == 'Gasoline' ? 'Gasoline' : 'Diesel';
          }
        } else if (t.fuelMovement == 'stock_in') {
          _fuelStockInTxId = t.id;
          _fuelLitersController.text = _strNum(t.quantity);
          _fuelAmountController.text =
              _strNum((t.amount).abs() > 0 ? t.amount : null);
          _fuelDetailsController.text =
              _stripRecorderSuffix(t.workDetails ?? '');
          final u = (t.unit ?? '').toLowerCase();
          if (u == 'gallon') _fuelUnitController.text = 'แกลลอน';
          if ((t.fuelType ?? '').isNotEmpty) {
            _fuelType = t.fuelType == 'Gasoline' ? 'Gasoline' : 'Diesel';
          }
        }
      }
      return;
    }

    if (_isLaborMode) {
      final t =
          txs.firstWhere((x) => (x.amount) > 0, orElse: () => txs.first);
      _laborTxId = t.id;
      _selectedLaborEmpIds
        ..clear()
        ..addAll(t.employeeIds);
      final mult = ((t.workType ?? '') == 'HalfDay') ? 0.5 : 1.0;
      if (mult > 0 && (t.amount) > 0 && t.employeeIds.isNotEmpty) {
        _laborDailyWageController.text = _strNum(
          (t.amount) / (t.employeeIds.length * mult),
        );
      }
      _laborWorkDetailsController.text =
          _stripRecorderSuffix(t.workDetails ?? '');
      _laborWorkType = (t.workType == 'HalfDay') ? 'HalfDay' : 'FullDay';
      return;
    }

    if (_isOtMode) {
      final t = txs.first;
      _otTxId = t.id;
      _selectedLaborEmpIds
        ..clear()
        ..addAll(t.employeeIds);
      _otRateController.text = _strNum(t.otAmount ?? t.amount);
      _otHoursController.text = _strNum(t.otHours);
      _otDescController.text =
          _stripRecorderSuffix(t.otDescription ?? '');
      return;
    }

    final g = txs.first;
    _genericTxId = g.id;
    _amountController.text = _strNum(g.amount);
    _descriptionController.text =
        _stripRecorderSuffix(g.description);
    if (g.category.isNotEmpty &&
        _categoryController.text.trim().isEmpty) {
      _categoryController.text = g.category;
    }
    setIfEmpty(_categoryController, g.category);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _sand1MorningController.dispose();
    _sand1AfternoonController.dispose();
    _sand2MorningController.dispose();
    _sand2AfternoonController.dispose();
    _sandDrumsObtainedController.dispose();
    _drumsWashedAtHomeController.dispose();
    _sandMorningStartController.dispose();
    _sandAfternoonStartController.dispose();
    _sandEveningEndController.dispose();
    _vehicleIdController.dispose();
    _driverIdController.dispose();
    _vehicleWageController.dispose();
    _driverWageController.dispose();
    _vehicleWorkDetailsController.dispose();
    _tripMorningController.dispose();
    _tripAfternoonController.dispose();
    _cubicPerTripController.dispose();
    _fuelLitersController.dispose();
    _fuelUnitController.dispose();
    _fuelAmountController.dispose();
    _fuelDetailsController.dispose();
    _fuelVehicleController.dispose();
    _fuelVehicleLitersController.dispose();
    _fuelVehicleTimeController.dispose();
    _laborDailyWageController.dispose();
    _laborWorkDetailsController.dispose();
    _otRateController.dispose();
    _otHoursController.dispose();
    _otDescController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await widget.employeeService.fetchEmployees();
      list.sort((a, b) {
        return (a.nickname.isNotEmpty ? a.nickname : a.name).compareTo(
          b.nickname.isNotEmpty ? b.nickname : b.name,
        );
      });
      if (!mounted) return;
      setState(() {
        _employees = list;
        _driverEmployees = list.where((e) {
          final pos = (e.position ?? '').toLowerCase();
          return pos.contains('คนขับ') || pos.contains('driver');
        }).toList();
      });
      if (_isSandWashMode && _moduleDayTransactions.isNotEmpty) {
        setState(() {
          _hydrateFormsFromTransactions(_moduleDayTransactions);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAppCars() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('app_settings')
          .select('cars')
          .eq('id', 'default')
          .limit(1);
      if (rows.isEmpty) return;
      final raw = rows.first['cars'];
      final cars = <String>[
        if (raw is List)
          ...raw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
      ];
      if (!mounted) return;
      setState(() => _cars = cars);
    } catch (_) {}
  }

  Future<void> _loadOtSuggestions() async {
    try {
      final txs = await widget.service.fetchTransactions();
      final ranked = <String, int>{};
      for (final tx in txs) {
        if (tx.category != 'Labor') continue;
        final status = (tx.laborStatus ?? '').toLowerCase();
        final sub = (tx.subCategory ?? '').toLowerCase();
        if (status != 'ot' && sub != 'ot') continue;
        final raw = (tx.otDescription ?? tx.description).trim();
        if (raw.isEmpty) continue;
        ranked[raw] = (ranked[raw] ?? 0) + 1;
      }
      final sorted = ranked.entries.toList()
        ..sort((a, b) {
          final c = b.value.compareTo(a.value);
          if (c != 0) return c;
          return a.key.compareTo(b.key);
        });
      if (!mounted) return;
      setState(() {
        _otDescSuggestions = sorted.map((e) => e.key).take(10).toList();
      });
    } catch (_) {}
  }

  static const Duration _successPopupHold = Duration(milliseconds: 1400);

  void _showSavingPopup() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Row(
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.8),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'กำลังบันทึกข้อมูล',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissSavingPopup() {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _showSuccessPopupAndPopToHome(String message) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 56,
                color: Colors.green.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(_successPopupHold);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _runSaveWithPopups({
    required Future<void> Function() body,
    required String successMessage,
  }) async {
    if (!mounted) return;
    final signature = await _requestSignatureBeforeSave();
    if (signature == null) return;
    _activeSignatureNote = signature.note;
    setState(() => _saving = true);
    var savingDialogOpen = false;
    try {
      _showSavingPopup();
      savingDialogOpen = true;
      await body();
      if (!mounted) return;
      _dismissSavingPopup();
      savingDialogOpen = false;
      await _showSuccessPopupAndPopToHome(successMessage);
    } catch (error) {
      if (savingDialogOpen && mounted) _dismissSavingPopup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')),
        );
      }
    } finally {
      _activeSignatureNote = null;
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveQuickEntry() async {
    if (_isSandWashMode) {
      await _saveSandWashEntry();
      return;
    }
    if (_isVehicleTripMode) {
      await _saveVehicleTripEntry();
      return;
    }
    if (_isFuelMode) {
      await _saveFuelStockInEntry();
      return;
    }
    if (_isHomeSandMode) {
      await _saveHomeSandEntry();
      return;
    }
    if (_isLaborMode) {
      await _saveLaborEntry();
      return;
    }
    if (_isOtMode) {
      await _saveOtEntry();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    await _runSaveWithPopups(
      successMessage: 'บันทึกข้อมูลสำเร็จ',
      body: () async {
        final description = _appendRecorder(_descriptionController.text.trim());

        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final gid = _genericTxId ??
            DateTime.now().millisecondsSinceEpoch.toString();
        _genericTxId = gid;
        final entry = AppTransaction(
          id: gid,
          date: '$y-$m-$d',
          type: 'Expense',
          category: _categoryController.text.trim(),
          description: description,
          amount: double.parse(_amountController.text.trim()),
          note: _activeSignatureNote,
        );

        await _persist(entry);
        _amountController.clear();
        _descriptionController.clear();
      },
    );
  }

  Future<void> _saveSandWashEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกล้างทรายสำเร็จ',
      body: () async {
      final s1m = double.tryParse(_sand1MorningController.text.trim()) ?? 0;
      final s1a = double.tryParse(_sand1AfternoonController.text.trim()) ?? 0;
      final s2m = double.tryParse(_sand2MorningController.text.trim()) ?? 0;
      final s2a = double.tryParse(_sand2AfternoonController.text.trim()) ?? 0;
      final drums = double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
      final total = s1m + s1a + s2m + s2a;
      final hadPriorSandRows = _sandRowIdsByKey.isNotEmpty;
      if (total <= 0 && drums <= 0 && !hadPriorSandRows) {
        throw 'กรุณากรอกอย่างน้อยจำนวนคิวทรายหรือจำนวนถัง (บันทึกได้ทีละช่วงแล้วกลับมาเพิ่มภายหลังได้)';
      }

      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final date = '$y-$m-$d';
      // Keep category aligned with web Daily Wizard schema.
      final commonCategory = 'DailyLog';
      final commonSub = 'Sand';
      final morningStart = _sandMorningStartController.text.trim();
      final afternoonStart = _sandAfternoonStartController.text.trim();
      final eveningEnd = _sandEveningEndController.text.trim();

      Future<void> saveMachine({
        required String suffix,
        required String machineType,
        required String description,
        required double morning,
        required double afternoon,
      }) async {
        final sandKey = machineType == 'Old' ? 'Old' : 'New';
        final existingRow = _sandRowIdsByKey[sandKey];
        if (morning + afternoon <= 0 && existingRow == null) return;
        final tid = existingRow ??
            '${DateTime.now().millisecondsSinceEpoch}_$suffix';
        _sandRowIdsByKey[sandKey] = tid;
        final tx = AppTransaction(
          id: tid,
          date: date,
          type: 'Expense',
          category: commonCategory,
          subCategory: commonSub,
          description: _appendRecorder(description),
          amount: 0,
          sandMorning: morning,
          sandAfternoon: afternoon,
          sandMachineType: machineType,
          drumsObtained: drums,
          drumsWashedAtHome: 0,
          note: _activeSignatureNote,
          sandMorningStart: morningStart.isEmpty ? null : morningStart,
          sandAfternoonStart: afternoonStart.isEmpty ? null : afternoonStart,
          sandEveningEnd: eveningEnd.isEmpty ? null : eveningEnd,
        );
        await _persist(tx);
      }

      await saveMachine(
        suffix: 's1',
        machineType: 'Old',
        description: 'ล้างทราย เครื่องร่อน 1 (เก่า)',
        morning: s1m,
        afternoon: s1a,
      );
      await saveMachine(
        suffix: 's2',
        machineType: 'New',
        description: 'ล้างทราย เครื่องร่อน 2 (ใหม่)',
        morning: s2m,
        afternoon: s2a,
      );

      final hasDrumsRow = _sandRowIdsByKey.containsKey('drums');
      // Keep a dedicated drums row whenever user provides drums,
      // so the data shape matches Daily Wizard expectations.
      final persistDrums = hasDrumsRow || drums > 0;
      if (persistDrums && (hasDrumsRow || drums > 0)) {
        final drumsId = _sandRowIdsByKey['drums'] ??
            '${DateTime.now().millisecondsSinceEpoch}_drums';
        _sandRowIdsByKey['drums'] = drumsId;
        await _persist(
          AppTransaction(
            id: drumsId,
            date: date,
            type: 'Expense',
            category: commonCategory,
            subCategory: commonSub,
            description: _appendRecorder('จำนวนถังที่ได้วันนี้'),
            amount: 0,
            drumsObtained: drums,
            drumsWashedAtHome: 0,
            note: _activeSignatureNote,
            sandMorningStart: morningStart.isEmpty ? null : morningStart,
            sandAfternoonStart: afternoonStart.isEmpty ? null : afternoonStart,
            sandEveningEnd: eveningEnd.isEmpty ? null : eveningEnd,
          ),
        );
      }

      _sand1MorningController.clear();
      _sand1AfternoonController.clear();
      _sand2MorningController.clear();
      _sand2AfternoonController.clear();
      _sandDrumsObtainedController.clear();
      _sandMorningStartController.clear();
      _sandAfternoonStartController.clear();
      _sandEveningEndController.clear();
      },
    );
  }

  Future<void> _saveHomeSandEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกทรายที่ล้างที่บ้านสำเร็จ',
      body: () async {
      final drums = double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
      final drumsHome =
          double.tryParse(_drumsWashedAtHomeController.text.trim()) ?? 0;
      if (drums <= 0 && drumsHome <= 0) {
        throw 'กรุณากรอกจำนวนถังอย่างน้อย 1 ค่า';
      }
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final homeId = _homeSandTxId ??
          '${DateTime.now().millisecondsSinceEpoch}_home_sand';
      _homeSandTxId = homeId;
      await _persist(
        AppTransaction(
          id: homeId,
          date: '$y-$m-$d',
          type: 'Expense',
          // Keep category aligned with web Daily Wizard schema.
          category: 'DailyLog',
          subCategory: 'Sand',
          description: _appendRecorder('ทรายที่ล้างที่บ้าน'),
          amount: 0,
          drumsObtained: drums,
          drumsWashedAtHome: drumsHome,
          note: _activeSignatureNote,
        ),
      );
      _sandDrumsObtainedController.clear();
      _drumsWashedAtHomeController.clear();
      },
    );
  }

  Future<void> _saveVehicleTripEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกรถและเที่ยวรถสำเร็จ',
      body: () async {
      final vehicle = _vehicleIdController.text.trim();
      final driver = _driverIdController.text.trim();
      final details = _vehicleWorkDetailsController.text.trim();
      final vehicleWage = double.tryParse(_vehicleWageController.text.trim()) ?? 0;
      final driverWage = double.tryParse(_driverWageController.text.trim()) ?? 0;
      final tripMorning = double.tryParse(_tripMorningController.text.trim()) ?? 0;
      final tripAfternoon =
          double.tryParse(_tripAfternoonController.text.trim()) ?? 0;
      final totalTrips = tripMorning + tripAfternoon;
      final cubicPerTrip = double.tryParse(_cubicPerTripController.text.trim()) ?? 0;
      if (vehicle.isEmpty || driver.isEmpty) {
        throw 'กรุณาระบุรถและคนขับ';
      }
      if (vehicleWage < 0 || driverWage < 0) throw 'ค่าจ้างต้องไม่ติดลบ';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final date = '$y-$m-$d';
      final mainVehId = _vehicleMainTxId ??
          '${DateTime.now().millisecondsSinceEpoch}_veh';
      _vehicleMainTxId = mainVehId;
      await _persist(
        AppTransaction(
          id: mainVehId,
          date: date,
          type: 'Expense',
          category: 'Vehicle',
          description:
              _appendRecorder(
                'รถ: $vehicle (${details.isEmpty ? '-' : details}) [${_vehicleWorkType == 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}]',
              ),
          amount: vehicleWage + driverWage,
          note: _activeSignatureNote,
          vehicleId: vehicle,
          driverId: driver,
          vehicleWage: vehicleWage,
          driverWage: driverWage,
          workDetails: _appendRecorder(details),
          workType: _vehicleWorkType,
        ),
      );
      if (totalTrips > 0) {
        final totalCubic = totalTrips * cubicPerTrip;
        final tripId = _vehicleTripTxId ??
            '${DateTime.now().millisecondsSinceEpoch}_trip';
        _vehicleTripTxId = tripId;
        await _persist(
          AppTransaction(
            id: tripId,
            date: date,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            description:
                _appendRecorder(
                  '$vehicle: ${totalTrips.toStringAsFixed(0)} เที่ยว × ${cubicPerTrip.toStringAsFixed(0)} คิว',
                ),
            amount: 0,
            note: _activeSignatureNote,
            vehicleId: vehicle,
            driverId: driver,
            tripCount: totalTrips,
            tripMorning: tripMorning,
            tripAfternoon: tripAfternoon,
            cubicPerTrip: cubicPerTrip,
            totalCubic: totalCubic,
            perCarTrips: totalTrips,
            perCarCubic: totalCubic,
            workDetails: _appendRecorder(details),
          ),
        );
      }
      _vehicleIdController.clear();
      _driverIdController.clear();
      _vehicleWageController.clear();
      _driverWageController.clear();
      _vehicleWorkDetailsController.clear();
      _tripMorningController.clear();
      _tripAfternoonController.clear();
      _cubicPerTripController.clear();
      },
    );
  }

  Future<void> _saveFuelStockInEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกซื้อน้ำมันสำเร็จ',
      body: () async {
      final liters = double.tryParse(_fuelLitersController.text.trim()) ?? 0;
      final amount = double.tryParse(_fuelAmountController.text.trim()) ?? 0;
      if (amount <= 0) throw 'กรุณาระบุราคาซื้อน้ำมัน';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final unit = _fuelUnitController.text.trim() == 'แกลลอน' ? 'gallon' : 'L';
      final fuelInId = _fuelStockInTxId ??
          '${DateTime.now().millisecondsSinceEpoch}_fuel_in';
      _fuelStockInTxId = fuelInId;
      await _persist(
        AppTransaction(
          id: fuelInId,
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Fuel',
          description:
              _appendRecorder(
                'ซื้อน้ำมัน ${_fuelType == 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${liters.toStringAsFixed(0)} ${_fuelUnitController.text} ${amount.toStringAsFixed(0)} บาท',
              ),
          amount: amount,
          note: _activeSignatureNote,
          quantity: liters,
          unit: unit,
          fuelType: _fuelType,
          fuelMovement: 'stock_in',
          workDetails: _appendRecorder(_fuelDetailsController.text.trim()),
        ),
      );
      _fuelLitersController.clear();
      _fuelAmountController.clear();
      _fuelDetailsController.clear();
      },
    );
  }

  Future<void> _saveFuelVehicleUsageEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกการใช้น้ำมันรายรถสำเร็จ',
      body: () async {
      final vehicle = _fuelVehicleController.text.trim();
      final liters = double.tryParse(_fuelVehicleLitersController.text.trim()) ?? 0;
      if (vehicle.isEmpty) throw 'กรุณาระบุรถ';
      if (liters <= 0) throw 'กรุณาระบุปริมาณน้ำมัน';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final fuelOutId = _fuelVehicleUseTxId ??
          '${DateTime.now().millisecondsSinceEpoch}_fuel_out';
      _fuelVehicleUseTxId = fuelOutId;
      await _persist(
        AppTransaction(
          id: fuelOutId,
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Fuel',
          subCategory: 'VehicleUsage',
          description:
              _appendRecorder(
                'ใช้น้ำมันรถ $vehicle: ${liters.toStringAsFixed(0)} ลิตร (${_fuelVehicleType == 'Diesel' ? 'ดีเซล' : 'เบนซิน'})',
              ),
          amount: 0,
          note: _activeSignatureNote,
          quantity: liters,
          unit: 'L',
          fuelType: _fuelVehicleType,
          fuelMovement: 'stock_out',
          vehicleId: vehicle,
          workDetails: _appendRecorder(_fuelVehicleTimeController.text.trim()),
        ),
      );
      _fuelVehicleLitersController.clear();
      _fuelVehicleTimeController.clear();
      },
    );
  }

  Future<void> _saveLaborEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกค่าแรงสำเร็จ',
      body: () async {
      if (_selectedLaborEmpIds.isEmpty) throw 'กรุณาเลือกพนักงาน';
      final wage = double.tryParse(_laborDailyWageController.text.trim()) ?? 0;
      if (wage <= 0) throw 'กรุณาระบุค่าแรงต่อวัน';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final multiplier = _laborWorkType == 'HalfDay' ? 0.5 : 1.0;
      final total = wage * _selectedLaborEmpIds.length * multiplier;
      final names = _selectedLaborEmpIds
          .map((id) {
            for (final e in _employees) {
              if (e.id == id) return e.nickname.isNotEmpty ? e.nickname : e.name;
            }
            return '';
          })
          .where((e) => e.isNotEmpty)
          .join(', ');
      final laborId = _laborTxId ??
          '${DateTime.now().millisecondsSinceEpoch}_labor';
      _laborTxId = laborId;
      await _persist(
        AppTransaction(
          id: laborId,
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Labor',
          subCategory: 'Attendance',
          laborStatus: 'Work',
          employeeIds: _selectedLaborEmpIds.toList(),
          workType: _laborWorkType,
          amount: total,
          note: _activeSignatureNote,
          description:
              _appendRecorder(
                'ค่าแรง (${_selectedLaborEmpIds.length} คน) ${_laborWorkType == 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}${names.isNotEmpty ? ' [$names]' : ''}',
              ),
          workDetails: _appendRecorder(_laborWorkDetailsController.text.trim()),
        ),
      );
      _selectedLaborEmpIds.clear();
      _laborDailyWageController.clear();
      _laborWorkDetailsController.clear();
      },
    );
  }

  Future<void> _saveOtEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึก OT สำเร็จ',
      body: () async {
      if (_selectedLaborEmpIds.isEmpty) throw 'กรุณาเลือกพนักงาน';
      final rate = double.tryParse(_otRateController.text.trim()) ?? 0;
      final hours = double.tryParse(_otHoursController.text.trim()) ?? 0;
      if (rate <= 0) throw 'กรุณาระบุค่า OT';
      if (hours <= 0) throw 'กรุณาระบุชั่วโมง OT';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final total = rate * hours * _selectedLaborEmpIds.length;
      final otId =
          _otTxId ?? '${DateTime.now().millisecondsSinceEpoch}_ot';
      _otTxId = otId;
      await _persist(
        AppTransaction(
          id: otId,
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Labor',
          subCategory: 'OT',
          laborStatus: 'OT',
          employeeIds: _selectedLaborEmpIds.toList(),
          amount: total,
          note: _activeSignatureNote,
          otAmount: rate,
          otHours: hours,
          otDescription: _otDescController.text.trim(),
          description:
              _appendRecorder(
                'OT ${_otDescController.text.trim()} (${hours.toStringAsFixed(1)}ชม.) ${_selectedLaborEmpIds.length} คน',
              ),
        ),
      );
      _selectedLaborEmpIds.clear();
      _otRateController.clear();
      _otHoursController.clear();
      _otDescController.clear();
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _selectedDate =
            DateTime(picked.year, picked.month, picked.day),
      );
      await _loadModuleTransactions();
    }
  }

  List<String> _presets() {
    final c = _categoryController.text.trim();
    if (c.contains('น้ำมัน')) {
      return ['เติมรถหัวลาก', 'ซื้อเข้าสต็อก', 'เติมรถแบคโฮ'];
    }
    if (c.contains('OT')) {
      return ['ทำงานล่วงเวลา 2 ชม.', 'ซ่อมงานด่วน', 'กะกลางคืน'];
    }
    if (c.contains('ค่าแรง')) {
      return ['ค่าแรงประจำวัน', 'ค่าแรงเสริม', 'เบิกล่วงหน้า'];
    }
    if (c.contains('ทราย')) {
      return ['ร่อนทรายเช้า', 'ร่อนทรายบ่าย', 'ล้างทราย'];
    }
    return ['บันทึกงานประจำวัน', 'งานพิเศษ', 'สรุปงานหน้างาน'];
  }

  String _formatDate(DateTime d) {
    final be = d.year + 543;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/$be';
  }

  Widget _buildModuleHistorySection() {
    if (_moduleDayLoading) return const SizedBox.shrink();

    final n = _moduleDayTransactions.length;
    if (n == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A2A3C),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFD9E4F1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => setState(
                    () => _moduleHistoryVisible = !_moduleHistoryVisible,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _moduleHistoryVisible
                            ? Icons.expand_less_rounded
                            : Icons.history_rounded,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _moduleHistoryVisible
                              ? 'ซ่อนประวัติ'
                              : 'ดูประวัติในวันนี้ ($n รายการ)',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'เมนูประวัติ',
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) {
                  if (value == 'show') {
                    setState(() => _moduleHistoryVisible = true);
                  } else if (value == 'hide') {
                    setState(() => _moduleHistoryVisible = false);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'show',
                    child: Text(
                      'แสดงรายการ',
                      style: GoogleFonts.kanit(),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'hide',
                    child: Text(
                      'ซ่อนรายการ',
                      style: GoogleFonts.kanit(),
                    ),
                  ),
                ],
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFD9E4F1)),
                  ),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.more_vert_rounded, size: 22),
                  ),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: _moduleHistoryVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE7EDF5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'เวลาที่แสดงคือเวลาสร้างแถวในระบบ — แก้ไขแถวเดิมยังใช้รหัสแถวเดิม',
                              style: GoogleFonts.kanit(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._moduleDayTransactions.map((t) {
                              final sub = (t.subCategory ?? '').trim();
                              final meta = [
                                t.category,
                                if (sub.isNotEmpty) sub,
                              ].join(' · ');
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  t.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.kanit(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '$meta\n${formatTxnHistoryTime(t.createdAt)} · id: ${t.id}',
                                  style: GoogleFonts.kanit(
                                    fontSize: 11,
                                    color: Colors.black54,
                                    height: 1.35,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _appendRecorder(String text) => text.trim();

  String _formatTimeDot(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh.$mm';
  }

  Future<void> _pickSandTime({
    required TextEditingController controller,
    required int hour,
    required int minute,
  }) async {
    final fallback = TimeOfDay(hour: hour, minute: minute);
    final picked = await showTimePicker(
      context: context,
      initialTime: fallback,
      helpText: 'เลือกเวลา',
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              surface: Colors.white,
              primary: const Color(0xFF1565C0),
              onSurface: const Color(0xFF1D2736),
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              helpTextStyle: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              dialBackgroundColor: const Color(0xFFF0F6FF),
              dialHandColor: const Color(0xFF1565C0),
              dialTextColor: const Color(0xFF24415E),
              entryModeIconColor: const Color(0xFF1565C0),
              hourMinuteTextStyle: GoogleFonts.kanit(
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
              hourMinuteColor: const Color(0xFFE8F1FF),
              hourMinuteTextColor: const Color(0xFF103D6C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              dayPeriodTextStyle: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              dayPeriodColor: const Color(0xFFE8F1FF),
              dayPeriodBorderSide: const BorderSide(color: Color(0xFFCFE0F8)),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                textStyle: GoogleFonts.kanit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
    final selected = picked ?? fallback;
    setState(() => controller.text = _formatTimeDot(selected));
  }

  Future<_CapturedSignature?> _requestSignatureBeforeSave() async {
    final signature = await showDialog<_CapturedSignature>(
      context: context,
      barrierDismissible: !_saving,
      builder: (context) => const _SignatureDialog(),
    );
    return signature;
  }

  ThemeData _quickFormTheme(BuildContext context) {
    final base = Theme.of(context);
    const primary = Color(0xFF0F9EA8);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: _bg,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFBFCFF),
        labelStyle: GoogleFonts.kanit(
          color: const Color(0xFF6A7280),
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: GoogleFonts.kanit(
          color: primary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: GoogleFonts.kanit(
          color: const Color(0xFFA0A8B5),
          fontSize: 15.5,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        prefixIconColor: const Color(0xFF8A95A5),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 50,
          minHeight: 50,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE7EBF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      textTheme: GoogleFonts.kanitTextTheme(base.textTheme).copyWith(
        bodyLarge: GoogleFonts.kanit(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF202939),
        ),
        bodyMedium: GoogleFonts.kanit(
          fontSize: 17,
          color: const Color(0xFF202939),
        ),
        titleMedium: GoogleFonts.kanit(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF202939),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.appBarTitle ?? 'คีย์ข้อมูลง่าย';
    final canPop = Navigator.of(context).canPop();
    return Theme(
      data: _quickFormTheme(context),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
            Navigator.maybePop(context);
          }
        },
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D98A5), Color(0xFF1BB7C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          if (canPop)
                            IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              heading,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.kanit(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 44),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                        children: [
                          _buildModuleHistorySection(),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFE7EDF5)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.035),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                (_isSandWashMode
                                    ? _buildSandWashFormCard()
                                    : _isVehicleTripMode
                                        ? _buildVehicleTripFormCard()
                                        : _isFuelMode
                                            ? _buildFuelFormCard()
                                            : _isHomeSandMode
                                                ? _buildHomeSandFormCard()
                                                : _isLaborMode
                                                    ? _buildLaborFormCard()
                                                    : _isOtMode
                                                        ? _buildOtFormCard()
                                                : _buildFormCard()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSandWashFormCard() {
    if (_sandMorningStartController.text.trim().isEmpty) {
      _sandMorningStartController.text = '07.20';
    }
    if (_sandAfternoonStartController.text.trim().isEmpty) {
      _sandAfternoonStartController.text = '13.00';
    }
    if (_sandEveningEndController.text.trim().isEmpty) {
      _sandEveningEndController.text = '16.20';
    }
    final s1 = (double.tryParse(_sand1MorningController.text) ?? 0) +
        (double.tryParse(_sand1AfternoonController.text) ?? 0);
    final s2 = (double.tryParse(_sand2MorningController.text) ?? 0) +
        (double.tryParse(_sand2AfternoonController.text) ?? 0);
    final total = s1 + s2;
    final drums = double.tryParse(_sandDrumsObtainedController.text) ?? 0;
    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.kanit(
            color: const Color(0xFF5A6B7F),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF5A6B7F), size: 18),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9E4F1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2D8CFF), width: 1.3),
          ),
        );

    Widget numberField({
      required TextEditingController controller,
      required String label,
    }) {
      return _AnimatedInputField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.next,
        readOnly: true,
        onTap: () => _openNumericPad(controller: controller, label: label),
        style: GoogleFonts.kanit(
          color: const Color(0xFF1D2A3A),
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
        decoration: deco(label, Icons.numbers),
      );
    }

    Widget periodRow({
      required String title,
      required IconData icon,
      required Color iconColor,
      required TextEditingController machine1Controller,
      required TextEditingController machine2Controller,
    }) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FBFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCEAF7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.kanit(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D2736),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: numberField(
                    controller: machine1Controller,
                    label: 'เครื่องร่อน 1 (เก่า)',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: numberField(
                    controller: machine2Controller,
                    label: 'เครื่องร่อน 2 (ใหม่)',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'บันทึกล้างทราย',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
                color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'บันทึกทีละส่วนได้ เช่น กรอกคิวเช้าก่อน แล้วกลับมาเพิ่มคิวบ่ายภายหลัง',
            style: GoogleFonts.kanit(
              fontSize: 13,
              height: 1.35,
              color: const Color(0xFF5A6B7F),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: deco('วันที่บันทึก', Icons.calendar_month_outlined),
              child: Text(
                _formatDate(_selectedDate),
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w600,
                    color: const Color(0xFF1D2A3A),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          periodRow(
            title: 'ช่วงเช้า',
            icon: Icons.wb_sunny_outlined,
            iconColor: const Color(0xFF1F9CF0),
            machine1Controller: _sand1MorningController,
            machine2Controller: _sand2MorningController,
          ),
          const SizedBox(height: 12),
          periodRow(
            title: 'ช่วงบ่าย',
            icon: Icons.wb_twilight_outlined,
            iconColor: const Color(0xFF2FB6B0),
            machine1Controller: _sand1AfternoonController,
            machine2Controller: _sand2AfternoonController,
          ),
          if (_sand1OperatorNames.isNotEmpty || _sand2OperatorNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCEAF7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'พนักงานที่ล้าง (ดึงจากข้อมูลเว็บ)',
                    style: GoogleFonts.kanit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D2736),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_sand1OperatorNames.isNotEmpty) ...[
                        Text(
                          'เครื่องร่อน 1 (เก่า)',
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E4FB8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _sand1OperatorNames
                              .map(
                                (name) => Chip(
                                  label: Text(
                                    name,
                                    style: GoogleFonts.kanit(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E4FB8),
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFE8F0FF),
                                  side: const BorderSide(color: Color(0xFFC9DAFF)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (_sand2OperatorNames.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'เครื่องร่อน 2 (ใหม่)',
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0A6F95),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _sand2OperatorNames
                              .map(
                                (name) => Chip(
                                  label: Text(
                                    name,
                                    style: GoogleFonts.kanit(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0A6F95),
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFE4F7FF),
                                  side: const BorderSide(color: Color(0xFFC3EFFF)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF8FCFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCEAF7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ช่วงเวลาการทำงาน',
                      style: GoogleFonts.kanit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D2736),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F8FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD9E9FA)),
                  ),
                  child: Row(
                    children: [
                      _TimelineDot(
                        icon: Icons.wb_sunny_outlined,
                        label: 'เช้า',
                        color: const Color(0xFF1F9CF0),
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 18),
                          child: Divider(
                            color: Color(0xFFBFD8F2),
                            thickness: 1.4,
                            height: 1,
                          ),
                        ),
                      ),
                      _TimelineDot(
                        icon: Icons.wb_twilight_outlined,
                        label: 'บ่าย',
                        color: const Color(0xFF2FB6B0),
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 18),
                          child: Divider(
                            color: Color(0xFFBFD8F2),
                            thickness: 1.4,
                            height: 1,
                          ),
                        ),
                      ),
                      _TimelineDot(
                        icon: Icons.nightlight_round_outlined,
                        label: 'เย็น',
                        color: const Color(0xFF5D74E7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedInputField(
                        controller: _sandMorningStartController,
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF1D2A3A),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textInputAction: TextInputAction.next,
                        readOnly: true,
                        onTap: () => _pickSandTime(
                          controller: _sandMorningStartController,
                          hour: 7,
                          minute: 20,
                        ),
                        decoration: deco('เช้าเริ่ม (07.20)', Icons.wb_sunny_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AnimatedInputField(
                        controller: _sandAfternoonStartController,
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF1D2A3A),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textInputAction: TextInputAction.next,
                        readOnly: true,
                        onTap: () => _pickSandTime(
                          controller: _sandAfternoonStartController,
                          hour: 13,
                          minute: 0,
                        ),
                        decoration: deco('บ่ายเริ่ม (13.00)', Icons.wb_twilight_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AnimatedInputField(
                        controller: _sandEveningEndController,
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF1D2A3A),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textInputAction: TextInputAction.done,
                        readOnly: true,
                        onTap: () => _pickSandTime(
                          controller: _sandEveningEndController,
                          hour: 16,
                          minute: 20,
                        ),
                        decoration: deco(
                          'เย็นหยุด (16.20)',
                          Icons.nightlight_round_outlined,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFF8FCFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: drums > 0 ? const Color(0xFF9FC5F0) : const Color(0xFFDCEAF7),
                width: drums > 0 ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(
                    alpha: drums > 0 ? 0.12 : 0.02,
                  ),
                  blurRadius: drums > 0 ? 14 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F2FF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        size: 17,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'จำนวนถังที่ได้วันนี้',
                      style: GoogleFonts.kanit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D2736),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                numberField(
                  controller: _sandDrumsObtainedController,
                  label: 'กรอกจำนวนถัง',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCFE3FA)),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                'รวมล้างทราย: ${total.toStringAsFixed(0)} คิว • จำนวนถังที่ได้: ${drums.toStringAsFixed(0)} ถัง',
                key: ValueKey('${total.toStringAsFixed(0)}-${drums.toStringAsFixed(0)}'),
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  color: const Color(0xFF0F5FAF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF26C6DA), Color(0xFF1565C0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveQuickEntry,
                icon: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.waves, color: Colors.white, size: 26),
                label: Text(
                  _saving ? 'กำลังบันทึก...' : 'บันทึกล้างทราย',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 60),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNumericPad({
    required TextEditingController controller,
    required String label,
  }) async {
    String value = controller.text;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        Widget key(String k) {
          return FilledButton(
            onPressed: () {
              value += k;
              controller.text = value;
              setState(() {});
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1D2A3A),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              k,
              style: GoogleFonts.kanit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F5FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8E2EE)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.kanit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      value.isEmpty ? '0' : value,
                      style: GoogleFonts.kanit(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.8,
                  children: [
                    key('1'),
                    key('2'),
                    key('3'),
                    key('4'),
                    key('5'),
                    key('6'),
                    key('7'),
                    key('8'),
                    key('9'),
                    FilledButton(
                      onPressed: () {
                        value = '';
                        controller.text = value;
                        setState(() {});
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFEFEF),
                        foregroundColor: const Color(0xFFD64545),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        'ล้าง',
                        style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                      ),
                    ),
                    key('0'),
                    FilledButton(
                      onPressed: () {
                        if (value.isNotEmpty) {
                          value = value.substring(0, value.length - 1);
                          controller.text = value;
                          setState(() {});
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE9F1FF),
                        foregroundColor: const Color(0xFF1565C0),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Icon(Icons.backspace_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_circle_outline, size: 24),
                    label: Text(
                      'เสร็จสิ้น',
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(62),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleTripFormCard() {
    final tripMorning = double.tryParse(_tripMorningController.text) ?? 0;
    final tripAfternoon = double.tryParse(_tripAfternoonController.text) ?? 0;
    final totalTrips = tripMorning + tripAfternoon;
    final cubicPerTrip = double.tryParse(_cubicPerTripController.text) ?? 0;
    final totalCubic = totalTrips * cubicPerTrip;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F9EA8).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'บันทึกการใช้รถ',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _vehicleIdController.text.isEmpty
                      ? null
                      : _vehicleIdController.text,
                  decoration: const InputDecoration(
                    labelText: 'รถ/เครื่องจักร',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: _cars
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c, style: GoogleFonts.kanit()),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => _vehicleIdController.text = v ?? '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _driverIdController.text.isEmpty
                      ? null
                      : _driverIdController.text,
                  decoration: const InputDecoration(
                    labelText: 'คนขับ',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: _driverEmployees
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.nickname.isNotEmpty ? e.nickname : e.name,
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => _driverIdController.text = v ?? '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('เต็มวัน', style: GoogleFonts.kanit()),
                selected: _vehicleWorkType == 'FullDay',
                onSelected: (_) => setState(() => _vehicleWorkType = 'FullDay'),
              ),
              ChoiceChip(
                label: Text('ครึ่งวัน', style: GoogleFonts.kanit()),
                selected: _vehicleWorkType == 'HalfDay',
                onSelected: (_) => setState(() => _vehicleWorkType = 'HalfDay'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AnimatedInputField(
                  controller: _vehicleWageController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'ค่าจ้างรถ (บาท)',
                    prefixIcon: Icon(Icons.currency_exchange_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnimatedInputField(
                  controller: _driverWageController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'เบี้ยเลี้ยงคนขับ (บาท)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _vehicleWorkDetailsController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'บันทึกรถและจำนวนเที่ยวรถ',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AnimatedInputField(
                  controller: _tripMorningController,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'ช่วงเช้า (เที่ยว)',
                    prefixIcon: Icon(Icons.wb_sunny_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnimatedInputField(
                  controller: _tripAfternoonController,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'ช่วงบ่าย (เที่ยว)',
                    prefixIcon: Icon(Icons.nightlight_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _cubicPerTripController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'คิวต่อเที่ยว',
              prefixIcon: Icon(Icons.straighten_outlined),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: totalTrips > 0 ? const Color(0xFFBFD8F4) : const Color(0xFFE2EAF4),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                'รวม ${totalTrips.toStringAsFixed(0)} เที่ยว • ${totalCubic.toStringAsFixed(0)} คิว',
                key: ValueKey('${totalTrips.toStringAsFixed(0)}-${totalCubic.toStringAsFixed(0)}'),
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveQuickEntry,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _saving ? 'กำลังบันทึก...' : 'บันทึกรถและเที่ยวรถ',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelFormCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F9EA8).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fuel Entry',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('ดีเซล', style: GoogleFonts.kanit()),
                selected: _fuelType == 'Diesel',
                onSelected: (_) => setState(() => _fuelType = 'Diesel'),
              ),
              ChoiceChip(
                label: Text('เบนซิน', style: GoogleFonts.kanit()),
                selected: _fuelType == 'Benzine',
                onSelected: (_) => setState(() => _fuelType = 'Benzine'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AnimatedInputField(
                  controller: _fuelLitersController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'จำนวนลิตร',
                    prefixIcon: Icon(Icons.local_gas_station_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _fuelUnitController.text,
                  decoration: const InputDecoration(
                    labelText: 'หน่วย',
                    prefixIcon: Icon(Icons.straighten_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ลิตร', child: Text('ลิตร')),
                    DropdownMenuItem(value: 'แกลลอน', child: Text('แกลลอน')),
                  ],
                  onChanged: (v) => _fuelUnitController.text = v ?? 'ลิตร',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _fuelAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ราคาซื้อน้ำมัน (บาท)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _fuelDetailsController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดเพิ่มเติม',
              prefixIcon: Icon(Icons.note_alt_outlined),
            ),
          ),
          const SizedBox(height: 10),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelStockInEntry,
              icon: const Icon(Icons.add_circle_outline),
              label: Text('บันทึกซื้อน้ำมันเข้า', style: GoogleFonts.kanit()),
            ),
          ),
          const Divider(height: 22),
          Text(
            'บันทึกการใช้น้ำมันของรถแต่ละคัน',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _fuelVehicleController.text.isEmpty
                ? null
                : _fuelVehicleController.text,
            decoration: const InputDecoration(
              labelText: 'เลือกรถ',
              prefixIcon: Icon(Icons.local_shipping_outlined),
            ),
            items: _cars
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c, style: GoogleFonts.kanit()),
                  ),
                )
                .toList(),
            onChanged: (v) => _fuelVehicleController.text = v ?? '',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('ดีเซล', style: GoogleFonts.kanit()),
                selected: _fuelVehicleType == 'Diesel',
                onSelected: (_) => setState(() => _fuelVehicleType = 'Diesel'),
              ),
              ChoiceChip(
                label: Text('เบนซิน', style: GoogleFonts.kanit()),
                selected: _fuelVehicleType == 'Benzine',
                onSelected: (_) => setState(() => _fuelVehicleType = 'Benzine'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _fuelVehicleLitersController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ใช้น้ำมัน (ลิตร)',
              prefixIcon: Icon(Icons.opacity_outlined),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _fuelVehicleTimeController,
            decoration: const InputDecoration(
              labelText: 'เวลาเติมน้ำมัน (เช่น 13:45)',
              prefixIcon: Icon(Icons.access_time_outlined),
            ),
          ),
          const SizedBox(height: 10),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelVehicleUsageEntry,
              icon: const Icon(Icons.directions_car_outlined),
              label: Text('บันทึกการใช้น้ำมันรายรถ', style: GoogleFonts.kanit()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSandFormCard() {
    final obtained = double.tryParse(_sandDrumsObtainedController.text) ?? 0;
    final home = double.tryParse(_drumsWashedAtHomeController.text) ?? 0;
    final remain = (obtained - home).clamp(0, 999999).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ทรายที่ล้างที่บ้าน',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _drumsWashedAtHomeController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'จำนวนทรายที่ล้างที่บ้านวันนี้',
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _sandDrumsObtainedController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'จำนวนถังที่ได้วันนี้',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'ล้างที่บ้านวันนี้: ${home.toStringAsFixed(0)} • จำนวนถังคงเหลือ: ${remain.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _saveQuickEntry,
            icon: const Icon(Icons.save_outlined),
            label: Text('บันทึกทรายที่ล้างที่บ้าน', style: GoogleFonts.kanit()),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }

  Widget _buildLaborEmployeePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _employees.map((e) {
        final id = e.id;
        final selected = _selectedLaborEmpIds.contains(id);
        final name = e.nickname.isNotEmpty ? e.nickname : e.name;
        return FilterChip(
          label: Text(name, style: GoogleFonts.kanit()),
          selected: selected,
          onSelected: (_) {
            setState(() {
              if (selected) {
                _selectedLaborEmpIds.remove(id);
              } else {
                _selectedLaborEmpIds.add(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildLaborFormCard() {
    final wage = double.tryParse(_laborDailyWageController.text) ?? 0;
    final multi = _laborWorkType == 'HalfDay' ? 0.5 : 1.0;
    final total = wage * _selectedLaborEmpIds.length * multi;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F9EA8).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'บันทึกค่าแรง',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 8),
          _buildLaborEmployeePicker(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('เต็มวัน', style: GoogleFonts.kanit()),
                selected: _laborWorkType == 'FullDay',
                onSelected: (_) => setState(() => _laborWorkType = 'FullDay'),
              ),
              ChoiceChip(
                label: Text('ครึ่งวัน', style: GoogleFonts.kanit()),
                selected: _laborWorkType == 'HalfDay',
                onSelected: (_) => setState(() => _laborWorkType = 'HalfDay'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _laborDailyWageController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ค่าแรงต่อวัน (บาท/คน)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _laborWorkDetailsController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน',
              prefixIcon: Icon(Icons.work_history_outlined),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: total > 0 ? const Color(0xFFBFD8F4) : const Color(0xFFE2EAF4),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                'รวมค่าแรง: ${total.toStringAsFixed(0)} บาท (${_selectedLaborEmpIds.length} คน)',
                key: ValueKey('${total.toStringAsFixed(0)}-${_selectedLaborEmpIds.length}'),
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveQuickEntry,
              icon: const Icon(Icons.save_outlined),
              label: Text('บันทึกค่าแรง', style: GoogleFonts.kanit()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtFormCard() {
    final rate = double.tryParse(_otRateController.text) ?? 0;
    final hours = double.tryParse(_otHoursController.text) ?? 0;
    final total = rate * hours * _selectedLaborEmpIds.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F9EA8).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'บันทึก OT',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 8),
          _buildLaborEmployeePicker(),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _otRateController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ค่า OT (บาท/คน/ชม.)',
              prefixIcon: Icon(Icons.attach_money_outlined),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _otHoursController,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'จำนวนชั่วโมง OT',
              prefixIcon: Icon(Icons.timelapse_outlined),
            ),
          ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _otDescController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน OT',
              prefixIcon: Icon(Icons.note_alt_outlined),
            ),
          ),
          if (_otDescSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _otDescSuggestions
                  .map(
                    (s) => ActionChip(
                      label: Text(s, style: GoogleFonts.kanit(fontSize: 12)),
                      onPressed: () => setState(() => _otDescController.text = s),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: total > 0 ? const Color(0xFFF2D39D) : const Color(0xFFF3E7CC),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                'รวม OT: ${total.toStringAsFixed(0)} บาท (${_selectedLaborEmpIds.length} คน × ${hours.toStringAsFixed(1)} ชม.)',
                key: ValueKey('${total.toStringAsFixed(0)}-${hours.toStringAsFixed(1)}-${_selectedLaborEmpIds.length}'),
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveQuickEntry,
              icon: const Icon(Icons.save_outlined),
              label: Text('บันทึก OT', style: GoogleFonts.kanit()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      padding: const EdgeInsets.all(16),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: GoogleFonts.kanit(color: Colors.black54),
            hintStyle: GoogleFonts.kanit(color: Colors.black38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD7E3F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3EA0FF), width: 1.2),
            ),
          ),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'บันทึกรายการหน้างาน',
                style: GoogleFonts.kanit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F5FAF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'รูปแบบ Modern Design',
                style: GoogleFonts.kanit(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'วันที่บันทึก',
                    prefixIcon: Icon(
                      Icons.calendar_month_outlined,
                      color: Colors.white70,
                    ),
                  ),
                  child: Text(
                    _formatDate(_selectedDate),
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 4),
              const SizedBox(height: 6),
              TextFormField(
                controller: _categoryController,
                style: GoogleFonts.kanit(color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'หมวดหมู่',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกหมวดหมู่' : null,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets()
                    .map(
                      (p) => ActionChip(
                        backgroundColor: const Color(0xFF172331),
                        side: const BorderSide(color: Color(0xFFD0DCE8)),
                        label: Text(
                          p,
                          style: GoogleFonts.kanit(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        onPressed: () => _descriptionController.text = p,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _amountController,
                style: GoogleFonts.kanit(color: Colors.black87),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'จำนวนเงิน',
                  prefixIcon: Icon(Icons.attach_money_outlined),
                ),
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
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                style: GoogleFonts.kanit(color: Colors.black87),
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'รายละเอียดงาน/รายการ',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกรายละเอียด' : null,
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  ),
                ),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveQuickEntry,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, color: Colors.white),
                  label: Text(
                    _saving ? 'กำลังบันทึก...' : 'บันทึกข้อมูล',
                    style: GoogleFonts.kanit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _AnimatedInputField extends StatefulWidget {
  const _AnimatedInputField({
    required this.controller,
    required this.decoration,
    this.keyboardType,
    this.onChanged,
    this.style,
    this.textInputAction,
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<_AnimatedInputField> createState() => _AnimatedInputFieldState();
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.kanit(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF35506E),
          ),
        ),
      ],
    );
  }
}

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog();

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final List<List<Offset>> _strokes = [];

  double _roundCoord(double value) =>
      double.parse(value.toStringAsFixed(2));

  _CapturedSignature _buildPayload() {
    final now = DateTime.now().toUtc().toIso8601String();
    final signer =
        Supabase.instance.client.auth.currentUser?.email?.trim().isNotEmpty ==
                true
            ? Supabase.instance.client.auth.currentUser!.email!.trim()
            : 'android-user';
    final pointCount = _strokes.fold<int>(0, (sum, s) => sum + s.length);
    final paths = <List<List<double>>>[];
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final sampled = <List<double>>[];
      final step = stroke.length > 180 ? (stroke.length / 180).ceil() : 1;
      for (var i = 0; i < stroke.length; i += step) {
        final p = stroke[i];
        sampled.add([_roundCoord(p.dx), _roundCoord(p.dy)]);
      }
      final last = stroke.last;
      if (sampled.isEmpty ||
          sampled.last[0] != _roundCoord(last.dx) ||
          sampled.last[1] != _roundCoord(last.dy)) {
        sampled.add([_roundCoord(last.dx), _roundCoord(last.dy)]);
      }
      if (sampled.length >= 2) {
        paths.add(sampled);
      }
    }
    final payload = {
      'source': 'android',
      'signedAt': now,
      'signedBy': signer,
      'strokes': _strokes.length,
      'points': pointCount,
      'paths': paths,
    };
    final note = 'mobile_signature:${jsonEncode(payload)}';
    return _CapturedSignature(note: note);
  }

  bool get _hasSignature =>
      _strokes.any((stroke) => stroke.length > 1);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final dialogWidth = (screen.width * 0.92).clamp(360.0, 820.0);
    final canvasHeight = (screen.height * 0.36).clamp(240.0, 420.0);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ลงลายเซ็นก่อนบันทึก',
                style: GoogleFonts.kanit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF203246),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'เซ็นชื่อในกรอบด้านล่าง แล้วกด "ยืนยันลายเซ็น"',
                style: GoogleFonts.kanit(
                  fontSize: 13.5,
                  color: const Color(0xFF6A7B8F),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    setState(() => _strokes.add([details.localPosition]));
                  },
                  onPanUpdate: (details) {
                    if (_strokes.isEmpty) return;
                    setState(() => _strokes.last.add(details.localPosition));
                  },
                  child: Container(
                    height: canvasHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFF),
                      border: Border.all(color: const Color(0xFFD7E2EE)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: CustomPaint(
                      painter: _SignaturePainter(strokes: _strokes),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(_strokes.clear),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      'ล้างลายเซ็น',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _hasSignature
                        ? () => Navigator.of(context).pop(_buildPayload())
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F9EA8),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'ยืนยันลายเซ็น',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1C3D5A)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _CapturedSignature {
  const _CapturedSignature({required this.note});
  final String note;
}

class _AnimatedInputFieldState extends State<_AnimatedInputField> {
  bool _focused = false;
  bool _pressed = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          _pressed ? 0.995 : (_focused ? 1.01 : 1.0),
          _pressed ? 0.995 : (_focused ? 1.01 : 1.0),
          1.0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: const Color(0xFF2D8CFF).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: TextFormField(
            focusNode: _focusNode,
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            style: widget.style ??
                GoogleFonts.kanit(
                  color: const Color(0xFF1D2A3A),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
            textInputAction: widget.textInputAction,
            inputFormatters: widget.inputFormatters,
            readOnly: widget.readOnly,
            onTap: () {
              widget.onTap?.call();
              if (widget.readOnly) return;
              if (!_focusNode.hasFocus) {
                _focusNode.requestFocus();
              }
              SystemChannels.textInput.invokeMethod<void>('TextInput.show');
            },
            decoration: widget.decoration,
          ),
        ),
      ),
    );
  }
}

class _SmoothPressable extends StatefulWidget {
  const _SmoothPressable({
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<_SmoothPressable> createState() => _SmoothPressableState();
}

class _SmoothPressableState extends State<_SmoothPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.985 : 1,
        child: widget.child,
      ),
    );
  }
}
