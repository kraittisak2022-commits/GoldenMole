import 'dart:async';
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

/// ชื่อเล่น/ชื่อจริงที่แสดงใน UI (แสดงตามที่บันทึกในฐานข้อมูล)
String _employeeUiDisplayName(Employee e) {
  return e.nickname.trim().isNotEmpty ? e.nickname.trim() : e.name.trim();
}

/// คิวต่อเที่ยวค่าเริ่มต้นตามชื่อรถในรายการ (`null` = ไม่จับคู่)
double? defaultCubicPerTripForVehicleName(String vehicleName) {
  final n = vehicleName.trim().toLowerCase();
  if (n.isEmpty) return null;
  if (n.contains('สิบล้อ') ||
      n.contains('10ล้อ') ||
      RegExp(r'10\s*ล้อ').hasMatch(n)) {
    return 7;
  }
  if (n.contains('ดั๊ม') || n.contains('ดั้ม')) {
    return 3;
  }
  return null;
}

void _applyDefaultCubicForVehicleRow(_VehicleTripDraft row, String vehicleId) {
  final def = defaultCubicPerTripForVehicleName(vehicleId);
  if (def == null) return;
  final s = def == def.roundToDouble() ? '${def.toInt()}' : '$def';
  row.cubicPerTrip = s;
  row.cubicPerTripController.text = s;
}

