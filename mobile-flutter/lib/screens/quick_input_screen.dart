import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../constants/thai_banks.dart';
import '../widgets/thai_bank_brand_icon.dart';
import '../widgets/thai_text_pad.dart';
import '../utils/advance_employee_filter.dart';
import '../utils/advance_line_notify.dart';
import '../utils/advance_work_details.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/labor_canvas_keys.dart';
import '../utils/device_perf.dart';
import '../services/mobile_error_report_service.dart';
import '../services/session_service.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/save_error_message.dart';

class QuickInputScreen extends StatefulWidget {
  const QuickInputScreen({
    super.key,
    required this.service,
    required this.employeeService,
    this.currentAdmin,
    this.initialCategory,
    this.appBarTitle,

    /// วันที่ตามที่เลือกบนแดชบอร์ด (ให้โหลดธุรกรรมเดิมของวันนั้นได้)
    this.selectedDateForModule,
  });

  final TransactionService service;
  final EmployeeService employeeService;
  final AdminUser? currentAdmin;

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

const String _kGeneralWorkPrefix = kGeneralWorkPrefix;
const Color _kGeneralWorkColor = Color(0xFF5F6AD8);

String _newGeneralSubJobId() =>
    DateTime.now().millisecondsSinceEpoch.toRadixString(36);

String _generalSubJobAssignmentKey(String subId) => '$_kGeneralWorkPrefix$subId';

bool _isGeneralAssignmentKey(String key) => isGeneralLaborAssignmentKey(key);

/// คีย์ yyyy-MM-dd — สอดคล้องกับ `normalizeDate` บนเว็บ (ตัด suffix หลังวันที่)
String _normalizeSandDayKey(String raw) {
  final s = raw.trim();
  if (s.length >= 10) return s.substring(0, 10);
  return s;
}

/// เลือกบันทึกรายจ่ายสาธารณูปโภคหรือรายรับประจำวัน
enum _IuEntryKind { expense, income }

class _QuickInputScreenState extends State<QuickInputScreen>
    with SingleTickerProviderStateMixin {
  static const List<_LaborWorkCategory> _laborCategories = [
    _LaborWorkCategory(
      id: 'wash_old',
      label: 'ล้างทราย เครื่องร่อน 1 (เก่า)',
      shortTitle: 'เครื่องร่อน 1 (เก่า)',
      color: Color(0xFF4A90E2),
    ),
    _LaborWorkCategory(
      id: 'wash_new',
      label: 'ล้างทราย เครื่องร่อน 2 (ใหม่)',
      shortTitle: 'เครื่องร่อน 2 (ใหม่)',
      color: Color(0xFF24A7B8),
    ),
    _LaborWorkCategory(
      id: 'washHome',
      label: 'ล้างทรายที่บ้าน',
      shortTitle: 'ล้างทรายที่บ้าน',
      color: Color(0xFF2CB67D),
    ),
    _LaborWorkCategory(
      id: 'sand_watch',
      label: 'เฝ้าท่าทราย',
      shortTitle: 'เฝ้าท่าทราย',
      color: Color(0xFFE64A9E),
    ),
    _LaborWorkCategory(
      id: 'night_shift',
      label: 'เวรกลางคืน',
      shortTitle: 'เวรกลางคืน',
      color: Color(0xFF7B5AE6),
    ),
    _LaborWorkCategory(
      id: 'dig_haul',
      label: 'ขุดขน',
      shortTitle: 'ขุดขน',
      color: Color(0xFF7962E6),
    ),
    _LaborWorkCategory(
      id: 'night_patrol',
      label: 'เฝ้ากลางคืน',
      shortTitle: 'เฝ้ากลางคืน',
      color: Color(0xFF9C4DCC),
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
  final _dailyEventDescController = TextEditingController();
  String _dailyEventType = 'info';
  String _dailyEventPriority = 'normal';
  final _leaveReasonController = TextEditingController();
  final _leaveDaysController = TextEditingController(text: '1');
  final _advanceAmountPerPersonController = TextEditingController();

  /// ชื่อธนาคารเต็มจากรายการ dropdown (โหมดโอน)
  String _advanceBank = '';
  final _advanceAccountController = TextEditingController();
  final _utilitiesTypeController = TextEditingController();
  final _utilitiesExtraController = TextEditingController();
  final _utilitiesAmountController = TextEditingController();
  final _incomeTypeController = TextEditingController();
  final _incomeQtyController = TextEditingController();
  final _incomeUnitPriceController = TextEditingController();
  final _incomeTotalController = TextEditingController();
  static const String _iuOtherSentinel = '__other__';
  _IuEntryKind? _iuEntryKind;
  String? _iuExpenseChoice;
  String? _iuIncomeChoice;

  /// รายรับประจำวัน: Paid | Unpaid — ตรงกับคอลัมน์ income_payment_status
  String _wizardIncomePaymentStatus = 'Paid';
  List<String> _appExpenseTypes = const [];
  List<String> _appIncomeTypes = const [];
  final Set<String> _selectedLeaveEmpIds = {};
  final Set<String> _selectedAdvanceEmpIds = {};
  String? _laborLeaveTxId;
  String? _advanceWorkDetailsSeed;
  String _advancePayoutSlot = AdvanceGmMeta.evening;
  String _advancePaymentMethod = AdvanceGmMeta.cash;

  /// Personal | Sick — สอดคล้องเว็บ (ลากิจ / ลาป่วย) เก็บใน sub_category
  String _leaveTypeChoice = 'Personal';
  /// ลาครึ่งวัน — เก็บช่วงใน [workDetails] เป็น meta สำหรับ LINE / แก้ไข
  static const String _leaveHalfMorningMeta = 'leave_half:morning';
  static const String _leaveHalfAfternoonMeta = 'leave_half:afternoon';
  bool _leaveIsHalfDay = false;
  String _leaveHalfPart = 'morning';
  List<Employee> _employees = const [];
  bool _employeesLoading = false;
  int _employeesLoadPercent = 0;
  Timer? _employeesLoadProgressTimer;
  List<Employee> _driverEmployees = const [];
  Map<String, Employee> _employeesById = const {};
  List<String> _cars = const [];

  late DateTime _selectedDate;
  late DateTime _leaveStartDate;
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

  /// ธุรกรรมทั้งหมดของวันที่เลือก (ใช้ดึงชื่อจากบันทึกการทำงาน / Labor ขณะเปิดเมนูร่อนทราย)
  List<AppTransaction> _moduleDayAllTransactions = const [];
  bool _moduleDayLoading = false;

  bool get _hasTrackedModuleCategory =>
      (widget.initialCategory?.trim().isNotEmpty ?? false);

  /// ระหว่างรอธุรกรรมของวันที่เลือก และ (ถ้าเป็นเมนูค่าแรง/OT) รายชื่อพนักงาน
  bool get _blockingModuleBootstrap {
    if (!_hasTrackedModuleCategory) return false;
    if (_moduleDayLoading) return true;
    if (_showsEmployeeLoadingUi && _employeesLoading) return true;
    return false;
  }

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
  String? _homeSandRoundTxId;
  String? _genericTxId;
  bool get _isSandWashMode =>
      (widget.initialCategory ?? '').contains('ร่อนทราย');
  bool get _isVehicleTripMode =>
      (widget.initialCategory ?? '').contains('เที่ยวรถ');
  bool get _isFuelMode => (widget.initialCategory ?? '').contains('น้ำมัน');
  bool get _isMacroVehicleMode => widget.initialCategory == 'การใช้รถแม็คโคร';

  _MacroVehicleDraft get _activeMacroVehicleDraft {
    if (_macroVehicleDrafts.isEmpty) {
      _macroVehicleDrafts.add(_MacroVehicleDraft.empty());
    }
    return _macroVehicleDrafts.first;
  }

  void _resetActiveMacroVehicleDraft() {
    _disposeMacroVehicleDrafts();
    _macroVehicleDrafts.add(_MacroVehicleDraft.empty());
  }

  int get _macroSavedVehicleCountToday => _moduleDayTransactions.length;

  bool get _isHomeSandMode =>
      (widget.initialCategory ?? '').contains('ทรายที่ล้างที่บ้าน');
  final List<_FuelVehicleDraft> _fuelVehicleDrafts = [
    _FuelVehicleDraft.empty(),
  ];
  final List<_MacroVehicleDraft> _macroVehicleDrafts = [
    _MacroVehicleDraft.empty(),
  ];
  final List<_VehicleTripDraft> _vehicleTripDrafts = [
    _VehicleTripDraft.empty(),
  ];
  double _homeSandAvailable = 0;
  double _homeSandBeforeToday = 0;
  double _homeSandTodayObtained = 0;
  /// ถังล้างที่บ้านที่บันทึกแล้วของวันที่เลือก — ใช้เมื่อช่องกรอกว่าง (สอดคล้องกับ `computeSandDrumStockSummary` บนเว็บ)
  double _homeSandTodayHomeSaved = 0;
  final Set<String> _selectedLaborEmpIds = {};
  final Set<String> _laborPickedIds = {};
  _LaborEmpPoolKind _laborEmpPoolKind = _LaborEmpPoolKind.sandSieve;
  final Map<String, Set<String>> _laborAssignments = {
    for (final c in _laborCategories) c.id: <String>{},
  };
  final Map<String, bool> _laborBucketExpanded = {
    for (final c in _laborCategories) c.id: false,
  };
  final List<_GeneralSubJob> _generalSubJobs = [];
  final List<_OtGroupDraft> _otGroups = [];
  List<String> _vehicleWorkSuggestions = const [];

  bool get _isLaborMode =>
      widget.initialCategory == 'ค่าแรง' ||
      (widget.initialCategory ?? '').contains('บันทึกการทำงาน');
  bool get _isOtMode => (widget.initialCategory ?? '').contains('OT');

  _OtGroupDraft get _activeOtGroup {
    if (_otGroups.isEmpty) {
      _otGroups.add(_OtGroupDraft.empty());
    }
    return _otGroups.first;
  }

  void _resetActiveOtGroup() {
    for (final g in _otGroups) {
      g.dispose();
    }
    _otGroups
      ..clear()
      ..add(_OtGroupDraft.empty());
  }

  int get _otSavedGroupCountToday => _moduleDayTransactions.length;
  bool get _isDailyEventMode => widget.initialCategory == 'เหตุการณ์';
  bool get _isLaborLeaveMode => widget.initialCategory == 'ลางาน';
  bool get _isLaborAdvanceMode => widget.initialCategory == 'เบิกเงิน';
  bool get _isSuperAdmin => (widget.currentAdmin?.role.trim() == 'SuperAdmin');

  /// SuperAdmin แก้ไข/ลบประวัติได้เฉพาะรายการที่ตรงกับเมนูและวันที่ปัจจุบัน
  bool _superAdminMayManageHistoryRow(AppTransaction t) {
    if (!_isSuperAdmin) return false;
    if (_isIncomeUtilitiesEntryMode) {
      final ymd = _quickYmd(_selectedDate);
      if (t.date.trim() != ymd.trim()) return false;
      return transactionIsUtilitiesExpense(t) ||
          transactionIsWizardDailyIncome(t);
    }
    final cat = widget.initialCategory?.trim() ?? '';
    if (cat.isEmpty) return false;
    return transactionMatchesDailyModule(t, _quickYmd(_selectedDate), cat);
  }

  /// สรุปรายจ่ายสาธารณูปโภค + รายรับประจำวันจากเว็บ (อ่านอย่างเดียว)
  bool get _isIncomeUtilitiesEntryMode =>
      widget.initialCategory?.trim() == 'รายจ่ายรายรับ';

  @override
  void initState() {
    super.initState();
    final pageTitle = widget.appBarTitle?.trim();
    final category = widget.initialCategory?.trim();
    MobileErrorScreenTracker.set(
      page: (pageTitle != null && pageTitle.isNotEmpty)
          ? pageTitle
          : ((category != null && category.isNotEmpty)
                ? category
                : 'บันทึกข้อมูล'),
      module: category,
    );
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final lowSpec = DevicePerf.isConstrainedDevice;
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: reduceMotion ? 80 : (lowSpec ? 120 : 195),
      ),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.56, curve: Curves.easeOutCubic),
          ),
        );
    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _entranceController.forward();
    _ensureDefaultGeneralSubJob();
    final d = widget.selectedDateForModule ?? DateTime.now();
    _selectedDate = DateTime(d.year, d.month, d.day);
    _leaveStartDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    _categoryController = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory!.trim()
          : 'ค่าแรง',
    );
    _loadEmployees(forceRefresh: _isLaborMode);
    _loadAppCars();
    _loadAppExpenseIncomeTypes();
    _loadOtSuggestions();
    _loadVehicleWorkSuggestions();
    _refreshHomeSandStock();
    _otGroups.add(_OtGroupDraft.empty());
    final cat = widget.initialCategory?.trim();
    if (cat != null && cat.isNotEmpty) {
      _moduleDayLoading = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
    _laborLeaveTxId = null;
    _homeSandTxId = null;
    _homeSandRoundTxId = null;
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

  /// ลบแถวรถดรัม: แถวที่บันทึกแล้ว (`tripTxId`) ลบจากฐานข้อมูลแล้วโหลดรายการใหม่ — ไม่เช่นนั้นลบเฉพาะในแบบฟอร์ม
  Future<void> _handleVehicleTripRowDelete(int index) async {
    if (index < 0 || index >= _vehicleTripDrafts.length) return;
    final row = _vehicleTripDrafts[index];
    final persistedId = row.tripTxId?.trim();
    if (persistedId != null && persistedId.isNotEmpty) {
      try {
        await widget.service.deleteTransaction(persistedId);
        if (!mounted) return;
        await _loadModuleTransactions(forceRefresh: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบรายการจากฐานข้อมูลแล้ว', style: GoogleFonts.kanit()),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบไม่สำเร็จ: $e', style: GoogleFonts.kanit()),
            ),
          );
        }
      }
      return;
    }
    setState(() {
      final removed = _vehicleTripDrafts.removeAt(index);
      removed.dispose();
      if (_vehicleTripDrafts.isEmpty) {
        _vehicleTripDrafts.add(_VehicleTripDraft.empty());
      }
    });
  }

  /// ลบแถวแม็คโคร: แถวที่บันทึกแล้ว (`txId`) ลบจากฐานข้อมูลแล้วโหลดรายการใหม่ — ไม่เช่นนั้นลบเฉพาะในแบบฟอร์ม
  Future<void> _handleMacroVehicleRowDelete(int index) async {
    if (index < 0 || index >= _macroVehicleDrafts.length) return;
    final row = _macroVehicleDrafts[index];
    final persistedId = row.txId?.trim();
    if (persistedId != null && persistedId.isNotEmpty) {
      try {
        await widget.service.deleteTransaction(persistedId);
        if (!mounted) return;
        await _loadModuleTransactions(forceRefresh: true);
        if (!mounted) return;
        setState(_resetActiveMacroVehicleDraft);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบรายการจากฐานข้อมูลแล้ว', style: GoogleFonts.kanit()),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบไม่สำเร็จ: $e', style: GoogleFonts.kanit()),
            ),
          );
        }
      }
      return;
    }
    setState(() {
      final removed = _macroVehicleDrafts.removeAt(index);
      removed.dispose();
      if (_macroVehicleDrafts.isEmpty) {
        _macroVehicleDrafts.add(_MacroVehicleDraft.empty());
      }
    });
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

  void _disposeMacroVehicleDrafts() {
    for (final row in _macroVehicleDrafts) {
      row.dispose();
    }
  }

  void _replaceMacroVehicleDrafts(List<_MacroVehicleDraft> nextRows) {
    _disposeMacroVehicleDrafts();
    _macroVehicleDrafts
      ..clear()
      ..addAll(nextRows.isEmpty ? [_MacroVehicleDraft.empty()] : nextRows);
  }

  /// ดึงข้อมูลแม็คโครของคันที่เลือกในวันนี้ (ล่าสุด) เพื่อแก้ไข — กันบันทึกซ้ำ
  void _applyMacroVehicleRowFromExistingTransaction(
    _MacroVehicleDraft row,
    List<AppTransaction> pool,
    String ymd,
  ) {
    final vid = row.vehicleId.trim();
    if (vid.isEmpty) {
      row.txId = null;
      return;
    }
    AppTransaction? best;
    for (final t in pool) {
      if (t.date.trim() != ymd.trim()) continue;
      if (!isMacroVehicleTransaction(t)) continue;
      if ((t.vehicleId ?? '').trim() != vid) continue;
      if (best == null) {
        best = t;
        continue;
      }
      final ta = t.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ba = best.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (ta.isAfter(ba)) best = t;
    }
    if (best != null) {
      row.txId = best.id;
      row.driverId = (best.driverId ?? '').trim();
      final wt = (best.workType ?? '').trim();
      row.workType = wt == 'HalfDay' ? 'HalfDay' : 'FullDay';
      row.workDetailsController.text = _stripRecorderSuffix(
        best.workDetails ?? '',
      );
      _persistOmitCreatedForIds.add(best.id);
    } else {
      row.txId = null;
      row.driverId = '';
      row.workType = 'FullDay';
      row.workDetailsController.clear();
    }
  }

  Future<void> _onMacroVehicleSelected(_MacroVehicleDraft row) async {
    final pickedVid = row.vehicleId.trim();
    final ymd = _quickYmd(_selectedDate);
    if (pickedVid.isEmpty) {
      row.txId = null;
      if (mounted) setState(() {});
      _scheduleUiRefresh();
      return;
    }
    try {
      final pool = await widget.service.fetchTransactionsForDate(
        ymd,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (row.vehicleId.trim() != pickedVid) return;
      final cat = widget.initialCategory?.trim() ?? '';
      final matched = pool
          .where((t) => transactionMatchesDailyModule(t, ymd, cat))
          .toList()
        ..sort((a, b) {
          final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
      setState(() {
        _moduleDayAllTransactions = pool;
        _moduleDayTransactions = matched;
      });
      _applyMacroVehicleRowFromExistingTransaction(row, pool, ymd);
      if (!mounted) return;
      setState(() {});
      if (row.txId != null && row.txId!.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'โหลดข้อมูลที่บันทึกไว้สำหรับรถคันนี้ในวันนี้แล้ว — แก้ไขแล้วกดบันทึก',
              style: GoogleFonts.kanit(fontSize: 14),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _scheduleUiRefresh();
    }
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
      _sandEveningEndController.clear();
      _sand1OperatorNames = const [];
      _sand2OperatorNames = const [];
    } else if (_isHomeSandMode) {
      _sandDrumsObtainedController.clear();
      _drumsWashedAtHomeController.clear();
    } else if (_isVehicleTripMode) {
      _vehicleIdController.clear();
      _driverIdController.clear();
      _vehicleWorkDetailsController.clear();
      _tripMorningController.clear();
      _tripAfternoonController.clear();
      _cubicPerTripController.clear();
      if (!_saving) _replaceVehicleDrafts(const []);
    } else if (_isFuelMode) {
      _fuelLitersController.clear();
      _fuelAmountController.clear();
      _fuelDetailsController.clear();
      _fuelVehicleController.clear();
      _fuelVehicleLitersController.clear();
      _fuelVehicleTimeController.clear();
      if (!_saving) _replaceFuelVehicleDrafts(const []);
    } else if (_isMacroVehicleMode) {
      if (!_saving) _replaceMacroVehicleDrafts(const []);
    } else if (_isLaborMode) {
      _selectedLaborEmpIds.clear();
      _laborPickedIds.clear();
      _laborEmpPoolKind = _LaborEmpPoolKind.sandSieve;
      for (final k in _laborAssignments.keys) {
        _laborAssignments[k]?.clear();
      }
      for (final k in _laborBucketExpanded.keys) {
        _laborBucketExpanded[k] = false;
      }
      _resetGeneralSubJobsAfterSave();
      _laborWorkDetailsController.clear();
    } else if (_isLaborLeaveMode) {
      if (!_saving) {
        _selectedLeaveEmpIds.clear();
        _laborLeaveTxId = null;
        _leaveTypeChoice = 'Personal';
        _leaveIsHalfDay = false;
        _leaveHalfPart = 'morning';
        _leaveReasonController.clear();
        _leaveDaysController.text = '1';
        _leaveStartDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
      }
    } else if (_isLaborAdvanceMode) {
      _selectedAdvanceEmpIds.clear();
      _advanceWorkDetailsSeed = null;
      _advancePayoutSlot = AdvanceGmMeta.evening;
      _advancePaymentMethod = AdvanceGmMeta.cash;
      _advanceBank = '';
      _advanceAccountController.clear();
      _advanceAmountPerPersonController.clear();
    } else if (_isOtMode) {
      if (!_saving) {
        _resetActiveOtGroup();
        _otDescController.clear();
      }
    } else if (_isDailyEventMode) {
      _dailyEventDescController.clear();
      _dailyEventType = 'info';
      _dailyEventPriority = 'normal';
    } else if (_isIncomeUtilitiesEntryMode) {
      _iuEntryKind = null;
      _iuExpenseChoice = null;
      _iuIncomeChoice = null;
      _wizardIncomePaymentStatus = 'Paid';
      _utilitiesTypeController.clear();
      _utilitiesExtraController.clear();
      _utilitiesAmountController.clear();
      _incomeTypeController.clear();
      _incomeQtyController.clear();
      _incomeUnitPriceController.clear();
      _incomeTotalController.clear();
    } else {
      _amountController.clear();
      _descriptionController.clear();
    }
  }

  Future<void> _loadModuleTransactions({
    bool preserveIncomeUtilitiesForm = false,
    bool forceRefresh = false,
  }) async {
    final cat = widget.initialCategory?.trim();
    if (!mounted || cat == null || cat.isEmpty) return;
    setState(() {
      _moduleDayLoading = true;
      _moduleHistoryVisible = false;
    });
    _clearHydrationSlots();
    if (!(preserveIncomeUtilitiesForm && cat == 'รายจ่ายรายรับ')) {
      _clearModuleFormFields();
    }
    try {
      final ymd = _quickYmd(_selectedDate);
      final forceServer = forceRefresh ||
          cat == 'ลางาน' ||
          cat == 'จำนวนเที่ยวรถ' ||
          cat == 'การใช้รถแม็คโคร' ||
          cat.toUpperCase().contains('OT');
      final rows = cat == 'ลางาน'
          ? await widget.service.fetchTransactions(forceRefresh: forceServer)
          : await widget.service.fetchTransactionsForDate(
              ymd,
              forceRefresh: forceServer,
            );
      final matched = cat == 'รายจ่ายรายรับ'
          ? rows
                .where(
                  (t) =>
                      t.date.trim() == ymd.trim() &&
                      (transactionIsUtilitiesExpense(t) ||
                          transactionIsWizardDailyIncome(t)),
                )
                .toList()
          : rows
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
        _moduleDayAllTransactions = rows;
        _moduleDayLoading = false;
        _moduleHistoryVisible = false;
      });
      if (cat != 'รายจ่ายรายรับ') {
        await _refreshHomeSandStock();
      }
      _hydrateFormsFromTransactions(matched, dayTransactions: rows);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _moduleDayTransactions = const [];
        _moduleDayAllTransactions = const [];
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

  /// ตัวเลขที่พิมพ์: ตัดเลขนำหน้าเป็น 0 เช่น "03" → "3", "080" → "80"
  static String normalizeVehicleTripNumericText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final n = double.tryParse(t);
    if (n == null) return raw;
    return _strNum(n);
  }

  /// จำนวนเที่ยวช่วงเช้า/บ่าย — ว่างได้ (นับเป็น 0); ถ้ากรอกต้องเป็นตัวเลขไม่ติดลบ
  static double parseOptionalVehicleTripCount(
    String raw,
    String fieldLabelForError,
  ) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    final normalized = normalizeVehicleTripNumericText(s);
    final n = double.tryParse(normalized);
    if (n == null) {
      throw 'จำนวนเที่ยว$fieldLabelForErrorต้องเป็นตัวเลข';
    }
    if (n < 0) {
      throw 'จำนวนเที่ยว$fieldLabelForErrorต้องไม่ติดลบ';
    }
    return n;
  }

  String _stripRecorderSuffix(String raw) =>
      raw.replaceAll(RegExp(r'\s*\(ผู้กรอก:[^)]+\)\s*$'), '').trim();

  String _vehicleLabelFromId(String vehicleId) {
    final v = vehicleId.trim();
    if (v.isEmpty) return '-';
    return v;
  }

  bool _isMacroCarName(String raw) => isMacroVehicleId(raw);

  List<String> _fuelMacroCars() {
    final seen = <String>{};
    final out = <String>[];
    for (final car in _cars) {
      if (!_isMacroCarName(car)) continue;
      if (seen.add(car)) out.add(car);
    }
    return out;
  }

  /// รถดรัม/เที่ยว — เฉพาะหกล้อและสิบล้อ (จากรายการตั้งค่าแอพ)
  List<String> _vehicleTripCars({String includeVehicleId = ''}) {
    final seen = <String>{};
    final out = <String>[];
    final extra = includeVehicleId.trim();
    if (extra.isNotEmpty && seen.add(extra)) out.add(extra);
    for (final car in _cars) {
      if (!isSixOrTenWheelVehicleName(car)) continue;
      if (seen.add(car)) out.add(car);
    }
    return out;
  }

  Iterable<String> _employeePositionTokens(Employee e) sync* {
    if (e.positions.isNotEmpty) {
      for (final p in e.positions) {
        final t = p.trim();
        if (t.isNotEmpty) yield t;
      }
      return;
    }
    final single = (e.position ?? '').trim();
    if (single.isNotEmpty) yield single;
  }

  bool _isDriverEmployee(Employee e) {
    return _employeePositionTokens(e).contains('คนขับรถ');
  }

  /// คนขับในเมนูแม็คโคร — เฉพาะตำแหน่ง «คนขับรถแม็คโคร» (รองรับสะกด แมค/แม็ค)
  bool _isMacroExcavatorDriverEmployee(Employee e) {
    const titles = {'คนขับรถแม็คโคร', 'คนขับรถแมคโคร'};
    for (final p in _employeePositionTokens(e)) {
      if (titles.contains(p)) return true;
    }
    return false;
  }

  List<Employee> get _macroDriverEmployees => _employees
      .where((e) => !e.inactive)
      .where(_isMacroExcavatorDriverEmployee)
      .toList();

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

  /// ชื่อผู้ล้างจากบันทึกการทำงาน (canvas) — รองรับคีย์เว็บ wash1/wash2 และคีย์แอป wash_old/wash_new
  ({List<String> oldNames, List<String> newNames})
  _operatorNamesFromLatestLaborWash(Iterable<AppTransaction> dayRows) {
    bool laborAttendanceLike(AppTransaction t) {
      if (t.category != 'Labor') return false;
      if ((t.subCategory ?? '').trim() != 'Attendance') return false;
      final ls = (t.laborStatus ?? '').trim().toLowerCase();
      if (ls == 'ot' || ls == 'leave' || ls == 'sick' || ls == 'personal') {
        return false;
      }
      return true;
    }

    final candidates = dayRows
        .where(laborAttendanceLike)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return (oldNames: const [], newNames: const []);
    }
    candidates.sort((a, b) {
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    final latest = candidates.first;
    final wa = latest.workAssignments;
    if (wa == null || wa.isEmpty) {
      return (oldNames: const [], newNames: const []);
    }

    List<String> uniqDisplayNames(Iterable<String> ids) {
      final seen = <String>{};
      final out = <String>[];
      for (final id in ids) {
        final label = _employeeLabelFromIdOrName(id);
        if (label.isEmpty || seen.contains(label)) continue;
        seen.add(label);
        out.add(label);
      }
      return out;
    }

    final oldIds = <String>{
      ...(wa['wash1'] ?? const []),
      ...(wa['wash_old'] ?? const []),
    };
    final newIds = <String>{
      ...(wa['wash2'] ?? const []),
      ...(wa['wash_new'] ?? const []),
    };
    return (
      oldNames: uniqDisplayNames(oldIds),
      newNames: uniqDisplayNames(newIds),
    );
  }

  void _hydrateSandWashModule(
    List<AppTransaction> sandMatched,
    List<AppTransaction> allDay,
  ) {
    var inferredMaxDrums = 0.0;
    List<String> oldMachineNames = const [];
    List<String> newMachineNames = const [];
    for (final t in sandMatched) {
      final rowDrums = t.drumsObtained ?? 0;
      if (rowDrums > inferredMaxDrums) {
        inferredMaxDrums = rowDrums;
      }
      final mt = (t.sandMachineType ?? '').toLowerCase();
      final desc = t.description;
      final isOldMachine =
          mt == 'old' ||
          desc.contains('เครื่องร่อน (เก่า)') ||
          desc.contains('เครื่องร่อน 1');
      final isNewMachine =
          mt == 'new' ||
          desc.contains('เครื่องร่อน (ใหม่)') ||
          desc.contains('เครื่องร่อน 2');
      if (isOldMachine) {
        _sandRowIdsByKey.putIfAbsent('Old', () => t.id);
        _sand1MorningController.text = _strNum(t.sandMorning);
        _sand1AfternoonController.text = _strNum(t.sandAfternoon);
        final names = _operatorNamesFromTransaction(t);
        if (oldMachineNames.isEmpty && names.isNotEmpty) {
          oldMachineNames = names;
        }
      } else if (isNewMachine) {
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
      if (t.sandEveningEnd?.isNotEmpty == true) {
        _sandEveningEndController.text = t.sandEveningEnd!;
      }
    }
    if (_sandDrumsObtainedController.text.trim().isEmpty &&
        inferredMaxDrums > 0) {
      _sandDrumsObtainedController.text = _strNum(inferredMaxDrums);
    }

    final laborWash = _operatorNamesFromLatestLaborWash(allDay);
    if (laborWash.oldNames.isNotEmpty) {
      oldMachineNames = laborWash.oldNames;
    }
    if (laborWash.newNames.isNotEmpty) {
      newMachineNames = laborWash.newNames;
    }

    _sand1OperatorNames = oldMachineNames;
    _sand2OperatorNames = newMachineNames;
  }

  void _hydrateFormsFromTransactions(
    List<AppTransaction> txs, {
    List<AppTransaction>? dayTransactions,
  }) {
    if (_isIncomeUtilitiesEntryMode) return;
    if (_isSandWashMode) {
      _hydrateSandWashModule(txs, dayTransactions ?? txs);
      return;
    }
    if (txs.isEmpty) return;
    if (_isDailyEventMode) return;
    void setIfEmpty(TextEditingController c, String val) {
      if (val.isEmpty) return;
      if (c.text.trim().isEmpty) c.text = val;
    }

    if (_isHomeSandMode) {
      AppTransaction? washRow;
      AppTransaction? roundRow;
      for (final t in txs) {
        if (isHomeSandRoundCloseRow(t)) {
          roundRow = t;
        } else if (isDedicatedHomeSandWashRow(t)) {
          washRow = t;
        }
      }
      if (washRow != null) {
        _homeSandTxId = washRow.id;
        _drumsWashedAtHomeController.text = _strNum(washRow.drumsWashedAtHome);
      }
      if (roundRow != null) _homeSandRoundTxId = roundRow.id;
      return;
    }

    if (_isVehicleTripMode) {
      // ฟอร์มว่างสำหรับเพิ่ม/แก้ไขทีละคัน — รายการที่บันทึกแล้วแสดงด้านล่าง
      if (!_saving) _replaceVehicleDrafts([_VehicleTripDraft.empty()]);
      return;
    }

    if (_isMacroVehicleMode) {
      // ฟอร์มว่าง — เลือกรถทีละคัน ถ้าซ้ำในวันเดียวกันจะโหลดมาแก้ไข
      if (!_saving) _replaceMacroVehicleDrafts(const []);
      return;
    }

    if (_isFuelMode) {
      // ฟอร์มสำหรับบันทึกใหม่ — บันทึกทีละคัน/หลายคันต่อครั้งได้ รายการเดิมดูในเมนูประวัติ
      if (!_saving) _replaceFuelVehicleDrafts(const []);
      return;
    }

    if (_isLaborLeaveMode) {
      // ไม่เติมฟอร์มจากลาที่บันทึกแล้ว — เปิดหน้ามาเพื่อส่งรายการใหม่ (เหมือนเบิกเงิน)
      return;
    }

    if (_isLaborAdvanceMode) {
      // ไม่เติมฟอร์มจากคำขอเบิกที่บันทึกแล้ว — เปิดหน้ามาพร้อมส่งคำขอใหม่ทุกครั้ง
      // (_moduleDayTransactions ยังโหลดไว้สำหรับส่วนประวัติรายวัน ถ้ามี)
      return;
    }

    if (_isLaborMode) {
      final dayKey = _quickYmd(_selectedDate);
      final moduleCat = widget.initialCategory?.trim() ?? 'ค่าแรง';
      AppTransaction? laborRow;
      for (final x in txs) {
        if (x.category == 'Labor' &&
            transactionMatchesDailyModule(x, dayKey, moduleCat)) {
          laborRow = x;
          break;
        }
      }
      if (laborRow == null) {
        for (final x in txs) {
          if (x.category == 'ค่าแรง') {
            laborRow = x;
            break;
          }
        }
      }
      final t = laborRow ?? txs.first;
      _laborTxId = t.id;
      _selectedLaborEmpIds
        ..clear()
        ..addAll(t.employeeIds);
      _laborPickedIds.clear();
      _loadLaborAssignmentsFromTransaction(t);
      return;
    }

    if (_isOtMode) {
      // ไม่เติมฟอร์มจาก OT ที่บันทึกแล้ว — เปิดหน้ามาเพื่อบันทึกชุดใหม่ (เหมือนเบิกเงิน)
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
    for (final job in _generalSubJobs) {
      job.dispose();
    }
    _leaveReasonController.dispose();
    _leaveDaysController.dispose();
    _advanceAmountPerPersonController.dispose();
    _advanceAccountController.dispose();
    _utilitiesTypeController.dispose();
    _utilitiesExtraController.dispose();
    _utilitiesAmountController.dispose();
    _incomeTypeController.dispose();
    _incomeQtyController.dispose();
    _incomeUnitPriceController.dispose();
    _incomeTotalController.dispose();
    for (final g in _otGroups) {
      g.dispose();
    }
    _otDescController.dispose();
    _dailyEventDescController.dispose();
    _disposeVehicleDrafts();
    _disposeFuelVehicleDrafts();
    _disposeMacroVehicleDrafts();
    super.dispose();
  }

  void _scheduleUiRefresh({Duration delay = const Duration(milliseconds: 22)}) {
    _uiRebuildDebounce?.cancel();
    _uiRebuildDebounce = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
    });
  }

  bool get _showsEmployeeLoadingUi =>
      _isLaborMode ||
      _isOtMode ||
      _isLaborLeaveMode ||
      _isLaborAdvanceMode ||
      _isMacroVehicleMode;

  Future<void> _loadEmployees({bool forceRefresh = false}) async {
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
      final list = await widget.employeeService.fetchEmployees(
        forceRefresh: forceRefresh,
      );
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
        await Future<void>.delayed(const Duration(milliseconds: 40));
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
      if (_isSandWashMode &&
          (_moduleDayTransactions.isNotEmpty ||
              _moduleDayAllTransactions.isNotEmpty)) {
        setState(() {
          _hydrateFormsFromTransactions(
            _moduleDayTransactions,
            dayTransactions: _moduleDayAllTransactions,
          );
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

  Future<void> _loadAppExpenseIncomeTypes() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('app_settings')
          .select('expense_types, income_types')
          .eq('id', 'default')
          .limit(1);
      if (rows.isEmpty) return;
      final exp = rows.first['expense_types'];
      final inc = rows.first['income_types'];
      final expenseList = <String>[
        if (exp is List)
          ...exp
              .map((e) => '$e')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty),
      ];
      final incomeList = <String>[
        if (inc is List)
          ...inc
              .map((e) => '$e')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && s != 'ขายแร่'),
      ];
      if (!mounted) return;
      setState(() {
        _appExpenseTypes = expenseList;
        _appIncomeTypes = incomeList;
      });
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

  static const List<String> _kMacroWorkQuickPhrases = [
    'เปิดหน้าดิน',
    'ทอยดิน',
    'ขุดแร่',
    'ร่อนทราย',
    'ชัพพอต',
    'อื่นๆ',
  ];

  /// บันทึกรถดรัม — ช่วยกรอกรายละเอียดงาน (คำย่อยทั่วไข)
  static const List<String> _kVehicleDrumWorkQuickPhrases = [
    'ขนทรายล้าง',
    'ขนทรายถม',
  ];

  void _applyMacroWorkPhrase(_MacroVehicleDraft row, String phrase) {
    final cur = row.workDetailsController.text.trim();
    final next = cur.isEmpty ? phrase : '$cur, $phrase';
    setState(() {
      row.workDetailsController.text = next;
      row.workDetailsController.selection = TextSelection.collapsed(
        offset: row.workDetailsController.text.length,
      );
    });
  }

  /// รถดรัม/เที่ยว — ต่อท้ายรายละเอียดงาน (ไม่ซ้ำคำเดิม)
  static void _applyVehicleDrumWorkPhrase(_VehicleTripDraft row, String phrase) {
    final cur = row.workDetailsController.text.trim();
    if (cur.contains(phrase)) return;
    final next = cur.isEmpty ? phrase : '$cur, $phrase';
    row.workDetails = next;
    row.workDetailsController.text = next;
    row.workDetailsController.selection = TextSelection.collapsed(
      offset: row.workDetailsController.text.length,
    );
  }

  Future<void> _refreshHomeSandStock() async {
    try {
      final rows = await widget.service.fetchTransactions();
      final byDay = <String, List<AppTransaction>>{};
      for (final t in rows) {
        if (t.category != 'DailyLog' || t.subCategory != 'Sand') continue;
        final day = _normalizeSandDayKey(t.date);
        byDay.putIfAbsent(day, () => []).add(t);
      }
      final map = <String, _HomeSandDaily>{};
      for (final e in byDay.entries) {
        final txs = e.value;
        final rec = _HomeSandDaily();
        for (final t in txs) {
          final o = (t.drumsObtained ?? 0).toDouble();
          if (o > rec.obtained) rec.obtained = o;
        }
        rec.home = persistedSandHomeDrumsForDay(txs);
        map[e.key] = rec;
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
        _homeSandTodayHomeSaved = today.home;
        _homeSandAvailable = available;
        if (_drumsWashedAtHomeController.text.trim().isEmpty &&
            today.home > 0) {
          _drumsWashedAtHomeController.text = _strNum(today.home);
        }
      });
    } catch (_) {}
  }

  static const Duration _successPopupHold = Duration(milliseconds: 1400);

  SaveErrorContext? _activeSaveErrorContext;

  String get _saveErrorPageTitle {
    final custom = widget.appBarTitle?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final cat = widget.initialCategory?.trim();
    if (cat != null && cat.isNotEmpty) return cat;
    return 'บันทึกข้อมูล';
  }

  Never _failSave(String message, {String? field}) {
    final ctx = _activeSaveErrorContext;
    if (ctx == null) throw message;
    return failSave(message, context: ctx, field: field);
  }

  Future<String?> _submitSaveErrorReport(
    Object error,
    SaveErrorContext? ctx,
  ) async {
    final reporter = await SessionService().getSavedAdmin();
    return MobileErrorReportService(Supabase.instance.client).submit(
      error: error,
      source: 'save_failed',
      saveContext: ctx,
      reporter: reporter,
    );
  }

  void _showSaveError(Object error, {SaveErrorContext? context}) {
    if (!mounted) return;
    final ctx = context ?? _activeSaveErrorContext;
    showSaveErrorSnackBar(
      this.context,
      error: error,
      saveContext: ctx,
      onSendReport: () => _submitSaveErrorReport(error, ctx),
    );
  }

  void _showSuperAdminHistorySaveError(
    BuildContext sheetContext, {
    required Object error,
    required String page,
    required String action,
    String button = 'บันทึก',
  }) {
    if (!sheetContext.mounted) return;
    final saveCtx = SaveErrorContext(
      page: page,
      action: action,
      button: button,
    );
    showSaveErrorSnackBar(
      sheetContext,
      error: error,
      saveContext: saveCtx,
      onSendReport: () => _submitSaveErrorReport(error, saveCtx),
    );
  }

  void _releaseKeyboardFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _showSavingPopup() {
    _releaseKeyboardFocus();
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
    _releaseKeyboardFocus();
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _showSuccessPopupAndPopToHome(String message) async {
    if (!mounted) return;
    _releaseKeyboardFocus();
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
    required String saveActionLabel,
    required String saveButtonLabel,
    bool requireSignature = true,
    bool stayOnPage = false,
    /// ล้างฟอร์มหลังบันทึกสำเร็จ — ต้องเรียกผ่าน [setState] หลัง [body] เท่านั้น (ห้าม dispose ใน [body])
    VoidCallback? onStayOnPageCleared,
  }) async {
    if (!mounted) return;
    final saveCtx = SaveErrorContext(
      page: _saveErrorPageTitle,
      action: saveActionLabel,
      button: saveButtonLabel,
    );
    _releaseKeyboardFocus();
    setState(() => _saving = true);
    var savingDialogOpen = false;
    _activeSaveErrorContext = saveCtx;
    try {
      if (requireSignature) {
        final signature = await _requestSignatureBeforeSave();
        if (signature == null) return;
        _activeSignatureNote = signature.note;
      } else {
        _activeSignatureNote = null;
      }
      if (!mounted) return;
      _releaseKeyboardFocus();
      _showSavingPopup();
      savingDialogOpen = true;
      await body();
      if (!mounted) return;
      _dismissSavingPopup();
      savingDialogOpen = false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (stayOnPage) {
        _releaseKeyboardFocus();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (onStayOnPageCleared != null) {
          setState(onStayOnPageCleared);
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(successMessage, style: GoogleFonts.kanit())),
        );
        await _loadModuleTransactions(preserveIncomeUtilitiesForm: true);
      } else {
        _releaseKeyboardFocus();
        await _showSuccessPopupAndPopToHome(successMessage);
      }
    } catch (error) {
      if (savingDialogOpen && mounted) {
        _dismissSavingPopup();
        savingDialogOpen = false;
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) _showSaveError(error, context: saveCtx);
    } finally {
      _activeSaveErrorContext = null;
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
    if (_isMacroVehicleMode) {
      await _saveMacroVehicleUsageEntries();
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
    if (_isLaborLeaveMode) {
      await _saveLaborLeaveEntry();
      return;
    }
    if (_isLaborAdvanceMode) {
      await _saveLaborAdvanceEntry();
      return;
    }
    if (_isOtMode) {
      await _saveOtEntry();
      return;
    }
    if (_isDailyEventMode) {
      await _saveDailyEventEntry();
      return;
    }
    if (_isIncomeUtilitiesEntryMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ใช้ปุ่มบันทึกในฟอร์มรายจ่ายหรือรายรับด้านล่าง',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    await _runSaveWithPopups(
      successMessage: 'บันทึกข้อมูลสำเร็จ',
      saveActionLabel: 'บันทึกรายการทั่วไป',
      saveButtonLabel: 'บันทึก',
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
      saveActionLabel: 'บันทึกการร่อนทราย / ล้างทราย',
      saveButtonLabel: 'บันทึก',
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
          _failSave('กรุณากรอกอย่างน้อยจำนวนคิวทรายหรือจำนวนถัง');
        }

        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        // Keep category aligned with web Daily Wizard schema.
        final commonCategory = 'DailyLog';
        final commonSub = 'Sand';
        final workStart = _sandMorningStartController.text.trim();
        final workEnd = _sandEveningEndController.text.trim();

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
            sandMorningStart: workStart.isEmpty ? null : workStart,
            sandEveningEnd: workEnd.isEmpty ? null : workEnd,
          );
          await _persist(tx);
        }

        await saveMachine(
          suffix: 's1',
          machineType: 'Old',
          description: 'ล้างทราย เครื่องร่อน (เก่า)',
          morning: s1m,
          afternoon: s1a,
        );
        await saveMachine(
          suffix: 's2',
          machineType: 'New',
          description: 'ล้างทราย เครื่องร่อน (ใหม่)',
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
              sandMorningStart: workStart.isEmpty ? null : workStart,
              sandEveningEnd: workEnd.isEmpty ? null : workEnd,
            ),
          );
        }

        _sand1MorningController.clear();
        _sand1AfternoonController.clear();
        _sand2MorningController.clear();
        _sand2AfternoonController.clear();
        _sandDrumsObtainedController.clear();
        _sandMorningStartController.clear();
        _sandEveningEndController.clear();
      },
    );
  }

  double _homeSandMaxWashableToday() => _homeSandAvailable;

  Future<void> _persistHomeSandWashRow(double drumsHome) async {
    final maxWashable = _homeSandMaxWashableToday();
    if (drumsHome < 0) {
            _failSave('จำนวนถังที่ล้างที่บ้านต้องไม่ติดลบ');
    }
    if (drumsHome > maxWashable) {
            _failSave('จำนวนถังที่ล้างเกินจำนวนคงเหลือ (${maxWashable.toStringAsFixed(0)} ถัง)');
    }
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    final homeId =
        _homeSandTxId ?? '${DateTime.now().millisecondsSinceEpoch}_home_sand';
    _homeSandTxId = homeId;
    await _persist(
      AppTransaction(
        id: homeId,
        date: '$y-$m-$d',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: _appendRecorder('ทรายที่ล้างที่บ้าน'),
        amount: 0,
        drumsObtained: 0,
        drumsWashedAtHome: drumsHome,
        note: _activeSignatureNote,
      ),
    );
    await _refreshHomeSandStock();
  }

  Future<void> _saveHomeSandEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกทรายที่ล้างที่บ้านสำเร็จ',
      saveActionLabel: 'บันทึกทรายที่ล้างที่บ้าน',
      saveButtonLabel: 'บันทึก',
      body: () async {
        final rawHome = _drumsWashedAtHomeController.text.trim();
        if (rawHome.isEmpty) {
          _failSave('กรุณาระบุจำนวนถังที่ล้างที่บ้านวันนี้ (กรอก 0 ได้หากไม่ล้าง)');
        }
        final drumsHome = double.tryParse(rawHome) ?? 0;
        await _persistHomeSandWashRow(drumsHome);
        _drumsWashedAtHomeController.clear();
      },
    );
  }

  Future<bool> _confirmHomeSandDialog({
    required String title,
    required String message,
    String confirmLabel = 'ยืนยัน',
  }) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        content: Text(message, style: GoogleFonts.kanit()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ยกเลิก', style: GoogleFonts.kanit()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel, style: GoogleFonts.kanit()),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _persistHomeSandRoundCloseRow() async {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    final roundId =
        _homeSandRoundTxId ??
        '${DateTime.now().millisecondsSinceEpoch}_home_sand_round';
    _homeSandRoundTxId = roundId;
    await _persist(
      AppTransaction(
        id: roundId,
        date: '$y-$m-$d',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: _appendRecorder('ตัดรอบล้างทรายที่บ้าน'),
        amount: 0,
        drumsObtained: 0,
        drumsWashedAtHome: 0,
        note: _activeSignatureNote,
      ),
    );
  }

  Future<void> _saveHomeSandWashAllAndRoundCloseEntry() async {
    final qty = _homeSandMaxWashableToday();
    final message = qty > 0
        ? 'บันทึกล้างทรายที่บ้านทั้งหมด ${qty.toStringAsFixed(0)} ถัง แล้วตัดรอบล้างทรายที่บ้าน ใช่หรือไม่?'
        : 'ไม่มีทรายคงเหลือให้ล้าง — ตัดรอบล้างทรายที่บ้านสำหรับวันนี้ใช่หรือไม่?';
    final ok = await _confirmHomeSandDialog(
      title: 'ล้างทั้งหมดแล้ว ตัดรอบ',
      message: message,
      confirmLabel: 'ล้างทั้งหมดแล้ว ตัดรอบ',
    );
    if (!ok) return;
    await _runSaveWithPopups(
      successMessage: 'ล้างทรายที่บ้านทั้งหมดและตัดรอบสำเร็จ',
      saveActionLabel: 'ล้างทรายที่บ้านทั้งหมดและตัดรอบ',
      saveButtonLabel: 'ล้างทั้งหมดแล้ว ตัดรอบ',
      stayOnPage: true,
      body: () async {
        await _persistHomeSandWashRow(qty);
        await _persistHomeSandRoundCloseRow();
        if (mounted) {
          _drumsWashedAtHomeController.text = _strNum(qty);
        }
      },
    );
  }

  Future<void> _saveVehicleTripEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกรถดรัมและจำนวนเที่ยวสำเร็จ',
      saveActionLabel: 'บันทึกรถดรัมและจำนวนเที่ยว',
      saveButtonLabel: 'บันทึกรถคันนี้',
      stayOnPage: true,
      onStayOnPageCleared: () => _replaceVehicleDrafts([_VehicleTripDraft.empty()]),
      body: () async {
        final activeRows = _vehicleTripDrafts.where((row) {
          final lumpFilled =
              row.tripBillingMode == 'LumpSum' &&
              row.lumpSumTotalCubic.trim().isNotEmpty;
          return row.vehicleId.trim().isNotEmpty ||
              row.driverId.trim().isNotEmpty ||
              row.workDetails.trim().isNotEmpty ||
              row.hourlyHours.trim().isNotEmpty ||
              row.tripMorning.trim().isNotEmpty ||
              row.tripAfternoon.trim().isNotEmpty ||
              row.cubicPerTrip.trim().isNotEmpty ||
              lumpFilled;
        }).toList();
        if (activeRows.isEmpty) {
          _failSave('กรุณาระบุข้อมูลรถอย่างน้อย 1 คัน');
        }

        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';

        for (final row in activeRows) {
          if (row.vehicleId.trim().isEmpty || row.driverId.trim().isEmpty) {
            _failSave('กรุณาระบุรถและคนขับให้ครบทุกคัน');
          }
        }

        final seenVehicle = <String>{};
        for (final row in activeRows) {
          final vehicle = row.vehicleId.trim();
          if (!seenVehicle.add(vehicle)) {
            _failSave('พบรถ "$vehicle" ซ้ำในฟอร์ม — แก้ไขที่แถวเดิมแทน');
          }
        }

        final serverDayRows = await widget.service.fetchTransactionsForDate(
          date,
          forceRefresh: true,
        );
        for (final row in activeRows) {
          final vehicle = row.vehicleId.trim();
          final selfId = row.tripTxId?.trim();
          for (final t in serverDayRows) {
            if (!_isVehicleTripHydrateSource(t)) continue;
            if (selfId != null && selfId.isNotEmpty && t.id == selfId) {
              continue;
            }
            if ((t.vehicleId ?? '').trim() == vehicle) {
              _failSave('มีบันทึกรถ "$vehicle" ในวันนี้แล้ว — เลือกรถคันนี้จากรายการอีกครั้งเพื่อโหลดมาแก้ไข');
            }
          }
        }

        for (var i = 0; i < activeRows.length; i++) {
          final row = activeRows[i];
          final vehicle = row.vehicleId.trim();
          final driver = row.driverId.trim();
          final details = row.workDetails.trim();
          final hourlyHours = double.tryParse(row.hourlyHours.trim()) ?? 0;
          final tripMorning = parseOptionalVehicleTripCount(
            row.tripMorning,
            'ช่วงเช้า ',
          );
          final tripAfternoon = parseOptionalVehicleTripCount(
            row.tripAfternoon,
            'ช่วงบ่าย ',
          );
          final totalTrips = tripMorning + tripAfternoon;
          final cubicPerTrip = double.tryParse(row.cubicPerTrip.trim()) ?? 0;
          if (row.workType == 'Hourly' && hourlyHours <= 0) {
            _failSave('กรุณาระบุชั่วโมงทำงานสำหรับรายการรายชั่วโมง');
          }
          final detailsWithHours = row.workType == 'Hourly'
              ? (details.isEmpty
                    ? 'งานรายชั่วโมง ${_strNum(hourlyHours)} ชม.'
                    : '$details (${_strNum(hourlyHours)} ชม.)')
              : details;

          final tripId =
              row.tripTxId ??
              '${DateTime.now().millisecondsSinceEpoch}_trip_$i';
          row.tripTxId = tripId;

          if (row.tripBillingMode == 'LumpSum') {
            final lumpCubic =
                double.tryParse(row.lumpSumTotalCubic.trim()) ?? 0;
            if (lumpCubic <= 0) {
              _failSave('กรุณาระบุรวมคิว (เหมา) ให้มากกว่า 0 สำหรับรถที่เลือกเหมา');
            }
            await _persist(
              AppTransaction(
                id: tripId,
                date: date,
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'VehicleTrip',
                description: _appendRecorder(
                  '$vehicle: เหมา ${lumpCubic.toStringAsFixed(0)} คิว • เช้า ${_strNum(tripMorning)} เที่ยว บ่าย ${_strNum(tripAfternoon)} เที่ยว',
                ),
                amount: 0,
                note: _activeSignatureNote,
                vehicleId: vehicle,
                driverId: driver,
                tripBillingMode: 'LumpSum',
                tripCount: totalTrips,
                tripMorning: tripMorning,
                tripAfternoon: tripAfternoon,
                cubicPerTrip: 0,
                totalCubic: lumpCubic,
                perCarTrips: totalTrips,
                perCarCubic: lumpCubic,
                workDetails: _appendRecorder(detailsWithHours),
                workType: row.workType == 'HalfDay' || row.workType == 'Hourly'
                    ? row.workType
                    : 'FullDay',
              ),
            );
            continue;
          }

          if (totalTrips <= 0) {
            _failSave('กรุณาระบุจำนวนเที่ยวรวม (เช้า+บ่าย) ให้มากกว่า 0 สำหรับรถที่คิดเป็นเที่ยว');
          }
          if (cubicPerTrip <= 0) {
            _failSave('กรุณาระบุคิวต่อเที่ยวให้มากกว่า 0 สำหรับรถที่คิดเป็นเที่ยว');
          }
          final totalCubic = totalTrips * cubicPerTrip;
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
              tripBillingMode: 'PerTrip',
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
      },
    );
  }

  AppTransaction? _findLatestVehicleTripForDay(String vehicleId) {
    final vehicle = vehicleId.trim();
    if (vehicle.isEmpty) return null;
    final ymd = _quickYmd(_selectedDate);
    final seenIds = <String>{};
    final pool = <AppTransaction>[];
    for (final t in [
      ..._moduleDayAllTransactions,
      ..._moduleDayTransactions,
    ]) {
      if (seenIds.add(t.id)) pool.add(t);
    }
    AppTransaction? best;
    for (final t in pool) {
      if (!_isVehicleTripHydrateSource(t)) continue;
      if (t.date.trim() != ymd) continue;
      if ((t.vehicleId ?? '').trim() != vehicle) continue;
      if (best == null) {
        best = t;
        continue;
      }
      final tb = t.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tab = best.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (tb.isAfter(tab)) best = t;
    }
    return best;
  }

  void _mergeVehicleTripDraftFrom(
    _VehicleTripDraft target,
    _VehicleTripDraft source,
  ) {
    target.tripTxId = source.tripTxId;
    target.vehicleId = source.vehicleId;
    target.driverId = source.driverId;
    target.workType = source.workType;
    target.tripBillingMode = source.tripBillingMode;
    target.hourlyHours = source.hourlyHours;
    target.workDetails = source.workDetails;
    target.tripMorning = source.tripMorning;
    target.tripAfternoon = source.tripAfternoon;
    target.cubicPerTrip = source.cubicPerTrip;
    target.lumpSumTotalCubic = source.lumpSumTotalCubic;
    target.workDetailsController.text = source.workDetails;
    target.hourlyHoursController.text = source.hourlyHours;
    target.tripMorningController.text = source.tripMorning;
    target.tripAfternoonController.text = source.tripAfternoon;
    target.cubicPerTripController.text = source.cubicPerTrip;
    target.lumpSumTotalCubicController.text = source.lumpSumTotalCubic;
  }

  void _hydrateVehicleRowFromExistingIfDuplicate(
    _VehicleTripDraft row,
    String vehicleId,
  ) {
    final vehicle = vehicleId.trim();
    row.vehicleId = vehicle;
    if (vehicle.isEmpty) {
      row.tripTxId = null;
      return;
    }
    _applyDefaultCubicForVehicleRow(row, vehicle);
    final existing = _findLatestVehicleTripForDay(vehicle);
    if (existing == null) {
      row.tripTxId = null;
      return;
    }
    final loaded = _vehicleTripDraftFromAppTransaction(existing);
    _mergeVehicleTripDraftFrom(row, loaded);
    loaded.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'โหลดข้อมูลรถ "$vehicle" ที่บันทึกแล้วมาแก้ไข',
          style: GoogleFonts.kanit(),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    _scheduleUiRefresh();
  }

  void _loadVehicleTripIntoForm(AppTransaction t) {
    if (_vehicleTripDrafts.isEmpty) {
      _vehicleTripDrafts.add(_VehicleTripDraft.empty());
    }
    final loaded = _vehicleTripDraftFromAppTransaction(t);
    _mergeVehicleTripDraftFrom(_vehicleTripDrafts.first, loaded);
    loaded.dispose();
    _scheduleUiRefresh();
  }

  Future<void> _saveMacroVehicleUsageEntries() async {
    final row = _activeMacroVehicleDraft;
    // เก็บค่าก่อน async — _loadModuleTransactions อาจ dispose controller ระหว่างบันทึก
    final vehicle = row.vehicleId.trim();
    final driver = row.driverId.trim();
    final details = row.workDetailsController.text.trim();
    final workType = row.workType;
    final existingTxId = row.txId?.trim();
    final isUpdate = existingTxId != null && existingTxId.isNotEmpty;
    await _runSaveWithPopups(
      successMessage: isUpdate
          ? 'อัปเดตรถคันนี้สำเร็จ — เลือกรถคันถัดไปได้'
          : 'บันทึกคันนี้สำเร็จ — เลือกรถคันถัดไปได้',
      saveActionLabel: 'บันทึกการใช้รถแม็คโคร',
      saveButtonLabel: 'บันทึกคันนี้ / อัปเดตคันนี้',
      stayOnPage: true,
      onStayOnPageCleared: _resetActiveMacroVehicleDraft,
      body: () async {
        final macroCars = _fuelMacroCars();
        if (macroCars.isEmpty) {
          _failSave('ยังไม่พบรถแม็คโครในตั้งค่าแอพ');
        }
        if (vehicle.isEmpty || driver.isEmpty) {
          _failSave('กรุณาเลือกรถแม็คโครและคนขับ');
        }
        if (!_macroDriverEmployees.any((e) => e.id == driver)) {
          _failSave('เลือกคนขับจากรายชื่อตำแหน่ง «คนขับรถแม็คโคร» เท่านั้น');
        }
        if (!macroCars.contains(vehicle)) {
          _failSave('เลือกรถได้เฉพาะรถแม็คโคร');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final dayLabel = workType == 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
        final txId =
            existingTxId ??
            '${DateTime.now().millisecondsSinceEpoch}_macro_vehicle';
        await _persist(
          AppTransaction(
            id: txId,
            date: date,
            type: 'Expense',
            category: 'Vehicle',
            description: _appendRecorder(
              'รถ: $vehicle (${details.isEmpty ? '—' : details}) [$dayLabel]',
            ),
            amount: 0,
            note: _activeSignatureNote,
            vehicleId: vehicle,
            driverId: driver,
            workDetails: details.isEmpty ? null : _appendRecorder(details),
            workType: workType == 'HalfDay' ? 'HalfDay' : 'FullDay',
          ),
        );
      },
    );
  }

  Future<void> _saveFuelVehicleUsageEntries() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกการใช้น้ำมันรายรถสำเร็จ',
      saveActionLabel: 'บันทึกการใช้น้ำมันรายรถ',
      saveButtonLabel: 'บันทึก',
      stayOnPage: true,
      onStayOnPageCleared: () => _replaceFuelVehicleDrafts(const []),
      body: () async {
        final fuelCars = _fuelMacroCars();
        if (fuelCars.isEmpty) {
          _failSave('ยังไม่พบรถแม็คโครในตั้งค่าแอพ');
        }
        final activeRows = _fuelVehicleDrafts.where((row) {
          return row.vehicleId.trim().isNotEmpty ||
              row.liters.trim().isNotEmpty ||
              row.time.trim().isNotEmpty;
        }).toList();
        if (activeRows.isEmpty) {
          _failSave('กรุณาระบุข้อมูลการใช้น้ำมันอย่างน้อย 1 คัน');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';

        for (var i = 0; i < activeRows.length; i++) {
          final row = activeRows[i];
          final vehicle = row.vehicleId.trim();
          final liters = double.tryParse(row.liters.trim()) ?? 0;
          if (vehicle.isEmpty) {
            _failSave('กรุณาเลือกรถให้ครบทุกคัน', field: 'เลือกรถ');
          }
          if (!fuelCars.contains(vehicle)) {
            _failSave('เลือกรถได้เฉพาะรถแม็คโคร');
          }
          if (liters <= 0) {
            _failSave('กรุณาระบุปริมาณน้ำมันให้มากกว่า 0', field: 'ปริมาณน้ำมัน (ลิตร)');
          }
          if (row.time.trim().isEmpty) {
            _failSave('กรุณาระบุเวลาเติมน้ำมัน (คัน ${i + 1})');
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
      },
    );
  }

  Future<void> _saveLaborEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกค่าแรงสำเร็จ',
      saveActionLabel: 'บันทึกการทำงาน / ค่าแรง',
      saveButtonLabel: 'บันทึก',
      body: () async {
        final assignedIds = _collectLaborAssignedIds();
        if (assignedIds.isEmpty) {
          _failSave('กรุณาเลือกพนักงานลงกล่องงาน', field: 'กล่องงาน canvas');
        }
        for (final job in _generalSubJobs) {
          final key = _generalSubJobAssignmentKey(job.id);
          final count = _laborAssignments[key]?.length ?? 0;
          if (count > 0 && job.nameController.text.trim().isEmpty) {
            _failSave('กรุณาระบุรายละเอียดงานสำหรับกล่องย่อยในงานทั่วไปที่มีพนักงาน');
          }
        }
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
        final generalWorkDetails = _generalSubJobs
            .where((job) {
              final key = _generalSubJobAssignmentKey(job.id);
              return (_laborAssignments[key]?.isNotEmpty ?? false) &&
                  job.nameController.text.trim().isNotEmpty;
            })
            .map((job) => job.nameController.text.trim())
            .join(', ');
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
            workDetails:
                generalWorkDetails.isEmpty ? null : generalWorkDetails,
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
        _resetGeneralSubJobsAfterSave();
        _laborWorkDetailsController.clear();
      },
    );
  }

  Future<void> _saveLaborLeaveEntry() async {
    // เก็บค่าก่อน async — โหลดรายการวันอาจล้าง controller ระหว่างลายเซ็น/บันทึก
    final leaveEmpIds = _selectedLeaveEmpIds.toList();
    final reason = _leaveReasonController.text.trim();
    final leaveDaysText = _leaveDaysController.text.trim();
    final leaveIsHalfDay = _leaveIsHalfDay;
    final leaveHalfPart = _leaveHalfPart;
    final leaveTypeChoice = _leaveTypeChoice;
    final leaveStartDate = _leaveStartDate;
    final existingLeaveTxId = _laborLeaveTxId;
    await _runSaveWithPopups(
      successMessage: 'บันทึกลางานสำเร็จ',
      saveActionLabel: 'บันทึกลางาน',
      saveButtonLabel: 'บันทึก',
      body: () async {
        if (leaveEmpIds.isEmpty) {
          _failSave('กรุณาเลือกพนักงาน');
        }
        final blockedLeave = leaveEmpIds.where((id) {
          final e = _employeesById[id];
          return e != null && isExcludedFromLeaveEmployeePicker(e);
        }).toList();
        if (blockedLeave.isNotEmpty) {
          _failSave('ไม่สามารถบันทึกลาให้คนขับรถหรือรับจ้างรายวันได้');
        }
        if (reason.isEmpty) {
          _failSave('กรุณากรอกเหตุผลการลา', field: 'เหตุผลการลา');
        }
        final days = double.tryParse(leaveDaysText) ?? 0;
        if (leaveIsHalfDay) {
          if (leaveHalfPart != 'morning' && leaveHalfPart != 'afternoon') {
            _failSave('กรุณาเลือกลาครึ่งเช้าหรือครึ่งบ่าย');
          }
        } else if (days <= 0) {
          _failSave('กรุณากรอกจำนวนวันให้มากกว่า 0');
        }
        final effectiveDays = leaveIsHalfDay ? 0.5 : days;
        final halfTh = leaveIsHalfDay
            ? (leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย')
            : '';
        final halfMeta = leaveIsHalfDay
            ? (leaveHalfPart == 'morning'
                  ? _leaveHalfMorningMeta
                  : _leaveHalfAfternoonMeta)
            : null;
        final y = leaveStartDate.year.toString().padLeft(4, '0');
        final m = leaveStartDate.month.toString().padLeft(2, '0');
        final d = leaveStartDate.day.toString().padLeft(2, '0');
        final ymd = '$y-$m-$d';
        final id =
            existingLeaveTxId ?? '${DateTime.now().millisecondsSinceEpoch}_leave';
        _laborLeaveTxId = id;
        final typeTh = leaveTypeChoice == 'Sick' ? 'ป่วย' : 'กิจ';
        final descCore = 'ลา$typeTh: $reason';
        final desc = leaveIsHalfDay
            ? '$descCore (ครึ่งวัน — $halfTh)'
            : descCore;
        final saved = AppTransaction(
          id: id,
          date: ymd,
          type: 'Leave',
          category: 'Leave',
          subCategory: leaveTypeChoice,
          laborStatus: 'Leave',
          employeeIds: leaveEmpIds,
          amount: 0,
          note: _activeSignatureNote,
          description: _appendRecorder(desc),
          leaveReason: reason,
          leaveDays: effectiveDays,
          workDetails: halfMeta,
        );
        await _persist(saved);
        unawaited(notifyLeaveLineAfterSaved(saved, _employees));
      },
    );
  }

  Future<void> _saveLaborAdvanceEntry() async {
    await _runSaveWithPopups(
      successMessage: 'ส่งคำขอเบิกเงินแล้ว',
      saveActionLabel: 'คำขอเบิกเงิน',
      saveButtonLabel: 'ส่งคำขอเบิกเงิน',
      body: () async {
        if (_selectedAdvanceEmpIds.isEmpty) {
          _failSave('กรุณาเลือกพนักงาน');
        }
        final blocked = _selectedAdvanceEmpIds.where((id) {
          final e = _employeesById[id];
          return e != null && isExcludedFromAdvanceEmployeePicker(e);
        }).toList();
        if (blocked.isNotEmpty) {
          _failSave('ไม่สามารถเบิกให้คนขับรถหรือรับจ้างรายวันได้');
        }
        final per =
            double.tryParse(_advanceAmountPerPersonController.text.trim()) ?? 0;
        if (per <= 0) {
          _failSave('กรุณากรอกจำนวนเงินที่ขอเบิกต่อคนให้มากกว่า 0');
        }
        if (_advancePaymentMethod == AdvanceGmMeta.transfer) {
          final bank = _advanceBank.trim();
          final acct = _advanceAccountController.text.trim();
          if (bank.isEmpty) {
            _failSave('กรุณาเลือกธนาคาร', field: 'ธนาคาร');
          }
          if (acct.isEmpty) {
            _failSave('กรุณากรอกเลขบัญชี', field: 'เลขบัญชี');
          }
        }
        final meta = AdvanceGmMeta(
          payoutSlot: _advancePayoutSlot,
          paymentMethod: _advancePaymentMethod,
          bank: _advanceBank.trim(),
          accountNumber: _advanceAccountController.text.trim(),
        );
        final slotTh = _advancePayoutSlot == AdvanceGmMeta.evening
            ? 'ช่วงเย็น'
            : 'ช่วงกลางวัน';
        final payTh = _advancePaymentMethod == AdvanceGmMeta.transfer
            ? 'เงินโอน'
            : 'เงินสด';
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final ymd = '$y-$m-$d';
        final empIds = _selectedAdvanceEmpIds.toList();
        final ts = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < empIds.length; i++) {
          final empId = empIds[i];
          final emp = _employeesById[empId];
          final name = emp != null ? _employeeUiDisplayName(emp) : empId;
          final workDetails = AdvanceGmMeta.encodeIntoWorkDetails(
            existingWorkDetails: i == 0 ? _advanceWorkDetailsSeed : null,
            meta: meta,
          );
          final id = '${ts}_adv_${i}_$empId';
          final saved = AppTransaction(
            id: id,
            date: ymd,
            type: 'Expense',
            category: 'Labor',
            subCategory: 'Advance',
            laborStatus: 'Advance',
            employeeIds: [empId],
            amount: per,
            advanceAmount: per,
            workDetails: workDetails,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'คำขอเบิกเงิน · $name · $slotTh · $payTh',
            ),
          );
          await _persist(saved);
          _advanceWorkDetailsSeed = workDetails;
          unawaited(notifyAdvanceLineAfterSaved(saved, _employees));
        }
      },
    );
  }

  Future<void> _saveOtEntry() async {
    final g = _activeOtGroup;
    final hours = double.tryParse(g.hoursController.text.trim()) ?? 0;
    final otEmpIds = g.employeeIds.toList();
    final otDesc = _otDescController.text.trim();
    final otPersistedId = g.persistedId;
    await _runSaveWithPopups(
      successMessage: 'บันทึกกลุ่ม OT สำเร็จ — กรอกกลุ่มถัดไปได้',
      saveActionLabel: 'บันทึกการทำงานล่วงเวลา (OT)',
      saveButtonLabel: 'บันทึกกลุ่มนี้',
      requireSignature: false,
      stayOnPage: true,
      onStayOnPageCleared: _resetActiveOtGroup,
      body: () async {
        if (otEmpIds.isEmpty) {
          _failSave('กรุณาเลือกพนักงาน');
        }
        final blockedOt = otEmpIds.where((id) {
          final e = _employeesById[id];
          return e != null && isExcludedFromOtEmployeePicker(e);
        }).toList();
        if (blockedOt.isNotEmpty) {
          _failSave(
            'ไม่สามารถบันทึก OT ให้คนขับรถ เฝ้ากลางคืน หรือรับจ้างรายวัน',
          );
        }
        if (hours <= 0) {
          _failSave('กรุณาระบุชั่วโมง OT');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final groupNum = _otSavedGroupCountToday + 1;
        final baseTs = DateTime.now().millisecondsSinceEpoch;
        final id = otPersistedId ?? '${baseTs}_ot_$groupNum';
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Expense',
            category: 'Labor',
            subCategory: 'OT',
            laborStatus: 'OT',
            employeeIds: otEmpIds,
            amount: 0,
            note: _activeSignatureNote,
            otAmount: 0,
            otHours: hours,
            otDescription: otDesc,
            description: _appendRecorder(
              'OT $otDesc (${hours.toStringAsFixed(1)}ชม.) กลุ่มที่ $groupNum (${otEmpIds.length} คน)',
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveDailyEventEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกเหตุการณ์สำเร็จ',
      saveActionLabel: 'บันทึกเหตุการณ์ประจำวัน',
      saveButtonLabel: 'บันทึก',
      stayOnPage: true,
      onStayOnPageCleared: () {
        _dailyEventDescController.clear();
        _dailyEventType = 'info';
        _dailyEventPriority = 'normal';
      },
      body: () async {
        final text = _dailyEventDescController.text.trim();
        if (text.isEmpty) {
          _failSave('กรุณาระบุรายละเอียดเหตุการณ์');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final id = '${DateTime.now().millisecondsSinceEpoch}_event';
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'Event',
            description: _appendRecorder(text),
            amount: 0,
            note: _activeSignatureNote,
            eventType: _dailyEventType.trim().isEmpty
                ? 'info'
                : _dailyEventType,
            eventPriority: _dailyEventPriority.trim().isEmpty
                ? 'normal'
                : _dailyEventPriority,
          ),
        );
      },
    );
  }

  Future<void> _pickLeaveStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaveStartDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _leaveStartDate = DateTime(picked.year, picked.month, picked.day),
      );
    }
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
      await _loadModuleTransactions(
        forceRefresh: _isVehicleTripMode || _isMacroVehicleMode,
      );
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
      return ['ค่าแรงประจำวัน', 'ค่าแรงเสริม', 'คำขอเบิกเงิน'];
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

  Widget _moduleBootstrapOverlay(double keyboardInset, bool reduceMotion) {
    final showEmployeesLine = _showsEmployeeLoadingUi && _employeesLoading;
    final showTxnLine = _moduleDayLoading;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_blockingModuleBootstrap,
        child: AnimatedOpacity(
          duration: Duration(milliseconds: reduceMotion ? 1 : 220),
          curve: Curves.easeOutCubic,
          opacity: _blockingModuleBootstrap ? 1 : 0,
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 16 + keyboardInset),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: reduceMotion
                  ? Container(
                      color: Colors.white.withValues(alpha: 0.94),
                      child: Center(
                        child: _bootstrapLoaderColumn(
                          showTxnLine: showTxnLine,
                          showEmployeesLine: showEmployeesLine,
                          reduceMotion: true,
                        ),
                      ),
                    )
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.86),
                              const Color(0xFFF0FBFC).withValues(alpha: 0.92),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(
                              0xFFCDECEF,
                            ).withValues(alpha: 0.85),
                          ),
                        ),
                        child: Center(
                          child: _bootstrapLoaderColumn(
                            showTxnLine: showTxnLine,
                            showEmployeesLine: showEmployeesLine,
                            reduceMotion: false,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bootstrapLoaderColumn({
    required bool showTxnLine,
    required bool showEmployeesLine,
    required bool reduceMotion,
  }) {
    final dateLine = _formatDate(_selectedDate);
    final employeeProgressFrac = (_showsEmployeeLoadingUi && _employeesLoading)
        ? _employeesLoadPercent.clamp(0, 100) / 100.0
        : null;

    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 1 : 150),
      child: Padding(
        key: ValueKey(
          '$showTxnLine-$showEmployeesLine-${employeeProgressFrac ?? -1}',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D98A5).withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.2,
                    color: const Color(0xFF0D98A5),
                    backgroundColor: const Color(0xFFDDF3F5),
                    value: employeeProgressFrac,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'กำลังโหลดข้อมูล',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.2,
                color: const Color(0xFF1A3440),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'วันที่ $dateLine · เก็บรายการที่บันทึกไว้ของเมนูนี้ให้ครบถ้ามี',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w500,
                fontSize: 13.8,
                height: 1.35,
                color: const Color(0xFF5B7585),
              ),
            ),
            if (showTxnLine || showEmployeesLine) ...[
              const SizedBox(height: 18),
              Column(
                children: [
                  if (showTxnLine)
                    _bootstrapStatusRow(
                      icon: Icons.cloud_download_rounded,
                      label: 'ดึงธุรกรรมของวันที่เลือก',
                      active: showTxnLine,
                    ),
                  if (showEmployeesLine && _showsEmployeeLoadingUi) ...[
                    if (showTxnLine) const SizedBox(height: 8),
                    _bootstrapStatusRow(
                      icon: Icons.groups_rounded,
                      label:
                          'โหลดรายชื่อพนักงาน${_employeesLoading ? ' (${_employeesLoadPercent.clamp(0, 100)}%)' : ''}',
                      active: showEmployeesLine,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bootstrapStatusRow({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 18,
          color: active ? const Color(0xFF0D98A5) : const Color(0xFF9EB9C4),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: active ? const Color(0xFF295C6E) : const Color(0xFF8899A3),
            ),
          ),
        ),
      ],
    );
  }

  String _displayNamesForEmployeeIds(List<String> ids) {
    final parts = <String>[];
    for (final id in ids) {
      final e = _employeesById[id];
      parts.add(e != null ? _employeeUiDisplayName(e) : id);
    }
    return parts.where((s) => s.isNotEmpty).join(', ');
  }

  Widget _defaultModuleHistoryListTile(AppTransaction t) {
    final sub = (t.subCategory ?? '').trim();
    final meta = [t.category, if (sub.isNotEmpty) sub].join(' · ');
    var detail = '${formatTxnHistoryTime(t.createdAt)} · id: ${t.id}';
    if (transactionIsWizardDailyIncome(t)) {
      final pay = (t.incomePaymentStatus ?? '').trim() == 'Unpaid'
          ? 'ยังไม่ได้จ่าย'
          : 'จ่ายแล้ว';
      detail = 'รับเงิน: $pay · $detail';
    }
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.kanit(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '$meta\n$detail',
          style: GoogleFonts.kanit(
            fontSize: 11,
            color: Colors.black54,
            height: 1.35,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: textBlock),
          if (_superAdminMayManageHistoryRow(t))
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'แก้ไข (SuperAdmin)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF1565C0),
                  ),
                  onPressed: () => _openSuperAdminHistoryEditor(t),
                ),
                IconButton(
                  tooltip: 'ลบจากฐานข้อมูล',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  onPressed: () => _confirmSuperAdminHardDelete(t),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmSuperAdminHardDelete(AppTransaction t) async {
    if (!_superAdminMayManageHistoryRow(t)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ลบจากฐานข้อมูล',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ลบรายการนี้ออกจากฐานข้อมูลถาวร ไม่สามารถกู้คืนได้',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ยกเลิก', style: GoogleFonts.kanit()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ลบ', style: GoogleFonts.kanit(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.deleteTransaction(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบรายการจากฐานข้อมูลแล้ว', style: GoogleFonts.kanit()),
        ),
      );
      await _loadModuleTransactions(
        preserveIncomeUtilitiesForm: _isIncomeUtilitiesEntryMode,
        forceRefresh: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบไม่สำเร็จ: $e', style: GoogleFonts.kanit())),
      );
    }
  }

  Future<void> _openSuperAdminHistoryEditor(AppTransaction t) async {
    if (!_superAdminMayManageHistoryRow(t)) return;
    if (_isLaborAdvanceMode) {
      await _openSuperAdminAdvanceEditor(t);
      return;
    }
    if (_isIncomeUtilitiesEntryMode) {
      if (transactionIsUtilitiesExpense(t)) {
        await _openSuperAdminUtilitiesExpenseEditor(t);
      } else {
        await _openSuperAdminWizardIncomeEditor(t);
      }
      return;
    }
    if (_isDailyEventMode) {
      await _openSuperAdminDailyEventEditor(t);
      return;
    }
    if (_isLaborLeaveMode) {
      await _openSuperAdminLeaveEditor(t);
      return;
    }
    if (_isOtMode) {
      await _openSuperAdminOtEditor(t);
      return;
    }
  }

  Future<void> _openSuperAdminDailyEventEditor(AppTransaction t) async {
    final descCtrl = TextEditingController(
      text: _stripRecorderSuffix(t.description),
    );
    var evType = (t.eventType ?? 'info').trim().isEmpty
        ? 'info'
        : t.eventType!.trim();
    var evPri = (t.eventPriority ?? 'normal').trim().isEmpty
        ? 'normal'
        : t.eventPriority!.trim();
    const typeOpts = <({String v, String label})>[
      (v: 'info', label: 'ℹ️ ข้อมูล'),
      (v: 'warning', label: '⚠️ เตือน'),
      (v: 'problem', label: '🚨 ปัญหา'),
      (v: 'success', label: '✅ สำเร็จ'),
      (v: 'complaint', label: '📢 ข้อร้องเรียน'),
      (v: 'request', label: '📋 ความต้องการ'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'แก้ไขเหตุการณ์ (SuperAdmin)',
                    style: GoogleFonts.kanit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final o in typeOpts)
                        ChoiceChip(
                          label: Text(
                            o.label,
                            style: GoogleFonts.kanit(fontSize: 12.5),
                          ),
                          selected: evType == o.v,
                          onSelected: (sel) {
                            if (sel) setModal(() => evType = o.v);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'normal', label: Text('ปกติ')),
                      ButtonSegment(value: 'urgent', label: Text('ด่วน')),
                    ],
                    selected: {evPri},
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setModal(() => evPri = s.first);
                    },
                    style: ButtonStyle(
                      textStyle: WidgetStatePropertyAll(
                        GoogleFonts.kanit(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'รายละเอียด',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      final text = descCtrl.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'กรุณากรอกรายละเอียด',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                        return;
                      }
                      final saved = t.copyWith(
                        description: _appendRecorder(text),
                        eventType: evType,
                        eventPriority: evPri,
                      );
                      try {
                        await _persist(saved);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'บันทึกการแก้ไขแล้ว',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                        await _loadModuleTransactions(forceRefresh: true);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        _showSuperAdminHistorySaveError(
                          ctx,
                          error: e,
                          page: 'แก้ไขเหตุการณ์ (SuperAdmin)',
                          action: 'แก้ไขประวัติเหตุการณ์',
                        );
                      }
                    },
                    child: Text('บันทึก', style: GoogleFonts.kanit()),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(descCtrl.dispose);
  }

  Future<void> _openSuperAdminLeaveEditor(AppTransaction t) async {
    final reasonCtrl = TextEditingController(
      text: (t.leaveReason ?? '').trim(),
    );
    final wd0 = (t.workDetails ?? '').trim();
    final halfFromMeta =
        wd0 == _leaveHalfMorningMeta || wd0 == _leaveHalfAfternoonMeta;
    final halfFromDays =
        t.leaveDays != null && (t.leaveDays! - 0.5).abs() < 1e-6;
    var adminLeaveIsHalf = halfFromMeta || halfFromDays;
    var adminLeaveHalfPart =
        wd0 == _leaveHalfAfternoonMeta ? 'afternoon' : 'morning';
    final daysCtrl = TextEditingController(
      text: adminLeaveIsHalf
          ? '0.5'
          : (t.leaveDays != null ? _strNum(t.leaveDays) : '1'),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'แก้ไขลางาน (SuperAdmin)',
                  style: GoogleFonts.kanit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ผู้ลา: ${_displayNamesForEmployeeIds(t.employeeIds)}',
                  style: GoogleFonts.kanit(
                    fontSize: 12.5,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: 'เหตุผล',
                    labelStyle: GoogleFonts.kanit(),
                  ),
                  style: GoogleFonts.kanit(fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  'ระยะเวลาลา',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF314C6D),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('เต็มวัน')),
                      ButtonSegment<bool>(value: true, label: Text('ครึ่งวัน')),
                    ],
                    selected: {adminLeaveIsHalf},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      setModal(() {
                        adminLeaveIsHalf = next.first;
                        if (adminLeaveIsHalf) {
                          daysCtrl.text = '0.5';
                          adminLeaveHalfPart = 'morning';
                        } else if (daysCtrl.text.trim() == '0.5') {
                          daysCtrl.text = '1';
                        }
                      });
                    },
                    style: ButtonStyle(
                      textStyle: WidgetStatePropertyAll(
                        GoogleFonts.kanit(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                if (adminLeaveIsHalf) ...[
                  const SizedBox(height: 10),
                  Text(
                    'ช่วงครึ่งวัน',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: const Color(0xFF314C6D),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'morning',
                          label: Text('ครึ่งเช้า'),
                        ),
                        ButtonSegment<String>(
                          value: 'afternoon',
                          label: Text('ครึ่งบ่าย'),
                        ),
                      ],
                      selected: {adminLeaveHalfPart},
                      onSelectionChanged: (next) {
                        if (next.isEmpty) return;
                        setModal(() => adminLeaveHalfPart = next.first);
                      },
                      style: ButtonStyle(
                        textStyle: WidgetStatePropertyAll(
                          GoogleFonts.kanit(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (!adminLeaveIsHalf)
                  TextField(
                    controller: daysCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'จำนวนวัน',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  )
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            color: Colors.teal.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'จำนวน 0.5 วัน (ครึ่งวัน — ${adminLeaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย'})',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: const Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final reason = reasonCtrl.text.trim();
                    if (reason.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            'กรุณากรอกเหตุผล',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      );
                      return;
                    }
                    if (adminLeaveIsHalf) {
                      if (adminLeaveHalfPart != 'morning' &&
                          adminLeaveHalfPart != 'afternoon') {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'กรุณาเลือกลาครึ่งเช้าหรือครึ่งบ่าย',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                        return;
                      }
                    }
                    final days =
                        adminLeaveIsHalf
                            ? 0.5
                            : (double.tryParse(daysCtrl.text.trim()) ?? 0);
                    if (!adminLeaveIsHalf && days <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            'จำนวนวันต้องมากกว่า 0',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      );
                      return;
                    }
                    final sub = (t.subCategory ?? 'Personal').trim();
                    final typeTh = sub == 'Sick' ? 'ป่วย' : 'กิจ';
                    final halfTh = adminLeaveIsHalf
                        ? (adminLeaveHalfPart == 'morning'
                              ? 'ครึ่งเช้า'
                              : 'ครึ่งบ่าย')
                        : '';
                    final halfMeta = adminLeaveIsHalf
                        ? (adminLeaveHalfPart == 'morning'
                              ? _leaveHalfMorningMeta
                              : _leaveHalfAfternoonMeta)
                        : '';
                    final descCore = 'ลา$typeTh: $reason';
                    final desc = adminLeaveIsHalf
                        ? '$descCore (ครึ่งวัน — $halfTh)'
                        : descCore;
                    final saved = t.copyWith(
                      leaveReason: reason,
                      leaveDays: days,
                      workDetails: adminLeaveIsHalf ? halfMeta : '',
                      description: _appendRecorder(desc),
                    );
                    try {
                      await _persist(saved);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'บันทึกการแก้ไขแล้ว',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      );
                      await _loadModuleTransactions(forceRefresh: true);
                    } catch (e) {
                      if (!ctx.mounted) return;
                      _showSuperAdminHistorySaveError(
                        ctx,
                        error: e,
                        page: 'แก้ไขลางาน (SuperAdmin)',
                        action: 'แก้ไขประวัติการลา',
                      );
                    }
                  },
                  child: Text('บันทึก', style: GoogleFonts.kanit()),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      reasonCtrl.dispose();
      daysCtrl.dispose();
    });
  }

  Future<void> _openSuperAdminOtEditor(AppTransaction t) async {
    final hoursCtrl = TextEditingController(
      text: t.otHours != null ? _strNum(t.otHours) : '',
    );
    final descCtrl = TextEditingController(
      text: (t.otDescription ?? '').trim(),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'แก้ไข OT (SuperAdmin)',
                style: GoogleFonts.kanit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'พนักงาน: ${_displayNamesForEmployeeIds(t.employeeIds)}',
                style: GoogleFonts.kanit(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'ชั่วโมง OT',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'รายละเอียด OT',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
                  final desc = descCtrl.text.trim();
                  if (hours <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'กรุณาระบุชั่วโมง OT',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    return;
                  }
                  if (desc.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'กรุณาระบุรายละเอียด',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    return;
                  }
                  final saved = t.copyWith(
                    otHours: hours,
                    otDescription: desc,
                    description: _appendRecorder(
                      'OT $desc (${hours.toStringAsFixed(1)}ชม.) กลุ่ม (${t.employeeIds.length} คน)',
                    ),
                  );
                  try {
                    await _persist(saved);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'บันทึกการแก้ไขแล้ว',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    await _loadModuleTransactions(forceRefresh: true);
                  } catch (e) {
                    if (!ctx.mounted) return;
                    _showSuperAdminHistorySaveError(
                      ctx,
                      error: e,
                      page: 'แก้ไข OT (SuperAdmin)',
                      action: 'แก้ไขประวัติ OT',
                    );
                  }
                },
                child: Text('บันทึก', style: GoogleFonts.kanit()),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      hoursCtrl.dispose();
      descCtrl.dispose();
    });
  }

  Future<void> _openSuperAdminUtilitiesExpenseEditor(AppTransaction t) async {
    final amtCtrl = TextEditingController(text: _strNum(t.amount));
    final descCtrl = TextEditingController(
      text: _stripRecorderSuffix(t.description),
    );
    final subCtrl = TextEditingController(text: (t.subCategory ?? '').trim());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'แก้ไขรายจ่ายสาธารณูปโภค (SuperAdmin)',
                style: GoogleFonts.kanit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subCtrl,
                decoration: InputDecoration(
                  labelText: 'ประเภทย่อย (sub_category)',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'คำอธิบาย',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'จำนวนเงิน (บาท)',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final sub = subCtrl.text.trim();
                  final desc = descCtrl.text.trim();
                  final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                  if (sub.isEmpty || desc.isEmpty || amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'กรุณากรอกประเภทย่อย คำอธิบาย และจำนวนเงิน',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    return;
                  }
                  final saved = t.copyWith(
                    subCategory: sub,
                    description: _appendRecorder(desc),
                    amount: amt,
                  );
                  try {
                    await _persist(saved);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'บันทึกการแก้ไขแล้ว',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    await _loadModuleTransactions(
                      preserveIncomeUtilitiesForm: true,
                      forceRefresh: true,
                    );
                  } catch (e) {
                    if (!ctx.mounted) return;
                    _showSuperAdminHistorySaveError(
                      ctx,
                      error: e,
                      page: 'แก้ไขรายจ่ายสาธารณูปโภค (SuperAdmin)',
                      action: 'แก้ไขประวัติรายจ่ายสาธารณูปโภค',
                    );
                  }
                },
                child: Text('บันทึก', style: GoogleFonts.kanit()),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      amtCtrl.dispose();
      descCtrl.dispose();
      subCtrl.dispose();
    });
  }

  Future<void> _openSuperAdminWizardIncomeEditor(AppTransaction t) async {
    final amtCtrl = TextEditingController(text: _strNum(t.amount));
    final descCtrl = TextEditingController(
      text: _stripRecorderSuffix(t.description),
    );
    final qtyCtrl = TextEditingController(
      text: t.quantity != null ? _strNum(t.quantity) : '',
    );
    final priceCtrl = TextEditingController(
      text: t.unitPrice != null ? _strNum(t.unitPrice) : '',
    );
    var payStatus = (t.incomePaymentStatus ?? 'Paid').trim().isEmpty
        ? 'Paid'
        : t.incomePaymentStatus!.trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'แก้ไขรายรับประจำวัน (SuperAdmin)',
                    style: GoogleFonts.kanit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: 'ประเภทรายรับ / คำอธิบาย',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'ยอดรวม (บาท)',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'จำนวน (ว่างได้)',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'ราคาต่อหน่วย (ว่างได้)',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'สถานะรับเงิน',
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('จ่ายแล้ว', style: GoogleFonts.kanit()),
                        selected: payStatus == 'Paid',
                        onSelected: (_) => setModal(() => payStatus = 'Paid'),
                      ),
                      ChoiceChip(
                        label: Text(
                          'ยังไม่ได้จ่าย',
                          style: GoogleFonts.kanit(),
                        ),
                        selected: payStatus == 'Unpaid',
                        onSelected: (_) => setModal(() => payStatus = 'Unpaid'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      final desc = descCtrl.text.trim();
                      final total = double.tryParse(amtCtrl.text.trim()) ?? 0;
                      final qty = double.tryParse(qtyCtrl.text.trim());
                      final unitPrice = double.tryParse(priceCtrl.text.trim());
                      if (desc.isEmpty || total <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'กรุณากรอกประเภทรายรับและยอดรวม',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                        return;
                      }
                      final saved = t.copyWith(
                        description: _appendRecorder(desc),
                        amount: total,
                        quantity: (qty != null && qty > 0) ? qty : null,
                        unitPrice: (unitPrice != null && unitPrice > 0)
                            ? unitPrice
                            : null,
                        incomePaymentStatus: payStatus,
                      );
                      try {
                        await _persist(saved);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'บันทึกการแก้ไขแล้ว',
                              style: GoogleFonts.kanit(),
                            ),
                          ),
                        );
                        await _loadModuleTransactions(
                          preserveIncomeUtilitiesForm: true,
                          forceRefresh: true,
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        _showSuperAdminHistorySaveError(
                          ctx,
                          error: e,
                          page: 'แก้ไขรายรับประจำวัน (SuperAdmin)',
                          action: 'แก้ไขประวัติรายรับประจำวัน',
                        );
                      }
                    },
                    child: Text('บันทึก', style: GoogleFonts.kanit()),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      amtCtrl.dispose();
      descCtrl.dispose();
      qtyCtrl.dispose();
      priceCtrl.dispose();
    });
  }

  Widget _iuHistoryListRow(AppTransaction t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stripRecorderSuffix(t.description),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  transactionIsUtilitiesExpense(t)
                      ? 'รายจ่าย · ฿${_strNum(t.amount)} · ${formatTxnHistoryTime(t.createdAt)}'
                      : 'รายรับ · ${(t.incomePaymentStatus ?? '').trim() == 'Unpaid' ? 'ยังไม่ได้จ่าย' : 'จ่ายแล้ว'} · ฿${_strNum(t.amount)} · ${formatTxnHistoryTime(t.createdAt)}',
                  style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (_superAdminMayManageHistoryRow(t))
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'แก้ไข (SuperAdmin)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF1565C0),
                  ),
                  onPressed: () => _openSuperAdminHistoryEditor(t),
                ),
                IconButton(
                  tooltip: 'ลบจากฐานข้อมูล',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                  onPressed: () => _confirmSuperAdminHardDelete(t),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openSuperAdminAdvanceEditor(AppTransaction t) async {
    if (!_superAdminMayManageHistoryRow(t) || !_isLaborAdvanceMode) return;
    final base = AdvanceGmMeta.decode(t.workDetails);
    final amtCtrl = TextEditingController(
      text: _strNum(t.advanceAmount ?? t.amount),
    );
    final acctCtrl = TextEditingController(text: base.accountNumber);
    var payout = base.payoutSlot;
    var payM = base.paymentMethod;
    var bank = base.bank;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              Future<void> submit() async {
                final per = double.tryParse(amtCtrl.text.trim()) ?? 0;
                if (per <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        'กรุณากรอกจำนวนเงินให้มากกว่า 0',
                        style: GoogleFonts.kanit(),
                      ),
                    ),
                  );
                  return;
                }
                if (payM == AdvanceGmMeta.transfer) {
                  final b = bank.trim();
                  final a = acctCtrl.text.trim();
                  if (b.isEmpty || a.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'โอนเงิน: กรุณาเลือกธนาคารและเลขบัญชี',
                          style: GoogleFonts.kanit(),
                        ),
                      ),
                    );
                    return;
                  }
                }
                final meta = AdvanceGmMeta(
                  payoutSlot: payout,
                  paymentMethod: payM,
                  bank: bank.trim(),
                  accountNumber: acctCtrl.text.trim(),
                );
                final workDetails = AdvanceGmMeta.encodeIntoWorkDetails(
                  existingWorkDetails: t.workDetails,
                  meta: meta,
                );
                final namesLine = _displayNamesForEmployeeIds(t.employeeIds);
                final slotTh = payout == AdvanceGmMeta.evening
                    ? 'ช่วงเย็น'
                    : 'ช่วงกลางวัน';
                final payTh = payM == AdvanceGmMeta.transfer
                    ? 'เงินโอน'
                    : 'เงินสด';
                final saved = t.copyWith(
                  amount: per,
                  advanceAmount: per,
                  workDetails: workDetails,
                  description: _appendRecorder(
                    'คำขอเบิกเงิน · $namesLine · $slotTh · $payTh',
                  ),
                );
                try {
                  await _persist(saved);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'บันทึกการแก้ไขแล้ว',
                        style: GoogleFonts.kanit(),
                      ),
                    ),
                  );
                  await _loadModuleTransactions(forceRefresh: true);
                } catch (e) {
                  if (!ctx.mounted) return;
                  _showSuperAdminHistorySaveError(
                    ctx,
                    error: e,
                    page: 'แก้ไขคำขอเบิก (SuperAdmin)',
                    action: 'แก้ไขประวัติคำขอเบิกเงิน',
                  );
                }
              }

              final bankItems = <DropdownMenuItem<String>>[];
              final seen = <String>{};
              for (final bn in kThaiBankNames) {
                if (seen.add(bn)) {
                  bankItems.add(
                    DropdownMenuItem(
                      value: bn,
                      child: Text(bn, style: GoogleFonts.kanit(fontSize: 14)),
                    ),
                  );
                }
              }
              final bTrim = bank.trim();
              if (bTrim.isNotEmpty && !kThaiBankNames.contains(bTrim)) {
                bankItems.add(
                  DropdownMenuItem(
                    value: bTrim,
                    child: Text(
                      '$bTrim (จากข้อมูลเดิม)',
                      style: GoogleFonts.kanit(fontSize: 14),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'แก้ไขคำขอเบิก (SuperAdmin)',
                      style: GoogleFonts.kanit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'จำนวนเงิน (บาท)',
                        labelStyle: GoogleFonts.kanit(),
                      ),
                      style: GoogleFonts.kanit(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'รับเงิน',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'ช่วงกลางวัน',
                            style: GoogleFonts.kanit(),
                          ),
                          selected: payout == AdvanceGmMeta.midday,
                          onSelected: (_) =>
                              setModal(() => payout = AdvanceGmMeta.midday),
                        ),
                        ChoiceChip(
                          label: Text('ช่วงเย็น', style: GoogleFonts.kanit()),
                          selected: payout == AdvanceGmMeta.evening,
                          onSelected: (_) =>
                              setModal(() => payout = AdvanceGmMeta.evening),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'วิธีรับ',
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('เงินสด', style: GoogleFonts.kanit()),
                          selected: payM == AdvanceGmMeta.cash,
                          onSelected: (_) =>
                              setModal(() => payM = AdvanceGmMeta.cash),
                        ),
                        ChoiceChip(
                          label: Text('โอน', style: GoogleFonts.kanit()),
                          selected: payM == AdvanceGmMeta.transfer,
                          onSelected: (_) =>
                              setModal(() => payM = AdvanceGmMeta.transfer),
                        ),
                      ],
                    ),
                    if (payM == AdvanceGmMeta.transfer) ...[
                      const SizedBox(height: 12),
                      Text(
                        'ธนาคาร',
                        style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: Text('เลือกธนาคาร', style: GoogleFonts.kanit()),
                          value: bankItems.any((it) => it.value == bTrim)
                              ? bTrim
                              : null,
                          items: bankItems,
                          onChanged: (v) => setModal(() => bank = v ?? ''),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: acctCtrl,
                        decoration: InputDecoration(
                          labelText: 'เลขบัญชี',
                          labelStyle: GoogleFonts.kanit(),
                        ),
                        style: GoogleFonts.kanit(fontSize: 15),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () async => submit(),
                      child: Text('บันทึก', style: GoogleFonts.kanit()),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      amtCtrl.dispose();
      acctCtrl.dispose();
    });
  }

  Widget _leaveHistoryListTile(AppTransaction t) {
    final names = _displayNamesForEmployeeIds(t.employeeIds);
    final namesLine = names.isEmpty ? '—' : names;
    final kind = leaveKindLabelTh(t);
    final duration = leaveDurationLabelTh(t);
    final reason = resolvedLeaveReason(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF5FAFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFBBDEFB)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFBBDEFB).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: Color(0xFF1565C0),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      namesLine,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0D47A1),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _leaveMetaChip(kind, Icons.label_outline_rounded),
                        if (duration.isNotEmpty)
                          _leaveMetaChip(
                            duration,
                            Icons.schedule_rounded,
                          ),
                      ],
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        reason,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.kanit(
                          fontSize: 12.5,
                          color: const Color(0xFF455A64),
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      formatTxnHistoryTime(t.createdAt),
                      style: GoogleFonts.kanit(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (_superAdminMayManageHistoryRow(t))
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'แก้ไข (SuperAdmin)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Color(0xFF1565C0),
                      ),
                      onPressed: () => _openSuperAdminHistoryEditor(t),
                    ),
                    IconButton(
                      tooltip: 'ลบจากฐานข้อมูล',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700,
                      ),
                      onPressed: () => _confirmSuperAdminHardDelete(t),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leaveMetaChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1565C0)),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.kanit(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF37474F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _advanceHistoryListTile(AppTransaction t) {
    final names = _displayNamesForEmployeeIds(t.employeeIds);
    final namesLine = names.isEmpty ? '—' : names;
    final per = t.advanceAmount ?? t.amount;
    final amtStr = per > 0 ? '฿${_strNum(per)}' : 'ยอด —';
    final meta = AdvanceGmMeta.decode(t.workDetails);
    final slotTh = meta.payoutSlot == AdvanceGmMeta.evening
        ? 'รับช่วงเย็น'
        : 'รับช่วงกลางวัน';
    final payTh = meta.paymentMethod == AdvanceGmMeta.transfer
        ? 'เงินโอน'
        : 'เงินสด';
    var bankLine = '';
    if (meta.paymentMethod == AdvanceGmMeta.transfer) {
      final b = meta.bank.trim();
      final a = meta.accountNumber.trim();
      if (b.isNotEmpty && a.isNotEmpty) {
        bankLine = ' · $b · $a';
      } else if (b.isNotEmpty) {
        bankLine = ' · $b';
      } else if (a.isNotEmpty) {
        bankLine = ' · เลข $a';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFFFFBF7),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFFE0B2)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE0B2).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.request_quote_rounded,
                  color: Color(0xFFE65100),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      namesLine,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A237E),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _advanceMetaChip(amtStr, Icons.payments_rounded),
                        _advanceMetaChip(slotTh, Icons.schedule_rounded),
                        _advanceMetaChip(
                          payTh,
                          Icons.account_balance_wallet_rounded,
                        ),
                      ],
                    ),
                    if (bankLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        bankLine.trimLeft(),
                        style: GoogleFonts.kanit(
                          fontSize: 11.5,
                          color: const Color(0xFF5C6BC0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      t.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(
                        fontSize: 12,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatTxnHistoryTime(t.createdAt)} · ${t.id}',
                      style: GoogleFonts.kanit(
                        fontSize: 10.5,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (_superAdminMayManageHistoryRow(t))
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'แก้ไข (SuperAdmin)',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Color(0xFFE65100),
                      ),
                      onPressed: () => _openSuperAdminHistoryEditor(t),
                    ),
                    IconButton(
                      tooltip: 'ลบจากฐานข้อมูล',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700,
                      ),
                      onPressed: () => _confirmSuperAdminHardDelete(t),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _advanceMetaChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE65100)),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.kanit(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF37474F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleHistorySection() {
    if (_isIncomeUtilitiesEntryMode) return const SizedBox.shrink();
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
                        color:
                            (_moduleHistoryVisible
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
                            ? (_isLaborAdvanceMode
                                  ? const Color(
                                      0xFFE65100,
                                    ).withValues(alpha: 0.55)
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.45,
                                    ))
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
                            color: _isLaborAdvanceMode
                                ? const Color(0xFFE65100)
                                : theme.colorScheme.primary,
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
                                  : _isLaborAdvanceMode
                                  ? 'ดูประวัติการเบิกวันนี้ ($n รายการ)'
                                  : _isLaborLeaveMode
                                  ? 'ดูประวัติการลาวันนี้ ($n รายการ)'
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
                        border: Border.all(
                          color: _isLaborAdvanceMode
                              ? const Color(0xFFFFE0B2)
                              : const Color(0xFFE7EDF5),
                        ),
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
                              _isLaborAdvanceMode
                                  ? 'แต่ละรายการ = คนละคำขอ — แสดงชื่อผู้เบิกและยอดที่ขอ'
                                  : _isLaborLeaveMode
                                  ? 'แสดงชื่อผู้ลา ประเภท และระยะเวลา — หนึ่งแถวต่อหนึ่งรายการบันทึก'
                                  : 'เวลาที่แสดงคือเวลาสร้างแถวในระบบ — แก้ไขแถวเดิมยังใช้รหัสแถวเดิม',
                              style: GoogleFonts.kanit(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._moduleDayTransactions.map(
                              (t) => _isLaborAdvanceMode
                                  ? _advanceHistoryListTile(t)
                                  : _isLaborLeaveMode
                                  ? _leaveHistoryListTile(t)
                                  : _defaultModuleHistoryListTile(t),
                            ),
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
    // Use sizeOf / viewInsets in narrow scopes so keyboard animation does not
    // rebuild the entire form tree every frame (see ListView spacer + overlay Builder).
    final isLargeTablet = MediaQuery.sizeOf(context).shortestSide >= 700;
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isLaborAdvanceMode
                        ? const [
                            Color(0xFFFF8A65),
                            Color(0xFFE64A19),
                            Color(0xFFBF360C),
                          ]
                        : _isIncomeUtilitiesEntryMode
                        ? const [Color(0xFF5C6BC0), Color(0xFF3949AB)]
                        : const [Color(0xFF0D98A5), Color(0xFF1BB7C0)],
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      heading,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.kanit(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (_isLaborAdvanceMode) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'ลงลายเซ็นเพื่อยืนยัน · แจ้งผู้ดูแลผ่าน LINE อัตโนมัติ',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.kanit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xE6FFFFFF),
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ],
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
                              child: Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.none,
                                children: [
                                  Center(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: contentMaxWidth,
                                      ),
                                      child: _isLaborMode &&
                                              _laborUseSideStickyPool(context)
                                          ? Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: _laborPoolAsideWidth(
                                                    context,
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 10,
                                                        ),
                                                    child: LayoutBuilder(
                                                      builder: (context, c) {
                                                        final poolH = c
                                                                .maxHeight
                                                                .isFinite
                                                            ? c.maxHeight
                                                            : MediaQuery.sizeOf(
                                                                    context,
                                                                  ).height *
                                                                  0.72;
                                                        return SizedBox(
                                                          height: poolH,
                                                          child:
                                                              _LaborCanvasSection(
                                                            child:
                                                                _buildLaborCanvasBoard(
                                                              layout:
                                                                  _LaborDragBoardLayout
                                                                      .poolOnly,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: ListView(
                                                    keyboardDismissBehavior:
                                                        ScrollViewKeyboardDismissBehavior
                                                            .onDrag,
                                                    cacheExtent:
                                                        DevicePerf
                                                            .isConstrainedDevice
                                                        ? (isLargeTablet
                                                              ? 380
                                                              : 220)
                                                        : (isLargeTablet
                                                              ? 1200
                                                              : 700),
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          0,
                                                          0,
                                                          0,
                                                          28,
                                                        ),
                                                    physics:
                                                        _blockingModuleBootstrap
                                                        ? const NeverScrollableScrollPhysics()
                                                        : const AlwaysScrollableScrollPhysics(),
                                                    children:
                                                        _quickInputScrollChildren(
                                                      laborFormIncludePool:
                                                          false,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : _isLaborMode
                                          ? _buildLaborPinnedScrollView(
                                              isLargeTablet: isLargeTablet,
                                            )
                                          : ListView(
                                              keyboardDismissBehavior:
                                                  ScrollViewKeyboardDismissBehavior
                                                      .onDrag,
                                              cacheExtent:
                                                  DevicePerf.isConstrainedDevice
                                                  ? (isLargeTablet ? 380 : 220)
                                                  : (isLargeTablet
                                                        ? 1200
                                                        : 700),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    0,
                                                    14,
                                                    28,
                                                  ),
                                              physics: _blockingModuleBootstrap
                                                  ? const NeverScrollableScrollPhysics()
                                                  : const AlwaysScrollableScrollPhysics(),
                                              children: _quickInputScrollChildren(),
                                            ),
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) =>
                                        _moduleBootstrapOverlay(
                                          MediaQuery.viewInsetsOf(
                                            context,
                                          ).bottom,
                                          WidgetsBinding
                                              .instance
                                              .platformDispatcher
                                              .accessibilityFeatures
                                              .disableAnimations,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _syncIncomeTotalFromQtyPrice() {
    final q = double.tryParse(_incomeQtyController.text.trim()) ?? 0;
    final p = double.tryParse(_incomeUnitPriceController.text.trim()) ?? 0;
    if (q > 0 && p > 0) {
      _incomeTotalController.text = _strNum(q * p);
    }
    if (mounted) setState(() {});
  }

  void _applyIncomeUtilitiesFormClear() {
    _iuExpenseChoice = null;
    _iuIncomeChoice = null;
    _wizardIncomePaymentStatus = 'Paid';
    _utilitiesTypeController.clear();
    _utilitiesExtraController.clear();
    _utilitiesAmountController.clear();
    _incomeTypeController.clear();
    _incomeQtyController.clear();
    _incomeUnitPriceController.clear();
    _incomeTotalController.clear();
  }

  String _effectiveUtilitySubcategory() {
    final choice = _iuExpenseChoice?.trim();
    if (choice == null || choice.isEmpty) return '';
    if (choice == _iuOtherSentinel) {
      return _utilitiesTypeController.text.trim();
    }
    return choice;
  }

  List<String> _incomeTypeDropdownOptions() {
    const removed = 'ขายแร่';
    bool keep(String t) {
      final s = t.trim();
      return s.isNotEmpty && s != removed;
    }

    final seen = <String>{};
    final out = <String>[];
    for (final t in _appIncomeTypes) {
      if (!keep(t)) continue;
      if (seen.add(t)) out.add(t);
    }
    for (final tx in _moduleDayTransactions) {
      if (!transactionIsWizardDailyIncome(tx)) continue;
      final d = _stripRecorderSuffix(tx.description).trim();
      if (d.isEmpty || !keep(d) || !seen.add(d)) continue;
      out.add(d);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  String _effectiveIncomeDescription() {
    final choice = _iuIncomeChoice?.trim();
    if (choice == null || choice.isEmpty) return '';
    if (choice == _iuOtherSentinel) {
      return _incomeTypeController.text.trim();
    }
    return choice;
  }

  Future<void> _saveUtilitiesExpense() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกสาธารณูปโภคสำเร็จ',
      saveActionLabel: 'บันทึกรายจ่ายสาธารณูปโภค',
      saveButtonLabel: 'บันทึกรายจ่าย',
      stayOnPage: true,
      onStayOnPageCleared: _applyIncomeUtilitiesFormClear,
      body: () async {
        final sub = _effectiveUtilitySubcategory();
        final extra = _utilitiesExtraController.text.trim();
        final amt =
            double.tryParse(_utilitiesAmountController.text.trim()) ?? 0;
        if (_iuExpenseChoice == null || _iuExpenseChoice!.trim().isEmpty) {
          _failSave('กรุณาเลือกประเภทค่าใช้จ่าย');
        }
        if (sub.isEmpty) {
          _failSave('กรุณาระบุประเภท (เลือกจากรายการหรือระบุเมื่อเลือกอื่นๆ)');
        }
        if (amt <= 0) {
          _failSave('กรุณาระบุจำนวนเงินให้ถูกต้อง');
        }
        final desc = extra.isEmpty ? sub : '$sub: $extra';
        final ymd = _quickYmd(_selectedDate);
        final id = '${DateTime.now().millisecondsSinceEpoch}_utils';
        await _persist(
          AppTransaction(
            id: id,
            date: ymd,
            type: 'Expense',
            category: 'Utilities',
            subCategory: sub,
            description: _appendRecorder(desc),
            amount: amt,
            note: _activeSignatureNote,
          ),
        );
      },
    );
  }

  Future<void> _saveWizardIncomeEntry() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกรายรับสำเร็จ',
      saveActionLabel: 'บันทึกรายรับประจำวัน',
      saveButtonLabel: 'บันทึกรายรับ',
      stayOnPage: true,
      onStayOnPageCleared: _applyIncomeUtilitiesFormClear,
      body: () async {
        final incomeType = _effectiveIncomeDescription();
        final total = double.tryParse(_incomeTotalController.text.trim()) ?? 0;
        final qtyRaw = _incomeQtyController.text.trim();
        final priceRaw = _incomeUnitPriceController.text.trim();
        final qty = double.tryParse(qtyRaw);
        final unitPrice = double.tryParse(priceRaw);
        if (_iuIncomeChoice == null || _iuIncomeChoice!.trim().isEmpty) {
          _failSave('กรุณาเลือกประเภทรายรับ');
        }
        if (incomeType.isEmpty) {
          _failSave('กรุณาระบุประเภทรายรับ (เลือกจากรายการหรือพิมพ์เมื่อเลือกอื่นๆ)');
        }
        if (incomeType.trim() == 'ขายแร่') {
          _failSave('ประเภท "ขายแร่" ไม่ใช้ในระบบแล้ว');
        }
        if (total <= 0) {
          _failSave('กรุณาระบุยอดรวม (บาท) ให้ถูกต้อง');
        }
        final ymd = _quickYmd(_selectedDate);
        final id = '${DateTime.now().millisecondsSinceEpoch}_income';
        await _persist(
          AppTransaction(
            id: id,
            date: ymd,
            type: 'Income',
            category: 'Income',
            description: _appendRecorder(incomeType),
            amount: total,
            quantity: (qty != null && qty > 0) ? qty : null,
            unitPrice: (unitPrice != null && unitPrice > 0) ? unitPrice : null,
            incomePaymentStatus: _wizardIncomePaymentStatus,
            note: _activeSignatureNote,
          ),
        );
      },
    );
  }

  Widget _buildIncomeUtilitiesEntryCard() {
    const indigo = Color(0xFF3949AB);
    const teal = Color(0xFF00897B);
    const green = Color(0xFF2E7D32);

    final expenseOpts = List<String>.from(_appExpenseTypes);
    final incomeOpts = _incomeTypeDropdownOptions();

    String expenseDropdownValue() {
      final c = _iuExpenseChoice;
      if (c == null || c.isEmpty) return '';
      if (c == _iuOtherSentinel) return _iuOtherSentinel;
      if (expenseOpts.contains(c)) return c;
      return '';
    }

    String incomeDropdownValue() {
      final c = _iuIncomeChoice;
      if (c == null || c.isEmpty) return '';
      if (c == _iuOtherSentinel) return _iuOtherSentinel;
      if (incomeOpts.contains(c)) return c;
      return '';
    }

    Widget dateRow() {
      return Material(
        color: const Color(0xFFF3F4FB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: indigo,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'วันที่ ${_formatDate(_selectedDate)} · แตะเพื่อเปลี่ยนวัน',
                    style: GoogleFonts.kanit(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D2736),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      );
    }

    InputDecoration deco(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.kanit(color: Colors.black54),
        prefixIcon: Icon(icon, color: indigo.withValues(alpha: 0.85)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7E3F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: indigo, width: 1.2),
        ),
      );
    }

    Widget kindTile({
      required _IuEntryKind kind,
      required String title,
      required String subtitle,
      required IconData icon,
      required Color accent,
    }) {
      final sel = _iuEntryKind == kind;
      return Material(
        color: sel ? accent.withValues(alpha: 0.12) : const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _iuEntryKind = kind),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.kanit(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1D2736),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.kanit(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (sel)
                  Icon(Icons.check_circle_rounded, color: accent, size: 22),
              ],
            ),
          ),
        ),
      );
    }

    List<Widget> todayRows() {
      final ymd = _quickYmd(_selectedDate);
      final list = _moduleDayTransactions.where((t) {
        if (t.date.trim() != ymd.trim()) return false;
        if (_iuEntryKind == null) {
          return transactionIsUtilitiesExpense(t) ||
              transactionIsWizardDailyIncome(t);
        }
        if (_iuEntryKind == _IuEntryKind.expense) {
          return transactionIsUtilitiesExpense(t);
        }
        return transactionIsWizardDailyIncome(t);
      }).toList();
      list.sort((a, b) {
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      if (list.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'ยังไม่มีรายการในวันนี้ (บันทึกได้หลายรายการ)',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontSize: 13.5,
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ];
      }
      return [
        for (final t in list.take(14)) ...[
          _iuHistoryListRow(t),
          const Divider(height: 1),
        ],
        if (list.length > 14)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '… และอีก ${list.length - 14} รายการ',
              style: GoogleFonts.kanit(
                fontSize: 12.5,
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'บันทึกรายรับ-รายจ่าย',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'เลือกรายจ่ายหรือรายรับก่อน แล้วกรอกฟอร์ม · ประเภทดึงจากตั้งค่าเว็บ (สาธารณูปโภค / รายรับ) และช่วยกรอกจากประวัติ',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(
            fontSize: 12.5,
            height: 1.35,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        dateRow(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: kindTile(
                kind: _IuEntryKind.expense,
                title: 'รายจ่าย',
                subtitle: 'สาธารณูปโภค',
                icon: Icons.south_west_rounded,
                accent: teal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: kindTile(
                kind: _IuEntryKind.income,
                title: 'รายรับ',
                subtitle: 'รายรับประจำวัน',
                icon: Icons.north_east_rounded,
                accent: green,
              ),
            ),
          ],
        ),
        if (_iuEntryKind == null) ...[
          const SizedBox(height: 18),
          Text(
            'แตะเลือก «รายจ่าย» หรือ «รายรับ» เพื่อแสดงฟอร์มกรอก',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontSize: 14,
              color: const Color(0xFF546E7A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_iuEntryKind == _IuEntryKind.expense) ...[
          const SizedBox(height: 18),
          Text(
            'สาธารณูปโภค',
            style: GoogleFonts.kanit(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A237E),
            ),
          ),
          if (expenseOpts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                'ยังไม่มีรายการประเภทในเว็บ (ตั้งค่า → สาธารณูปโภค → ประเภทค่าใช้จ่าย) — ใช้ «อื่นๆ» ด้านล่าง',
                style: GoogleFonts.kanit(
                  fontSize: 12.5,
                  color: const Color(0xFFB45309),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — ต้องสะท้อน state หลังบันทึก/โหลด
            value: expenseDropdownValue().isEmpty
                ? null
                : expenseDropdownValue(),
            isExpanded: true,
            decoration: deco('ประเภทค่าใช้จ่าย', Icons.category_outlined),
            hint: Text('— เลือกประเภท —', style: GoogleFonts.kanit()),
            items: [
              ...expenseOpts.map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style: GoogleFonts.kanit(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DropdownMenuItem(
                value: _iuOtherSentinel,
                child: Text('อื่นๆ (พิมพ์เอง)', style: GoogleFonts.kanit()),
              ),
            ],
            onChanged: (v) => setState(() => _iuExpenseChoice = v),
          ),
          if (_iuExpenseChoice == _iuOtherSentinel) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _utilitiesTypeController,
              decoration: deco('ระบุประเภท', Icons.edit_outlined),
              style: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D2A3A),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _utilitiesExtraController,
            decoration: deco(
              'รายละเอียดเพิ่ม (ไม่บังคับ)',
              Icons.notes_outlined,
            ),
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D2A3A),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _utilitiesAmountController,
            decoration: deco('จำนวนเงิน (บาท)', Icons.attach_money_outlined),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D2A3A),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    teal.withValues(alpha: 0.92),
                    const Color(0xFF00695C),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: teal.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveUtilitiesExpense,
                icon: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_alt_rounded, color: Colors.white),
                label: Text(
                  _saving
                      ? 'กำลังบันทึก...'
                      : 'บันทึกรายจ่าย (เพิ่มรายการได้หลายครั้ง)',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (_iuEntryKind == _IuEntryKind.income) ...[
          const SizedBox(height: 18),
          Text(
            'รายรับประจำวัน',
            style: GoogleFonts.kanit(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A237E),
            ),
          ),
          if (_appIncomeTypes.isEmpty && incomeOpts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                'ยังไม่มีประเภทรายรับในเว็บ — เลือก «อื่นๆ» แล้วพิมพ์ประเภท',
                style: GoogleFonts.kanit(
                  fontSize: 12.5,
                  color: const Color(0xFFB45309),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — ต้องสะท้อน state หลังบันทึก/โหลด
            value: incomeDropdownValue().isEmpty ? null : incomeDropdownValue(),
            isExpanded: true,
            decoration: deco('ประเภทรายรับ', Icons.label_outline_rounded),
            hint: Text(
              '— เลือกหรือใช้จากประวัติ —',
              style: GoogleFonts.kanit(),
            ),
            items: [
              ...incomeOpts.map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style: GoogleFonts.kanit(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DropdownMenuItem(
                value: _iuOtherSentinel,
                child: Text('อื่นๆ (พิมพ์เอง)', style: GoogleFonts.kanit()),
              ),
            ],
            onChanged: (v) => setState(() => _iuIncomeChoice = v),
          ),
          if (_iuIncomeChoice == _iuOtherSentinel) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _incomeTypeController,
              decoration: deco('ระบุประเภทรายรับ', Icons.edit_outlined),
              style: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D2A3A),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สถานะรับเงิน',
                  style: GoogleFonts.kanit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF37474F),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        label: Text(
                          'ยังไม่ได้จ่ายเงิน',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        selected: _wizardIncomePaymentStatus == 'Unpaid',
                        onSelected: (_) => setState(
                          () => _wizardIncomePaymentStatus = 'Unpaid',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        label: Text(
                          'จ่ายเงินแล้ว',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        selected: _wizardIncomePaymentStatus == 'Paid',
                        onSelected: (_) =>
                            setState(() => _wizardIncomePaymentStatus = 'Paid'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _incomeQtyController,
                  decoration: deco('จำนวน (ไม่บังคับ)', Icons.numbers_outlined),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: GoogleFonts.kanit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1D2A3A),
                  ),
                  onChanged: (_) => _syncIncomeTotalFromQtyPrice(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _incomeUnitPriceController,
                  decoration: deco(
                    'ราคาต่อหน่วย (ไม่บังคับ)',
                    Icons.price_change_outlined,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: GoogleFonts.kanit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1D2A3A),
                  ),
                  onChanged: (_) => _syncIncomeTotalFromQtyPrice(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _incomeTotalController,
            decoration: deco('ยอดรวม (บาท)', Icons.payments_outlined),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D2A3A),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    green.withValues(alpha: 0.95),
                    const Color(0xFF1B5E20),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: green.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveWizardIncomeEntry,
                icon: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.savings_outlined, color: Colors.white),
                label: Text(
                  _saving
                      ? 'กำลังบันทึก...'
                      : 'บันทึกรายรับ (เพิ่มรายการได้หลายครั้ง)',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'รายการวันนี้',
          style: GoogleFonts.kanit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 6),
        ...todayRows(),
      ],
    );
  }

  Widget _buildSandWashFormCard() {
    if (_sandMorningStartController.text.trim().isEmpty) {
      _sandMorningStartController.text = '08.20';
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
    const Color sandM1Border = Color(0xFF1D4ED8);
    const Color sandM1Fill = Color(0xFFEFF6FF);
    const Color sandM1Label = Color(0xFF1E3A8A);
    const Color sandM1ChipFg = Color(0xFF1E40AF);
    const Color sandM1ChipBg = Color(0xFFDBEAFE);
    const Color sandM1ChipSide = Color(0xFF93C5FD);

    const Color sandM2Border = Color(0xFFD97706);
    const Color sandM2Fill = Color(0xFFFFF7ED);
    const Color sandM2Label = Color(0xFF9A3412);
    const Color sandM2ChipFg = Color(0xFFC2410C);
    const Color sandM2ChipBg = Color(0xFFFFEDD5);
    const Color sandM2ChipSide = Color(0xFFFDBA74);

    InputDecoration sandMachineDeco({
      required String label,
      required IconData icon,
      required Color accent,
      required Color fill,
      required Color labelColor,
    }) => InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.kanit(
        color: labelColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: accent, size: 18),
      filled: true,
      fillColor: fill,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.35),
      ),
    );

    Widget operatorChips(List<String> names, Color fg, Color bg, Color side) {
      if (names.isEmpty) {
        return Text(
          'ยังไม่ระบุ',
          style: GoogleFonts.kanit(
            fontSize: 11.5,
            height: 1.3,
            color: const Color(0xFF94A3B8),
            fontStyle: FontStyle.italic,
          ),
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: names
            .map(
              (name) => Chip(
                label: Text(
                  name,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: fg,
                  ),
                ),
                backgroundColor: bg,
                side: BorderSide(color: side),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
            .toList(),
      );
    }

    Widget sandMachineColumn({
      required TextEditingController controller,
      required String label,
      required List<String> operatorNames,
      required Color accent,
      required Color fill,
      required Color labelTint,
      required Color chipFg,
      required Color chipBg,
      required Color chipSide,
    }) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: fill.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AnimatedInputField(
              controller: controller,
              onChanged: (_) => _scheduleUiRefresh(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              readOnly: true,
              onTap: () =>
                  _openNumericPad(controller: controller, label: label),
              style: GoogleFonts.kanit(
                color: const Color(0xFF1D2A3A),
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
              decoration: sandMachineDeco(
                label: label,
                icon: Icons.precision_manufacturing_outlined,
                accent: accent,
                fill: Colors.white,
                labelColor: labelTint,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'พนักงานล้าง',
              style: GoogleFonts.kanit(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 4),
            operatorChips(operatorNames, chipFg, chipBg, chipSide),
          ],
        ),
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: sandMachineColumn(
                    controller: machine2Controller,
                    label: 'เครื่องร่อน (ใหม่)',
                    operatorNames: _sand2OperatorNames,
                    accent: sandM2Border,
                    fill: sandM2Fill,
                    labelTint: sandM2Label,
                    chipFg: sandM2ChipFg,
                    chipBg: sandM2ChipBg,
                    chipSide: sandM2ChipSide,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: sandMachineColumn(
                    controller: machine1Controller,
                    label: 'เครื่องร่อน (เก่า)',
                    operatorNames: _sand1OperatorNames,
                    accent: sandM1Border,
                    fill: sandM1Fill,
                    labelTint: sandM1Label,
                    chipFg: sandM1ChipFg,
                    chipBg: sandM1ChipBg,
                    chipSide: sandM1ChipSide,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    InputDecoration deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.kanit(
        color: const Color(0xFF5A6B7F),
        fontSize: 15,
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
                      'เวลาเริ่มงาน / หยุดล้าง',
                      style: GoogleFonts.kanit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D2736),
                      ),
                    ),
                  ],
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
                          hour: 8,
                          minute: 20,
                        ),
                        decoration: deco('เริ่มงาน', Icons.play_arrow_rounded),
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
                          'หยุดล้าง',
                          Icons.stop_circle_outlined,
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
    if (!mounted) return;

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x48000000),
      transitionDuration: const Duration(milliseconds: 80),
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
                begin: const Offset(0, 0.06),
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
                      final landscape = mq.orientation == Orientation.landscape;
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
                            child: _CmNumericKeypadPanel(
                              dialogContext: dialogCtx,
                              label: label,
                              initialText: controller.text,
                              allowDecimal: allowDecimal,
                              maxDecimalPlaces: maxDecimalPlaces,
                              landscape: landscape,
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

    if (!mounted || result == null) return;
    final normalized = normalizeVehicleTripNumericText(result);
    if (controller.text != normalized) {
      controller.text = normalized;
    }
    onChanged?.call(normalized);
    if (mounted) _scheduleUiRefresh();
  }

  Future<void> _openThaiTextPad({
    required TextEditingController controller,
    required String label,
    VoidCallback? onChanged,
    int? minLines,
    int? maxLines,
  }) async {
    if (!mounted) return;
    final result = await showThaiTextPad(
      context: context,
      label: label,
      initialText: controller.text,
      minLines: minLines ?? 2,
      maxLines: maxLines ?? 4,
    );
    if (!mounted || result == null) return;
    if (controller.text != result) {
      controller.text = result;
    }
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    onChanged?.call();
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

  /// แถวที่โหลดเข้าฟอร์มรถดรัมได้ (เว็บ Daily Wizard / เลกาซี category Vehicle)
  bool _isVehicleTripHydrateSource(AppTransaction t) {
    if (isMacroVehicleTransaction(t)) return false;
    if (t.description.contains('ทรายที่ล้างที่บ้าน')) return false;
    if (isHomeSandRoundCloseRow(t)) return false;
    if (t.category == 'DailyLog' &&
        (t.subCategory ?? '').trim().toLowerCase() == 'vehicletrip') {
      return true;
    }
    if (t.category == 'Vehicle') return true;
    return false;
  }

  _VehicleTripDraft _vehicleTripDraftFromAppTransaction(AppTransaction t) {
    final d = _VehicleTripDraft.empty();
    d.tripTxId = t.id;
    d.vehicleId = (t.vehicleId ?? '').trim();
    d.driverId = (t.driverId ?? '').trim();

    final wt = (t.workType ?? '').trim();
    if (wt == 'HalfDay') {
      d.workType = 'HalfDay';
    } else if (wt == 'Hourly') {
      d.workType = 'Hourly';
    } else {
      d.workType = 'FullDay';
    }

    final modeRaw = (t.tripBillingMode ?? '').trim();
    final isLump =
        modeRaw.toLowerCase() == 'lumpsum' || modeRaw == 'เหมา';
    d.tripBillingMode = isLump ? 'LumpSum' : 'PerTrip';

    final tm = t.tripMorning ?? 0;
    final ta = t.tripAfternoon ?? 0;
    d.tripMorning = _strNum(tm);
    d.tripAfternoon = _strNum(ta);
    d.tripMorningController.text = d.tripMorning;
    d.tripAfternoonController.text = d.tripAfternoon;

    final lumpVal = (t.perCarCubic ?? t.totalCubic ?? 0).toDouble();
    if (isLump) {
      d.lumpSumTotalCubic = lumpVal > 0 ? _strNum(lumpVal) : '';
      d.lumpSumTotalCubicController.text = d.lumpSumTotalCubic;
      d.cubicPerTrip = '';
      d.cubicPerTripController.clear();
    } else {
      d.lumpSumTotalCubic = '';
      d.lumpSumTotalCubicController.clear();
      final cptVal = t.cubicPerTrip ?? 0;
      d.cubicPerTrip = cptVal > 0 ? _strNum(cptVal) : '';
      d.cubicPerTripController.text = d.cubicPerTrip;
    }

    final wd = _stripRecorderSuffix(t.workDetails ?? '');
    d.workDetails = wd;
    d.workDetailsController.text = wd;

    if (d.workType == 'Hourly') {
      final oh = t.otHours;
      if (oh != null && oh > 0) {
        final hs = _strNum(oh);
        d.hourlyHours = hs;
        d.hourlyHoursController.text = hs;
      }
    }

    return d;
  }

  String _vehicleTripWorkTypeLabel(String? workType) {
    switch ((workType ?? '').trim()) {
      case 'HalfDay':
        return 'ครึ่งวัน';
      case 'Hourly':
        return 'รายชั่วโมง';
      default:
        return 'เต็มวัน';
    }
  }

  Widget _vehicleTripSavedDetailCard(AppTransaction t) {
    final vehicle = _vehicleLabelFromId((t.vehicleId ?? '').trim());
    final driver = _driverLabelFromId((t.driverId ?? '').trim());
    final mode = (t.tripBillingMode ?? '').trim();
    final isLump = mode.toLowerCase() == 'lumpsum' || mode == 'เหมา';
    final tm = t.tripMorning ?? 0;
    final ta = t.tripAfternoon ?? 0;
    final cubic = (t.perCarCubic ?? t.totalCubic ?? 0).toDouble();
    final cpt = t.cubicPerTrip ?? 0;
    final totalTripCount = (t.perCarTrips ?? t.tripCount ?? (tm + ta))
        .toDouble();
    final wd = _stripRecorderSuffix(t.workDetails ?? '').trim();
    final wtLabel = _vehicleTripWorkTypeLabel(t.workType);
    final modeLabel = isLump ? 'เหมา' : 'คิดเป็นเที่ยว';
    final tripLine = 'เช้า ${_strNum(tm)} เที่ยว • บ่าย ${_strNum(ta)} เที่ยว';
    final cubicLine = isLump
        ? 'รวม ${cubic.toStringAsFixed(0)} คิว (เหมา)'
        : '${_strNum(totalTripCount)} เที่ยว × ${_strNum(cpt)} คิว = ${cubic.toStringAsFixed(0)} คิว';
    final created = t.createdAt;
    final timeHint = created != null
        ? 'บันทึกในระบบ ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC5DCF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$vehicle • $driver',
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A4A7A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$modeLabel • $wtLabel',
            style: GoogleFonts.kanit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3D5A80),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tripLine,
            style: GoogleFonts.kanit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2C4D77),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cubicLine,
            style: GoogleFonts.kanit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          if (wd.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'รายละเอียด: $wd',
              style: GoogleFonts.kanit(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                height: 1.25,
              ),
            ),
          ],
          if (timeHint != null) ...[
            const SizedBox(height: 6),
            Text(
              timeHint,
              style: GoogleFonts.kanit(fontSize: 12, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVehicleTripSavedTodaySection() {
    final hydratedIds = _vehicleTripDrafts
        .map((r) => r.tripTxId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final saved = _moduleDayTransactions
        .where(transactionMatchesVehicleTripModuleList)
        .where((t) => !hydratedIds.contains(t.id))
        .toList();
    if (saved.isEmpty) {
      final hasHydratedRows =
          hydratedIds.isNotEmpty ||
          _vehicleTripDrafts.any((r) => r.tripTxId != null && r.tripTxId!.isNotEmpty);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          hasHydratedRows
              ? 'กำลังแก้ไขรายการด้านบน — กดบันทึกรถคันนี้เพื่ออัปเดต'
              : 'ยังไม่มีบันทึกรถดรัมในวันที่เลือก — เลือกรถด้านบนเพื่อเพิ่ม',
          textAlign: TextAlign.center,
          style: GoogleFonts.kanit(fontSize: 13.5, color: Colors.black45),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          'รายละเอียดรถที่บันทึกแล้ว (${saved.length} รายการ)',
          style: GoogleFonts.kanit(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF205A9A),
          ),
        ),
        const SizedBox(height: 8),
        ...saved.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  _loadVehicleTripIntoForm(t);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'โหลดรถ "${_vehicleLabelFromId((t.vehicleId ?? "").trim())}" มาแก้ไขด้านบน',
                        style: GoogleFonts.kanit(),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: _vehicleTripSavedDetailCard(t),
              ),
            ),
          ),
        ),
      ],
    );
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
              'บันทึกรถดรัมและจำนวนเที่ยว',
              style: GoogleFonts.kanit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F5FAF),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'บันทึกทีละคัน — เลือกรถที่บันทึกแล้วในวันนี้จะโหลดข้อมูลมาแก้ไขอัตโนมัติ หรือแตะการ์ดด้านล่าง — ช่วงเช้า/บ่าย ไม่บังคับ (ว่าง = 0)',
              style: GoogleFonts.kanit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            _VehicleTripRowsBoard(
              rows: _vehicleTripDrafts,
              cars: _vehicleTripCars(),
              drivers: _driverEmployees,
              workSuggestions: _vehicleWorkSuggestions,
              vehicleLabelFromId: _vehicleLabelFromId,
              driverLabelFromId: _driverLabelFromId,
              openNumericPad: _openNumericPad,
              onVehicleTripRowDelete: _handleVehicleTripRowDelete,
              onVehicleSelected: _hydrateVehicleRowFromExistingIfDuplicate,
              notifyParentRefresh: _scheduleUiRefresh,
            ),
            const SizedBox(height: 12),
            _SmoothPressable(
              enabled: !_saving,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveQuickEntry,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _saving ? 'กำลังบันทึก...' : 'บันทึกรถคันนี้',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            _buildVehicleTripSavedTodaySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroVehicleFormCard() {
    final macroCars = _fuelMacroCars();
    final row = _activeMacroVehicleDraft;
    final savedToday = _macroSavedVehicleCountToday;
    final isEditing = row.txId?.trim().isNotEmpty == true;
    final hasDraftData =
        row.vehicleId.trim().isNotEmpty ||
        row.driverId.trim().isNotEmpty ||
        row.workDetailsController.text.trim().isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE3ECF7)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'บันทึกการใช้รถแม็คโคร',
                style: GoogleFonts.kanit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F5FAF),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'บันทึกทีละคัน — เลือกรถ กรอกคนขับและรายละเอียด แล้วกดบันทึก หากรถคันเดิมในวันนี้จะโหลดข้อมูลมาแก้ไข',
                style: GoogleFonts.kanit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                  height: 1.35,
                ),
              ),
              if (savedToday > 0) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'บันทึกแล้ว $savedToday คันวันนี้',
                      style: GoogleFonts.kanit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                key: ObjectKey(row),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEditing
                        ? const Color(0xFF81C784)
                        : const Color(0xFFFFE0B2),
                    width: isEditing ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEditing
                                ? 'แก้ไขข้อมูลรถคันนี้ (บันทึกแล้ว)'
                                : 'กรอกรถคันถัดไป',
                            style: GoogleFonts.kanit(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isEditing
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                        if (isEditing || hasDraftData)
                          IconButton(
                            onPressed: () async {
                              await _handleMacroVehicleRowDelete(0);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: const Color(0xFFD14343),
                            tooltip: isEditing
                                ? 'ลบรายการที่บันทึก'
                                : 'ล้างฟอร์ม',
                          ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('macro_vehicle_${row.vehicleId}'),
                        isExpanded: true,
                        initialValue:
                            row.vehicleId.isEmpty ||
                                !macroCars.contains(row.vehicleId)
                            ? null
                            : row.vehicleId,
                        decoration: const InputDecoration(
                          labelText: 'รถแม็คโคร',
                          prefixIcon: Icon(Icons.construction_outlined),
                        ),
                        items: macroCars
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
                      onChanged: (v) async {
                        row.vehicleId = v ?? '';
                        await _onMacroVehicleSelected(row);
                      },
                    ),
                    if (macroCars.isEmpty)
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
                    DropdownButtonFormField<String>(
                      key: ValueKey('macro_driver_${row.driverId}'),
                        isExpanded: true,
                        initialValue:
                            row.driverId.isEmpty ||
                                !_macroDriverEmployees.any(
                                  (e) => e.id == row.driverId,
                                )
                            ? null
                            : row.driverId,
                        decoration: const InputDecoration(
                          labelText: 'คนขับ (ตำแหน่งคนขับรถแม็คโคร)',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: _macroDriverEmployees
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e.id,
                                child: Text(
                                  e.nickname.isNotEmpty ? e.nickname : e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.kanit(fontSize: 18),
                                ),
                              ),
                            )
                            .toList(),
                      onChanged: (v) {
                        row.driverId = v ?? '';
                        _scheduleUiRefresh();
                      },
                    ),
                    if (_macroDriverEmployees.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'ยังไม่พบพนักงานที่ตำแหน่งเป็น "คนขับรถแม็คโคร" (ตั้งค่าในเมนูพนักงาน)',
                          style: GoogleFonts.kanit(
                            color: const Color(0xFFD14343),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'FullDay',
                            label: Text('เต็มวัน'),
                          ),
                          ButtonSegment<String>(
                            value: 'HalfDay',
                            label: Text('ครึ่งวัน'),
                          ),
                        ],
                        selected: {
                          row.workType == 'HalfDay' ? 'HalfDay' : 'FullDay',
                        },
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setState(() => row.workType = selection.first);
                      },
                      style: ButtonStyle(
                        textStyle: WidgetStatePropertyAll(
                          GoogleFonts.kanit(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: row.workDetailsController,
                        minLines: 2,
                        maxLines: 4,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF1D2A3A),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียดงาน',
                        hintText:
                            'พิมพ์รายละเอียดงานเป็นภาษาไทย หรือกดชิปด้านล่าง',
                        hintMaxLines: 3,
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ช่วยกรอกด่วน',
                      style: GoogleFonts.kanit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แตะพื้นที่ว่างบนการ์ดเพื่อซ่อนแป้นพิมพ์',
                      style: GoogleFonts.kanit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in _kMacroWorkQuickPhrases)
                          ActionChip(
                            label: Text(
                              s,
                              style: GoogleFonts.kanit(fontSize: 12.5),
                            ),
                            onPressed: () => _applyMacroWorkPhrase(row, s),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SmoothPressable(
                enabled: !_saving,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveQuickEntry,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'กำลังบันทึก...'
                        : (isEditing ? 'อัปเดตคันนี้' : 'บันทึกคันนี้'),
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFFFF8F00),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
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
          const SizedBox(height: 6),
          Text(
            'บันทึกคันที่ 1 แล้วกดบันทึกได้เลย จากนั้นกรอกคันที่ 2 ต่อได้ (หรือกด «เพิ่มรถอีกคัน» เพื่อส่งหลายคันในครั้งเดียว)',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              height: 1.35,
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
                      prefixIcon: Icon(Icons.fire_truck_outlined),
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
    final rawHome = _drumsWashedAtHomeController.text.trim();
    final parsedHome = double.tryParse(rawHome);
    final homeForSummary =
        rawHome.isEmpty ? _homeSandTodayHomeSaved : (parsedHome ?? 0);
    final remain = (_homeSandBeforeToday + _homeSandTodayObtained - homeForSummary)
        .clamp(0, 999999)
        .toDouble();
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
          _AnimatedInputField(
            controller: _drumsWashedAtHomeController,
            onChanged: (_) => _scheduleUiRefresh(),
            keyboardType: TextInputType.number,
            readOnly: true,
            onTap: () {
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'คงเหลือก่อนวันนี้: ${_homeSandBeforeToday.toStringAsFixed(0)} • ได้เพิ่มวันนี้: ${_homeSandTodayObtained.toStringAsFixed(0)}\nล้างที่บ้านวันนี้: ${homeForSummary.toStringAsFixed(0)} • คงเหลือหลังล้าง: ${remain.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          if (_homeSandRoundTxId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF81C784)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'วันนี้ตัดรอบล้างทรายที่บ้านแล้ว',
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _saveHomeSandWashAllAndRoundCloseEntry,
            icon: const Icon(Icons.done_all_outlined),
            label: Text(
              'ล้างทั้งหมดแล้ว ตัดรอบ',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: const Color(0xFF00897B),
            ),
          ),
          const SizedBox(height: 10),
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

  void _ensureDefaultGeneralSubJob() {
    if (_generalSubJobs.isNotEmpty) return;
    _addGeneralSubJob(notify: false);
  }

  void _clearGeneralSubJobs() {
    for (final job in _generalSubJobs) {
      job.dispose();
    }
    _generalSubJobs.clear();
    for (final key in _laborAssignments.keys
        .where(_isGeneralAssignmentKey)
        .toList()) {
      _laborAssignments.remove(key);
      _laborBucketExpanded.remove(key);
    }
  }

  void _addGeneralSubJob({bool notify = true, String? id, String? title}) {
    final subId = id ?? _newGeneralSubJobId();
    final job = _GeneralSubJob(id: subId, name: title ?? '');
    _generalSubJobs.add(job);
    final key = _generalSubJobAssignmentKey(subId);
    _laborAssignments[key] = <String>{};
    _laborBucketExpanded[key] = false;
    if (notify) setState(() {});
  }

  void _removeGeneralSubJob(String subId) {
    if (_generalSubJobs.length <= 1) return;
    final key = _generalSubJobAssignmentKey(subId);
    _laborAssignments.remove(key);
    _laborBucketExpanded.remove(key);
    final idx = _generalSubJobs.indexWhere((j) => j.id == subId);
    if (idx >= 0) {
      _generalSubJobs[idx].dispose();
      _generalSubJobs.removeAt(idx);
    }
    setState(() {});
  }

  void _resetGeneralSubJobsAfterSave() {
    _clearGeneralSubJobs();
    _addGeneralSubJob(notify: false);
  }

  String _generalSubJobDisplayLabel(_GeneralSubJob job) {
    final name = job.nameController.text.trim();
    return name.isEmpty ? 'งานทั่วไป' : name;
  }

  _LaborWorkCategory _generalCategoryFor(_GeneralSubJob job) {
    final label = _generalSubJobDisplayLabel(job);
    final short =
        label.length > 18 ? '${label.substring(0, 16)}…' : label;
    return _LaborWorkCategory(
      id: _generalSubJobAssignmentKey(job.id),
      label: label,
      shortTitle: short,
      color: _kGeneralWorkColor,
    );
  }

  void _loadLaborAssignmentsFromTransaction(AppTransaction t) {
    for (final key in _laborAssignments.keys.toList()) {
      if (!_isGeneralAssignmentKey(key)) {
        _laborAssignments[key]?.clear();
      }
    }
    for (final key in _laborBucketExpanded.keys.toList()) {
      if (!_isGeneralAssignmentKey(key)) {
        _laborBucketExpanded[key] = false;
      }
    }
    _clearGeneralSubJobs();

    final loaded = t.workAssignments ?? const <String, List<String>>{};
    final labelByKey = <String, String>{};
    for (final row in t.customWorkCategories ?? const []) {
      final id = row['id']?.trim();
      final label = row['label']?.trim();
      if (id != null && label != null && label.isNotEmpty) {
        labelByKey[id] = label;
      }
    }

    final generalBuckets = <String, List<String>>{};
    if (loaded.isNotEmpty) {
      loaded.forEach((key, ids) {
        final list = ids
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isEmpty) return;
        final canon = normalizeLaborCanvasKey(key);
        if (_isGeneralAssignmentKey(canon) ||
            _isGeneralAssignmentKey(key) ||
            !isFlutterLaborCanvasCategoryKey(canon)) {
          final bucketKey = key.startsWith(_kGeneralWorkPrefix)
              ? key
              : (canon.startsWith(_kGeneralWorkPrefix) ? canon : canon);
          generalBuckets[bucketKey] = [
            ...?generalBuckets[bucketKey],
            ...list,
          ];
          return;
        }
        _laborAssignments[canon]!.addAll(list);
        _laborBucketExpanded[canon] = true;
      });
    } else if (t.employeeIds.isNotEmpty) {
      generalBuckets['general'] = t.employeeIds.toList();
    }

    final legacyName = _stripRecorderSuffix(
      t.workDetails ?? _laborWorkDetailsController.text,
    ).trim();

    if (generalBuckets.isEmpty) {
      _addGeneralSubJob(
        notify: false,
        title: legacyName.isNotEmpty ? legacyName : null,
      );
      return;
    }

    for (final entry in generalBuckets.entries) {
      late final String subId;
      late final String assignKey;
      if (entry.key.startsWith(_kGeneralWorkPrefix)) {
        subId = entry.key.substring(_kGeneralWorkPrefix.length);
        assignKey = entry.key;
      } else {
        subId = _newGeneralSubJobId();
        assignKey = _generalSubJobAssignmentKey(subId);
      }
      final title =
          labelByKey[entry.key] ??
          labelByKey[assignKey] ??
          ((entry.key == 'general' || entry.key == 'generalWork')
              ? legacyName
              : '');
      _addGeneralSubJob(notify: false, id: subId, title: title);
      _laborAssignments[assignKey] = entry.value.toSet();
      _laborBucketExpanded[assignKey] = entry.value.isNotEmpty;
    }
    if (_generalSubJobs.isEmpty) {
      _addGeneralSubJob(
        notify: false,
        title: legacyName.isNotEmpty ? legacyName : null,
      );
    }
  }

  List<Map<String, String>> _laborCategoryPayload() {
    return [
      ..._laborCategories.map((c) => {'id': c.id, 'label': c.label}),
      ..._generalSubJobs.map(
        (j) => {
          'id': _generalSubJobAssignmentKey(j.id),
          'label': _generalSubJobDisplayLabel(j),
        },
      ),
    ];
  }

  String _laborCategoryLabel(String id) {
    if (_isGeneralAssignmentKey(id)) {
      if (id.startsWith(_kGeneralWorkPrefix)) {
        final subId = id.substring(_kGeneralWorkPrefix.length);
        for (final job in _generalSubJobs) {
          if (job.id == subId) return _generalSubJobDisplayLabel(job);
        }
      }
      final legacy = _laborWorkDetailsController.text.trim();
      return legacy.isNotEmpty ? legacy : 'งานทั่วไป';
    }
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

  String _employeePositionBlob(Employee e) =>
      _employeePositionTokens(e).join(' ').toLowerCase();

  bool _isNightWatchPoolEmployee(Employee e) {
    final blob = _employeePositionBlob(e);
    return blob.contains('เฝ้ากลางคืน') ||
        blob.contains('เวรกลางคืน') ||
        blob.contains('กลางคืน') ||
        blob.contains('night');
  }

  bool _isSandSievePoolEmployee(Employee e) {
    for (final p in _employeePositionTokens(e)) {
      if (p.contains('ร่อน')) return true;
    }
    return false;
  }

  /// กลุ่ม «พนักงานทั่วไป» — เฉพาะตำแหน่งที่ระบุว่าเป็นพนักงานทั่วไป
  bool _isGeneralLaborPoolEmployee(Employee e) {
    for (final p in _employeePositionTokens(e)) {
      final t = p.trim();
      if (t.contains('พนักงานทั่วไป') || t == 'ทั่วไป') return true;
    }
    return false;
  }

  _LaborEmpPoolKind? _laborEmpPoolKindFor(Employee e) {
    if (_isMacroExcavatorDriverEmployee(e)) {
      return _LaborEmpPoolKind.excavatorMac;
    }
    if (_isSandSievePoolEmployee(e)) {
      return _LaborEmpPoolKind.sandSieve;
    }
    if (_isNightWatchPoolEmployee(e)) {
      return _LaborEmpPoolKind.nightWatch;
    }
    if (_isGeneralLaborPoolEmployee(e)) {
      return _LaborEmpPoolKind.generalLabor;
    }
    return null;
  }

  Widget _buildLaborCanvasBoard({
    _LaborDragBoardLayout layout = _LaborDragBoardLayout.combined,
  }) {
    return _LaborDragBoard(
      key: ValueKey('labor_drag_board_${layout.name}'),
      layout: layout,
      poolKind: _laborEmpPoolKind,
      onPoolKindChanged: (kind) => setState(() => _laborEmpPoolKind = kind),
      categories: _laborCategories,
      generalSubJobs: _generalSubJobs,
      generalCategoryFor: _generalCategoryFor,
      onAddGeneralSubJob: () => _addGeneralSubJob(),
      onRemoveGeneralSubJob: _removeGeneralSubJob,
      onGeneralJobNameChanged: () => setState(() {}),
      employees: _employees,
      employeesById: _employeesById,
      assignments: _laborAssignments,
      pickedIds: _laborPickedIds,
      bucketExpanded: _laborBucketExpanded,
      laborEmpPoolKind: _laborEmpPoolKindFor,
      onSharedStateChanged: () => setState(() {}),
      openThaiTextPad: _openThaiTextPad,
    );
  }

  double _laborPoolPinHeight(BuildContext context) {
    // 4 กลุ่มตำแหน่ง + คำแนะนำ — ต้องสูงพอไม่ให้ Column ล้น (เคย overflow ~24px ที่ 420)
    return (MediaQuery.sizeOf(context).height * 0.42).clamp(360.0, 500.0);
  }

  double _laborPoolAsideWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.36).clamp(272.0, 384.0);
  }

  bool _laborUseSideStickyPool(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 660;

  List<Widget> _quickInputScrollChildren({
    bool laborFormIncludePool = true,
    bool laborFormIncludeCanvas = true,
  }) {
    return [
      _buildModuleHistorySection(),
      RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7EDF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _isIncomeUtilitiesEntryMode
              ? _buildIncomeUtilitiesEntryCard()
              : _isSandWashMode
              ? _buildSandWashFormCard()
              : _isVehicleTripMode
              ? _buildVehicleTripFormCard()
              : _isMacroVehicleMode
              ? _buildMacroVehicleFormCard()
              : _isFuelMode
              ? _buildFuelFormCard()
              : _isHomeSandMode
              ? _buildHomeSandFormCard()
              : _isLaborLeaveMode
              ? _buildLaborLeaveFormCard()
              : _isLaborAdvanceMode
              ? _buildLaborAdvanceFormCard()
              : _isLaborMode
              ? _buildLaborFormCard(
                  includePool: laborFormIncludePool,
                  includeCanvas: laborFormIncludeCanvas,
                )
              : _isOtMode
              ? _buildOtFormCard()
              : _isDailyEventMode
              ? _buildDailyEventFormCard()
              : _buildFormCard(),
        ),
      ),
      Builder(
        builder: (context) {
          final kb = MediaQuery.viewInsetsOf(context).bottom;
          return SizedBox(height: kb);
        },
      ),
    ];
  }

  Widget _buildLaborPinnedScrollView({
    required bool isLargeTablet,
  }) {
    final poolH = _laborPoolPinHeight(context);
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: DevicePerf.isConstrainedDevice
          ? (isLargeTablet ? 380 : 220)
          : (isLargeTablet ? 1200 : 700),
      physics: _blockingModuleBootstrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          sliver: SliverToBoxAdapter(child: _buildModuleHistorySection()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(color: const Color(0xFFE7EDF5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _buildLaborFormCard(
                  includePool: false,
                  includeCanvas: false,
                  includeSave: false,
                  roundBottom: false,
                ),
              ),
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _LaborPoolPinHeaderDelegate(
            height: poolH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _LaborDragBoard(
                key: const ValueKey('labor_drag_board_pool_pinned'),
                layout: _LaborDragBoardLayout.poolOnly,
                poolKind: _laborEmpPoolKind,
                onPoolKindChanged: (kind) =>
                    setState(() => _laborEmpPoolKind = kind),
                categories: _laborCategories,
                generalSubJobs: _generalSubJobs,
                generalCategoryFor: _generalCategoryFor,
                onAddGeneralSubJob: () => _addGeneralSubJob(),
                onRemoveGeneralSubJob: _removeGeneralSubJob,
                onGeneralJobNameChanged: () => setState(() {}),
                employees: _employees,
                employeesById: _employeesById,
                assignments: _laborAssignments,
                pickedIds: _laborPickedIds,
                bucketExpanded: _laborBucketExpanded,
                laborEmpPoolKind: _laborEmpPoolKindFor,
                onSharedStateChanged: () => setState(() {}),
                openThaiTextPad: _openThaiTextPad,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  border: Border.all(color: const Color(0xFFE7EDF5)),
                ),
                child: _buildLaborFormCard(
                  includePool: false,
                  includeCanvas: true,
                  includeSave: true,
                  headerOnly: true,
                  roundTop: false,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Builder(
            builder: (context) {
              final kb = MediaQuery.viewInsetsOf(context).bottom;
              return SizedBox(height: kb);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLaborLeaveFormCard() {
    final employees = _employeesForLeavePicker();
    final days = double.tryParse(_leaveDaysController.text.trim()) ?? 0;
    final summaryDuration = _leaveIsHalfDay
        ? 'ครึ่งวัน (${_leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย'})'
        : (days == days.roundToDouble()
              ? '${days.round()} วัน'
              : '$days วัน');
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
            color: const Color(0xFF00897B).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'บันทึกลางาน',
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF00695C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'รูปแบบสอดคล้องเว็บแอพ: ค่าแรง/ลา → ลา',
            style: GoogleFonts.kanit(
              fontSize: 13,
              color: const Color(0xFF5B6D83),
            ),
          ),
          _employeeDataLoadProgressBanner(),
          const SizedBox(height: 8),
          Text(
            'ประเภทการลา',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF314C6D),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'Personal', label: Text('ลากิจ')),
                ButtonSegment<String>(value: 'Sick', label: Text('ลาป่วย')),
              ],
              selected: {_leaveTypeChoice},
              onSelectionChanged: (next) {
                setState(() => _leaveTypeChoice = next.first);
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ระยะเวลาลา',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF314C6D),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('เต็มวัน')),
                ButtonSegment<bool>(value: true, label: Text('ครึ่งวัน')),
              ],
              selected: {_leaveIsHalfDay},
              onSelectionChanged: (next) {
                if (next.isEmpty) return;
                setState(() {
                  _leaveIsHalfDay = next.first;
                  if (_leaveIsHalfDay) {
                    _leaveDaysController.text = '0.5';
                    _leaveHalfPart = 'morning';
                  } else if (_leaveDaysController.text.trim() == '0.5') {
                    _leaveDaysController.text = '1';
                  }
                });
              },
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
          if (_leaveIsHalfDay) ...[
            const SizedBox(height: 10),
            Text(
              'ช่วงครึ่งวัน',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: const Color(0xFF314C6D),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'morning',
                    label: Text('ครึ่งเช้า'),
                  ),
                  ButtonSegment<String>(
                    value: 'afternoon',
                    label: Text('ครึ่งบ่าย'),
                  ),
                ],
                selected: {_leaveHalfPart},
                onSelectionChanged: (next) {
                  if (next.isEmpty) return;
                  setState(() => _leaveHalfPart = next.first);
                },
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'วันเริ่มลา',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF314C6D),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickLeaveStartDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            label: Text(
              _formatDate(_leaveStartDate),
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'เลือกพนักงาน',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF314C6D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ไม่แสดงตำแหน่ง: คนขับรถ, รับจ้างรายวัน',
            style: GoogleFonts.kanit(
              fontSize: 12,
              color: const Color(0xFF64748B),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          employees.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'ยังไม่มีพนักงานที่เลือกได้ (ยกเว้นคนขับรถและรับจ้างรายวัน)',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8A6A2C),
                    ),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: employees.map((e) {
                    final id = e.id;
                    final selected = _selectedLeaveEmpIds.contains(id);
                    final name = _employeeUiDisplayName(e);
                    return FilterChip(
                      label: Text(name, style: GoogleFonts.kanit(fontSize: 13)),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _selectedLeaveEmpIds.remove(id);
                          } else {
                            _selectedLeaveEmpIds.add(id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
          const SizedBox(height: 10),
          if (!_leaveIsHalfDay) ...[
            Text(
              'จำนวนวัน',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: const Color(0xFF314C6D),
              ),
            ),
            const SizedBox(height: 6),
            _AnimatedInputField(
              controller: _leaveDaysController,
              decoration: const InputDecoration(
                labelText: 'จำนวนวัน',
                prefixIcon: Icon(Icons.timelapse_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              readOnly: true,
              onTap: () => _openNumericPad(
                controller: _leaveDaysController,
                label: 'จำนวนวันลา',
                allowDecimal: true,
                maxDecimalPlaces: 1,
                onChanged: (_) => setState(() {}),
              ),
              style: GoogleFonts.kanit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1D2A3A),
              ),
            ),
          ] else ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      color: Colors.teal.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'จำนวน 0.5 วัน (ครึ่งวัน — ${_leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย'})',
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _leaveReasonController,
            decoration: const InputDecoration(
              labelText: 'เหตุผลการลา',
              prefixIcon: Icon(Icons.note_alt_outlined),
              hintText: 'กด Enter เพื่อบันทึก',
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            maxLines: 1,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) {
              if (_saving) return;
              FocusManager.instance.primaryFocus?.unfocus();
              _saveQuickEntry();
            },
          ),
          if (_leaveIsHalfDay ||
              days > 0 ||
              _selectedLeaveEmpIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF2D39D)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'สรุป: ${_selectedLeaveEmpIds.length} คน · เริ่ม ${_formatDate(_leaveStartDate)} · $summaryDuration',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7A6A4A),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveQuickEntry,
              icon: const Icon(Icons.save_outlined),
              label: Text('บันทึกลางาน', style: GoogleFonts.kanit()),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _advanceBankDropdownItems() {
    final style = GoogleFonts.kanit(fontSize: 15);
    final items = <DropdownMenuItem<String>>[];
    final seen = <String>{};
    for (final b in kThaiBankNames) {
      if (seen.add(b)) {
        items.add(
          DropdownMenuItem<String>(
            value: b,
            child: Row(
              children: [
                ThaiBankBrandIcon(bankName: b, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(b, style: style, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      }
    }
    final cur = _advanceBank.trim();
    if (cur.isNotEmpty && !kThaiBankNames.contains(cur)) {
      items.add(
        DropdownMenuItem<String>(
          value: cur,
          child: Row(
            children: [
              ThaiBankBrandIcon(bankName: cur, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$cur (จากข้อมูลเดิม)',
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return items;
  }

  /// ค่าที่ตรงกับรายการใน dropdown หรือ null เมื่อยังไม่เลือก
  String? _advanceBankDropdownValue() {
    final cur = _advanceBank.trim();
    if (cur.isEmpty) return null;
    for (final it in _advanceBankDropdownItems()) {
      if (it.value == cur) return cur;
    }
    return null;
  }

  Widget _buildLaborAdvanceFormCard() {
    const advPrimary = Color(0xFFE65100);
    const advDeep = Color(0xFFBF360C);
    const warmSurface = Color(0xFFFFF8F1);
    final employees = _employeesForAdvancePicker();
    final nSel = _selectedAdvanceEmpIds.length;
    final per =
        double.tryParse(_advanceAmountPerPersonController.text.trim()) ?? 0;
    final totalHint = (nSel > 0 && per > 0) ? per * nSel : null;

    Widget advancePanel({required Widget child}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: warmSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE0B2)),
        ),
        child: child,
      );
    }

    Widget stepLabel(String n, String title, String hint) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: advPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              n,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: advDeep,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: const Color(0xFF37474F),
                  ),
                ),
                Text(
                  hint,
                  style: GoogleFonts.kanit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Material(
      elevation: 4,
      shadowColor: advPrimary.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFE0B2), Color(0xFFFFCC80)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: advPrimary.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.savings_rounded,
                      color: advPrimary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ส่งคำขอเบิกเงิน',
                          style: GoogleFonts.kanit(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4E342E),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'กรอกครบแล้วกดส่งด้านล่าง — ระบบจะให้ลงลายเซ็นก่อนส่ง และแจ้งผู้ดูแลผ่าน LINE',
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6D4C41),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _employeeDataLoadProgressBanner(),
                  const SizedBox(height: 4),
                  stepLabel(
                    '1',
                    'เลือกพนักงาน',
                    'เลือกได้หลายคน — ไม่แสดงคนขับรถและรับจ้างรายวัน',
                  ),
                  const SizedBox(height: 10),
                  advancePanel(
                    child: employees.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.groups_outlined,
                                  color: Colors.orange.shade700,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'ยังไม่มีรายการพนักงานในระบบ',
                                    style: GoogleFonts.kanit(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: const Color(0xFF8A6A2C),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: employees.map((e) {
                              final id = e.id;
                              final selected = _selectedAdvanceEmpIds.contains(
                                id,
                              );
                              final name = _employeeUiDisplayName(e);
                              return FilterChip(
                                showCheckmark: false,
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selected) ...[
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                        color: Color(0xFF2E7D32),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      name,
                                      style: GoogleFonts.kanit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                selected: selected,
                                selectedColor: advPrimary.withValues(
                                  alpha: 0.2,
                                ),
                                side: BorderSide(
                                  color: selected
                                      ? advPrimary
                                      : const Color(0xFFE0E0E0),
                                  width: selected ? 1.8 : 1,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    if (selected) {
                                      _selectedAdvanceEmpIds.remove(id);
                                    } else {
                                      _selectedAdvanceEmpIds.add(id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 18),
                  stepLabel(
                    '2',
                    'จำนวนเงินที่ขอ (บาทต่อคน)',
                    'แตะช่องเพื่อเปิดตัวเลข — ทุกคนที่เลือกใช้ยอดเดียวกัน',
                  ),
                  const SizedBox(height: 10),
                  _AnimatedInputField(
                    controller: _advanceAmountPerPersonController,
                    decoration: InputDecoration(
                      labelText: 'บาทต่อคน',
                      labelStyle: GoogleFonts.kanit(),
                      prefixIcon: const Icon(Icons.payments_outlined),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: advPrimary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    readOnly: true,
                    onTap: () => _openNumericPad(
                      controller: _advanceAmountPerPersonController,
                      label: 'จำนวนเงินที่ขอเบิก (บาทต่อคน)',
                      allowDecimal: true,
                      maxDecimalPlaces: 2,
                    ),
                    style: GoogleFonts.kanit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D2A3A),
                    ),
                  ),
                  if (totalHint != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9).withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC8E6C9)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calculate_rounded,
                            color: Colors.green.shade800,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ประมาณการรวม $nSel คน × ฿${_strNum(per)} = ฿${_strNum(totalHint)}',
                              style: GoogleFonts.kanit(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1B5E20),
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  stepLabel(
                    '3',
                    'รับเงินเมื่อไหร่ และรูปแบบใด',
                    'เลือกช่วงเวลาและเงินสดหรือโอน — ถ้าโอนให้กรอกธนาคารและเลขบัญชี',
                  ),
                  const SizedBox(height: 10),
                  advancePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'ช่วงรับเงิน',
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: const Color(0xFF455A64),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _AdvanceChoiceButton(
                                selected:
                                    _advancePayoutSlot == AdvanceGmMeta.midday,
                                label: 'กลางวัน',
                                icon: Icons.wb_sunny_rounded,
                                primaryColor: advPrimary,
                                onTap: () => setState(
                                  () =>
                                      _advancePayoutSlot = AdvanceGmMeta.midday,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AdvanceChoiceButton(
                                selected:
                                    _advancePayoutSlot == AdvanceGmMeta.evening,
                                label: 'เย็น',
                                icon: Icons.nightlight_round,
                                primaryColor: advPrimary,
                                onTap: () => setState(
                                  () => _advancePayoutSlot =
                                      AdvanceGmMeta.evening,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'รูปแบบการรับ',
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: const Color(0xFF455A64),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _AdvanceChoiceButton(
                                selected:
                                    _advancePaymentMethod == AdvanceGmMeta.cash,
                                label: 'เงินสด',
                                icon: Icons.payments_rounded,
                                primaryColor: advPrimary,
                                onTap: () => setState(
                                  () => _advancePaymentMethod =
                                      AdvanceGmMeta.cash,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AdvanceChoiceButton(
                                selected:
                                    _advancePaymentMethod ==
                                    AdvanceGmMeta.transfer,
                                label: 'เงินโอน',
                                icon: Icons.account_balance_wallet_rounded,
                                primaryColor: advPrimary,
                                onTap: () => setState(
                                  () => _advancePaymentMethod =
                                      AdvanceGmMeta.transfer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _advancePaymentMethod == AdvanceGmMeta.transfer
                        ? Column(
                            key: const ValueKey('adv_transfer'),
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  14,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFE3F2FD,
                                  ).withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF90CAF9),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.account_balance_rounded,
                                          color: Colors.blue.shade800,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'ข้อมูลบัญชีรับโอน',
                                          style: GoogleFonts.kanit(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: const Color(0xFF0D47A1),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'ธนาคาร',
                                        labelStyle: GoogleFonts.kanit(),
                                        prefixIcon: _advanceBank.trim().isEmpty
                                            ? const Icon(
                                                Icons.account_balance_outlined,
                                              )
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 10,
                                                  right: 2,
                                                ),
                                                child: ThaiBankBrandIcon(
                                                  bankName: _advanceBank.trim(),
                                                  size: 28,
                                                ),
                                              ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFBBDEFB),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: advPrimary,
                                            width: 1.4,
                                          ),
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          isExpanded: true,
                                          itemHeight: 52,
                                          value: _advanceBankDropdownValue(),
                                          hint: Text(
                                            'เลือกธนาคาร',
                                            style: GoogleFonts.kanit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF8A9BA8),
                                            ),
                                          ),
                                          items: _advanceBankDropdownItems(),
                                          onChanged: (v) => setState(
                                            () =>
                                                _advanceBank = (v ?? '').trim(),
                                          ),
                                          style: GoogleFonts.kanit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF1D2A3A),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _advanceAccountController,
                                      decoration: InputDecoration(
                                        labelText: 'เลขบัญชี',
                                        labelStyle: GoogleFonts.kanit(),
                                        prefixIcon: const Icon(
                                          Icons.numbers_outlined,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: advPrimary,
                                            width: 1.4,
                                          ),
                                        ),
                                      ),
                                      style: GoogleFonts.kanit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(
                            key: ValueKey('adv_no_transfer'),
                            height: 0,
                          ),
                  ),
                  const SizedBox(height: 20),
                  _SmoothPressable(
                    enabled: !_saving,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFE65100)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: advPrimary.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveQuickEntry,
                        icon: const Icon(Icons.draw_rounded),
                        label: Text(
                          'ส่งคำขอเบิกเงิน',
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'กดแล้วจะเปิดหน้าลายเซ็น — ยกเลิกได้จนกว่าจะยืนยัน',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.black45,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLaborFormCard({
    bool includePool = true,
    bool includeCanvas = true,
    bool includeSave = true,
    bool headerOnly = false,
    bool roundTop = true,
    bool roundBottom = true,
  }) {
    final assigned = _collectLaborAssignedIds().length;
    final showHeader = !headerOnly;
    final borderRadius = BorderRadius.vertical(
      top: roundTop ? const Radius.circular(18) : Radius.zero,
      bottom: roundBottom ? const Radius.circular(18) : Radius.zero,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0xFFE3ECF7)),
        boxShadow: roundTop && roundBottom
            ? [
                BoxShadow(
                  color: const Color(0xFF0F9EA8).withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'บันทึกค่าแรง',
                      style: GoogleFonts.kanit(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F5FAF),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'เลือกพนักงานตามกลุ่มตำแหน่ง → จัดลงกล่องงาน → บันทึก',
                      style: GoogleFonts.kanit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF5C6B7F),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (assigned > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 18,
                        color: Colors.green.shade800,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$assigned คนในงาน',
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (showHeader) _employeeDataLoadProgressBanner(),
          if (showHeader && (includePool || includeCanvas))
            const SizedBox(height: 10),
          if (includePool && includeCanvas)
            _LaborCanvasSection(
              child: _buildLaborCanvasBoard(
                layout: _LaborDragBoardLayout.combined,
              ),
            )
          else ...[
            if (includePool)
              _LaborCanvasSection(
                child: _buildLaborCanvasBoard(
                  layout: _LaborDragBoardLayout.poolOnly,
                ),
              ),
            if (includePool && includeCanvas) const SizedBox(height: 14),
            if (includeCanvas)
              _LaborCanvasSection(
                child: _buildLaborCanvasBoard(
                  layout: _LaborDragBoardLayout.canvasOnly,
                ),
              ),
          ],
          if (includeSave) ...[
            const SizedBox(height: 14),
            _SmoothPressable(
              enabled: !_saving,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveQuickEntry,
                icon: const Icon(Icons.save_outlined),
                label: Text('บันทึกค่าแรง', style: GoogleFonts.kanit()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Employee> _sortedEmployeesForOt() {
    final list = _employees.where((e) => !e.inactive).toList()
      ..sort(
        (a, b) =>
            _employeeUiDisplayName(a).compareTo(_employeeUiDisplayName(b)),
      );
    return list;
  }

  /// คีย์รวมคนซ้ำเมื่อชื่อแสดงต่างกันเฉพาะวงเล็บ เช่น "ชื่อ (นอน)" กับ "ชื่อ (แรงงาน)" — ใช้ในเบิกเงินและ OT
  String _employeeDisplayDedupeKey(Employee e) {
    var s = _employeeUiDisplayName(e);
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return e.id;
    return s.toLowerCase();
  }

  List<Employee> _employeesForOtPicker() {
    final seen = <String>{};
    final out = <Employee>[];
    for (final e in _sortedEmployeesForOt()) {
      if (!employeeEligibleForOtPicker(e)) continue;
      if (seen.add(_employeeDisplayDedupeKey(e))) {
        out.add(e);
      }
    }
    return out;
  }

  List<Employee> _employeesForLeavePicker() =>
      _sortedEmployeesForOt().where(employeeEligibleForLeavePicker).toList();

  List<Employee> _employeesForAdvancePicker() {
    final seen = <String>{};
    final out = <Employee>[];
    for (final e in _sortedEmployeesForOt()) {
      if (!employeeEligibleForAdvancePicker(e)) continue;
      if (seen.add(_employeeDisplayDedupeKey(e))) {
        out.add(e);
      }
    }
    return out;
  }

  /// ชื่อบนชิป OT — ตัดส่วนในวงเล็บท้ายชื่อออกเพื่อไม่ซ้ำกับแท็กอื่นของคนเดียวกัน
  String _employeeOtChipLabel(Employee e) {
    var s = _employeeUiDisplayName(e);
    s = s.replaceAll(RegExp(r'\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return _employeeUiDisplayName(e);
    return s;
  }

  Widget _buildOtEmployeeChips(_OtGroupDraft group) {
    final list = _employeesForOtPicker();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5E8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF3DEB8)),
        ),
        child: Text(
          'ยังไม่มีพนักงานที่เลือกได้ (ยกเว้นคนขับรถ เฝ้ากลางคืน รับจ้างรายวัน)',
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
        final name = _employeeOtChipLabel(e);
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
    final g = _activeOtGroup;
    final hours = double.tryParse(g.hoursController.text.trim()) ?? 0;
    final empCount = g.employeeIds.length;
    final hasValidPreview = empCount > 0 && hours > 0;
    final nextGroupNum = _otSavedGroupCountToday + 1;
    final savedToday = _otSavedGroupCountToday;

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
            'บันทึกทีละกลุ่ม — กรอกคนและชั่วโมง OT แล้วกดบันทึก จากนั้นกรอกกลุ่มถัดไปได้',
            style: GoogleFonts.kanit(
              fontSize: 13,
              color: const Color(0xFF5B6D83),
            ),
          ),
          if (savedToday > 0) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'บันทึกแล้ว $savedToday กลุ่มวันนี้ · กำลังกรอกกลุ่มที่ $nextGroupNum',
                  style: GoogleFonts.kanit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ),
            ),
          ],
          _employeeDataLoadProgressBanner(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCE8F5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'กลุ่มที่ $nextGroupNum',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF205A9A),
                  ),
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
                const SizedBox(height: 4),
                Text(
                  'ไม่แสดงเมื่อทุกตำแหน่งเป็นคนขับรถ / เฝ้ากลางคืน / รับจ้างรายวัน — หลายตำแหน่งยังแสดงถ้ามีตำแหน่งอื่น',
                  style: GoogleFonts.kanit(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    height: 1.3,
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
                    label: 'ชั่วโมง OT (กลุ่มที่ $nextGroupNum)',
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
          const SizedBox(height: 8),
          _AnimatedInputField(
            controller: _otDescController,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดงาน OT',
              prefixIcon: Icon(Icons.note_alt_outlined),
            ),
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 2,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
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
              child: !hasValidPreview
                  ? Text(
                      'เลือกพนักงานและระบุชั่วโมง OT ก่อนกดบันทึกกลุ่มนี้',
                      key: const ValueKey('ot-empty'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7A6A4A),
                      ),
                    )
                  : Text(
                      'กลุ่มที่ $nextGroupNum: $empCount คน × ${hours.toStringAsFixed(1)} ชม.',
                      key: ValueKey('$empCount|$hours'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      _releaseKeyboardFocus();
                      _saveQuickEntry();
                    },
              icon: const Icon(Icons.save_outlined),
              label: Text(
                'บันทึกกลุ่มนี้',
                style: GoogleFonts.kanit(),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _eventDescSuggestionsFromDay() {
    final seen = <String>{};
    final out = <String>[];
    for (final t in _moduleDayAllTransactions) {
      if (t.category != 'DailyLog') continue;
      if ((t.subCategory ?? '').trim() != 'Event') continue;
      final s = _stripRecorderSuffix(t.description).trim();
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
      if (out.length >= 10) break;
    }
    return out;
  }

  Widget _buildDailyEventFormCard() {
    const quickPhrases = <String>[
      'ฝนตก หยุดงาน',
      'เครื่องจักรเสีย',
      'ทรายไม่ครบ',
      'คนงานมาสาย',
      'งานเสร็จตามแผน',
      'ไฟฟ้าดับ',
      'อุบัติเหตุเล็กน้อย',
    ];
    final typeOpts = <({String v, String label})>[
      (v: 'info', label: 'ℹ️ ข้อมูล'),
      (v: 'warning', label: '⚠️ เตือน'),
      (v: 'problem', label: '🚨 ปัญหา'),
      (v: 'success', label: '✅ สำเร็จ'),
      (v: 'complaint', label: '📢 ข้อร้องเรียน'),
      (v: 'request', label: '📋 ความต้องการ'),
    ];
    final suggestions = _eventDescSuggestionsFromDay();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE3ECF7)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6D00).withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เหตุการณ์สำคัญประจำวัน',
                    style: GoogleFonts.kanit(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'ประเภท',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in typeOpts)
                  ChoiceChip(
                    label: Text(
                      o.label,
                      style: GoogleFonts.kanit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: _dailyEventType == o.v,
                    onSelected: (sel) {
                      if (sel) setState(() => _dailyEventType = o.v);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'ความสำคัญ',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'normal', label: Text('ปกติ')),
                ButtonSegment<String>(value: 'urgent', label: Text('ด่วน')),
              ],
              selected: {_dailyEventPriority},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _dailyEventPriority = s.first);
              },
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'แตะพื้นที่ว่างบนการ์ดเพื่อซ่อนแป้นพิมพ์',
              style: GoogleFonts.kanit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _dailyEventDescController,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D2A3A),
              ),
              decoration: const InputDecoration(
                labelText: 'รายละเอียดเหตุการณ์',
                hintText:
                    'พิมพ์รายละเอียดเป็นภาษาไทย เช่น ฝนตกหนักต้องหยุดงาน หรือกดวลีด่วนด้านล่าง',
                hintMaxLines: 3,
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
              onChanged: (_) => _scheduleUiRefresh(),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'จากประวัติ',
                style: GoogleFonts.kanit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(
                        s,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.kanit(fontSize: 12),
                      ),
                      onPressed: () {
                        setState(() => _dailyEventDescController.text = s);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'วลีด่วน',
              style: GoogleFonts.kanit(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tmpl in quickPhrases)
                  ActionChip(
                    label: Text(tmpl, style: GoogleFonts.kanit(fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        final prev = _dailyEventDescController.text.trim();
                        _dailyEventDescController.text = prev.isEmpty
                            ? tmpl
                            : '$prev, $tmpl';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SmoothPressable(
              enabled: !_saving,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveQuickEntry,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _saving ? 'กำลังบันทึก...' : 'บันทึกเหตุการณ์',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
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

/// ปุ่มเลือกแบบการ์ด (กลางวัน/เย็น, เงินสด/โอน) — ไอคอน + เช็คเขียว + แอนิเมชั่นกด
class _AdvanceChoiceButton extends StatefulWidget {
  const _AdvanceChoiceButton({
    required this.selected,
    required this.label,
    required this.icon,
    required this.primaryColor,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  State<_AdvanceChoiceButton> createState() => _AdvanceChoiceButtonState();
}

class _AdvanceChoiceButtonState extends State<_AdvanceChoiceButton> {
  double _pressedScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressedScale = 0.96),
      onTapCancel: () => setState(() => _pressedScale = 1.0),
      onTapUp: (_) {
        setState(() => _pressedScale = 1.0);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressedScale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.primaryColor.withValues(alpha: 0.12)
                : const Color(0xFFF4F6F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? widget.primaryColor
                  : const Color(0xFFE0E6ED),
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 24,
                color: widget.selected
                    ? widget.primaryColor
                    : const Color(0xFF78909C),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: widget.selected
                        ? const Color(0xFF1D2A3A)
                        : const Color(0xFF546E7A),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: widget.selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey<String>('${widget.label}_on'),
                        color: const Color(0xFF2E7D32),
                        size: 26,
                      )
                    : SizedBox(
                        key: ValueKey<String>('${widget.label}_off'),
                        width: 26,
                        height: 26,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// แป้นตัวเลขลอย — state แยกจาก [QuickInputScreen] เพื่อลดการรีบิลด์และแลคเวลากดเลข
class _CmNumericKeypadPanel extends StatefulWidget {
  const _CmNumericKeypadPanel({
    required this.dialogContext,
    required this.label,
    required this.initialText,
    required this.allowDecimal,
    required this.maxDecimalPlaces,
    required this.landscape,
  });

  final BuildContext dialogContext;
  final String label;
  final String initialText;
  final bool allowDecimal;
  final int maxDecimalPlaces;
  final bool landscape;

  @override
  State<_CmNumericKeypadPanel> createState() => _CmNumericKeypadPanelState();
}

class _CmNumericKeypadPanelState extends State<_CmNumericKeypadPanel> {
  late String _digits;

  @override
  void initState() {
    super.initState();
    _digits = widget.initialText;
  }

  void _tapDigit(String k) {
    if (k == '.' && !widget.allowDecimal) return;
    if (k == '.') {
      if (_digits.contains('.')) return;
      HapticFeedback.selectionClick();
      setState(() {
        _digits = _digits.isEmpty ? '0.' : '$_digits.';
      });
      return;
    }
    if (widget.allowDecimal && _digits.contains('.')) {
      final idx = _digits.indexOf('.');
      final decimals = _digits.substring(idx + 1);
      if (decimals.length >= widget.maxDecimalPlaces) return;
    }
    HapticFeedback.selectionClick();
    setState(() => _digits += k);
  }

  void _clear() {
    HapticFeedback.selectionClick();
    setState(() => _digits = '');
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _confirm() {
    Navigator.of(widget.dialogContext).pop(_digits);
  }

  @override
  Widget build(BuildContext context) {
    final ls = widget.landscape;
    final keyH = ls ? 42.0 : 52.0;
    final gap = ls ? 6.0 : 8.0;
    final keyStyle = GoogleFonts.kanit(
      fontSize: ls ? 19.0 : 22.0,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1D2A3A),
    );
    final labelStyle = GoogleFonts.kanit(
      fontSize: ls ? 14.5 : 17,
      fontWeight: FontWeight.w800,
    );
    final previewStyle = GoogleFonts.kanit(
      fontSize: ls ? 17.0 : 21.0,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF1565C0),
    );

    Widget cell(Widget child) => Expanded(child: child);

    Widget digitKey(String d) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _tapDigit(d),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: keyH,
          child: Center(child: Text(d, style: keyStyle)),
        ),
      ),
    );

    Widget auxKey({
      required Color bg,
      required Color fg,
      required VoidCallback? onTap,
      required Widget child,
    }) {
      return Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: keyH,
            child: Center(child: child),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          ls ? 10 : 12,
          ls ? 8 : 10,
          ls ? 10 : 12,
          ls ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8E2EE)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: ls ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _digits.isEmpty ? '0' : _digits,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: previewStyle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: ls ? 6 : 10),
              Row(
                children: [
                  cell(digitKey('1')),
                  SizedBox(width: gap),
                  cell(digitKey('2')),
                  SizedBox(width: gap),
                  cell(digitKey('3')),
                ],
              ),
              SizedBox(height: gap),
              Row(
                children: [
                  cell(digitKey('4')),
                  SizedBox(width: gap),
                  cell(digitKey('5')),
                  SizedBox(width: gap),
                  cell(digitKey('6')),
                ],
              ),
              SizedBox(height: gap),
              Row(
                children: [
                  cell(digitKey('7')),
                  SizedBox(width: gap),
                  cell(digitKey('8')),
                  SizedBox(width: gap),
                  cell(digitKey('9')),
                ],
              ),
              SizedBox(height: gap),
              Row(
                children: [
                  cell(
                    auxKey(
                      bg: const Color(0xFFFFEFEF),
                      fg: const Color(0xFFD64545),
                      onTap: _clear,
                      child: Text(
                        'ล้าง',
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w700,
                          fontSize: ls ? 13.0 : 14.5,
                          color: const Color(0xFFD64545),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  cell(digitKey('0')),
                  SizedBox(width: gap),
                  if (widget.allowDecimal) cell(digitKey('.')),
                  if (widget.allowDecimal) SizedBox(width: gap),
                  cell(
                    auxKey(
                      bg: const Color(0xFFE9F1FF),
                      fg: const Color(0xFF1565C0),
                      onTap: _backspace,
                      child: const Icon(Icons.backspace_outlined),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ls ? 6 : 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: Icon(Icons.check_circle_outline, size: ls ? 20 : 24),
                  label: Text(
                    'เสร็จสิ้น',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: ls ? 15.5 : 19,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(ls ? 44 : 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
}

class _AnimatedInputField extends StatefulWidget {
  const _AnimatedInputField({
    required this.controller,
    required this.decoration,
    this.keyboardType,
    this.onChanged,
    this.onFieldSubmitted,
    this.style,
    this.textInputAction,
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
    this.minLines,
    this.maxLines,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextStyle? style;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final VoidCallback? onTap;
  final int? minLines;
  final int? maxLines;

  @override
  State<_AnimatedInputField> createState() => _AnimatedInputFieldState();
}

typedef _OpenNumericPad =
    void Function({
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
    required this.onVehicleTripRowDelete,
    required this.onVehicleSelected,
    required this.notifyParentRefresh,
  });

  final List<_VehicleTripDraft> rows;
  final List<String> cars;
  final List<Employee> drivers;
  final List<String> workSuggestions;
  final String Function(String vehicleId) vehicleLabelFromId;
  final String Function(String driverId) driverLabelFromId;
  final _OpenNumericPad openNumericPad;
  final Future<void> Function(int index) onVehicleTripRowDelete;
  final void Function(_VehicleTripDraft row, String vehicleId) onVehicleSelected;
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
      final rowTrips = morning + afternoon;
      sumTrips += rowTrips;
      if (row.tripBillingMode == 'LumpSum') {
        sumCubic += double.tryParse(row.lumpSumTotalCubic) ?? 0;
      } else {
        final perTrip = double.tryParse(row.cubicPerTrip) ?? 0;
        sumCubic += rowTrips * perTrip;
      }
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
            canDelete:
                widget.rows.length > 1 ||
                (row.tripTxId?.trim().isNotEmpty ?? false),
            cars: widget.cars,
            drivers: widget.drivers,
            workSuggestions: widget.workSuggestions,
            vehicleLabelFromId: widget.vehicleLabelFromId,
            driverLabelFromId: widget.driverLabelFromId,
            openNumericPad: widget.openNumericPad,
            onVehicleSelected: widget.onVehicleSelected,
            onDelete: () async {
              await widget.onVehicleTripRowDelete(index);
              if (!mounted) return;
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
                color: agg.sumTrips > 0 || agg.sumCubic > 0
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
    required this.onVehicleSelected,
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
  final void Function(_VehicleTripDraft row, String vehicleId) onVehicleSelected;
  final Future<void> Function() onDelete;
  final VoidCallback onChanged;

  @override
  State<_VehicleTripRowItem> createState() => _VehicleTripRowItemState();
}

class _VehicleTripRowItemState extends State<_VehicleTripRowItem> {
  List<String> _vehicleTripDropdownCars(String currentVehicleId) {
    final cur = currentVehicleId.trim();
    if (cur.isEmpty || widget.cars.contains(cur)) return widget.cars;
    return [cur, ...widget.cars];
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final isLump = row.tripBillingMode == 'LumpSum';
    final tripM = double.tryParse(row.tripMorning) ?? 0;
    final tripA = double.tryParse(row.tripAfternoon) ?? 0;
    final rowTrips = tripM + tripA;
    final rowCubic = isLump
        ? (double.tryParse(row.lumpSumTotalCubic) ?? 0)
        : rowTrips * (double.tryParse(row.cubicPerTrip) ?? 0);
    final vLabel = widget.vehicleLabelFromId(row.vehicleId);
    final dLabel = widget.driverLabelFromId(row.driverId);
    final vehicleOptions = _vehicleTripDropdownCars(row.vehicleId);
    final tripPart =
        'เช้า ${_QuickInputScreenState._strNum(tripM)} • บ่าย ${_QuickInputScreenState._strNum(tripA)} เที่ยว';
    final summaryLine = isLump
        ? '$vLabel • $dLabel • $tripPart • เหมา ${rowCubic.toStringAsFixed(0)} คิว'
        : '$vLabel • $dLabel • $tripPart • ${rowTrips.toStringAsFixed(0)} เที่ยวรวม • ${rowCubic.toStringAsFixed(0)} คิว';
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
              Flexible(
                child: Text(
                  row.tripTxId != null && row.tripTxId!.isNotEmpty
                      ? 'แก้ไขรายการเดิม'
                      : 'เพิ่มรถคันใหม่',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF205A9A),
                  ),
                ),
              ),
              if (row.tripTxId != null && row.tripTxId!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'มีข้อมูลแล้ว',
                      style: GoogleFonts.kanit(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                  ),
                ),
              if (widget.canDelete) ...[
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    await widget.onDelete();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFD14343),
                  tooltip: 'ลบคันนี้',
                ),
              ],
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
                    prefixIcon: Icon(Icons.fire_truck_outlined),
                  ),
                  items: vehicleOptions
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
                    setState(() => row.vehicleId = id);
                    widget.onVehicleSelected(row, id);
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('driver_${widget.index}_${row.driverId}'),
                  isExpanded: true,
                  initialValue:
                      row.driverId.isEmpty ||
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
                ButtonSegment<String>(
                  value: 'HalfDay',
                  label: Text('ครึ่งวัน'),
                ),
                ButtonSegment<String>(
                  value: 'Hourly',
                  label: Text('รายชั่วโมง'),
                ),
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
            decoration: InputDecoration(
              labelText: 'รายละเอียดงาน',
              hintText:
                  'พิมพ์ได้ หรือกดชิป «ขนทรายล้าง» / «ขนทรายถม» ด้านล่าง',
              hintStyle: GoogleFonts.kanit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black45,
              ),
              prefixIcon: const Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ช่วยกรอก',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final phrase
                  in _QuickInputScreenState._kVehicleDrumWorkQuickPhrases)
                ActionChip(
                  label: Text(phrase, style: GoogleFonts.kanit(fontSize: 13.5)),
                  onPressed: () {
                    _QuickInputScreenState._applyVehicleDrumWorkPhrase(
                      row,
                      phrase,
                    );
                    setState(() {});
                    widget.onChanged();
                  },
                ),
            ],
          ),
          if (widget.workSuggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'จากประวัติการบันทึก',
              style: GoogleFonts.kanit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE0B2)),
            ),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'LumpSum', label: Text('เหมา')),
                ButtonSegment<String>(
                  value: 'PerTrip',
                  label: Text('คิดเป็นเที่ยว'),
                ),
              ],
              selected: {row.tripBillingMode},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() => row.tripBillingMode = selection.first);
                widget.onChanged();
              },
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.tripMorningController,
                  readOnly: true,
                  onTap: () => widget.openNumericPad(
                    controller: row.tripMorningController,
                    label: 'ช่วงเช้า (เที่ยว) — ไม่บังคับ',
                    onChanged: (v) {
                      final n =
                          _QuickInputScreenState.normalizeVehicleTripNumericText(
                            v,
                          );
                      row.tripMorning = n;
                      if (row.tripMorningController.text != n) {
                        row.tripMorningController.text = n;
                      }
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'ช่วงเช้า (เที่ยว)',
                    hintText: 'ไม่บังคับ · ว่าง = 0',
                    hintStyle: GoogleFonts.kanit(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                    prefixIcon: const Icon(Icons.wb_sunny_outlined),
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
                    label: 'ช่วงบ่าย (เที่ยว) — ไม่บังคับ',
                    onChanged: (v) {
                      final n =
                          _QuickInputScreenState.normalizeVehicleTripNumericText(
                            v,
                          );
                      row.tripAfternoon = n;
                      if (row.tripAfternoonController.text != n) {
                        row.tripAfternoonController.text = n;
                      }
                      widget.onChanged();
                      setState(() {});
                    },
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'ช่วงบ่าย (เที่ยว)',
                    hintText: 'ไม่บังคับ · ว่าง = 0',
                    hintStyle: GoogleFonts.kanit(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                    prefixIcon: const Icon(Icons.nightlight_outlined),
                  ),
                ),
              ),
            ],
          ),
          if (row.tripBillingMode == 'LumpSum') ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: row.lumpSumTotalCubicController,
              readOnly: true,
              onTap: () => widget.openNumericPad(
                controller: row.lumpSumTotalCubicController,
                label: 'รวมคิว (เหมา)',
                onChanged: (v) {
                  final n =
                      _QuickInputScreenState.normalizeVehicleTripNumericText(v);
                  row.lumpSumTotalCubic = n;
                  if (row.lumpSumTotalCubicController.text != n) {
                    row.lumpSumTotalCubicController.text = n;
                  }
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
                labelText: 'รวมคิว (เหมา)',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: row.cubicPerTripController,
              readOnly: true,
              onTap: () => widget.openNumericPad(
                controller: row.cubicPerTripController,
                label: 'คิวต่อเที่ยว',
                onChanged: (v) {
                  final n =
                      _QuickInputScreenState.normalizeVehicleTripNumericText(v);
                  row.cubicPerTrip = n;
                  if (row.cubicPerTripController.text != n) {
                    row.cubicPerTripController.text = n;
                  }
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
          ],
          const SizedBox(height: 8),
          Text(
            summaryLine,
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

enum _LaborEmpPoolKind { sandSieve, excavatorMac, nightWatch, generalLabor }

const _sandSievePoolCategoryIds = {
  'wash_old',
  'wash_new',
  'washHome',
  'sand_watch',
};
const _excavatorMacPoolCategoryIds = {'dig_haul'};
const _nightWatchPoolCategoryIds = {'night_shift', 'night_patrol'};

enum _LaborDragBoardLayout { combined, poolOnly, canvasOnly }

class _LaborDragBoard extends StatefulWidget {
  const _LaborDragBoard({
    super.key,
    this.layout = _LaborDragBoardLayout.combined,
    required this.poolKind,
    required this.onPoolKindChanged,
    required this.categories,
    required this.generalSubJobs,
    required this.generalCategoryFor,
    required this.onAddGeneralSubJob,
    required this.onRemoveGeneralSubJob,
    required this.onGeneralJobNameChanged,
    required this.employees,
    required this.employeesById,
    required this.assignments,
    required this.pickedIds,
    required this.bucketExpanded,
    required this.laborEmpPoolKind,
    required this.onSharedStateChanged,
    required this.openThaiTextPad,
  });

  final _LaborDragBoardLayout layout;
  final _LaborEmpPoolKind poolKind;
  final ValueChanged<_LaborEmpPoolKind> onPoolKindChanged;
  final List<_LaborWorkCategory> categories;
  final List<_GeneralSubJob> generalSubJobs;
  final _LaborWorkCategory Function(_GeneralSubJob job) generalCategoryFor;
  final VoidCallback onAddGeneralSubJob;
  final void Function(String subId) onRemoveGeneralSubJob;
  final VoidCallback onGeneralJobNameChanged;
  final List<Employee> employees;
  final Map<String, Employee> employeesById;
  final Map<String, Set<String>> assignments;
  final Set<String> pickedIds;
  final Map<String, bool> bucketExpanded;
  final _LaborEmpPoolKind? Function(Employee e) laborEmpPoolKind;
  final VoidCallback onSharedStateChanged;
  final Future<void> Function({
    required TextEditingController controller,
    required String label,
    VoidCallback? onChanged,
    int? minLines,
    int? maxLines,
  }) openThaiTextPad;

  @override
  State<_LaborDragBoard> createState() => _LaborDragBoardState();
}

class _LaborDragBoardState extends State<_LaborDragBoard> {
  void _syncBoard(VoidCallback fn) {
    setState(fn);
    widget.onSharedStateChanged();
  }

  bool get _showsGeneralWorkEditors =>
      widget.layout != _LaborDragBoardLayout.poolOnly;

  Widget _generalSubJobNameField(_GeneralSubJob job, Color parentColor) {
    return ListenableBuilder(
      listenable: job.nameController,
      builder: (context, _) {
        final text = job.nameController.text.trim();
        return Material(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.openThaiTextPad(
              controller: job.nameController,
              label: 'รายละเอียดงาน',
              onChanged: widget.onGeneralJobNameChanged,
              minLines: 2,
              maxLines: 4,
            ),
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                labelText: 'รายละเอียดงาน',
                labelStyle: GoogleFonts.kanit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
                suffixIcon: Icon(
                  Icons.edit_note_rounded,
                  size: 20,
                  color: parentColor.withValues(alpha: 0.75),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: parentColor.withValues(alpha: 0.35),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: parentColor.withValues(alpha: 0.28),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: parentColor,
                    width: 1.3,
                  ),
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text.isEmpty ? 'รายละเอียดงานที่ทำ' : text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: text.isEmpty
                        ? Colors.black38
                        : const Color(0xFF1D2A3A),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Set<String> _collectAssigned() {
    final out = <String>{};
    for (final entry in widget.assignments.values) {
      out.addAll(entry);
    }
    return out;
  }

  Widget _poolKindTile({
    required _LaborEmpPoolKind kind,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = widget.poolKind == kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? const Color(0xFFE8F1FF) : const Color(0xFFF6F8FC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? const Color(0xFF1565C0)
                : const Color(0xFFE1E8F0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onPoolKindChanged(kind),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF5B6D83),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.kanit(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1D2A3A),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.kanit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: Color(0xFF1565C0),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _employeePoolCard(List<Employee> available) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final empId = details.data;
        _syncBoard(() {
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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          decoration: BoxDecoration(
            color: isHovering
                ? const Color(0xFFDDEBFA)
                : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovering
                  ? const Color(0xFF73A6E8)
                  : const Color(0xFFE1E8F0),
            ),
          ),
          child: available.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'ไม่มีพนักงานในกลุ่มนี้ (หรือจัดลงกล่องงานหมดแล้ว)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: 13,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: available.map((e) {
                    final id = e.id;
                    final selected = widget.pickedIds.contains(id);
                    final name = _employeeUiDisplayName(e);
                    return LongPressDraggable<String>(
                      data: id,
                      feedback: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.transparent,
                        child: Chip(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          label: Text(
                            name,
                            style: GoogleFonts.kanit(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          backgroundColor: const Color(0xFF1565C0),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: FilterChip(
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          label: Text(
                            name,
                            style: GoogleFonts.kanit(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          selected: selected,
                          onSelected: null,
                        ),
                      ),
                      child: FilterChip(
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        showCheckmark: true,
                        selectedColor: const Color(0xFFBBDEFB),
                        checkmarkColor: const Color(0xFF0D47A1),
                        label: Text(
                          name,
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        selected: selected,
                        onSelected: (_) => _syncBoard(() {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignedIds = _collectAssigned();
    final mq = MediaQuery.sizeOf(context);
    final sideBySide = mq.width >= 660;

    final available =
        widget.employees
            .where((e) => !e.inactive)
            .where((e) => !assignedIds.contains(e.id))
            .where((e) => widget.laborEmpPoolKind(e) == widget.poolKind)
            .toList()
          ..sort(
            (a, b) =>
                _employeeUiDisplayName(a).compareTo(_employeeUiDisplayName(b)),
          );

    Widget bucketCard(_LaborWorkCategory category, {bool compact = false}) {
      final id = category.id;
      final ids = widget.assignments[id] ?? <String>{};
      final expanded = (widget.bucketExpanded[id] ?? false) || ids.isNotEmpty;
      return _LaborBucketCard(
        category: category,
        ids: ids,
        expanded: expanded,
        compact: compact,
        employeesById: widget.employeesById,
        onToggleExpanded: () => _syncBoard(() {
          widget.bucketExpanded[id] = !expanded;
        }),
        onMovePickedHere: widget.pickedIds.isEmpty
            ? null
            : () => _syncBoard(() {
                for (final bucket in widget.assignments.values) {
                  bucket.removeAll(widget.pickedIds);
                }
                widget.assignments[id]?.addAll(widget.pickedIds);
                widget.bucketExpanded[id] = true;
                widget.pickedIds.clear();
              }),
        onDropEmployee: (empId) => _syncBoard(() {
          for (final bucket in widget.assignments.values) {
            bucket.remove(empId);
          }
          widget.assignments[id]?.add(empId);
          widget.bucketExpanded[id] = true;
          widget.pickedIds.remove(empId);
        }),
        onDeleteEmployee: (empId) => _syncBoard(() {
          widget.assignments[id]?.remove(empId);
          if ((widget.assignments[id]?.isEmpty ?? true)) {
            widget.bucketExpanded[id] = false;
          }
        }),
      );
    }

    Widget generalWorkSection(double maxWidth) {
      const spacing = 10.0;
      const minCardWidth = 168.0;
      final nCol = ((maxWidth + spacing) / (minCardWidth + spacing))
          .floor()
          .clamp(1, 3);
      final itemWidth = (maxWidth - spacing * (nCol - 1)) / nCol;
      const parentColor = _kGeneralWorkColor;
      final assignedInGeneral = widget.generalSubJobs.fold<int>(0, (sum, job) {
        final key = widget.generalCategoryFor(job).id;
        return sum + (widget.assignments[key]?.length ?? 0);
      });

      Widget subJobTile(_GeneralSubJob job) {
        final category = widget.generalCategoryFor(job);
        final canRemove = widget.generalSubJobs.length > 1;
        final subAssigned = widget.assignments[category.id]?.length ?? 0;
        return SizedBox(
          width: itemWidth,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: parentColor.withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: parentColor.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 18,
                      color: parentColor.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'กล่องย่อย',
                        style: GoogleFonts.kanit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    if (subAssigned > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: parentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$subAssigned คน',
                          style: GoogleFonts.kanit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: parentColor,
                          ),
                        ),
                      ),
                    if (canRemove) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        tooltip: 'ลบกล่องย่อย',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        onPressed: () =>
                            widget.onRemoveGeneralSubJob(job.id),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                _generalSubJobNameField(job, parentColor),
                const SizedBox(height: 8),
                bucketCard(category, compact: true),
              ],
            ),
          ),
        );
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: parentColor.withValues(alpha: 0.42),
          ),
          boxShadow: [
            BoxShadow(
              color: parentColor.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, color: parentColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
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
                            Text(
                              'งานทั่วไป',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'เพิ่มกล่องย่อยด้านใน ระบุรายละเอียดงาน แล้วลากพนักงานลงแต่ละกล่อง',
                              style: GoogleFonts.kanit(
                                fontSize: 12,
                                height: 1.35,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: parentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${widget.generalSubJobs.length} กล่องย่อย · $assignedInGeneral คน',
                              style: GoogleFonts.kanit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: parentColor,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: widget.onAddGeneralSubJob,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              'เพิ่มกล่องย่อย',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F6FD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: parentColor.withValues(alpha: 0.22),
                        width: 1.2,
                      ),
                    ),
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: widget.generalSubJobs.map(subJobTile).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    List<_LaborWorkCategory> categoriesForPool(_LaborEmpPoolKind kind) {
      final Set<String> ids;
      switch (kind) {
        case _LaborEmpPoolKind.sandSieve:
          ids = _sandSievePoolCategoryIds;
          break;
        case _LaborEmpPoolKind.excavatorMac:
          ids = _excavatorMacPoolCategoryIds;
          break;
        case _LaborEmpPoolKind.nightWatch:
          ids = _nightWatchPoolCategoryIds;
          break;
        case _LaborEmpPoolKind.generalLabor:
          return const [];
      }
      return widget.categories.where((c) => ids.contains(c.id)).toList();
    }

    Widget bucketsGrid(double maxWidth) {
      const spacing = 10.0;
      const minCardWidth = 172.0;
      final nCol = ((maxWidth + spacing) / (minCardWidth + spacing))
          .floor()
          .clamp(1, 3);
      final itemWidth = (maxWidth - spacing * (nCol - 1)) / nCol;
      final visibleCategories = categoriesForPool(widget.poolKind);
      final showGeneralOnly = widget.poolKind == _LaborEmpPoolKind.generalLabor;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visibleCategories.isNotEmpty)
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: visibleCategories
                  .map(
                    (category) => SizedBox(
                      width: itemWidth,
                      child: bucketCard(category),
                    ),
                  )
                  .toList(),
            ),
          if (visibleCategories.isNotEmpty && showGeneralOnly)
            const SizedBox(height: 12),
          if (_showsGeneralWorkEditors &&
              (showGeneralOnly ||
                  widget.poolKind == _LaborEmpPoolKind.generalLabor))
            generalWorkSection(maxWidth),
        ],
      );
    }

    final poolColumn = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC8DCF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'เลือกพนักงาน',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.layout == _LaborDragBoardLayout.poolOnly
                  ? 'ตำแหน่งล็อกไว้ — เลื่อนหน้าจอแล้วรายการยังอยู่ที่เดิม'
                  : 'สลับกลุ่มตามตำแหน่ง — ลากลงกล่องงาน',
              style: GoogleFonts.kanit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _poolKindTile(
                      kind: _LaborEmpPoolKind.sandSieve,
                      icon: Icons.water_drop_outlined,
                      title: 'พนักงานร่อนทราย',
                      subtitle: 'ตำแหน่งมีคำว่า «ร่อน»',
                    ),
                    _poolKindTile(
                      kind: _LaborEmpPoolKind.excavatorMac,
                      icon: Icons.precision_manufacturing_outlined,
                      title: 'คนขับรถแม็คโคร',
                      subtitle: 'ตำแหน่งคนขับรถแม็คโคร/แมคโคร',
                    ),
                    _poolKindTile(
                      kind: _LaborEmpPoolKind.nightWatch,
                      icon: Icons.nightlight_round,
                      title: 'เฝ้ากลางคืน',
                      subtitle: 'ตำแหน่งเวร/เฝ้ากลางคืน',
                    ),
                    _poolKindTile(
                      kind: _LaborEmpPoolKind.generalLabor,
                      icon: Icons.groups_2_outlined,
                      title: 'พนักงานทั่วไป',
                      subtitle: 'เฉพาะตำแหน่งพนักงานทั่วไป',
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFE082)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 18,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'แตะชื่อเพื่อเลือกหลายคน · กดค้างแล้วลากไปกล่อง หรือกดปุ่ม «ย้ายมาที่นี่» ในกล่องงาน',
                                style: GoogleFonts.kanit(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF5D4037),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'รายชื่อในกลุ่ม',
                            style: GoogleFonts.kanit(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.pickedIds.isEmpty
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: widget.pickedIds.isEmpty
                                  ? const Color(0xFFCBD5E1)
                                  : const Color(0xFF64B5F6),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              '${widget.pickedIds.length} เลือก',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: widget.pickedIds.isEmpty
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF0D47A1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _employeePoolCard(available),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final canvasColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'กล่องงาน',
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: const Color(0xFF0D47A1),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'เลือกพนักงานด้านซ้าย → ลากหรือกด «ย้ายมาที่นี่» ในกล่อง',
          style: GoogleFonts.kanit(
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return bucketsGrid(constraints.maxWidth);
          },
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: assignedIds.isNotEmpty
                  ? const [
                      Color(0xFFE8F5E9),
                      Color(0xFFC8E6C9),
                    ]
                  : const [
                      Color(0xFFF1F5F9),
                      Color(0xFFE2E8F0),
                    ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: assignedIds.isNotEmpty
                  ? const Color(0xFF81C784)
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                assignedIds.isNotEmpty
                    ? Icons.groups_rounded
                    : Icons.info_outline_rounded,
                size: 22,
                color: assignedIds.isNotEmpty
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  assignedIds.isNotEmpty
                      ? 'จัดลงงานแล้ว ${assignedIds.length} คน'
                      : 'ยังไม่มีคนในกล่องงาน — เลือกพนักงานด้านซ้าย',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: assignedIds.isNotEmpty
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    Widget wrapBoardChrome(Widget child, {EdgeInsetsGeometry? padding}) {
      return Container(
        padding: padding ?? const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC5D9EF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
    }

    switch (widget.layout) {
      case _LaborDragBoardLayout.poolOnly:
        return wrapBoardChrome(
          LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
                  ? constraints.maxHeight
                  : mq.height * 0.72;
              return SizedBox(
                height: h,
                child: poolColumn,
              );
            },
          ),
        );
      case _LaborDragBoardLayout.canvasOnly:
        return wrapBoardChrome(canvasColumn);
      case _LaborDragBoardLayout.combined:
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : mq.width;
        final poolW = (w * 0.36).clamp(272.0, 384.0);
        final boardH = (mq.height * 0.58).clamp(360.0, 640.0);
        return wrapBoardChrome(
          SizedBox(
            height: boardH,
            child: sideBySide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: poolW, child: poolColumn),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          child: canvasColumn,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: 5,
                        child: poolColumn,
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: canvasColumn,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _LaborPoolPinHeaderDelegate extends SliverPersistentHeaderDelegate {
  _LaborPoolPinHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black26,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _LaborPoolPinHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

class _LaborBucketCard extends StatelessWidget {
  const _LaborBucketCard({
    required this.category,
    required this.ids,
    required this.expanded,
    this.compact = false,
    required this.employeesById,
    required this.onToggleExpanded,
    required this.onDropEmployee,
    required this.onDeleteEmployee,
    required this.onMovePickedHere,
  });

  final _LaborWorkCategory category;
  final Set<String> ids;
  final bool expanded;
  final bool compact;
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
        final canMove = onMovePickedHere != null;
        final title = category.shortTitle;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: category.color.withValues(
                alpha: isHovering ? 0.9 : 0.42,
              ),
              width: isHovering ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: category.color.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                color: category.color,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 8 : 10,
                  compact ? 6 : 8,
                  compact ? 4 : 6,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact)
                      Tooltip(
                        message: category.label,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kanit(
                            fontSize: 14,
                            height: 1.28,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    if (!compact) const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: category.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${ids.length} คน',
                            style: GoogleFonts.kanit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: category.color.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip: expanded ? 'ยุบรายชื่อ' : 'ดูรายชื่อ',
                          onPressed: onToggleExpanded,
                          icon: AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 22,
                              color: category.color.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                        child: hasMembers
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
                                        backgroundColor: category.color
                                            .withValues(alpha: 0.92),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.35,
                                      child: InputChip(
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 2,
                                        ),
                                        label: Text(
                                          label,
                                          style: GoogleFonts.kanit(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        onDeleted: null,
                                      ),
                                    ),
                                    child: InputChip(
                                      labelPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 2,
                                      ),
                                      label: Text(
                                        label,
                                        style: GoogleFonts.kanit(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      onDeleted: () =>
                                          onDeleteEmployee(empId),
                                    ),
                                  );
                                }).toList(),
                              )
                            : Row(
                                children: [
                                  Icon(
                                    Icons.touch_app_outlined,
                                    size: 16,
                                    color: category.color.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'ว่าง — ลากชื่อมาวาง',
                                      style: GoogleFonts.kanit(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      )
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: canMove
                      ? FilledButton.icon(
                          onPressed: onMovePickedHere,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'ย้ายมาที่นี่',
                            style: GoogleFonts.kanit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: category.color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.person_search_outlined,
                              size: 17),
                          label: Text(
                            'เลือกพนักงาน',
                            style: GoogleFonts.kanit(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF94A3B8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                        ),
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
    return RepaintBoundary(child: child);
  }
}

class _VehicleTripFormSection extends StatelessWidget {
  const _VehicleTripFormSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: child);
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

class _MacroVehicleDraft {
  _MacroVehicleDraft() : workDetailsController = TextEditingController();

  factory _MacroVehicleDraft.empty() => _MacroVehicleDraft();

  String? txId;
  String vehicleId = '';
  String driverId = '';
  String workType = 'FullDay';
  final TextEditingController workDetailsController;

  void dispose() {
    workDetailsController.dispose();
  }
}

class _VehicleTripDraft {
  _VehicleTripDraft()
    : workDetailsController = TextEditingController(),
      hourlyHoursController = TextEditingController(),
      tripMorningController = TextEditingController(),
      tripAfternoonController = TextEditingController(),
      cubicPerTripController = TextEditingController(),
      lumpSumTotalCubicController = TextEditingController();

  factory _VehicleTripDraft.empty() => _VehicleTripDraft();

  String? tripTxId;
  String vehicleId = '';
  String driverId = '';
  String workType = 'FullDay';

  /// PerTrip | LumpSum
  String tripBillingMode = 'LumpSum';
  String hourlyHours = '';
  String workDetails = '';
  String tripMorning = '';
  String tripAfternoon = '';
  String cubicPerTrip = '';
  String lumpSumTotalCubic = '';
  final TextEditingController workDetailsController;
  final TextEditingController hourlyHoursController;
  final TextEditingController tripMorningController;
  final TextEditingController tripAfternoonController;
  final TextEditingController cubicPerTripController;
  final TextEditingController lumpSumTotalCubicController;

  void dispose() {
    workDetailsController.dispose();
    hourlyHoursController.dispose();
    tripMorningController.dispose();
    tripAfternoonController.dispose();
    cubicPerTripController.dispose();
    lumpSumTotalCubicController.dispose();
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
    required this.shortTitle,
    required this.color,
  });

  final String id;
  final String label;
  final String shortTitle;
  final Color color;
}

class _GeneralSubJob {
  _GeneralSubJob({required this.id, String? name})
    : nameController = TextEditingController(text: name ?? '');

  final String id;
  final TextEditingController nameController;

  void dispose() => nameController.dispose();
}

class _AnimatedInputFieldState extends State<_AnimatedInputField> {
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
    // ไม่ห่อด้วย GestureDetector / AnimatedScale / Focus+setState — ลดการรีบิลด์และแย่งเฟรมกับแอนิเมชันคีย์บอร์ดระบบ
    return TextFormField(
      focusNode: _focusNode,
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      enableSuggestions: !widget.readOnly,
      autocorrect: !widget.readOnly,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
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
      onTap: widget.onTap,
      decoration: widget.decoration,
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