class _QuickInputScreenState extends State<QuickInputScreen>
    with SingleTickerProviderStateMixin {
  static const List<_LaborWorkCategory> _laborCategories = [
    _LaborWorkCategory(
      id: 'wash_old',
      label: 'ล้างทราย เครื่องร่อน1(เก่า)',
      color: Color(0xFF4A90E2),
    ),
    _LaborWorkCategory(
      id: 'wash_new',
      label: 'ล้างทราย เครื่องร่อน2(ใหม่)',
      color: Color(0xFF24A7B8),
    ),
    _LaborWorkCategory(
      id: 'wash_home',
      label: 'ล้างทรายที่บ้าน',
      color: Color(0xFF2CB67D),
    ),
    _LaborWorkCategory(
      id: 'wash_yard',
      label: 'ล้างทรายที่ท่าทราย',
      color: Color(0xFF6B6FEA),
    ),
    _LaborWorkCategory(
      id: 'general',
      label: 'งานทั่วไป',
      color: Color(0xFF5F6AD8),
    ),
    _LaborWorkCategory(
      id: 'new_machine',
      label: 'ทำเครื่องใหม่',
      color: Color(0xFF28A0D7),
    ),
    _LaborWorkCategory(
      id: 'new_house',
      label: 'ทำบ้านใหม่',
      color: Color(0xFFC447E3),
    ),
    _LaborWorkCategory(
      id: 'filter_a',
      label: 'ทำกรองเครื่องสูบน้ำ',
      color: Color(0xFFC447E3),
    ),
    _LaborWorkCategory(
      id: 'filter_b',
      label: 'ทำกรองเครื่องสูบน้ำ B',
      color: Color(0xFF27A1DA),
    ),
    _LaborWorkCategory(
      id: 'night_shift',
      label: 'เวรกลางคืน',
      color: Color(0xFF7B5AE6),
    ),
    _LaborWorkCategory(
      id: 'wash_yard_house',
      label: 'ล้างทรายบ้าน',
      color: Color(0xFF7A66E3),
    ),
    _LaborWorkCategory(
      id: 'sift_home',
      label: 'ร่อนทรายบ้าน',
      color: Color(0xFFE14897),
    ),
    _LaborWorkCategory(
      id: 'house_team',
      label: 'ทำบ้านแม่มะงาน',
      color: Color(0xFFE64CA0),
    ),
    _LaborWorkCategory(
      id: 'excavator_control',
      label: 'ควบคุมรถขุด',
      color: Color(0xFF7962E6),
    ),
    _LaborWorkCategory(
      id: 'sand_watch',
      label: 'เฝ้าทำทราย',
      color: Color(0xFFE64A9E),
    ),
  ];
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
  final _laborWorkDetailsController = TextEditingController();
  final _otDescController = TextEditingController();
  List<Employee> _employees = const [];
  bool _employeesLoading = false;
  int _employeesLoadPercent = 0;
  Timer? _employeesLoadProgressTimer;
  List<Employee> _driverEmployees = const [];
  Map<String, Employee> _employeesById = const {};
  List<String> _cars = const [];

  late DateTime _selectedDate;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;
  Timer? _uiRebuildDebounce;
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
  String? _laborTxId;
  String? _homeSandTxId;
  String? _genericTxId;
  bool get _isSandWashMode =>
      (widget.initialCategory ?? '').contains('ร่อนทราย');
  bool get _isVehicleTripMode =>
      (widget.initialCategory ?? '').contains('เที่ยวรถ');
  bool get _isFuelMode => (widget.initialCategory ?? '').contains('น้ำมัน');
  bool get _isHomeSandMode =>
      (widget.initialCategory ?? '').contains('ทรายที่ล้างที่บ้าน');
  final List<_FuelVehicleDraft> _fuelVehicleDrafts = [
    _FuelVehicleDraft.empty(),
  ];
  final List<_VehicleTripDraft> _vehicleTripDrafts = [
    _VehicleTripDraft.empty(),
  ];
  double _homeSandAvailable = 0;
  double _homeSandBeforeToday = 0;
  double _homeSandTodayObtained = 0;
  bool _homeWashAll = false;
  final Set<String> _selectedLaborEmpIds = {};
  final Set<String> _laborPickedIds = {};
  final Map<String, Set<String>> _laborAssignments = {
    for (final c in _laborCategories) c.id: <String>{},
  };
  final Map<String, bool> _laborBucketExpanded = {
    for (final c in _laborCategories) c.id: false,
  };
  final List<_OtGroupDraft> _otGroups = [];
  List<String> _vehicleWorkSuggestions = const [];
  bool get _isLaborMode =>
      widget.initialCategory == 'ค่าแรง' ||
      (widget.initialCategory ?? '').contains('บันทึกการทำงาน');
  bool get _isOtMode => (widget.initialCategory ?? '').contains('OT');

  @override
  void initState() {
    super.initState();
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduceMotion ? 320 : 440),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.62, curve: Curves.easeOutCubic),
      ),
    );
    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _entranceController.forward();
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
    _loadVehicleWorkSuggestions();
    _refreshHomeSandStock();
    _otGroups.add(_OtGroupDraft.empty());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      await _loadModuleTransactions();
    });
  }

  String _quickYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _persist(AppTransaction t) async {
    final omitCreated =
        _persistOmitCreatedForIds.contains(t.id) ||
        _persistOmitCreatedSessionIds.contains(t.id);
    await widget.service.upsertTransaction(t, omitCreatedAt: omitCreated);
    _persistOmitCreatedSessionIds.add(t.id);
  }

  void _clearHydrationSlots() {
    _persistOmitCreatedForIds.clear();
    _persistOmitCreatedSessionIds.clear();
    _sandRowIdsByKey.clear();
    _laborTxId = null;
    _homeSandTxId = null;
    _genericTxId = null;
  }

  void _disposeVehicleDrafts() {
    for (final row in _vehicleTripDrafts) {
      row.dispose();
    }
  }

  void _replaceVehicleDrafts(List<_VehicleTripDraft> nextRows) {
    _disposeVehicleDrafts();
    _vehicleTripDrafts
      ..clear()
      ..addAll(nextRows.isEmpty ? [_VehicleTripDraft.empty()] : nextRows);
  }

  void _disposeFuelVehicleDrafts() {
    for (final row in _fuelVehicleDrafts) {
      row.dispose();
    }
  }

  void _replaceFuelVehicleDrafts(List<_FuelVehicleDraft> nextRows) {
    _disposeFuelVehicleDrafts();
    _fuelVehicleDrafts
      ..clear()
      ..addAll(nextRows.isEmpty ? [_FuelVehicleDraft.empty()] : nextRows);
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
      _homeWashAll = false;
    } else if (_isVehicleTripMode) {
      _vehicleIdController.clear();
      _driverIdController.clear();
      _vehicleWorkDetailsController.clear();
      _tripMorningController.clear();
      _tripAfternoonController.clear();
      _cubicPerTripController.clear();
      _replaceVehicleDrafts(const []);
    } else if (_isFuelMode) {
      _fuelLitersController.clear();
      _fuelAmountController.clear();
      _fuelDetailsController.clear();
      _fuelVehicleController.clear();
      _fuelVehicleLitersController.clear();
      _fuelVehicleTimeController.clear();
      _replaceFuelVehicleDrafts(const []);
    } else if (_isLaborMode) {
      _selectedLaborEmpIds.clear();
      _laborPickedIds.clear();
      for (final k in _laborAssignments.keys) {
        _laborAssignments[k]?.clear();
      }
      for (final k in _laborBucketExpanded.keys) {
        _laborBucketExpanded[k] = false;
      }
      _laborWorkDetailsController.clear();
    } else if (_isOtMode) {
      for (final g in _otGroups) {
        g.dispose();
      }
      _otGroups.clear();
      _otGroups.add(_OtGroupDraft.empty());
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
      await _refreshHomeSandStock();
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

  String _vehicleLabelFromId(String vehicleId) {
    final v = vehicleId.trim();
    if (v.isEmpty) return '-';
    return v;
  }

  bool _isMacroCarName(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('แม็คโคร') ||
        s.contains('แมคโคร') ||
        s.contains('excavator') ||
        s.contains('backhoe');
  }

  List<String> _fuelMacroCars() {
    final seen = <String>{};
    final out = <String>[];
    for (final car in _cars) {
      if (!_isMacroCarName(car)) continue;
      if (seen.add(car)) out.add(car);
    }
    return out;
  }

  bool _isDriverEmployee(Employee e) {
    final positions = e.positions.isNotEmpty
        ? e.positions
        : ((e.position ?? '').trim().isEmpty ? const <String>[] : <String>[e.position!.trim()]);
    return positions.contains('คนขับรถ');
  }

  String _driverLabelFromId(String driverId) {
    final id = driverId.trim();
    if (id.isEmpty) return '-';
    final e = _employeesById[id];
    if (e != null) {
      return e.nickname.isNotEmpty ? e.nickname : e.name;
    }
    return id;
  }

  String _employeeLabelFromIdOrName(String raw) {
    final token = raw.trim();
    if (token.isEmpty) return '';
    final e = _employeesById[token];
    if (e != null) {
      return (e.nickname.isNotEmpty ? e.nickname : e.name).trim();
    }
    return token;
  }

  List<String> _extractNamesFromDescription(String description) {
    final plain = _stripRecorderSuffix(description);
    final m = RegExp(r'\[([^\]]+)\]').firstMatch(plain);
    if (m == null) return const [];
    return m
        .group(1)!
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
        if (mt == 'old' || (t.description).contains('เครื่องร่อน 1')) {
          _sandRowIdsByKey.putIfAbsent('Old', () => t.id);
          _sand1MorningController.text = _strNum(t.sandMorning);
          _sand1AfternoonController.text = _strNum(t.sandAfternoon);
          final names = _operatorNamesFromTransaction(t);
          if (oldMachineNames.isEmpty && names.isNotEmpty) {
            oldMachineNames = names;
          }
        } else if (mt == 'new' || (t.description).contains('เครื่องร่อน 2')) {
          _sandRowIdsByKey.putIfAbsent('New', () => t.id);
          _sand2MorningController.text = _strNum(t.sandMorning);
          _sand2AfternoonController.text = _strNum(t.sandAfternoon);
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
      if (_sandDrumsObtainedController.text.trim().isEmpty &&
          inferredMaxDrums > 0) {
        _sandDrumsObtainedController.text = _strNum(inferredMaxDrums);
      }
      _sand1OperatorNames = oldMachineNames;
      _sand2OperatorNames = newMachineNames;
      return;
    }

    if (_isHomeSandMode) {
      final t = txs.first;
      _homeSandTxId = t.id;
      _drumsWashedAtHomeController.text = _strNum(t.drumsWashedAtHome);
      return;
    }

    if (_isVehicleTripMode) {
      final byVehicle = <String, _VehicleTripDraft>{};
      _VehicleTripDraft ensureDraft(String vehicleId) {
        final key = vehicleId.trim().isEmpty ? '__unknown__' : vehicleId.trim();
        return byVehicle.putIfAbsent(
          key,
          () => _VehicleTripDraft.empty()..vehicleId = vehicleId.trim(),
        );
      }

      for (final t in txs) {
        final key = (t.vehicleId ?? '').trim();
        final draft = ensureDraft(key);
        if (transactionCountsAsVehicleTripMenu(t)) {
          draft.tripTxId = t.id;
          draft.vehicleId = draft.vehicleId.isEmpty
              ? (t.vehicleId ?? '').trim()
              : draft.vehicleId;
          draft.driverId = draft.driverId.isEmpty
              ? (t.driverId ?? '').trim()
              : draft.driverId;
          draft.tripMorning = _strNum(t.tripMorning);
          draft.tripAfternoon = _strNum(t.tripAfternoon);
          draft.cubicPerTrip = _strNum(t.cubicPerTrip);
          draft.tripMorningController.text = draft.tripMorning;
          draft.tripAfternoonController.text = draft.tripAfternoon;
          draft.cubicPerTripController.text = draft.cubicPerTrip;
          if (draft.workDetails.isEmpty) {
            draft.workDetails = _stripRecorderSuffix(t.workDetails ?? '');
            draft.workDetailsController.text = draft.workDetails;
          }
          final wt = (t.workType ?? '').trim();
          draft.workType = wt == 'HalfDay' || wt == 'Hourly' ? wt : 'FullDay';
          if (draft.workType == 'Hourly') {
            final hourlyMatch = RegExp(
              r'(\d+(?:\.\d+)?)\s*ชม',
            ).firstMatch(_stripRecorderSuffix(t.workDetails ?? ''));
            if (hourlyMatch != null) {
              draft.hourlyHours = hourlyMatch.group(1) ?? '';
              draft.hourlyHoursController.text = draft.hourlyHours;
            }
          }
        }
      }

      final loaded = byVehicle.values.where((d) {
        return d.vehicleId.isNotEmpty ||
            d.driverId.isNotEmpty ||
            d.workDetails.isNotEmpty ||
            d.tripMorning.isNotEmpty ||
            d.tripAfternoon.isNotEmpty ||
            d.cubicPerTrip.isNotEmpty;
      }).toList();
      _replaceVehicleDrafts(loaded);
      return;
    }

    if (_isFuelMode) {
      final drafts = <_FuelVehicleDraft>[];
      for (final t in txs) {
        final isVehicleUsage =
            t.fuelMovement == 'stock_out' ||
            (t.vehicleId ?? '').trim().isNotEmpty;
        if (!isVehicleUsage) continue;
        final draft = _FuelVehicleDraft.empty();
        draft.txId = t.id;
        draft.vehicleId = (t.vehicleId ?? '').trim();
        draft.fuelType = ((t.fuelType ?? '').toLowerCase().contains('ben'))
            ? 'Benzine'
            : 'Diesel';
        draft.liters = _strNum(t.quantity);
        draft.time = _stripRecorderSuffix(t.workDetails ?? '');
        draft.litersController.text = draft.liters;
        draft.timeController.text = draft.time;
        drafts.add(draft);
      }
      _replaceFuelVehicleDrafts(drafts);
      return;
    }

    if (_isLaborMode) {
      final t = txs.first;
      _laborTxId = t.id;
      _selectedLaborEmpIds
        ..clear()
        ..addAll(t.employeeIds);
      _laborPickedIds.clear();
      for (final k in _laborAssignments.keys) {
        _laborAssignments[k]?.clear();
      }
      for (final k in _laborBucketExpanded.keys) {
        _laborBucketExpanded[k] = false;
      }
      final loadedAssignments =
          t.workAssignments ?? const <String, List<String>>{};
      if (loadedAssignments.isNotEmpty) {
        loadedAssignments.forEach((key, ids) {
          if (!_laborAssignments.containsKey(key)) return;
          _laborAssignments[key]?.addAll(ids);
          if ((_laborAssignments[key]?.isNotEmpty ?? false)) {
            _laborBucketExpanded[key] = true;
          }
        });
      } else {
        _laborAssignments['general']?.addAll(t.employeeIds);
        if ((_laborAssignments['general']?.isNotEmpty ?? false)) {
          _laborBucketExpanded['general'] = true;
        }
      }
      _laborWorkDetailsController.text = _stripRecorderSuffix(
        t.workDetails ?? '',
      );
      return;
    }

    if (_isOtMode) {
      for (final g in _otGroups) {
        g.dispose();
      }
      _otGroups.clear();
      for (final t in txs) {
        final g = _OtGroupDraft.empty();
        g.persistedId = t.id;
        g.employeeIds.addAll(t.employeeIds);
        g.hoursController.text = _strNum(t.otHours);
        _otGroups.add(g);
      }
      if (_otGroups.isEmpty) _otGroups.add(_OtGroupDraft.empty());
      _otDescController.text = txs.isNotEmpty
          ? _stripRecorderSuffix(txs.first.otDescription ?? '')
          : '';
      return;
    }

    final g = txs.first;
    _genericTxId = g.id;
    _amountController.text = _strNum(g.amount);
    _descriptionController.text = _stripRecorderSuffix(g.description);
    if (g.category.isNotEmpty && _categoryController.text.trim().isEmpty) {
      _categoryController.text = g.category;
    }
    setIfEmpty(_categoryController, g.category);
  }

  @override
  void dispose() {
    _employeesLoadProgressTimer?.cancel();
    _uiRebuildDebounce?.cancel();
    _entranceController.dispose();
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
    _laborWorkDetailsController.dispose();
    for (final g in _otGroups) {
      g.dispose();
    }
    _otDescController.dispose();
    _disposeVehicleDrafts();
    _disposeFuelVehicleDrafts();
    super.dispose();
  }

  void _scheduleUiRefresh({Duration delay = const Duration(milliseconds: 110)}) {
    _uiRebuildDebounce?.cancel();
    _uiRebuildDebounce = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
    });
  }

  bool get _showsEmployeeLoadingUi => _isLaborMode || _isOtMode;

  Future<void> _loadEmployees() async {
    _employeesLoadProgressTimer?.cancel();
    _employeesLoadProgressTimer = null;
    final showPct = _showsEmployeeLoadingUi;
    if (showPct && mounted) {
      setState(() {
        _employeesLoading = true;
        _employeesLoadPercent = 0;
      });
      _employeesLoadProgressTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (!mounted) return;
          setState(() {
            if (_employeesLoadPercent < 92) {
              _employeesLoadPercent += 7;
              if (_employeesLoadPercent > 92) _employeesLoadPercent = 92;
            }
          });
        },
      );
    }

    try {
      final list = await widget.employeeService.fetchEmployees();
      list.sort((a, b) {
        return (a.nickname.isNotEmpty ? a.nickname : a.name).compareTo(
          b.nickname.isNotEmpty ? b.nickname : b.name,
        );
      });
      _employeesLoadProgressTimer?.cancel();
      _employeesLoadProgressTimer = null;
      if (!mounted) return;
      if (showPct && _employeesLoading) {
        setState(() => _employeesLoadPercent = 100);
        await Future<void>.delayed(const Duration(milliseconds: 240));
      }
      if (!mounted) return;
      setState(() {
        _employees = list;
        _employeesById = {for (final e in list) e.id: e};
        _driverEmployees = list
            .where((e) => !e.inactive)
            .where(_isDriverEmployee)
            .toList();
        _employeesLoading = false;
        _employeesLoadPercent = 0;
      });
      if (_isSandWashMode && _moduleDayTransactions.isNotEmpty) {
        setState(() {
          _hydrateFormsFromTransactions(_moduleDayTransactions);
        });
      }
    } catch (_) {
      _employeesLoadProgressTimer?.cancel();
      _employeesLoadProgressTimer = null;
      if (mounted) {
        setState(() {
          _employeesLoading = false;
          _employeesLoadPercent = 0;
        });
      }
    }
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

  Future<void> _loadVehicleWorkSuggestions() async {
    try {
      final txs = await widget.service.fetchTransactions();
      final ranked = <String, int>{};
      for (final tx in txs) {
        if (!transactionCountsAsVehicleTripMenu(tx)) continue;
        final raw = (tx.workDetails ?? '').trim();
        if (raw.isEmpty) continue;
        ranked[raw] = (ranked[raw] ?? 0) + 1;
      }
      final sorted = ranked.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return a.key.compareTo(b.key);
        });
      if (!mounted) return;
      setState(() {
        _vehicleWorkSuggestions = sorted.map((e) => e.key).take(10).toList();
      });
    } catch (_) {}
  }

  Future<void> _refreshHomeSandStock() async {
    try {
      final rows = await widget.service.fetchTransactions();
      final map = <String, _HomeSandDaily>{};
      for (final t in rows) {
        if (t.category != 'DailyLog' || t.subCategory != 'Sand') continue;
        final day = t.date;
        final rec = map.putIfAbsent(day, () => _HomeSandDaily());
        final obtained = t.drumsObtained ?? 0;
        final home = t.drumsWashedAtHome ?? 0;
        if (obtained > rec.obtained) rec.obtained = obtained;
        if (home > rec.home) rec.home = home;
      }
      final selected = _quickYmd(_selectedDate);
      final days = map.keys.toList()..sort();
      var before = 0.0;
      for (final d in days) {
        if (d.compareTo(selected) >= 0) continue;
        final rec = map[d]!;
        before = (before + rec.obtained - rec.home).clamp(0.0, 9999999.0);
      }
      final today = map[selected] ?? _HomeSandDaily();
      final available = (before + today.obtained).clamp(0.0, 9999999.0);
      if (!mounted) return;
      setState(() {
        _homeSandBeforeToday = before;
        _homeSandTodayObtained = today.obtained;
        _homeSandAvailable = available;
        if (_drumsWashedAtHomeController.text.trim().isEmpty &&
            today.home > 0) {
          _drumsWashedAtHomeController.text = _strNum(today.home);
        }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
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
      await _saveFuelVehicleUsageEntries();
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
        final gid =
            _genericTxId ?? DateTime.now().millisecondsSinceEpoch.toString();
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
        final drums =
            double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
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
          final tid =
              existingRow ?? '${DateTime.now().millisecondsSinceEpoch}_$suffix';
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
          final drumsId =
              _sandRowIdsByKey['drums'] ??
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
              sandAfternoonStart: afternoonStart.isEmpty
                  ? null
                  : afternoonStart,
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
        final maxWashable = _homeSandAvailable;
        final typedHome =
            double.tryParse(_drumsWashedAtHomeController.text.trim()) ?? 0;
        final drumsHome = _homeWashAll ? maxWashable : typedHome;
        if (drumsHome <= 0) throw 'กรุณาระบุจำนวนถังที่ล้างที่บ้านวันนี้';
        if (drumsHome > maxWashable) {
          throw 'จำนวนถังที่ล้างเกินจำนวนคงเหลือ (${maxWashable.toStringAsFixed(0)} ถัง)';
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final homeId =
            _homeSandTxId ??
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
            drumsObtained: 0,
            drumsWashedAtHome: drumsHome,
            note: _activeSignatureNote,
          ),
        );
        _drumsWashedAtHomeController.clear();
        _homeWashAll = false;
        await _refreshHomeSandStock();
      },
    );
  }

  Future<void> _saveVehicleTripEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกรถและเที่ยวรถสำเร็จ',
      body: () async {
        final activeRows = _vehicleTripDrafts.where((row) {
          return row.vehicleId.trim().isNotEmpty ||
              row.driverId.trim().isNotEmpty ||
              row.workDetails.trim().isNotEmpty ||
              row.hourlyHours.trim().isNotEmpty ||
              row.tripMorning.trim().isNotEmpty ||
              row.tripAfternoon.trim().isNotEmpty ||
              row.cubicPerTrip.trim().isNotEmpty;
        }).toList();
        if (activeRows.isEmpty) {
          throw 'กรุณาระบุข้อมูลรถอย่างน้อย 1 คัน';
        }

        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';

        for (var i = 0; i < activeRows.length; i++) {
          final row = activeRows[i];
          final vehicle = row.vehicleId.trim();
          final driver = row.driverId.trim();
          final details = row.workDetails.trim();
          final hourlyHours = double.tryParse(row.hourlyHours.trim()) ?? 0;
          final tripMorning = double.tryParse(row.tripMorning.trim()) ?? 0;
          final tripAfternoon = double.tryParse(row.tripAfternoon.trim()) ?? 0;
          final totalTrips = tripMorning + tripAfternoon;
          final cubicPerTrip = double.tryParse(row.cubicPerTrip.trim()) ?? 0;

          if (vehicle.isEmpty || driver.isEmpty) {
            throw 'กรุณาระบุรถและคนขับให้ครบทุกคัน';
          }
          if (row.workType == 'Hourly' && hourlyHours <= 0) {
            throw 'กรุณาระบุชั่วโมงทำงานสำหรับรายการรายชั่วโมง';
          }
          final detailsWithHours = row.workType == 'Hourly'
              ? (details.isEmpty
                    ? 'งานรายชั่วโมง ${_strNum(hourlyHours)} ชม.'
                    : '$details (${_strNum(hourlyHours)} ชม.)')
              : details;

          if (totalTrips <= 0) continue;
          final totalCubic = totalTrips * cubicPerTrip;
          final tripId =
              row.tripTxId ??
              '${DateTime.now().millisecondsSinceEpoch}_trip_$i';
          row.tripTxId = tripId;
          await _persist(
            AppTransaction(
              id: tripId,
              date: date,
              type: 'Expense',
              category: 'DailyLog',
              subCategory: 'VehicleTrip',
              description: _appendRecorder(
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
              workDetails: _appendRecorder(detailsWithHours),
              workType: row.workType == 'HalfDay' || row.workType == 'Hourly'
                  ? row.workType
                  : 'FullDay',
            ),
          );
        }
        _replaceVehicleDrafts(const []);
      },
    );
  }

  Future<void> _saveFuelVehicleUsageEntries() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกการใช้น้ำมันรายรถสำเร็จ',
      body: () async {
        final fuelCars = _fuelMacroCars();
        if (fuelCars.isEmpty) {
          throw 'ยังไม่พบรถแม็คโครในตั้งค่าแอพ';
        }
        final activeRows = _fuelVehicleDrafts.where((row) {
          return row.vehicleId.trim().isNotEmpty ||
              row.liters.trim().isNotEmpty ||
              row.time.trim().isNotEmpty;
        }).toList();
        if (activeRows.isEmpty) {
          throw 'กรุณาระบุข้อมูลการใช้น้ำมันอย่างน้อย 1 คัน';
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';

        for (var i = 0; i < activeRows.length; i++) {
          final row = activeRows[i];
          final vehicle = row.vehicleId.trim();
          final liters = double.tryParse(row.liters.trim()) ?? 0;
          if (vehicle.isEmpty) throw 'กรุณาเลือกรถให้ครบทุกคัน';
          if (!fuelCars.contains(vehicle)) {
            throw 'เลือกรถได้เฉพาะรถแม็คโคร';
          }
          if (liters <= 0) throw 'กรุณาระบุปริมาณน้ำมันให้มากกว่า 0';
          if (row.time.trim().isEmpty) {
            throw 'กรุณาระบุเวลาเติมน้ำมัน (คัน ${i + 1})';
          }
          final txId =
              row.txId ??
              '${DateTime.now().millisecondsSinceEpoch}_fuel_out_$i';
          row.txId = txId;
          await _persist(
            AppTransaction(
              id: txId,
              date: date,
              type: 'Expense',
              category: 'Fuel',
              subCategory: 'VehicleUsage',
              description: _appendRecorder(
                'ใช้น้ำมันรถ $vehicle: ${liters.toStringAsFixed(0)} ลิตร (${row.fuelType == 'Diesel' ? 'ดีเซล' : 'เบนซิน'})',
              ),
              amount: 0,
              note: _activeSignatureNote,
              quantity: liters,
              unit: 'L',
              fuelType: row.fuelType,
              fuelMovement: 'stock_out',
              vehicleId: vehicle,
              workDetails: _appendRecorder(row.time.trim()),
            ),
          );
        }
        _replaceFuelVehicleDrafts(const []);
      },
    );
  }

  Future<void> _saveLaborEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกค่าแรงสำเร็จ',
      body: () async {
        final assignedIds = _collectLaborAssignedIds();
        if (assignedIds.isEmpty) throw 'กรุณาเลือกพนักงานลงกล่องงาน';
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final assignmentPayload = <String, List<String>>{};
        for (final entry in _laborAssignments.entries) {
          if (entry.value.isEmpty) continue;
          assignmentPayload[entry.key] = entry.value.toList();
        }
        final assignmentText = assignmentPayload.entries
            .map((e) => '${_laborCategoryLabel(e.key)}(${e.value.length})')
            .join(', ');
        final names = assignedIds
            .map((id) {
              for (final e in _employees) {
                if (e.id == id) {
                  return _employeeUiDisplayName(e);
                }
              }
              return '';
            })
            .where((e) => e.isNotEmpty)
            .join(', ');
        final laborId =
            _laborTxId ?? '${DateTime.now().millisecondsSinceEpoch}_labor';
        _laborTxId = laborId;
        await _persist(
          AppTransaction(
            id: laborId,
            date: '$y-$m-$d',
            type: 'Expense',
            category: 'Labor',
            subCategory: 'Attendance',
            laborStatus: 'Work',
            employeeIds: assignedIds.toList(),
            amount: 0,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'ค่าแรง (${assignedIds.length} คน)${names.isNotEmpty ? ' [$names]' : ''}${assignmentText.isNotEmpty ? ' {$assignmentText}' : ''}',
            ),
            workAssignments: assignmentPayload,
            customWorkCategories: _laborCategoryPayload(),
          ),
        );
        _selectedLaborEmpIds.clear();
        _laborPickedIds.clear();
        for (final k in _laborAssignments.keys) {
          _laborAssignments[k]?.clear();
        }
        for (final k in _laborBucketExpanded.keys) {
          _laborBucketExpanded[k] = false;
        }
        _laborWorkDetailsController.clear();
      },
    );
  }

  Future<void> _saveOtEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึก OT สำเร็จ',
      body: () async {
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final desc = _otDescController.text.trim();
        var savedCount = 0;
        final baseTs = DateTime.now().millisecondsSinceEpoch;
        for (var gi = 0; gi < _otGroups.length; gi++) {
          final g = _otGroups[gi];
          final hours = double.tryParse(g.hoursController.text.trim()) ?? 0;
          final ids = g.employeeIds.toList();
          final hasEmployees = ids.isNotEmpty;
          final hasHours = hours > 0;
          if (!hasEmployees && !hasHours) continue;
          if (!hasEmployees) {
            throw 'กลุ่มที่ ${gi + 1}: กรุณาเลือกพนักงาน';
          }
          if (!hasHours || hours <= 0) {
            throw 'กลุ่มที่ ${gi + 1}: กรุณาระบุชั่วโมง OT';
          }
          final id = g.persistedId ?? '${baseTs}_ot_${gi}_$savedCount';
          g.persistedId = id;
          await _persist(
            AppTransaction(
              id: id,
              date: date,
              type: 'Expense',
              category: 'Labor',
              subCategory: 'OT',
              laborStatus: 'OT',
              employeeIds: ids,
              amount: 0,
              note: _activeSignatureNote,
              otAmount: 0,
              otHours: hours,
              otDescription: desc,
              description: _appendRecorder(
                'OT $desc (${hours.toStringAsFixed(1)}ชม.) กลุ่มที่ ${savedCount + 1} (${ids.length} คน)',
              ),
            ),
          );
          savedCount++;
        }
        if (savedCount == 0) {
          throw 'กรุณาเลือกพนักงานและระบุชั่วโมงอย่างน้อยหนึ่งกลุ่ม';
        }
        for (final g in _otGroups) {
          g.dispose();
        }
        _otGroups.clear();
        _otGroups.add(_OtGroupDraft.empty());
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
        () => _selectedDate = DateTime(picked.year, picked.month, picked.day),
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (_moduleHistoryVisible
                                ? theme.colorScheme.primary
                                : Colors.black)
                            .withValues(
                              alpha: _moduleHistoryVisible ? 0.2 : 0.04,
                            ),
                        blurRadius: _moduleHistoryVisible ? 14 : 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A2A3C),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: _moduleHistoryVisible
                            ? theme.colorScheme.primary.withValues(alpha: 0.45)
                            : const Color(0xFFD9E4F1),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(
                        () => _moduleHistoryVisible = !_moduleHistoryVisible,
                      );
                    },
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: _moduleHistoryVisible ? 0.5 : 0,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            _moduleHistoryVisible
                                ? Icons.expand_less_rounded
                                : Icons.history_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.06, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: Text(
                              _moduleHistoryVisible
                                  ? 'ซ่อนประวัติ'
                                  : 'ดูประวัติในวันนี้ ($n รายการ)',
                              key: ValueKey(_moduleHistoryVisible),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                    child: Text('แสดงรายการ', style: GoogleFonts.kanit()),
                  ),
                  PopupMenuItem<String>(
                    value: 'hide',
                    child: Text('ซ่อนรายการ', style: GoogleFonts.kanit()),
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
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final isLargeTablet = media.size.shortestSide >= 700;
    final contentMaxWidth = isLargeTablet ? 980.0 : 760.0;
    return Theme(
      data: _quickFormTheme(context),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 550) {
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
                child: FadeTransition(
                  opacity: _entranceFade,
                  child: SlideTransition(
                    position: _entranceSlide,
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
                      child: FadeTransition(
                        opacity: _contentFade,
                        child: SlideTransition(
                          position: _contentSlide,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: contentMaxWidth),
                              child: ListView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                cacheExtent: isLargeTablet ? 1200 : 700,
                                padding: EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  28 + keyboardInset,
                                ),
                                children: [
                                  _buildModuleHistorySection(),
                                  RepaintBoundary(
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: const Color(0xFFE7EDF5),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: isLargeTablet ? 14 : 18,
                                            offset: const Offset(0, 6),
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
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                    ),
                  ),
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
    final s1 =
        (double.tryParse(_sand1MorningController.text) ?? 0) +
        (double.tryParse(_sand1AfternoonController.text) ?? 0);
    final s2 =
        (double.tryParse(_sand2MorningController.text) ?? 0) +
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
        onChanged: (_) => _scheduleUiRefresh(),
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
          if (_sand1OperatorNames.isNotEmpty ||
              _sand2OperatorNames.isNotEmpty) ...[
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
                                  side: const BorderSide(
                                    color: Color(0xFFC9DAFF),
                                  ),
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
                                  side: const BorderSide(
                                    color: Color(0xFFC3EFFF),
                                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
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
                        decoration: deco(
                          'เช้าเริ่ม (07.20)',
                          Icons.wb_sunny_outlined,
                        ),
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
                        decoration: deco(
                          'บ่ายเริ่ม (13.00)',
                          Icons.wb_twilight_outlined,
                        ),
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
                color: drums > 0
                    ? const Color(0xFF9FC5F0)
                    : const Color(0xFFDCEAF7),
                width: drums > 0 ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF1565C0,
                  ).withValues(alpha: drums > 0 ? 0.12 : 0.02),
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
                key: ValueKey(
                  '${total.toStringAsFixed(0)}-${drums.toStringAsFixed(0)}',
                ),
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
    ValueChanged<String>? onChanged,
    bool allowDecimal = false,
    int maxDecimalPlaces = 2,
  }) async {
    await Future<void>.delayed(Duration.zero);

    final rootContext = context;
    if (!rootContext.mounted) return;

    String value = controller.text;

    await showGeneralDialog<void>(
      context: rootContext,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(rootContext).modalBarrierDismissLabel,
      barrierColor: const Color(0x48000000),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogCtx, animation, _) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.085),
                end: Offset.zero,
              ).animate(curve),
              child: FadeTransition(
                opacity: curve,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.viewInsetsOf(dialogCtx).bottom + 14,
                  ),
                  child: LayoutBuilder(
                    builder: (layoutContext, _) {
                      final mq = MediaQuery.of(layoutContext);
                      final landscape =
                          mq.orientation == Orientation.landscape;
                      final padV = mq.viewPadding.vertical;
                      final maxPanelH = (mq.size.height - padV - 20).clamp(
                        120.0,
                        mq.size.height,
                      );
                      final maxPanelW = landscape
                          ? (mq.size.shortestSide * 0.92).clamp(
                              220.0,
                              mq.size.width - 28,
                            )
                          : (mq.size.width - 26).clamp(0.0, 520.0);

                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxPanelW,
                            maxHeight: maxPanelH,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            clipBehavior: Clip.none,
                            child: StatefulBuilder(
                              builder: (context, setModalState) {
                                final keyH = landscape ? 40.0 : 52.0;
                                final keyFont = landscape ? 19.0 : 23.0;
                                final aspect = landscape ? 2.85 : 1.75;

                                Widget keyButton(String k) {
                                  return FilledButton(
                                    onPressed: () {
                                      if (k == '.' && !allowDecimal) return;
                                      if (k == '.') {
                                        if (value.contains('.')) return;
                                        value =
                                            value.isEmpty ? '0.' : '$value.';
                                        controller.text = value;
                                        onChanged?.call(value);
                                        setModalState(() {});
                                        return;
                                      }
                                      if (allowDecimal &&
                                          value.contains('.')) {
                                        final idx = value.indexOf('.');
                                        final decimals =
                                            value.substring(idx + 1);
                                        if (decimals.length >=
                                            maxDecimalPlaces) {
                                          return;
                                        }
                                      }
                                      value += k;
                                      controller.text = value;
                                      onChanged?.call(value);
                                      setModalState(() {});
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor:
                                          const Color(0xFF1D2A3A),
                                      minimumSize:
                                          Size.fromHeight(keyH),
                                      padding:
                                          EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      k,
                                      style: GoogleFonts.kanit(
                                        fontSize: keyFont,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                }

                                Widget auxButton({
                                  required Widget child,
                                  required Color fg,
                                  required Color bg,
                                  required VoidCallback? onTap,
                                }) {
                                  return FilledButton(
                                    onPressed: onTap,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: bg,
                                      foregroundColor: fg,
                                      minimumSize: Size.fromHeight(keyH),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: child,
                                  );
                                }

                                return Container(
                                  padding: EdgeInsets.fromLTRB(
                                    landscape ? 10 : 12,
                                    landscape ? 8 : 10,
                                    landscape ? 10 : 12,
                                    landscape ? 8 : 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F5FA),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFD8E2EE),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 18,
                                        offset: const Offset(0, -4),
                                      ),
                                    ],
                                  ),
                                  child: SingleChildScrollView(
                                    physics:
                                        const ClampingScrollPhysics(),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                label,
                                                maxLines: landscape ? 2 : 3,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style:
                                                    GoogleFonts.kanit(
                                                  fontSize: landscape
                                                      ? 14.5
                                                      : 17,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                value.isEmpty ? '0' : value,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                textAlign: TextAlign.end,
                                                style: GoogleFonts.kanit(
                                                  fontSize: landscape
                                                      ? 17
                                                      : 21,
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  color:
                                                      const Color(0xFF1565C0),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: landscape ? 6 : 10),
                                        GridView.count(
                                          crossAxisCount: 3,
                                          mainAxisSpacing:
                                              landscape ? 5 : 8,
                                          crossAxisSpacing:
                                              landscape ? 5 : 8,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          childAspectRatio: aspect,
                                          children: [
                                            keyButton('1'),
                                            keyButton('2'),
                                            keyButton('3'),
                                            keyButton('4'),
                                            keyButton('5'),
                                            keyButton('6'),
                                            keyButton('7'),
                                            keyButton('8'),
                                            keyButton('9'),
                                            auxButton(
                                              bg: const Color(0xFFFFEFEF),
                                              fg: const Color(0xFFD64545),
                                              onTap: () {
                                                value = '';
                                                controller.text = value;
                                                onChanged?.call(value);
                                                setModalState(() {});
                                              },
                                              child: Text(
                                                'ล้าง',
                                                style: GoogleFonts.kanit(
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: landscape ? 13.0 : 14.5,
                                                ),
                                              ),
                                            ),
                                            keyButton('0'),
                                            if (allowDecimal)
                                              keyButton('.'),
                                            auxButton(
                                              bg: const Color(0xFFE9F1FF),
                                              fg:
                                                  const Color(0xFF1565C0),
                                              onTap: () {
                                                if (value.isNotEmpty) {
                                                  value = value.substring(
                                                    0,
                                                    value.length - 1,
                                                  );
                                                  controller.text = value;
                                                  onChanged?.call(value);
                                                  setModalState(() {});
                                                }
                                              },
                                              child: const Icon(
                                                Icons.backspace_outlined,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: landscape ? 6 : 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: () =>
                                                Navigator.of(
                                                  dialogCtx,
                                                ).pop(),
                                            icon: Icon(
                                              Icons.check_circle_outline,
                                              size: landscape ? 20 : 24,
                                            ),
                                            label: Text(
                                              'เสร็จสิ้น',
                                              style: GoogleFonts.kanit(
                                                fontWeight:
                                                    FontWeight.w800,
                                                fontSize: landscape ? 15.5 : 19,
                                              ),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(
                                                0xFF1565C0,
                                              ),
                                              foregroundColor:
                                                  Colors.white,
                                              minimumSize: Size.fromHeight(
                                                landscape ? 44 : 54,
                                              ),
                                              shape:
                                                  RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      14,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFuelTime(_FuelVehicleDraft row) async {
    final initial = TimeOfDay.now();
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFF1565C0)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t == null) return;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final value = '$hh:$mm';
    setState(() {
      row.time = value;
      row.timeController.text = value;
    });
  }

  Widget _buildVehicleTripFormCard() {
    if (_vehicleTripDrafts.isEmpty) {
      _vehicleTripDrafts.add(_VehicleTripDraft.empty());
    }
    return _VehicleTripFormSection(
      child: AnimatedContainer(
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
          _VehicleTripRowsBoard(
            rows: _vehicleTripDrafts,
            cars: _cars,
            drivers: _driverEmployees,
            workSuggestions: _vehicleWorkSuggestions,
            vehicleLabelFromId: _vehicleLabelFromId,
            driverLabelFromId: _driverLabelFromId,
            openNumericPad: _openNumericPad,
            notifyParentRefresh: _scheduleUiRefresh,
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
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildFuelFormCard() {
    final fuelCars = _fuelMacroCars();
    if (_fuelVehicleDrafts.isEmpty) {
      _fuelVehicleDrafts.add(_FuelVehicleDraft.empty());
    }
    double totalLiters = 0;
    for (final row in _fuelVehicleDrafts) {
      totalLiters += double.tryParse(row.liters) ?? 0;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
            'บันทึกการใช้น้ำมันของรถแต่ละคัน',
            style: GoogleFonts.kanit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(_fuelVehicleDrafts.length, (index) {
            final row = _fuelVehicleDrafts[index];
            return Container(
              margin: EdgeInsets.only(
                bottom: index == _fuelVehicleDrafts.length - 1 ? 0 : 12,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FCFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE8F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'คันที่ ${index + 1}',
                        style: GoogleFonts.kanit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF205A9A),
                        ),
                      ),
                      const Spacer(),
                      if (_fuelVehicleDrafts.length > 1)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              final removed = _fuelVehicleDrafts.removeAt(
                                index,
                              );
                              removed.dispose();
                            });
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: const Color(0xFFD14343),
                          tooltip: 'ลบคันนี้',
                        ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('fuel_vehicle_${index}_${row.vehicleId}'),
                    isExpanded: true,
                    initialValue:
                        row.vehicleId.isEmpty ||
                            !fuelCars.contains(row.vehicleId)
                        ? null
                        : row.vehicleId,
                    decoration: const InputDecoration(
                      labelText: 'เลือกรถแม็คโคร',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: fuelCars
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(
                              c,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(fontSize: 18),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      row.vehicleId = v ?? '';
                      _scheduleUiRefresh();
                    },
                  ),
                  if (fuelCars.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'ยังไม่พบรายการรถแม็คโครในตั้งค่าแอพ',
                        style: GoogleFonts.kanit(
                          color: const Color(0xFFD14343),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(
                          'ดีเซล',
                          style: GoogleFonts.kanit(fontSize: 16),
                        ),
                        selected: row.fuelType == 'Diesel',
                        onSelected: (_) =>
                            setState(() => row.fuelType = 'Diesel'),
                      ),
                      ChoiceChip(
                        label: Text(
                          'เบนซิน',
                          style: GoogleFonts.kanit(fontSize: 16),
                        ),
                        selected: row.fuelType == 'Benzine',
                        onSelected: (_) =>
                            setState(() => row.fuelType = 'Benzine'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: row.litersController,
                    readOnly: true,
                    onTap: () => _openNumericPad(
                      controller: row.litersController,
                      label: 'ใช้น้ำมัน (ลิตร)',
                      onChanged: (v) => row.liters = v,
                      allowDecimal: true,
                      maxDecimalPlaces: 2,
                    ),
                    style: GoogleFonts.kanit(
                      color: const Color(0xFF1D2A3A),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'ใช้น้ำมัน (ลิตร)',
                      prefixIcon: Icon(Icons.opacity_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: row.timeController,
                    readOnly: true,
                    onTap: () => _pickFuelTime(row),
                    style: GoogleFonts.kanit(
                      color: const Color(0xFF1D2A3A),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'เวลาเติมน้ำมัน',
                      prefixIcon: Icon(Icons.access_time_outlined),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: fuelCars.isEmpty
                ? null
                : () => setState(
                    () => _fuelVehicleDrafts.add(_FuelVehicleDraft.empty()),
                  ),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'เพิ่มรถอีกคัน',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: totalLiters > 0
                    ? const Color(0xFFBFD8F4)
                    : const Color(0xFFE2EAF4),
              ),
            ),
            child: Text(
              'รวมใช้น้ำมัน ${totalLiters.toStringAsFixed(0)} ลิตร (${_fuelVehicleDrafts.length} คัน)',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelVehicleUsageEntries,
              icon: const Icon(Icons.directions_car_outlined),
              label: Text(
                'บันทึกการใช้น้ำมันรายรถ',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSandFormCard() {
    final typedHome = double.tryParse(_drumsWashedAtHomeController.text) ?? 0;
    final home = _homeWashAll ? _homeSandAvailable : typedHome;
    final remain = (_homeSandAvailable - home).clamp(0, 999999).toDouble();
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
          IgnorePointer(
            ignoring: _homeWashAll,
            child: Opacity(
              opacity: _homeWashAll ? 0.55 : 1,
              child: _AnimatedInputField(
                controller: _drumsWashedAtHomeController,
                onChanged: (_) => _scheduleUiRefresh(),
                keyboardType: TextInputType.number,
                readOnly: true,
                onTap: () {
                  if (_homeWashAll) return;
                  _openNumericPad(
                    controller: _drumsWashedAtHomeController,
                    label: 'จำนวนทรายที่ล้างที่บ้านวันนี้ (ถัง)',
                    onChanged: (_) => _scheduleUiRefresh(),
                  );
                },
                style: GoogleFonts.kanit(
                  color: const Color(0xFF1D2A3A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  labelText: 'จำนวนทรายที่ล้างที่บ้านวันนี้',
                  prefixIcon: Icon(Icons.home_work_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _homeWashAll,
            onChanged: (v) {
              setState(() {
                _homeWashAll = v;
                if (v) {
                  _drumsWashedAtHomeController.text = _strNum(
                    _homeSandAvailable,
                  );
                }
              });
            },
            title: Text(
              'ล้างทรายทั้งหมด (ตัดรอบ)',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'ระบบจะใช้จำนวนคงเหลือทั้งหมด ${_homeSandAvailable.toStringAsFixed(0)} ถัง',
              style: GoogleFonts.kanit(fontSize: 12.5),
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
              'คงเหลือก่อนวันนี้: ${_homeSandBeforeToday.toStringAsFixed(0)} • ได้เพิ่มวันนี้: ${_homeSandTodayObtained.toStringAsFixed(0)}\nล้างที่บ้านวันนี้: ${home.toStringAsFixed(0)} • คงเหลือหลังล้าง: ${remain.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _saveQuickEntry,
            icon: const Icon(Icons.save_outlined),
            label: Text('บันทึกทรายที่ล้างที่บ้าน', style: GoogleFonts.kanit()),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _collectLaborAssignedIds() {
    final out = <String>{};
    for (final entry in _laborAssignments.values) {
      out.addAll(entry);
    }
    return out;
  }

  List<Map<String, String>> _laborCategoryPayload() {
    return _laborCategories
        .map((c) => {'id': c.id, 'label': c.label})
        .toList(growable: false);
  }

  String _laborCategoryLabel(String id) {
    for (final c in _laborCategories) {
      if (c.id == id) return c.label;
    }
    return id;
  }

  Widget _employeeDataLoadProgressBanner() {
    if (!_employeesLoading) return const SizedBox.shrink();
    final pct = _employeesLoadPercent.clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEFF7FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC8DCF2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: pct / 100.0,
                  backgroundColor: const Color(0xFFD6E8FA),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF1565C0),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'โหลดข้อมูลพนักงาน $pct%',
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: const Color(0xFF205A9A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLaborCanvasBoard() {
    return _LaborDragBoard(
      categories: _laborCategories,
      employees: _employees,
      employeesById: _employeesById,
      assignments: _laborAssignments,
      pickedIds: _laborPickedIds,
      bucketExpanded: _laborBucketExpanded,
    );
  }

  Widget _buildLaborFormCard() {
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
          _employeeDataLoadProgressBanner(),
          const SizedBox(height: 8),
          _LaborCanvasSection(
            child: _buildLaborCanvasBoard(),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveQuickEntry,
              icon: const Icon(Icons.save_outlined),
              label: Text('บันทึกค่าแรง', style: GoogleFonts.kanit()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Employee> _sortedEmployeesForOt() {
    final list = _employees.where((e) => !e.inactive).toList()
      ..sort(
        (a, b) => _employeeUiDisplayName(a).compareTo(
          _employeeUiDisplayName(b),
        ),
      );
    return list;
  }

  Widget _buildOtEmployeeChips(_OtGroupDraft group) {
    final list = _sortedEmployeesForOt();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF3DEB8)),
        ),
        child: Text(
          'ยังไม่มีรายการพนักงานในระบบ',
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF8A6A2C),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: list.map((e) {
        final id = e.id;
        final selected = group.employeeIds.contains(id);
        final name = _employeeUiDisplayName(e);
        return FilterChip(
          label: Text(name, style: GoogleFonts.kanit(fontSize: 13)),
          selected: selected,
          onSelected: (_) {
            setState(() {
              if (selected) {
                group.employeeIds.remove(id);
              } else {
                group.employeeIds.add(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildOtFormCard() {
    final employees = _sortedEmployeesForOt();
    final summaryLines = <String>[];
    for (var i = 0; i < _otGroups.length; i++) {
      final g = _otGroups[i];
      final h = double.tryParse(g.hoursController.text.trim()) ?? 0;
      final c = g.employeeIds.length;
      if (c == 0 && h == 0) continue;
      if (c > 0 && h > 0) {
        summaryLines.add('กลุ่ม ${i + 1}: $c คน × ${h.toStringAsFixed(1)} ชม.');
      }
    }
    final summaryKey = summaryLines.join('|');
    final hasValidPreview = summaryLines.isNotEmpty;

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
          const SizedBox(height: 6),
          Text(
            'แบ่งกลุ่มได้หลายกลุ่ม — แต่ละกลุ่มเลือกคนและชั่วโมง OT แยกกัน',
            style: GoogleFonts.kanit(
              fontSize: 13,
              color: const Color(0xFF5B6D83),
            ),
          ),
          _employeeDataLoadProgressBanner(),
          const SizedBox(height: 10),
          ...List.generate(_otGroups.length, (index) {
            final g = _otGroups[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == _otGroups.length - 1 ? 0 : 12,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FCFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE8F5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'กลุ่มที่ ${index + 1}',
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF205A9A),
                          ),
                        ),
                        const Spacer(),
                        if (_otGroups.length > 1)
                          IconButton(
                            tooltip: 'ลบกลุ่มนี้',
                            onPressed: () {
                              setState(() {
                                final removed = _otGroups.removeAt(index);
                                removed.dispose();
                              });
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFD14343),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'เลือกพนักงาน',
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: const Color(0xFF314C6D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildOtEmployeeChips(g),
                    const SizedBox(height: 10),
                    _AnimatedInputField(
                      controller: g.hoursController,
                      onChanged: (_) => _scheduleUiRefresh(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      readOnly: true,
                      onTap: () => _openNumericPad(
                        controller: g.hoursController,
                        label: 'ชั่วโมง OT (กลุ่มที่ ${index + 1})',
                        onChanged: (_) => _scheduleUiRefresh(),
                        allowDecimal: true,
                        maxDecimalPlaces: 2,
                      ),
                      style: GoogleFonts.kanit(
                        color: const Color(0xFF1D2A3A),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'จำนวนชั่วโมง OT ของกลุ่มนี้',
                        prefixIcon: Icon(Icons.timelapse_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (employees.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _otGroups.add(_OtGroupDraft.empty());
              }),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'เพิ่มกลุ่ม OT',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _otDescController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน OT (ใช้ร่วมทุกกลุ่ม)',
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
                      onPressed: () =>
                          setState(() => _otDescController.text = s),
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
                color: hasValidPreview
                    ? const Color(0xFFF2D39D)
                    : const Color(0xFFF3E7CC),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: summaryLines.isEmpty
                  ? Text(
                      'ยังไม่มีกลุ่มที่ครบทั้งคนและชั่วโมง',
                      key: const ValueKey('ot-empty'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7A6A4A),
                      ),
                    )
                  : Text(
                      summaryLines.join('\n'),
                      key: ValueKey(summaryKey),
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
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
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
              borderSide: const BorderSide(
                color: Color(0xFF3EA0FF),
                width: 1.2,
              ),
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

typedef _OpenNumericPad = void Function({
  required TextEditingController controller,
  required String label,
  ValueChanged<String>? onChanged,
  bool allowDecimal,
  int maxDecimalPlaces,
});

class _VehicleTripRowsBoard extends StatefulWidget {
  const _VehicleTripRowsBoard({
    required this.rows,
    required this.cars,
    required this.drivers,
    required this.workSuggestions,
    required this.vehicleLabelFromId,
    required this.driverLabelFromId,
    required this.openNumericPad,
    required this.notifyParentRefresh,
  });

  final List<_VehicleTripDraft> rows;
  final List<String> cars;
  final List<Employee> drivers;
  final List<String> workSuggestions;
  final String Function(String vehicleId) vehicleLabelFromId;
  final String Function(String driverId) driverLabelFromId;
  final _OpenNumericPad openNumericPad;
  final VoidCallback notifyParentRefresh;

  @override
  State<_VehicleTripRowsBoard> createState() => _VehicleTripRowsBoardState();
}

class _VehicleTripRowsBoardState extends State<_VehicleTripRowsBoard> {
  late final ValueNotifier<_VehicleTripAggregate> _summaryNotifier;

  _VehicleTripAggregate _calcAggregate() {
    double sumTrips = 0;
    double sumCubic = 0;
    for (final row in widget.rows) {
      final morning = double.tryParse(row.tripMorning) ?? 0;
      final afternoon = double.tryParse(row.tripAfternoon) ?? 0;
      final perTrip = double.tryParse(row.cubicPerTrip) ?? 0;
      final rowTrips = morning + afternoon;
      sumTrips += rowTrips;
      sumCubic += rowTrips * perTrip;
    }
    return _VehicleTripAggregate(
      sumTrips: sumTrips,
      sumCubic: sumCubic,
      rowCount: widget.rows.length,
    );
  }

  void _refreshAggregate() {
    _summaryNotifier.value = _calcAggregate();
  }

  @override
  void initState() {
    super.initState();
    _summaryNotifier = ValueNotifier<_VehicleTripAggregate>(_calcAggregate());
  }

  @override
  void didUpdateWidget(covariant _VehicleTripRowsBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rows, widget.rows)) {
      _refreshAggregate();
    }
  }

  @override
  void dispose() {
    _summaryNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        ...List.generate(widget.rows.length, (index) {
          final row = widget.rows[index];
          return _VehicleTripRowItem(
            key: ValueKey('row_${row.tripTxId ?? index}'),
            index: index,
            row: row,
            canDelete: widget.rows.length > 1,
            cars: widget.cars,
            drivers: widget.drivers,
            workSuggestions: widget.workSuggestions,
            vehicleLabelFromId: widget.vehicleLabelFromId,
            driverLabelFromId: widget.driverLabelFromId,
            openNumericPad: widget.openNumericPad,
            onDelete: () {
              setState(() {
                final removed = widget.rows.removeAt(index);
                removed.dispose();
              });
              _refreshAggregate();
              widget.notifyParentRefresh();
            },
            onChanged: () {
              _refreshAggregate();
              widget.notifyParentRefresh();
            },
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              widget.rows.add(_VehicleTripDraft.empty());
            });
            _refreshAggregate();
            widget.notifyParentRefresh();
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'เพิ่มรถอีกคัน',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<_VehicleTripAggregate>(
          valueListenable: _summaryNotifier,
          builder: (context, agg, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: agg.sumTrips > 0
                    ? const Color(0xFFBFD8F4)
                    : const Color(0xFFE2EAF4),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                'รวม ${agg.sumTrips.toStringAsFixed(0)} เที่ยว • ${agg.sumCubic.toStringAsFixed(0)} คิว (${agg.rowCount} คัน)',
                key: ValueKey(
                  '${agg.sumTrips.toStringAsFixed(0)}-${agg.sumCubic.toStringAsFixed(0)}-${agg.rowCount}',
                ),
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleTripAggregate {
  const _VehicleTripAggregate({
    required this.sumTrips,
    required this.sumCubic,
    required this.rowCount,
  });

  final double sumTrips;
  final double sumCubic;
  final int rowCount;
}

class _VehicleTripRowItem extends StatefulWidget {
  const _VehicleTripRowItem({
    super.key,
    required this.index,
    required this.row,
    required this.canDelete,
    required this.cars,
    required this.drivers,
    required this.workSuggestions,
    required this.vehicleLabelFromId,
    required this.driverLabelFromId,
    required this.openNumericPad,
    required this.onDelete,
    required this.onChanged,
  });

  final int index;
  final _VehicleTripDraft row;
  final bool canDelete;
  final List<String> cars;
  final List<Employee> drivers;
  final List<String> workSuggestions;
  final String Function(String vehicleId) vehicleLabelFromId;
  final String Function(String driverId) driverLabelFromId;
  final _OpenNumericPad openNumericPad;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  State<_VehicleTripRowItem> createState() => _VehicleTripRowItemState();
}

class _VehicleTripRowItemState extends State<_VehicleTripRowItem> {
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final rowTrips =
        (double.tryParse(row.tripMorning) ?? 0) +
        (double.tryParse(row.tripAfternoon) ?? 0);
    final rowCubic = rowTrips * (double.tryParse(row.cubicPerTrip) ?? 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'คันที่ ${widget.index + 1}',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF205A9A),
                ),
              ),
              const Spacer(),
              if (widget.canDelete)
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFD14343),
                  tooltip: 'ลบคันนี้',
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('vehicle_${widget.index}_${row.vehicleId}'),
                  isExpanded: true,
                  initialValue: row.vehicleId.isEmpty ? null : row.vehicleId,
                  decoration: const InputDecoration(
                    labelText: 'รถ/เครื่องจักร',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: widget.cars
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(
                            c,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final id = v ?? '';
                    setState(() {
                      row.vehicleId = id;
                      _applyDefaultCubicForVehicleRow(row, id);
                    });
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('driver_${widget.index}_${row.driverId}'),
                  isExpanded: true,
                  initialValue: row.driverId.isEmpty ||
                          !widget.drivers.any((e) => e.id == row.driverId)
                      ? null
                      : row.driverId,
                  decoration: const InputDecoration(
                    labelText: 'คนขับ',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: widget.drivers
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.nickname.isNotEmpty ? e.nickname : e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() => row.driverId = v ?? '');
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          if (widget.drivers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'ยังไม่พบพนักงานที่ตำแหน่งเป็น "คนขับรถ"',
                style: GoogleFonts.kanit(
                  color: const Color(0xFFD14343),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD7E6F7)),
            ),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'FullDay', label: Text('เต็มวัน')),
                ButtonSegment<String>(value: 'HalfDay', label: Text('ครึ่งวัน')),
                ButtonSegment<String>(value: 'Hourly', label: Text('รายชั่วโมง')),
              ],
              selected: {
                row.workType == 'HalfDay' || row.workType == 'Hourly'
                    ? row.workType
                    : 'FullDay',
              },
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() => row.workType = selection.first);
                widget.onChanged();
              },
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          if (row.workType == 'Hourly') ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: row.hourlyHoursController,
              readOnly: true,
              onTap: () => widget.openNumericPad(
                controller: row.hourlyHoursController,
                label: 'จำนวนชั่วโมง (ชม.)',
                onChanged: (v) {
                  row.hourlyHours = v;
                  widget.onChanged();
                  setState(() {});
                },
                allowDecimal: true,
                maxDecimalPlaces: 2,
              ),
              style: GoogleFonts.kanit(
                color: const Color(0xFF1D2A3A),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'รายชั่วโมง (ชม.)',
                prefixIcon: Icon(Icons.schedule_rounded),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: row.workDetailsController,
            onChanged: (v) => row.workDetails = v,
            style: GoogleFonts.kanit(
              color: const Color(0xFF1D2A3A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          if (widget.workSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.workSuggestions
                  .map(
                    (s) => ActionChip(
                      label: Text(s, style: GoogleFonts.kanit(fontSize: 13.5)),
                      onPressed: () {
                        setState(() {
                          row.workDetails = s;
                          row.workDetailsController.text = s;
                          row.workDetailsController.selection =
                              TextSelection.collapsed(offset: s.length);
                        });
                        widget.onChanged();
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.tripMorningController,
                  readOnly: true,
                  onTap: () => widget.openNumericPad(
                    controller: row.tripMorningController,
                    label: 'ช่วงเช้า (เที่ยว)',
                    onChanged: (v) {
                      row.tripMorning = v;
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'ช่วงเช้า (เที่ยว)',
                    prefixIcon: Icon(Icons.wb_sunny_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.tripAfternoonController,
                  readOnly: true,
                  onTap: () => widget.openNumericPad(
                    controller: row.tripAfternoonController,
                    label: 'ช่วงบ่าย (เที่ยว)',
                    onChanged: (v) {
                      row.tripAfternoon = v;
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'ช่วงบ่าย (เที่ยว)',
                    prefixIcon: Icon(Icons.nightlight_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: row.cubicPerTripController,
            readOnly: true,
            onTap: () => widget.openNumericPad(
              controller: row.cubicPerTripController,
              label: 'คิวต่อเที่ยว',
              onChanged: (v) {
                row.cubicPerTrip = v;
                widget.onChanged();
                setState(() {});
              },
            ),
            style: GoogleFonts.kanit(
              color: const Color(0xFF1D2A3A),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              labelText: 'คิวต่อเที่ยว',
              prefixIcon: Icon(Icons.straighten_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.vehicleLabelFromId(row.vehicleId)} • ${widget.driverLabelFromId(row.driverId)} • ${rowTrips.toStringAsFixed(0)} เที่ยว • ${rowCubic.toStringAsFixed(0)} คิว',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C4D77),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaborDragBoard extends StatefulWidget {
  const _LaborDragBoard({
    required this.categories,
    required this.employees,
    required this.employeesById,
    required this.assignments,
    required this.pickedIds,
    required this.bucketExpanded,
  });

  final List<_LaborWorkCategory> categories;
  final List<Employee> employees;
  final Map<String, Employee> employeesById;
  final Map<String, Set<String>> assignments;
  final Set<String> pickedIds;
  final Map<String, bool> bucketExpanded;

  @override
  State<_LaborDragBoard> createState() => _LaborDragBoardState();
}

class _LaborDragBoardState extends State<_LaborDragBoard> {
  Set<String> _collectAssigned() {
    final out = <String>{};
    for (final entry in widget.assignments.values) {
      out.addAll(entry);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final assignedIds = _collectAssigned();
    final available = widget.employees
        .where((e) => !assignedIds.contains(e.id))
        .toList();

    Widget bucketCard(_LaborWorkCategory category) {
      final id = category.id;
      final ids = widget.assignments[id] ?? <String>{};
      final expanded = (widget.bucketExpanded[id] ?? false) || ids.isNotEmpty;
      return _LaborBucketCard(
        category: category,
        ids: ids,
        expanded: expanded,
        employeesById: widget.employeesById,
        onToggleExpanded: () => setState(() {
          widget.bucketExpanded[id] = !expanded;
        }),
        onMovePickedHere: widget.pickedIds.isEmpty
            ? null
            : () => setState(() {
                for (final bucket in widget.assignments.values) {
                  bucket.removeAll(widget.pickedIds);
                }
                widget.assignments[id]?.addAll(widget.pickedIds);
                widget.bucketExpanded[id] = true;
                widget.pickedIds.clear();
              }),
        onDropEmployee: (empId) => setState(() {
          for (final bucket in widget.assignments.values) {
            bucket.remove(empId);
          }
          widget.assignments[id]?.add(empId);
          widget.bucketExpanded[id] = true;
          widget.pickedIds.remove(empId);
        }),
        onDeleteEmployee: (empId) => setState(() {
          widget.assignments[id]?.remove(empId);
          if ((widget.assignments[id]?.isEmpty ?? true)) {
            widget.bucketExpanded[id] = false;
          }
        }),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE7F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'เลือกพนักงานเพื่อย้ายลงกล่องงาน',
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.28,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.pickedIds.length} คน',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5B6D83),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DragTarget<String>(
            onWillAcceptWithDetails: (details) => true,
            onAcceptWithDetails: (details) {
              final empId = details.data;
              setState(() {
                for (final bucket in widget.assignments.values) {
                  bucket.remove(empId);
                }
                widget.pickedIds.remove(empId);
              });
            },
            builder: (context, candidateData, rejectedData) {
              final isHovering = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHovering ? const Color(0xFFDDEBFA) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isHovering
                        ? const Color(0xFF73A6E8)
                        : Colors.transparent,
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: available.map((e) {
                    final id = e.id;
                    final selected = widget.pickedIds.contains(id);
                    final name = _employeeUiDisplayName(e);
                    return LongPressDraggable<String>(
                      data: id,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Chip(
                          label: Text(
                            name,
                            style: GoogleFonts.kanit(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: const Color(0xFF3C78C8),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: FilterChip(
                          label: Text(
                            name,
                            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                          ),
                          selected: selected,
                          onSelected: null,
                        ),
                      ),
                      child: FilterChip(
                        label: Text(
                          name,
                          style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                        ),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          if (selected) {
                            widget.pickedIds.remove(id);
                          } else {
                            widget.pickedIds.add(id);
                          }
                        }),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              final itemWidth = (constraints.maxWidth - (spacing * 2)) / 3;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: widget.categories
                    .map((category) => SizedBox(width: itemWidth, child: bucketCard(category)))
                    .toList(),
              );
            },
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
                color: assignedIds.isNotEmpty
                    ? const Color(0xFFBFD8F4)
                    : const Color(0xFFE2EAF4),
              ),
            ),
            child: Text(
              'พนักงานที่จัดลงงานแล้ว ${assignedIds.length} คน',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaborBucketCard extends StatelessWidget {
  const _LaborBucketCard({
    required this.category,
    required this.ids,
    required this.expanded,
    required this.employeesById,
    required this.onToggleExpanded,
    required this.onDropEmployee,
    required this.onDeleteEmployee,
    required this.onMovePickedHere,
  });

  final _LaborWorkCategory category;
  final Set<String> ids;
  final bool expanded;
  final Map<String, Employee> employeesById;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onDropEmployee;
  final ValueChanged<String> onDeleteEmployee;
  final VoidCallback? onMovePickedHere;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onDropEmployee(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final hasMembers = ids.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.all(hasMembers ? 10 : 8),
          decoration: BoxDecoration(
            color: category.color.withValues(alpha: isHovering ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: category.color.withValues(alpha: isHovering ? 0.85 : 0.45),
              width: isHovering ? 1.8 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Tooltip(
                      message: category.label,
                      child: Text(
                        category.label,
                        maxLines: 5,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.kanit(
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2B3A),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: category.color.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${ids.length} คน',
                      maxLines: 1,
                      style: GoogleFonts.kanit(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF314C6D),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: expanded ? 'ยุบช่อง' : 'ขยายช่อง',
                    onPressed: onToggleExpanded,
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: Color(0xFF314C6D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ids.map((empId) {
                          final emp = employeesById[empId];
                          final label = emp == null
                              ? empId
                              : _employeeUiDisplayName(emp);
                          return LongPressDraggable<String>(
                            data: empId,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Chip(
                                label: Text(
                                  label,
                                  style: GoogleFonts.kanit(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: category.color.withValues(alpha: 0.92),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: InputChip(
                                label: Text(
                                  label,
                                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                                ),
                                onDeleted: null,
                              ),
                            ),
                            child: InputChip(
                              label: Text(
                                label,
                                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                              ),
                              onDeleted: () => onDeleteEmployee(empId),
                            ),
                          );
                        }).toList(),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ลากคนมาวางที่ช่องนี้',
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            color: const Color(0xFF5B6D83),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onMovePickedHere,
                icon: const Icon(Icons.south_west_rounded, size: 16),
                label: Text(
                  'ย้ายคนที่เลือกมาที่กล่องนี้',
                  style: GoogleFonts.kanit(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LaborCanvasSection extends StatelessWidget {
  const _LaborCanvasSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: child,
    );
  }
}

class _VehicleTripFormSection extends StatelessWidget {
  const _VehicleTripFormSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: child,
    );
  }
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
  int _paintRevision = 0;

  double _roundCoord(double value) => double.parse(value.toStringAsFixed(2));

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

  bool get _hasSignature => _strokes.any((stroke) => stroke.length > 1);

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
                    setState(() {
                      _strokes.add([details.localPosition]);
                      _paintRevision++;
                    });
                  },
                  onPanUpdate: (details) {
                    if (_strokes.isEmpty) return;
                    setState(() {
                      _strokes.last.add(details.localPosition);
                      _paintRevision++;
                    });
                  },
                  child: Container(
                    height: canvasHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFF),
                      border: Border.all(color: const Color(0xFFD7E2EE)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          strokes: _strokes,
                          revision: _paintRevision,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _strokes.clear();
                      _paintRevision++;
                    }),
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
  const _SignaturePainter({required this.strokes, required this.revision});

  final List<List<Offset>> strokes;
  final int revision;

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
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.revision != revision;
}

class _CapturedSignature {
  const _CapturedSignature({required this.note});
  final String note;
}

class _VehicleTripDraft {
  _VehicleTripDraft()
      : workDetailsController = TextEditingController(),
        hourlyHoursController = TextEditingController(),
        tripMorningController = TextEditingController(),
        tripAfternoonController = TextEditingController(),
        cubicPerTripController = TextEditingController();

  factory _VehicleTripDraft.empty() => _VehicleTripDraft();

  String? tripTxId;
  String vehicleId = '';
  String driverId = '';
  String workType = 'FullDay';
  String hourlyHours = '';
  String workDetails = '';
  String tripMorning = '';
  String tripAfternoon = '';
  String cubicPerTrip = '';
  final TextEditingController workDetailsController;
  final TextEditingController hourlyHoursController;
  final TextEditingController tripMorningController;
  final TextEditingController tripAfternoonController;
  final TextEditingController cubicPerTripController;

  void dispose() {
    workDetailsController.dispose();
    hourlyHoursController.dispose();
    tripMorningController.dispose();
    tripAfternoonController.dispose();
    cubicPerTripController.dispose();
  }
}

/// กลุ่ม OT หนึ่งกลุ่ม (คน + ชม. แยกจากกลุ่มอื่น)
class _OtGroupDraft {
  _OtGroupDraft() : hoursController = TextEditingController();

  factory _OtGroupDraft.empty() => _OtGroupDraft();

  String? persistedId;
  final Set<String> employeeIds = {};
  final TextEditingController hoursController;

  void dispose() {
    hoursController.dispose();
  }
}

class _FuelVehicleDraft {
  _FuelVehicleDraft()
      : litersController = TextEditingController(),
        timeController = TextEditingController();

  factory _FuelVehicleDraft.empty() => _FuelVehicleDraft();

  String? txId;
  String vehicleId = '';
  String fuelType = 'Diesel';
  String liters = '';
  String time = '';
  final TextEditingController litersController;
  final TextEditingController timeController;

  void dispose() {
    litersController.dispose();
    timeController.dispose();
  }
}

class _HomeSandDaily {
  double obtained = 0;
  double home = 0;
}

class _LaborWorkCategory {
  const _LaborWorkCategory({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        duration: Duration(milliseconds: reduceMotion ? 80 : 140),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.996 : (_focused ? 1.004 : 1.0),
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 80 : 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (_focused)
                BoxShadow(
                  color: const Color(0xFF2D8CFF).withValues(alpha: 0.14),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
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
              style:
                  widget.style ??
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
      ),
    );
  }
}

class _SmoothPressable extends StatefulWidget {
  const _SmoothPressable({required this.child, this.enabled = true});

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
      onTapDown: widget.enabled
          ? (_) {
              HapticFeedback.lightImpact();
              setState(() => _pressed = true);
            }
          : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _pressed = false)
          : null,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        offset: Offset(0, _pressed ? 0.004 : 0),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.988 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
