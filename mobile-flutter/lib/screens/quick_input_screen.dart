import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../constants/thai_banks.dart';
import '../widgets/attendance_sub_mode_picker.dart';
import '../widgets/daily_record_day_picker.dart';
import '../widgets/fuel_sub_mode_picker.dart';
import '../widgets/fuel_time_picker_dialog.dart';
import '../widgets/thai_bank_brand_icon.dart';
import '../widgets/save_operation_feedback.dart';
import '../widgets/soft_press_button.dart';
import '../widgets/soft_sync_indicator.dart';
import '../widgets/thai_text_pad.dart';
import '../utils/app_haptics.dart';
import '../utils/advance_employee_filter.dart';
import '../utils/advance_line_notify.dart';
import '../utils/advance_work_details.dart';
import '../utils/attendance_session_times.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/fuel_stock.dart';
import '../utils/count_record_vehicle_defaults.dart';
import '../utils/labor_canvas_keys.dart';
import '../utils/device_perf.dart';
import '../services/mobile_error_report_service.dart';
import '../services/session_service.dart';
import '../services/local_data_cache.dart';
import '../services/count_record_offline_sync.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
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

    /// สถานะเน็ตจากแดชบอร์ด — false = ใช้คิวออฟไลน์สำหรับเมนูที่รองรับ
    this.serverOnlineHint = true,
  });

  final TransactionService service;
  final EmployeeService employeeService;
  final AdminUser? currentAdmin;

  /// ตั้งหมวดหมู่เริ่มต้นเมื่อเปิดจากการ์ดหน้าแรก
  final String? initialCategory;
  final String? appBarTitle;
  final DateTime? selectedDateForModule;
  final bool serverOnlineHint;

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
  // ค่ามาตรฐานคิวต่อเที่ยว = 3 คิว (รถดรัม/ดั๊ม และรถอื่นที่ไม่มีกฎเฉพาะ)
  return 3;
}

void _applyDefaultCubicForVehicleRow(_VehicleTripDraft row, String vehicleId) {
  final def = defaultCubicPerTripForVehicleName(vehicleId);
  if (def == null) return;
  final s = def == def.roundToDouble() ? '${def.toInt()}' : '$def';
  row.cubicPerTrip = s;
  row.cubicPerTripController.text = s;
}

/// หมวดเมนูบันทึกประจำวันที่ทำงานออฟไลน์ได้ (คิวเดียวกับ «บันทึกและนับจำนวน»)
const _kOfflineCapableModuleCategories = {
  'จำนวนเที่ยวรถ',
  'บันทึกการร่อนทราย',
  'เช็คชื่อ',
  'การใช้รถแม็คโคร',
  'น้ำมัน',
  'เหตุการณ์',
  'ลางาน',
};

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

/// รถแม็คโครหลักบนหน้าบันทึกน้ำมัน — จับคู่ชื่อเล่น (รุ่นเปลี่ยนได้จากการตั้งค่า)
const _kFuelPinnedVehicleNicknames = <String>[
  'น้องโกลเด้น',
  'พี่ยักษ์ใหญ่',
  'พี่เดอะฮัก',
];
const _kFuelPinnedVehicleCap = 3;

/// เลือกบันทึกรายจ่ายสาธารณูปโภคหรือรายรับประจำวัน
enum _IuEntryKind { expense, income }

class _QuickInputScreenState extends State<QuickInputScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
      id: 'sand_watch',
      label: 'เฝ้าท่าทราย',
      shortTitle: 'เฝ้าท่าทราย',
      color: Color(0xFFE64A9E),
    ),
    _LaborWorkCategory(
      id: 'night_shift',
      label: 'เวร/เฝ้ากลางคืน',
      shortTitle: 'เวร/เฝ้ากลางคืน',
      color: Color(0xFF7B5AE6),
    ),
    _LaborWorkCategory(
      id: 'dig_haul',
      label: 'ขุดขน',
      shortTitle: 'ขุดขน',
      color: Color(0xFF7962E6),
    ),
    _LaborWorkCategory(
      id: 'macro_driver',
      label: 'คนขับรถแม็คโคร',
      shortTitle: 'คนขับแม็คโคร',
      color: Color(0xFFEF6C00),
    ),
  ];
  static const Color _bg = Color(0xFFFDFEFF);
  static const Color _macroAccent = Color(0xFF0F9EA8);
  static const Color _macroAccentInk = Color(0xFF00838F);
  static const Color _macroAccentTint = Color(0xFFE0F2F1);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final TextEditingController _categoryController;
  /// จำนวนคิวที่ร่อน — รวมเครื่องใหม่/เก่าเป็นค่าเดียวต่อช่วงเวลา
  final _sandQtyMorningController = TextEditingController();
  final _sandQtyAfternoonController = TextEditingController();
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
  /// id เหตุการณ์ที่กำลังแก้ไข — null = บันทึกใหม่
  String? _dailyEventTxId;
  final _leaveReasonController = TextEditingController();
  final _leaveDaysController = TextEditingController(text: '1');
  final _advanceAmountPerPersonController = TextEditingController();

  /// ชื่อธนาคารเต็มจากรายการ dropdown (โหมดโอน)
  String _advanceBank = '';
  final _advanceAccountController = TextEditingController();
  final _utilitiesTypeController = TextEditingController();
  final _iuPartyNameController = TextEditingController();
  final _iuPartyAddressController = TextEditingController();
  final _iuPartyDetailController = TextEditingController();
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
  Map<String, String> _vehicleDefaultDrivers = const {};

  late DateTime _selectedDate;
  late DateTime _leaveStartDate;

  /// วันสุดท้ายของการลา — เท่ากับวันเริ่มเมื่อลาวันเดียว
  late DateTime _leaveEndDate;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;
  Timer? _uiRebuildDebounce;
  Timer? _remoteRefreshDebounce;
  Timer? _pollFallbackTimer;
  static const Duration _remoteRefreshDebounceDelay =
      Duration(milliseconds: 300);
  static const Duration _pollFallbackInterval = Duration(minutes: 5);
  bool _saving = false;
  String? _activeSignatureNote;
  List<String> _otDescSuggestions = const [];
  List<AppTransaction> _moduleDayTransactions = const [];

  /// ธุรกรรมทั้งหมดของวันที่เลือก (ใช้ดึงชื่อจากบันทึกการทำงาน / Labor ขณะเปิดเมนูร่อนทราย)
  List<AppTransaction> _moduleDayAllTransactions = const [];
  bool _moduleDayLoading = false;

  /// กันผล _loadModuleTransactions ที่เสร็จช้ากว่า (เช่น โหลดตอนเปิดหน้าแล้วบันทึกเสร็จก่อน) ไป dispose draft ที่ใช้อยู่
  int _moduleTransactionsLoadGeneration = 0;

  bool get _hasTrackedModuleCategory =>
      (widget.initialCategory?.trim().isNotEmpty ?? false);

  /// ระหว่างรอธุรกรรมของวันที่เลือก และ (ถ้าเป็นเมนูค่าแรง/OT) รายชื่อพนักงาน
  bool get _blockingModuleBootstrap {
    if (!_hasTrackedModuleCategory) return false;
    if (_moduleDayLoading && _moduleDayTransactions.isEmpty) return true;
    if (_showsEmployeeLoadingUi && _employeesLoading && _employees.isEmpty) {
      return true;
    }
    return false;
  }

  bool get _softModuleRefreshing =>
      _hasTrackedModuleCategory &&
      _moduleDayLoading &&
      _moduleDayTransactions.isNotEmpty;

  /// แสดงรายการประวัติเฉพาะเมื่อผู้ใช้กด (ค่าเริ่มต้นซ่อน)
  bool _moduleHistoryVisible = false;

  /// แถวที่โหลดจากระบบ (คงค่า created_at เดิมเมื่ออัปเดตซ้ำ)
  final Set<String> _persistOmitCreatedForIds = {};

  /// แถวที่บันทึกในวงจรนี้แล้ว — อย่ายิง created_at ซ้ำ
  final Set<String> _persistOmitCreatedSessionIds = {};
  final Map<String, String> _sandRowIdsByKey = {};
  List<String> _sandOperatorNames = const [];
  String? _laborTxId;
  String? _homeSandTxId;
  String? _homeSandRoundTxId;
  String? _genericTxId;
  bool get _isSandWashMode =>
      (widget.initialCategory ?? '').contains('ร่อนทราย');
  /// เมนูบันทึกรถดรัม / จำนวนเที่ยว — จับทั้งรหัสหมวดและชื่อที่แสดง
  bool get _isVehicleTripMode {
    final c = (widget.initialCategory ?? '').trim();
    return c.contains('เที่ยวรถ') || c.contains('รถดรัม');
  }
  bool get _isFuelMode => (widget.initialCategory ?? '').contains('น้ำมัน');
  bool get _isMacroVehicleMode => widget.initialCategory == 'การใช้รถแม็คโคร';

  bool get _isOfflineCapableCategory =>
      _kOfflineCapableModuleCategories.contains(
        widget.initialCategory?.trim(),
      );

  bool _lastPersistQueued = false;

  void _deferDisposeVehicleDrafts(Iterable<_VehicleTripDraft> rows) {
    final old = rows.toList();
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in old) {
        row.dispose();
      }
    });
  }

  void _deferDisposeMacroVehicleDrafts(Iterable<_MacroVehicleDraft> rows) {
    final old = rows.toList();
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in old) {
        row.dispose();
      }
    });
  }

  void _deferDisposeFuelVehicleDrafts(Iterable<_FuelVehicleDraft> rows) {
    final old = rows.toList();
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in old) {
        row.dispose();
      }
    });
  }

  void _hydrateMacroDraftFromTransaction(
    _MacroVehicleDraft row,
    AppTransaction t,
  ) {
    row.txId = t.id;
    final vid = (t.vehicleId ?? '').trim();
    if (vid.isNotEmpty) row.vehicleId = vid;
    row.driverId = (t.driverId ?? '').trim();
    final wt = (t.workType ?? '').trim();
    row.workType = wt == 'HalfDay' ? 'HalfDay' : 'FullDay';
    if (!row.isDisposed) {
      row.workDetailsController.text = _stripRecorderSuffix(
        t.workDetails ?? '',
      );
    }
    _persistOmitCreatedForIds.add(t.id);
  }

  /// สร้างแถวบันทึกแม็คโคร 1 แถวต่อ 1 รถจากตั้งค่าแอพ
  void _syncMacroVehicleDraftsFromMacroCars({
    Iterable<AppTransaction>? dayRows,
    bool forceHydrate = false,
  }) {
    final cars = _fuelMacroCars();
    final ymd = _quickYmd(_selectedDate);
    final byVehicle = <String, AppTransaction>{};
    final source = dayRows ?? _moduleDayTransactions;
    for (final t in source) {
      if (t.date.trim() != ymd.trim()) continue;
      if (!isMacroVehicleTransaction(t)) continue;
      final vid = (t.vehicleId ?? '').trim();
      if (vid.isEmpty) continue;
      final existing = byVehicle[vid];
      if (existing == null) {
        byVehicle[vid] = t;
        continue;
      }
      // แถวที่ยังค้างคิวออฟไลน์ไม่มี createdAt — ถือว่าใหม่กว่าแถวที่ขึ้นเซิร์ฟเวอร์แล้ว
      final ta = t.createdAt;
      final ea = existing.createdAt;
      if (ta == null || (ea != null && ta.isAfter(ea))) {
        byVehicle[vid] = t;
      }
    }

    final preserved = <String, _MacroVehicleDraft>{
      for (final r in _macroVehicleDrafts)
        if (r.vehicleId.trim().isNotEmpty) r.vehicleId.trim(): r,
    };

    if (cars.isEmpty) {
      final orphans = List<_MacroVehicleDraft>.from(_macroVehicleDrafts);
      _macroVehicleDrafts.clear();
      _deferDisposeMacroVehicleDrafts(orphans);
      return;
    }

    final next = <_MacroVehicleDraft>[];
    for (final car in cars) {
      final row = preserved[car] ?? (_MacroVehicleDraft.empty()..vehicleId = car);
      row.vehicleId = car;
      final typed = row.driverId.trim().isNotEmpty ||
          (!row.isDisposed && row.workDetailsController.text.trim().isNotEmpty);
      final missingTxId =
          row.txId == null || row.txId!.trim().isEmpty;
      if (forceHydrate) {
        if (byVehicle.containsKey(car)) {
          _hydrateMacroDraftFromTransaction(row, byVehicle[car]!);
        } else {
          row.txId = null;
          row.driverId = '';
          row.workType = 'FullDay';
          if (!row.isDisposed) row.workDetailsController.clear();
        }
      } else if (byVehicle.containsKey(car) && (!typed || missingTxId)) {
        // มีแถวของคันนี้แล้ว — hydrate เสมอเมื่อยังไม่ผูก txId
        // (คนขับเริ่มต้นจากเว็บต้องไม่บล็อกการติด id กันสร้างแถวซ้ำ)
        _hydrateMacroDraftFromTransaction(row, byVehicle[car]!);
      }
      // เติมคนขับเริ่มต้นจากเว็บ เมื่อยังไม่บันทึกและยังไม่ได้เลือกคนขับ
      // (รองรับคนขับที่เว็บตั้งจากตำแหน่ง «คนขับรถ» ไม่ใช่เฉพาะแม็คโคร)
      _applyMacroDefaultDriver(row);
      next.add(row);
    }

    final nextSet = next.toSet();
    final orphans =
        _macroVehicleDrafts.where((r) => !nextSet.contains(r)).toList();
    _macroVehicleDrafts
      ..clear()
      ..addAll(next);
    _deferDisposeMacroVehicleDrafts(orphans);
  }

  _MacroVehicleDraft? _macroDraftForVehicle(String vehicle) {
    final v = vehicle.trim();
    for (final row in _macroVehicleDrafts) {
      if (row.vehicleId.trim() == v) return row;
    }
    return null;
  }

  void _hydrateFuelDraftFromTransaction(_FuelVehicleDraft row, AppTransaction t) {
    row.txId = t.id;
    final vid = (t.vehicleId ?? '').trim();
    if (vid.isNotEmpty) row.vehicleId = vid;
    final ft = (t.fuelType ?? 'Diesel').trim();
    row.fuelType = ft.isEmpty ? 'Diesel' : ft;
    // แถว VehicleUsage ไม่ระบุถัง = ถังสำรอง (ตรงกับยอดที่คิดจริง)
    row.fuelTank = fuelUsageTankOf(t);
    final lit = t.quantity ?? 0;
    if (lit > 0) {
      row.liters = _strNum(lit);
      row.litersController.text = row.liters;
    }
    final time = _stripRecorderSuffix(t.workDetails ?? '').trim();
    if (time.isNotEmpty) {
      row.time = time;
      row.timeController.text = time;
    }
  }

  /// สร้างแถวบันทึกน้ำมัน 1 แถวต่อ 1 รถแม็คโครจากตั้งค่าแอพ
  void _syncFuelVehicleDraftsFromMacroCars({
    Iterable<AppTransaction>? dayFuelRows,
    bool forceHydrate = false,
  }) {
    final cars = _fuelMacroCars();
    final fuelByVehicle = <String, AppTransaction>{};
    final source = dayFuelRows ?? _moduleDayTransactions;
    for (final t in source) {
      if (t.category != 'Fuel') continue;
      final mov = (t.fuelMovement ?? '').trim();
      if (mov.isNotEmpty && mov != 'stock_out') continue;
      final vid = (t.vehicleId ?? '').trim();
      if (vid.isEmpty) continue;
      fuelByVehicle[vid] = t;
    }

    final preserved = <String, _FuelVehicleDraft>{
      for (final r in _fuelVehicleDrafts)
        if (r.vehicleId.trim().isNotEmpty) r.vehicleId.trim(): r,
    };

    if (cars.isEmpty) {
      final orphans = List<_FuelVehicleDraft>.from(_fuelVehicleDrafts);
      _fuelVehicleDrafts
        ..clear()
        ..add(_FuelVehicleDraft.empty());
      _deferDisposeFuelVehicleDrafts(orphans);
      return;
    }

    final next = <_FuelVehicleDraft>[];
    for (final car in cars) {
      final row = preserved[car] ?? (_FuelVehicleDraft.empty()..vehicleId = car);
      row.vehicleId = car;
      if (row.fuelType.trim().isEmpty) row.fuelType = 'Diesel';
      final typed = row.litersController.text.trim().isNotEmpty ||
          row.liters.trim().isNotEmpty;
      if (forceHydrate) {
        if (fuelByVehicle.containsKey(car)) {
          _hydrateFuelDraftFromTransaction(row, fuelByVehicle[car]!);
        } else {
          row.txId = null;
          row.liters = '';
          row.time = '';
          row.litersController.clear();
          row.timeController.clear();
        }
      } else if (!typed && fuelByVehicle.containsKey(car)) {
        _hydrateFuelDraftFromTransaction(row, fuelByVehicle[car]!);
      }
      next.add(row);
    }

    final nextSet = next.toSet();
    final orphans = _fuelVehicleDrafts.where((r) => !nextSet.contains(r)).toList();
    _fuelVehicleDrafts
      ..clear()
      ..addAll(next);
    _deferDisposeFuelVehicleDrafts(orphans);
  }

  bool get _isHomeSandMode =>
      (widget.initialCategory ?? '').contains('ทรายที่ล้างที่บ้าน');
  final List<_FuelVehicleDraft> _fuelVehicleDrafts = [];
  bool _fuelExtraVehiclesExpanded = false;

  // ── น้ำมัน: เมนูย่อย + สต็อกถัง ──
  /// เมนูย่อยที่เลือกอยู่ใน «น้ำมัน» (null = ยังอยู่หน้าเลือกเมนู)
  FuelSubMode? _fuelSubMode;
  ({double diesel, double benzine}) _fuelOpeningStock = (
    diesel: 0.0,
    benzine: 0.0,
  );
  FuelStockBalance _fuelStock = const FuelStockBalance(
    mainDiesel: 0,
    reserveDiesel: 0,
  );
  /// ถังที่ใช้ตอนเบิกน้ำมัน (default = หลัก)
  final _fuelStockInLitersController = TextEditingController();
  final _fuelStockInPricePerLiterController = TextEditingController();
  final _fuelStockInAmountController = TextEditingController();
  final _fuelStockInTimeController = TextEditingController();
  /// id รายการ StockIn ที่กำลังแก้ — null = รายการใหม่
  String? _fuelStockInTxId;
  /// ผู้ใช้กดล้างฟอร์มเพื่อเพิ่มแถวใหม่ — กัน auto-hydrate ทับจนกว่าจะเซฟ/เลือกรายการ
  bool _fuelStockInComposingNew = false;
  final _fuelWithdrawLitersController = TextEditingController();
  final _fuelWithdrawTimeController = TextEditingController();
  final _fuelWithdrawOtherController = TextEditingController();
  FuelWithdrawPurpose _fuelWithdrawPurpose = FuelWithdrawPurpose.machine;
  /// id แถวเบิก/โอนออกที่กำลังแก้ — null = รายการใหม่
  String? _fuelWithdrawTxId;
  /// คู่รับเข้าถังสำรอง (เฉพาะเครื่องจักร)
  String? _fuelWithdrawTransferInTxId;
  final _fuelCarFillLitersController = TextEditingController();
  final _fuelCarFillTimeController = TextEditingController();
  final _fuelCarFillOtherController = TextEditingController();
  FuelCarFillVehicle? _fuelCarFillVehicle;
  /// id แถวเติมรถยนต์ที่กำลังแก้ — null = รายการใหม่
  String? _fuelCarFillTxId;
  bool _macroExtraVehiclesExpanded = false;
  final List<_MacroVehicleDraft> _macroVehicleDrafts = [];
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
  _LaborEmpPoolKind _laborEmpPoolKind = _LaborEmpPoolKind.allEmployees;
  final Map<String, Set<String>> _laborAssignments = {
    for (final c in _laborCategories) c.id: <String>{},
  };
  final Map<String, bool> _laborBucketExpanded = {
    for (final c in _laborCategories) c.id: false,
  };

  // ── เช็คชื่อ (Attendance) — กระดานลากรายชื่อ ──
  static const List<_LaborWorkCategory> _attendanceGeneralBuckets = [
    _LaborWorkCategory(
      id: 'att_work',
      label: 'ทำงาน (เต็มวัน)',
      shortTitle: 'ทำงาน',
      color: Color(0xFF2FB6A6),
    ),
    _LaborWorkCategory(
      id: 'att_half_morning',
      label: 'ครึ่งวัน • ช่วงเช้า',
      shortTitle: 'ครึ่งวัน · เช้า',
      color: Color(0xFF3B9AE1),
    ),
    _LaborWorkCategory(
      id: 'att_half_afternoon',
      label: 'ครึ่งวัน • ช่วงบ่าย',
      shortTitle: 'ครึ่งวัน · บ่าย',
      color: Color(0xFF6C6FE6),
    ),
    _LaborWorkCategory(
      id: 'att_leave',
      label: 'ลางาน',
      shortTitle: 'ลางาน',
      color: Color(0xFFEF5D6E),
    ),
  ];
  static const List<_LaborWorkCategory> _attendanceDriverBuckets = [
    _LaborWorkCategory(
      id: 'att_drv_macro',
      label: 'ขับรถแม็คโคร',
      shortTitle: 'ขับรถแม็คโคร',
      color: Color(0xFFEF6C00),
    ),
    _LaborWorkCategory(
      id: 'att_drv_drum',
      label: 'ขับรถดรัม',
      shortTitle: 'ขับรถดรัม',
      color: Color(0xFF6C6FE6),
    ),
    _LaborWorkCategory(
      id: 'att_drv_leave',
      label: 'ลางาน',
      shortTitle: 'ลางาน',
      color: Color(0xFFEF5D6E),
    ),
  ];
  static const List<_LaborWorkCategory> _attendanceAllBuckets = [
    ..._attendanceGeneralBuckets,
    ..._attendanceDriverBuckets,
  ];
  static const Set<String> _attGeneralPresenceIds = {
    'att_work',
    'att_half_morning',
    'att_half_afternoon',
    'att_leave',
  };
  static const Set<String> _attDriverIds = {
    'att_drv_macro',
    'att_drv_drum',
    'att_drv_leave',
  };
  final Map<String, Set<String>> _attendanceAssignments = {
    for (final c in _attendanceAllBuckets) c.id: <String>{},
  };
  final Map<String, bool> _attendanceBucketExpanded = {
    for (final c in _attendanceAllBuckets) c.id: false,
  };
  final Set<String> _attendanceGeneralPicked = <String>{};
  final Set<String> _attendanceDriverPicked = <String>{};

  /// ความสูงกล่อง «#ทำงาน» — ลากขอบล่างปรับได้ เพราะบางวันมีคนเยอะกว่าปกติมาก
  static const String _kAttWorkCardHeightKey = 'attendance_work_card_height_v1';
  static const double _kAttWorkCardMinHeight = 220;
  static const double _kAttWorkCardMaxHeight = 900;
  double _attWorkCardHeight = 380;

  String? _attendanceLaborTxId;
  String? _attendanceLeaveTxId;
  String? _attendanceDriverLaborTxId;
  String? _attendanceDriverLeaveTxId;
  String? _attendanceLegacyLaborTxId;
  String? _attendanceLegacyLeaveTxId;

  /// เมนูย่อยเช็คชื่อ (null = หน้าเลือกเมนู)
  AttendanceSection? _attendanceSection;

  static const Set<String> _attSandWaKeys = {
    'work',
    'half:morning',
    'half:afternoon',
  };
  /// `drum:morning` / `drum:afternoon` เป็นคีย์เดิมก่อนรวมกะเช้า-บ่าย
  static const Set<String> _attDriverWaKeys = {
    'macro_driver',
    'drum',
    'drum:morning',
    'drum:afternoon',
  };
  static const String _attLeaveReasonSand =
      'เช็คชื่อ: ลางาน (พนักงานท่าทราย)';
  static const String _attLeaveReasonDriver = 'เช็คชื่อ: ลางาน (คนขับรถ)';
  static const String _attLeaveReasonLegacy = 'เช็คชื่อ: ลางาน';

  /// จำนวนวันที่ «มาทำงาน» ของแต่ละคนจากประวัติทั้งหมด — ใช้เรียงพูลรายชื่อ
  Map<String, int> _attendanceDaysWorked = const {};
  final ScrollController _attendanceGeneralPoolScroll = ScrollController();
  final ScrollController _attendanceDriverPoolScroll = ScrollController();
  /// ชิปที่เพิ่งวาง — ใช้เด้ง AnimatedScale ชั่วคราว
  final Set<String> _attendanceJustDroppedIds = <String>{};

  /// เซสชันเวลา (work / macro_driver / drum) — เปิดตอนลากเข้า ปิดตอนลากออก
  List<AttendanceWorkSession> _attendanceSessions = [];

  /// หน่วงก่อนเริ่มลากชื่อ — สั้นพอให้รู้สึกเหมือนแตะแล้วลากได้ทันที
  /// แต่ยังเหลือช่วงให้เลื่อนดูรายชื่อในพูลได้ตามปกติ
  static const _attDragDelay = Duration(milliseconds: 120);

  String _attendanceNowHHmm() =>
      AttendanceSessionTimes.formatHHmm(DateTime.now());

  final List<_GeneralSubJob> _generalSubJobs = [];
  final List<_OtGroupDraft> _otGroups = [];
  List<String> _vehicleWorkSuggestions = const [];

  bool get _isLaborMode =>
      widget.initialCategory == 'ค่าแรง' ||
      (widget.initialCategory ?? '').contains('บันทึกการทำงาน');
  bool get _isOtMode => (widget.initialCategory ?? '').contains('OT');

  /// เมนู «เช็คชื่อ» — กระดานลากรายชื่อ (เขียนลง Labor Attendance / Leave)
  bool get _isAttendanceMode => widget.initialCategory == 'เช็คชื่อ';

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
    WidgetsBinding.instance.addObserver(this);
    final pageTitle = widget.appBarTitle?.trim();
    final category = widget.initialCategory?.trim();
    MobileErrorScreenTracker.set(
      page: (pageTitle != null && pageTitle.isNotEmpty)
          ? pageTitle
          : ((category != null && category.isNotEmpty)
                ? category
                : 'บันทึกข้อมูล'),
      pageId: MobileScreenIds.pageQuickInput,
      module: category,
      stepId: MobileScreenIds.quickInputStep(category),
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
    _leaveEndDate = _leaveStartDate;
    _categoryController = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory!.trim()
          : 'ค่าแรง',
    );
    // ออฟไลน์ห้ามบังคับดึงเน็ต — ไม่งั้นกระดานลากชื่อจะว่างจนกว่า request จะ timeout
    // ค่าแรง/เช็คชื่อใช้แคชพนักงาน 25 นาที (ไม่ force)
    _loadEmployees();
    if (_isFuelMode) {
      // ต้องได้ค่ายกมาก่อนคิดคงเหลือในถัง
      unawaited(_loadAppCars().then((_) => _refreshFuelStock()));
    } else {
      _loadAppCars();
    }
    _loadAppExpenseIncomeTypes();
    _loadOtSuggestions();
    _loadVehicleWorkSuggestions();
    _refreshHomeSandStock();
    if (_isAttendanceMode) {
      _refreshAttendanceDaysWorked();
      unawaited(_loadAttWorkCardHeight());
    }
    _otGroups.add(_OtGroupDraft.empty());
    CountRecordOfflineSync.instance.addRemoteChangeListener(
      this,
      _onRemoteTransactionsChanged,
    );
    _startPollFallback();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadModuleTransactions();
    });
  }

  /// เครื่องอื่นแก้ transactions → รีเฟรชเมื่อฟอร์มไม่ dirty
  void _onRemoteTransactionsChanged() {
    if (!mounted) return;
    _scheduleRemoteModuleRefresh();
  }

  void _scheduleRemoteModuleRefresh() {
    _remoteRefreshDebounce?.cancel();
    _remoteRefreshDebounce = Timer(_remoteRefreshDebounceDelay, () {
      if (!mounted || _saving || _hasUnsavedModuleChanges) return;
      unawaited(_loadModuleTransactions(forceRefresh: true));
    });
  }

  void _startPollFallback() {
    _pollFallbackTimer?.cancel();
    // ลางานดึงธุรกรรมทั้งก้อน — ไม่ poll ทุก 12 วิ (พึ่ง realtime + resume)
    if (_isLaborLeaveMode) return;
    _pollFallbackTimer = Timer.periodic(_pollFallbackInterval, (_) {
      if (!mounted || _saving || _hasUnsavedModuleChanges) return;
      if (widget.serverOnlineHint == false) return;
      // Soft poll: use cache TTL; Realtime + resume force refresh when needed.
      unawaited(_loadModuleTransactions(forceRefresh: false));
    });
  }

  void _stopPollFallback() {
    _pollFallbackTimer?.cancel();
    _pollFallbackTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPollFallback();
      if (!_saving && !_hasUnsavedModuleChanges) {
        unawaited(_loadModuleTransactions(forceRefresh: false));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopPollFallback();
    }
  }

  String _quickYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// «ลางาน» อ่านรายการทุกวันเพราะการลาคร่อมหลายวันได้ — เมนูอื่นดูเฉพาะวันที่เลือก
  bool get _moduleReadsAllTransactions =>
      widget.initialCategory?.trim() == 'ลางาน';

  /// รวมแถวที่ค้างคิวออฟไลน์เข้ากับรายการที่โหลดมา
  Future<List<AppTransaction>> _mergeOfflineQueue(
    List<AppTransaction> rows,
    String ymd,
  ) {
    return _moduleReadsAllTransactions
        ? CountRecordOfflineSync.instance.mergeAllTransactionsAsync(rows)
        : CountRecordOfflineSync.instance.mergeForDayAsync(ymd, rows);
  }

  Future<void> _persist(AppTransaction t) async {
    final omitCreated =
        _persistOmitCreatedForIds.contains(t.id) ||
        _persistOmitCreatedSessionIds.contains(t.id);
    if (_isOfflineCapableCategory) {
      final queued = await CountRecordOfflineSync.instance.persist(
        service: widget.service,
        client: Supabase.instance.client,
        transaction: t,
        omitCreatedAt: omitCreated,
        dayServerRows: _moduleDayAllTransactions,
        serverOnlineHint: widget.serverOnlineHint,
      );
      _lastPersistQueued = queued;
      _persistOmitCreatedSessionIds.add(t.id);
      final ymd = t.date;
      final mergedDay = await _mergeOfflineQueue(
        _moduleDayAllTransactions,
        ymd,
      );
      if (mounted) {
        setState(() {
          _moduleDayAllTransactions = mergedDay;
          _moduleDayTransactions = mergedDay
              .where(
                (row) => transactionMatchesDailyModule(
                  row,
                  ymd,
                  widget.initialCategory!.trim(),
                ),
              )
              .toList();
        });
      }
      return;
    }
    _lastPersistQueued = false;
    await widget.service.upsertTransaction(t, omitCreatedAt: omitCreated);
    _persistOmitCreatedSessionIds.add(t.id);
  }

  Future<bool> _deleteTransactionOfflineAware(
    String id, {
    String? ymd,
  }) async {
    final date = ymd ?? _quickYmd(_selectedDate);
    if (_isOfflineCapableCategory) {
      final queued = await CountRecordOfflineSync.instance.delete(
        service: widget.service,
        client: Supabase.instance.client,
        id: id,
        ymd: date,
        dayServerRows: _moduleDayAllTransactions,
        serverOnlineHint: widget.serverOnlineHint,
      );
      final mergedDay = await _mergeOfflineQueue(
        _moduleDayAllTransactions,
        date,
      );
      if (mounted) {
        setState(() {
          _moduleDayAllTransactions = mergedDay;
          _moduleDayTransactions = mergedDay
              .where(
                (row) => transactionMatchesDailyModule(
                  row,
                  date,
                  widget.initialCategory!.trim(),
                ),
              )
              .toList();
        });
      }
      return queued;
    }
    await widget.service.deleteTransaction(id, affectingDate: date);
    return false;
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
    _dailyEventTxId = null;
  }

  void _disposeVehicleDrafts() {
    for (final row in _vehicleTripDrafts) {
      row.dispose();
    }
  }

  void _replaceVehicleDrafts(List<_VehicleTripDraft> nextRows) {
    final old = List<_VehicleTripDraft>.from(_vehicleTripDrafts);
    _vehicleTripDrafts
      ..clear()
      ..addAll(nextRows.isEmpty ? [_VehicleTripDraft.empty()] : nextRows);
    _deferDisposeVehicleDrafts(old);
  }

  /// ลบแถวรถดรัม: แถวที่บันทึกแล้ว (`tripTxId`) ลบจากฐานข้อมูลแล้วโหลดรายการใหม่ — ไม่เช่นนั้นลบเฉพาะในแบบฟอร์ม
  Future<void> _handleVehicleTripRowDelete(int index) async {
    if (index < 0 || index >= _vehicleTripDrafts.length) return;
    final row = _vehicleTripDrafts[index];
    final persistedId = row.tripTxId?.trim();
    if (persistedId != null && persistedId.isNotEmpty) {
      try {
        await _deleteTransactionOfflineAware(persistedId);
        if (!mounted) return;
        await _loadModuleTransactions(forceRefresh: !_isOfflineCapableCategory);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ลบรายการจากฐานข้อมูลแล้ว',
              style: GoogleFonts.kanit(),
            ),
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
      _deferDisposeVehicleDrafts([removed]);
      if (_vehicleTripDrafts.isEmpty) {
        _vehicleTripDrafts.add(_VehicleTripDraft.empty());
      }
    });
  }

  /// ลบแถวแม็คโคร: รายการที่บันทึกแล้ว (`txId`) ลบจากฐานข้อมูล — ไม่เช่นนั้นล้างเฉพาะแถว
  Future<void> _handleMacroVehicleRowDelete(_MacroVehicleDraft row) async {
    final persistedId = row.txId?.trim();
    if (persistedId != null && persistedId.isNotEmpty) {
      try {
        await _deleteTransactionOfflineAware(persistedId);
        if (!mounted) return;
        await _loadModuleTransactions(forceRefresh: !_isOfflineCapableCategory);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ลบรายการจากฐานข้อมูลแล้ว',
              style: GoogleFonts.kanit(),
            ),
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
      row.txId = null;
      row.driverId = '';
      row.workType = 'FullDay';
      if (!row.isDisposed) row.workDetailsController.clear();
    });
  }

  void _disposeFuelVehicleDrafts() {
    for (final row in _fuelVehicleDrafts) {
      row.dispose();
    }
  }

  void _disposeMacroVehicleDrafts() {
    for (final row in _macroVehicleDrafts) {
      row.dispose();
    }
  }

  /// ล้างฟอร์มก่อนโหลดวันใหม่ เพื่อไม่ให้เหลือค่าจากวันก่อนหน้า
  void _clearModuleFormFields() {
    if (_isSandWashMode) {
      _sandQtyMorningController.clear();
      _sandQtyAfternoonController.clear();
      _sandDrumsObtainedController.clear();
      _sandMorningStartController.clear();
      _sandEveningEndController.clear();
      _sandOperatorNames = const [];
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
      if (!_saving) _syncFuelVehicleDraftsFromMacroCars();
    } else if (_isMacroVehicleMode) {
      if (!_saving) _syncMacroVehicleDraftsFromMacroCars();
    } else if (_isLaborMode) {
      _selectedLaborEmpIds.clear();
      _laborPickedIds.clear();
      _laborEmpPoolKind = _LaborEmpPoolKind.allEmployees;
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
        _leaveEndDate = _leaveStartDate;
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
      if (!_saving) {
        _dailyEventTxId = null;
        _dailyEventDescController.clear();
        _dailyEventType = 'info';
        _dailyEventPriority = 'normal';
      }
    } else if (_isIncomeUtilitiesEntryMode) {
      _iuEntryKind = null;
      _iuExpenseChoice = null;
      _iuIncomeChoice = null;
      _wizardIncomePaymentStatus = 'Paid';
      _utilitiesTypeController.clear();
      _iuPartyNameController.clear();
      _iuPartyAddressController.clear();
      _iuPartyDetailController.clear();
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
    final loadId = ++_moduleTransactionsLoadGeneration;
    bool isCurrentLoad() => loadId == _moduleTransactionsLoadGeneration;
    final ymd = _quickYmd(_selectedDate);

    Future<void> applyRows(
      List<AppTransaction> rows, {
      required bool clearForm,
    }) async {
      if (!isCurrentLoad()) return;
      if (clearForm &&
          !(preserveIncomeUtilitiesForm && cat == 'รายจ่ายรายรับ')) {
        _clearModuleFormFields();
      }
      if (!isCurrentLoad()) return;
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
      if (!mounted || !isCurrentLoad()) return;
      for (final t in matched) {
        _persistOmitCreatedForIds.add(t.id);
      }
      setState(() {
        _moduleDayTransactions = matched;
        _moduleDayAllTransactions = rows;
        _moduleDayLoading = false;
        _moduleHistoryVisible = false;
      });
      if (!isCurrentLoad()) return;
      if (cat != 'รายจ่ายรายรับ') {
        await _refreshHomeSandStock();
      }
      if (!mounted || !isCurrentLoad()) return;
      _hydrateFormsFromTransactions(matched, dayTransactions: rows);
      if (!mounted || !isCurrentLoad()) return;
      if (_isLaborMode) {
        _syncMacroDriverCanvasFromVehicleUsage();
      }
      _captureModuleFormBaseline();
      if (mounted && isCurrentLoad()) setState(() {});
    }

    if (!forceRefresh) {
      List<AppTransaction>? cachedRows;
      if (cat == 'ลางาน') {
        cachedRows = await LocalDataCache.readTransactionsFullAny();
      } else {
        cachedRows = await LocalDataCache.readTransactionsForDayAny(ymd);
        if (cachedRows == null || cachedRows.isEmpty) {
          final full = await LocalDataCache.readTransactionsFullAny();
          if (full != null) {
            cachedRows = full
                .where((t) => t.date.trim() == ymd.trim())
                .toList(growable: false);
          }
        }
      }
      if (_isOfflineCapableCategory && cachedRows != null) {
        cachedRows = await _mergeOfflineQueue(cachedRows, ymd);
      }
      if (cachedRows != null && cachedRows.isNotEmpty) {
        if (!mounted || !isCurrentLoad()) return;
        _clearHydrationSlots();
        await applyRows(cachedRows, clearForm: true);
      }
    }

    final skipNetwork =
        _isOfflineCapableCategory && !widget.serverOnlineHint;
    if (skipNetwork) {
      if (!mounted || !isCurrentLoad()) return;
      if (_moduleDayTransactions.isEmpty) {
        var rows = (_moduleReadsAllTransactions
                ? await LocalDataCache.readTransactionsFullAny()
                : await LocalDataCache.readTransactionsForDayAny(ymd)) ??
            const <AppTransaction>[];
        rows = await _mergeOfflineQueue(rows, ymd);
        if (rows.isNotEmpty) {
          _clearHydrationSlots();
          await applyRows(rows, clearForm: true);
          return;
        }
      }
      if (mounted && isCurrentLoad()) {
        setState(() => _moduleDayLoading = false);
        _captureModuleFormBaseline();
      }
      return;
    }

    if (!mounted || !isCurrentLoad()) return;
    // มีข้อมูลแล้ว → รีเฟรชเงียบ ไม่โชว์ «กำลังโหลดข้อมูล» / ไม่ซ่อนประวัติ
    final hasCachedModule = cat == 'ลางาน'
        ? _moduleDayAllTransactions.isNotEmpty
        : _moduleDayTransactions.isNotEmpty;
    if (!hasCachedModule) {
      setState(() {
        _moduleDayLoading = true;
        _moduleHistoryVisible = false;
      });
      _clearHydrationSlots();
      if (!(preserveIncomeUtilitiesForm && cat == 'รายจ่ายรายรับ')) {
        _clearModuleFormFields();
      }
    }
    if (!mounted || !isCurrentLoad()) return;

    try {
      // Soft poll ใช้แคช/TTL — force เฉพาะเมื่อ realtime/ผู้ใช้ดึง (forceRefresh)
      // ลางาน: ใช้แคชเต็มชุดในเครื่องก่อน — ยิงเน็ตเฉพาะแคชว่างหรือ forceRefresh
      final forceServer = forceRefresh;
      if (cat == 'ลางาน' && !forceServer && hasCachedModule) {
        if (mounted && isCurrentLoad()) {
          setState(() => _moduleDayLoading = false);
        }
        return;
      }
      final rows = cat == 'ลางาน'
          ? await widget.service.fetchTransactions(forceRefresh: forceServer)
          : await widget.service.fetchTransactionsForDate(
              ymd,
              forceRefresh: forceServer,
            );
      if (!mounted || !isCurrentLoad()) return;
      final mergedRows = _isOfflineCapableCategory
          ? await _mergeOfflineQueue(rows, ymd)
          : rows;
      if (!mounted || !isCurrentLoad()) return;
      _clearHydrationSlots();
      await applyRows(
        mergedRows,
        clearForm: _moduleDayTransactions.isEmpty,
      );
      if (_isFuelMode && forceRefresh && mounted && isCurrentLoad()) {
        await _refreshFuelStock(forceNetwork: true);
      }
    } catch (_) {
      if (!mounted || !isCurrentLoad()) return;
      if (_moduleDayTransactions.isEmpty) {
        setState(() {
          _moduleDayTransactions = const [];
          _moduleDayAllTransactions = const [];
          _moduleDayLoading = false;
          _moduleHistoryVisible = false;
        });
        _captureModuleFormBaseline();
      } else if (mounted) {
        setState(() => _moduleDayLoading = false);
      }
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

  bool _fuelVehicleMatchesPinned(String car, String nickname) {
    return car.contains(nickname);
  }

  List<String> _fuelPinnedMacroCars(List<String> allCars) {
    final pinned = <String>[];
    final used = <String>{};
    for (final nickname in _kFuelPinnedVehicleNicknames) {
      if (pinned.length >= _kFuelPinnedVehicleCap) break;
      String? hit;
      for (final car in allCars) {
        if (used.contains(car)) continue;
        if (_fuelVehicleMatchesPinned(car, nickname)) {
          hit = car;
          break;
        }
      }
      if (hit != null) {
        pinned.add(hit);
        used.add(hit);
      }
    }
    for (final car in allCars) {
      if (pinned.length >= _kFuelPinnedVehicleCap) break;
      if (used.add(car)) pinned.add(car);
    }
    return pinned;
  }

  List<String> _fuelExtraMacroCars(List<String> allCars) {
    final pinned = _fuelPinnedMacroCars(allCars).toSet();
    return allCars.where((c) => !pinned.contains(c)).toList();
  }

  Set<String> _macroDriverIdsFromVehicleUsageToday() {
    final dayKey = _quickYmd(_selectedDate);
    return macroDriverIdsUsedForDay(dayKey, _moduleDayAllTransactions);
  }

  /// เติมกล่อง canvas คนขับแม็คโครจากบันทึกการใช้รถ (เมื่อยังไม่มีคนในกล่อง)
  void _syncMacroDriverCanvasFromVehicleUsage() {
    if (!_isLaborMode) return;
    final driverIds = _macroDriverIdsFromVehicleUsageToday();
    if (driverIds.isEmpty) return;
    final bucket = _laborAssignments['macro_driver'];
    if (bucket == null || bucket.isNotEmpty) return;
    bucket.addAll(driverIds);
    _laborBucketExpanded['macro_driver'] = true;
  }

  _FuelVehicleDraft? _fuelDraftForVehicle(String vehicle) {
    final v = vehicle.trim();
    for (final row in _fuelVehicleDrafts) {
      if (row.vehicleId.trim() == v) return row;
    }
    return null;
  }

  /// รถดรัม/เที่ยว — ดรัม + หกล้อ/สิบล้อ (จากรายการตั้งค่าแอพ)
  List<String> _vehicleTripCars({String includeVehicleId = ''}) {
    final seen = <String>{};
    final out = <String>[];
    final extra = includeVehicleId.trim();
    if (extra.isNotEmpty && seen.add(extra)) out.add(extra);
    for (final car in _cars) {
      if (!isVehicleTripDrumCarName(car)) continue;
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

  /// คนขับที่เลือกได้ในแถวแม็คโคร — ตำแหน่งแม็คโคร + คนขับเริ่มต้นจากเว็บ
  /// (เว็บตั้งค่าจากตำแหน่ง «คนขับรถ» ซึ่งอาจไม่อยู่ในรายชื่อแม็คโคร)
  List<Employee> _macroSelectableDriversFor(String vehicle) {
    final byId = <String, Employee>{
      for (final e in _macroDriverEmployees) e.id: e,
    };
    final defId = _defaultDriverIdForVehicle(vehicle);
    if (defId != null) {
      final emp = _employeesById[defId];
      if (emp != null && !emp.inactive) {
        byId.putIfAbsent(emp.id, () => emp);
      }
    }
    return byId.values.toList();
  }

  bool _isAllowedMacroDriverId(String driverId, String vehicle) {
    final id = driverId.trim();
    if (id.isEmpty) return false;
    if (_macroDriverEmployees.any((e) => e.id == id)) return true;
    final defId = _defaultDriverIdForVehicle(vehicle);
    return defId != null && defId == id && _employeesById[id] != null;
  }

  /// เติมคนขับเริ่มต้นจากเว็บเมื่อแถวยังว่าง — ไม่บังคับตำแหน่งแม็คโคร
  void _applyMacroDefaultDriver(_MacroVehicleDraft row) {
    if (row.txId != null && row.txId!.trim().isNotEmpty) return;
    if (row.driverId.trim().isNotEmpty) return;
    final defId = _defaultDriverIdForVehicle(row.vehicleId);
    if (defId == null || defId.isEmpty) return;
    final emp = _employeesById[defId];
    if (emp == null || emp.inactive) return;
    row.driverId = defId;
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

  /// คนขับเริ่มต้นของรถจากตั้งค่าเว็บ (`vehicleDefaultDrivers`) — รองรับชื่อไม่ตรงเป๊ะ
  String? _defaultDriverIdForVehicle(String vehicle) {
    final v = vehicle.trim();
    if (v.isEmpty || _vehicleDefaultDrivers.isEmpty) return null;
    final exact = _vehicleDefaultDrivers[v]?.trim();
    if (exact != null && exact.isNotEmpty) return exact;
    for (final entry in _vehicleDefaultDrivers.entries) {
      if (vehicleIdsLikelyMatch(entry.key, v)) {
        final id = entry.value.trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  /// ชื่อคนขับเริ่มต้นสำหรับแสดงหลังชื่อรถ — ว่างถ้ายังไม่ได้ตั้งค่า
  String _fuelDriverLabelForVehicle(String vehicle) {
    final id = _defaultDriverIdForVehicle(vehicle);
    if (id == null || id.isEmpty) return '';
    final label = _driverLabelFromId(id);
    return label == '-' ? '' : label;
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
    bool hasWashKeys(AppTransaction t) {
      final wa = t.workAssignments;
      if (wa == null || wa.isEmpty) return false;
      return (wa['wash1']?.isNotEmpty ?? false) ||
          (wa['wash2']?.isNotEmpty ?? false) ||
          (wa['wash_old']?.isNotEmpty ?? false) ||
          (wa['wash_new']?.isNotEmpty ?? false);
    }

    candidates.sort((a, b) {
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    final withWash = candidates.where(hasWashKeys).toList(growable: false);
    final latest = withWash.isNotEmpty ? withWash.first : candidates.first;
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
    final operatorNames = <String>[];
    void addOperators(Iterable<String> names) {
      for (final n in names) {
        if (n.trim().isEmpty || operatorNames.contains(n)) continue;
        operatorNames.add(n);
      }
    }

    // รวมค่าของทั้งสองเครื่องเป็นช่องเดียว — แถวเก่าที่แยกไว้ยังอ่านมารวมได้
    var morningTotal = 0.0;
    var afternoonTotal = 0.0;
    var hasMachineRow = false;
    for (final t in sandMatched) {
      final mt = (t.sandMachineType ?? '').toLowerCase();
      final desc = t.description;
      final isOldMachine =
          mt == 'old' ||
          desc.contains('เครื่องร่อน (เก่า)') ||
          desc.contains('เครื่องร่อน 1');
      final isNewMachine =
          mt == 'new' ||
          desc.contains('เครื่องร่อน (ใหม่)') ||
          desc.contains('เครื่องร่อน 2') ||
          (mt.isEmpty && desc.contains('เครื่องร่อน'));
      if (isOldMachine || isNewMachine) {
        _sandRowIdsByKey.putIfAbsent(isOldMachine ? 'Old' : 'New', () => t.id);
        morningTotal += (t.sandMorning ?? 0);
        afternoonTotal += (t.sandAfternoon ?? 0);
        hasMachineRow = true;
        addOperators(_operatorNamesFromTransaction(t));
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
    if (hasMachineRow) {
      _sandQtyMorningController.text = _strNum(morningTotal);
      _sandQtyAfternoonController.text = _strNum(afternoonTotal);
    }
    _prefillSandWashFromCountRecord(allDay);

    final laborWash = _operatorNamesFromLatestLaborWash(allDay);
    if (laborWash.oldNames.isNotEmpty || laborWash.newNames.isNotEmpty) {
      operatorNames.clear();
      addOperators(laborWash.newNames);
      addOperators(laborWash.oldNames);
    }

    _sandOperatorNames = List.unmodifiable(operatorNames);
  }

  /// เติมช่องจำนวนคิว จากจำนวนที่นับใน «บันทึกและนับจำนวน → การร่อนทราย»
  /// แยกตามช่วงเช้า/บ่าย — ผู้ใช้แก้ไขทับได้ก่อนบันทึก
  void _prefillSandWashFromCountRecord(List<AppTransaction> allDay) {
    final ymd = _quickYmd(_selectedDate);
    final periods = countRecordSandPeriodTotals(ymd, allDay);
    if (periods.morning <= 0 && periods.afternoon <= 0) return;

    if (periods.morning > 0) {
      _sandQtyMorningController.text = _strNum(periods.morning.toDouble());
    }
    if (periods.afternoon > 0) {
      _sandQtyAfternoonController.text = _strNum(periods.afternoon.toDouble());
    }
  }

  Future<void> _loadAttWorkCardHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kAttWorkCardHeightKey);
    if (saved == null || !mounted) return;
    setState(() {
      _attWorkCardHeight = saved.clamp(
        _kAttWorkCardMinHeight,
        _kAttWorkCardMaxHeight,
      );
    });
  }

  void _resizeAttWorkCard(double height) {
    final next = height.clamp(_kAttWorkCardMinHeight, _kAttWorkCardMaxHeight);
    if (next == _attWorkCardHeight) return;
    setState(() => _attWorkCardHeight = next);
  }

  Future<void> _saveAttWorkCardHeight() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAttWorkCardHeightKey, _attWorkCardHeight);
  }

  /// เติมกระดานเช็คชื่อจากรายการที่บันทึกไว้ของวันนั้น (Labor Attendance / Leave)
  void _hydrateAttendanceFromTransactions(List<AppTransaction> txs) {
    // ล้างค่าก่อนเติมใหม่ (กันค้างจากรอบก่อน)
    for (final k in _attendanceAssignments.keys) {
      _attendanceAssignments[k]?.clear();
    }
    for (final k in _attendanceBucketExpanded.keys.toList()) {
      _attendanceBucketExpanded[k] = false;
    }
    _attendanceGeneralPicked.clear();
    _attendanceDriverPicked.clear();
    _attendanceLaborTxId = null;
    _attendanceLeaveTxId = null;
    _attendanceDriverLaborTxId = null;
    _attendanceDriverLeaveTxId = null;
    _attendanceLegacyLaborTxId = null;
    _attendanceLegacyLeaveTxId = null;
    _attendanceJustDroppedIds.clear();
    _attendanceSessions = [];

    void assign(String bucketId, String empId) {
      _attendanceAssignments[bucketId]?.add(empId);
      _attendanceBucketExpanded[bucketId] = true;
    }

    ({bool sand, bool driver}) classifyWa(Map<String, List<String>>? wa) {
      if (wa == null || wa.isEmpty) {
        return (sand: false, driver: false);
      }
      var sand = false;
      var driver = false;
      for (final key in wa.keys) {
        final list = wa[key];
        if (list == null || list.isEmpty) continue;
        if (key == AttendanceSessionTimes.key) {
          for (final s in AttendanceSessionTimes.parseList(list)) {
            if (s.role == AttendanceSessionTimes.roleWork) sand = true;
            if (s.role == AttendanceSessionTimes.roleMacro ||
                s.role == AttendanceSessionTimes.roleDrum) {
              driver = true;
            }
          }
          continue;
        }
        if (_attSandWaKeys.contains(key)) sand = true;
        if (_attDriverWaKeys.contains(key)) driver = true;
      }
      return (sand: sand, driver: driver);
    }

    for (final t in txs) {
      final ls = (t.laborStatus ?? '').toLowerCase();
      final sc = (t.subCategory ?? '').toLowerCase();
      final isLeave = t.category == 'Leave' ||
          t.type.toLowerCase() == 'leave' ||
          ls == 'leave' ||
          ls == 'sick' ||
          ls == 'personal';
      final isOt = t.category == 'Labor' && (ls == 'ot' || sc == 'ot');
      final isAttendance = t.category == 'Labor' &&
          !isOt &&
          (sc == 'attendance' || ls == 'work' || (!isLeave && sc != 'advance'));

      if (isLeave) {
        final reason = (t.leaveReason ?? '').trim();
        final isSandLeave = reason.contains('พนักงานท่าทราย');
        final isDriverLeave = reason.contains('คนขับรถ');
        final isLegacyLeave = reason == _attLeaveReasonLegacy ||
            reason == 'เช็คชื่อ: ลางาน' ||
            (!isSandLeave && !isDriverLeave && reason.contains('เช็คชื่อ'));

        if (isLegacyLeave && !isSandLeave && !isDriverLeave) {
          _attendanceLegacyLeaveTxId = t.id;
        } else if (isDriverLeave && !isSandLeave) {
          _attendanceDriverLeaveTxId = t.id;
        } else if (isSandLeave && !isDriverLeave) {
          _attendanceLeaveTxId = t.id;
        } else {
          // ไม่มี leaveReason ชัด — กระจายตามตำแหน่งพนักงาน
          _attendanceLegacyLeaveTxId ??= t.id;
        }

        for (final id in t.employeeIds) {
          if (isSandLeave && !isDriverLeave) {
            assign('att_leave', id);
            continue;
          }
          if (isDriverLeave && !isSandLeave) {
            assign('att_drv_leave', id);
            continue;
          }
          final e = _employeesById[id];
          if (e != null && _attendanceIsDriver(e)) {
            assign('att_drv_leave', id);
          } else {
            assign('att_leave', id);
          }
        }
        continue;
      }

      // OT ย้ายไปเมนู «การทำงานล่วงเวลา» แล้ว — กระดานเช็คชื่อไม่แตะแถว OT
      if (isOt) continue;

      if (isAttendance) {
        final wa = t.workAssignments;
        final kind = classifyWa(wa);
        final hasWa = wa != null && wa.isNotEmpty;
        final isSandOnly = hasWa && kind.sand && !kind.driver;
        final isDriverOnly = hasWa && kind.driver && !kind.sand;
        final isLegacy = !hasWa || (kind.sand && kind.driver);

        if (isLegacy) {
          _attendanceLegacyLaborTxId = t.id;
        } else if (isSandOnly) {
          _attendanceLaborTxId = t.id;
        } else if (isDriverOnly) {
          _attendanceDriverLaborTxId = t.id;
        }

        final assigned = <String>{};
        void takeRole(String role, String bucketId) {
          final list = wa?[role];
          if (list == null) return;
          for (final id in list) {
            assign(bucketId, id);
            assigned.add(id);
          }
        }

        if (wa != null) {
          final sessionRaw = wa[AttendanceSessionTimes.key];
          if (sessionRaw != null && sessionRaw.isNotEmpty) {
            _attendanceSessions.addAll(
              AttendanceSessionTimes.parseList(sessionRaw),
            );
          }
          // ครึ่งวันเดิม → รวมเข้าช่องทำงาน
          takeRole('work', 'att_work');
          takeRole('half:morning', 'att_work');
          takeRole('half:afternoon', 'att_work');
          takeRole('macro_driver', 'att_drv_macro');
          takeRole('drum', 'att_drv_drum');
          takeRole('drum:morning', 'att_drv_drum');
          takeRole('drum:afternoon', 'att_drv_drum');
        }
        // คนที่เหลือ (ไม่มีใน workAssignments) — ใช้ workTypeByEmployee เดา
        final wtByEmp = t.workTypeByEmployee ?? const {};
        for (final id in t.employeeIds) {
          if (assigned.contains(id)) continue;
          final wt = (wtByEmp[id] ?? '').toLowerCase();
          final isDriver = _employeesById[id] != null &&
              _attendanceIsDriver(_employeesById[id]!);
          if (isSandOnly) {
            assign('att_work', id);
          } else if (isDriverOnly) {
            assign(wt == 'halfday' ? 'att_drv_drum' : 'att_drv_macro', id);
          } else if (wt == 'halfday') {
            assign(isDriver ? 'att_drv_drum' : 'att_work', id);
          } else if (isDriver) {
            assign('att_drv_macro', id);
          } else {
            assign('att_work', id);
          }
        }
      }
    }

    // เซสชันที่ยังเปิดอยู่ → ต้องอยู่ในช่อง
    for (final s in _attendanceSessions) {
      if (!s.isOpen) continue;
      final bucket = AttendanceSessionTimes.bucketForRole(s.role);
      if (bucket != null) assign(bucket, s.empId);
    }
    // เคลียร์ช่องครึ่งวันเก่า (ถ้ามีค้าง)
    _attendanceAssignments['att_half_morning']?.clear();
    _attendanceAssignments['att_half_afternoon']?.clear();
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
    if (_isFuelMode) {
      _syncFuelVehicleDraftsFromMacroCars(
        dayFuelRows: dayTransactions ?? txs,
        forceHydrate: true,
      );
      _hydrateFuelStockInFromDay(
        dayRows: dayTransactions ?? txs,
      );
      if (_fuelSubMode == FuelSubMode.carFill) {
        _hydrateFuelCarFillForSelectedVehicle();
      } else if (_fuelSubMode == FuelSubMode.withdraw) {
        _hydrateFuelWithdrawForSelectedPurpose();
      }
      return;
    }
    if (_isMacroVehicleMode) {
      _syncMacroVehicleDraftsFromMacroCars(
        dayRows: dayTransactions ?? txs,
        forceHydrate: true,
      );
      return;
    }
    if (_isAttendanceMode) {
      _hydrateAttendanceFromTransactions(txs);
      return;
    }
    if (_isDailyEventMode) {
      if (!_saving) _hydrateDailyEventFromTransactions(txs);
      return;
    }
    if (txs.isEmpty) return;
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
      // วันที่มีบันทึก: โหลดแถวต่อคันเข้าฟอร์มเลย — วันว่าง: แถวเปล่า 1 แถว
      if (!_saving) {
        final pool = dayTransactions ?? txs;
        final latest = latestVehicleTripsByVehicle(
          pool,
          ymd: _quickYmd(_selectedDate),
        );
        if (latest.isEmpty) {
          _replaceVehicleDrafts([_VehicleTripDraft.empty()]);
        } else {
          final drafts = latest
              .map(_vehicleTripDraftFromAppTransaction)
              .toList(growable: false);
          _replaceVehicleDrafts(drafts);
        }
      }
      return;
    }

    if (_isMacroVehicleMode) {
      return;
    }

    if (_isLaborLeaveMode) {
      // ไม่เติมฟอร์มจากลาที่บันทึกแล้ว — เปิดหน้ามาเพื่อส่งรายการใหม่ (เหมือนเบิกเงิน)
      return;
    }

    if (_isLaborAdvanceMode) {
      // ไม่เติมฟอร์มจากคำขอเบิกที่บันทึกแล้ว — แต่ถอดคนที่ขอวันนี้แล้วออกจากรายการเลือก
      final already = _advanceEmpIdsAlreadyRequestedOnSelectedDay();
      _selectedAdvanceEmpIds.removeWhere(already.contains);
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
    WidgetsBinding.instance.removeObserver(this);
    CountRecordOfflineSync.instance.removeRemoteChangeListener(this);
    _employeesLoadProgressTimer?.cancel();
    _uiRebuildDebounce?.cancel();
    _remoteRefreshDebounce?.cancel();
    _stopPollFallback();
    _entranceController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _sandQtyMorningController.dispose();
    _sandQtyAfternoonController.dispose();
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
    _fuelStockInLitersController.dispose();
    _fuelStockInPricePerLiterController.dispose();
    _fuelStockInAmountController.dispose();
    _fuelStockInTimeController.dispose();
    _fuelWithdrawLitersController.dispose();
    _fuelWithdrawTimeController.dispose();
    _fuelWithdrawOtherController.dispose();
    _fuelCarFillLitersController.dispose();
    _fuelCarFillTimeController.dispose();
    _fuelCarFillOtherController.dispose();
    _laborWorkDetailsController.dispose();
    _attendanceGeneralPoolScroll.dispose();
    _attendanceDriverPoolScroll.dispose();
    for (final job in _generalSubJobs) {
      job.dispose();
    }
    _leaveReasonController.dispose();
    _leaveDaysController.dispose();
    _advanceAmountPerPersonController.dispose();
    _advanceAccountController.dispose();
    _utilitiesTypeController.dispose();
    _iuPartyNameController.dispose();
    _iuPartyAddressController.dispose();
    _iuPartyDetailController.dispose();
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
      _isMacroVehicleMode ||
      _isAttendanceMode;

  void _applyEmployeeList(List<Employee> list) {
    final sorted = List<Employee>.from(list)
      ..sort((a, b) {
        return (a.nickname.isNotEmpty ? a.nickname : a.name).compareTo(
          b.nickname.isNotEmpty ? b.nickname : b.name,
        );
      });
    _employees = sorted;
    _employeesById = {for (final e in sorted) e.id: e};
    _driverEmployees = sorted
        .where((e) => !e.inactive)
        .where(_isDriverEmployee)
        .toList();
    if (_isMacroVehicleMode) {
      _syncMacroVehicleDraftsFromMacroCars();
    }
    _employeesLoading = false;
    _employeesLoadPercent = 0;
  }

  Future<void> _loadEmployees({bool forceRefresh = false}) async {
    _employeesLoadProgressTimer?.cancel();
    _employeesLoadProgressTimer = null;
    final showPct = _showsEmployeeLoadingUi;

    if (!forceRefresh) {
      // รวมแคชแดชบอร์ด (CountRecordOfflineSync) + LocalDataCache
      final merged =
          await CountRecordOfflineSync.instance.mergedEmployeeSources();
      if (merged.isNotEmpty && mounted) {
        final localOnly = await LocalDataCache.readEmployeesAny();
        if (localOnly == null || localOnly.isEmpty) {
          // เติม LocalDataCache จากแคชแดชบอร์ด — รอบถัดไป/EmployeeService ใช้ได้
          unawaited(LocalDataCache.writeEmployees(merged));
        }
        setState(() => _applyEmployeeList(merged));
      }
    }

    if (_employees.isNotEmpty && !forceRefresh) {
      unawaited(
        widget.employeeService.fetchEmployees(forceRefresh: false).then((list) {
          if (!mounted || list.isEmpty) return;
          setState(() => _applyEmployeeList(list));
          unawaited(
            CountRecordOfflineSync.instance.cacheEmployees(list),
          );
        }),
      );
      return;
    }

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
      _employeesLoadProgressTimer?.cancel();
      _employeesLoadProgressTimer = null;
      if (!mounted) return;
      if (showPct && _employeesLoading) {
        setState(() => _employeesLoadPercent = 100);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (!mounted) return;
      setState(() => _applyEmployeeList(list));
      unawaited(CountRecordOfflineSync.instance.cacheEmployees(list));
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
    Future<void> applyCars(List<String> cars) async {
      if (cars.isEmpty || !mounted) return;
      setState(() {
        _cars = cars;
        if (_isFuelMode) {
          _syncFuelVehicleDraftsFromMacroCars();
        }
        if (_isMacroVehicleMode) {
          _syncMacroVehicleDraftsFromMacroCars();
        }
      });
    }

    Future<void> applyDefaultDrivers(Map<String, String> map) async {
      if (!mounted) return;
      setState(() {
        _vehicleDefaultDrivers = map;
        if (_isMacroVehicleMode) {
          _syncMacroVehicleDraftsFromMacroCars();
        }
      });
    }

    Future<void> applyOpeningStock(
      ({double diesel, double benzine}) opening,
    ) async {
      if (!mounted) return;
      setState(() => _fuelOpeningStock = opening);
    }

    final sync = CountRecordOfflineSync.instance;
    // แคชก่อน — แถวแม็คโคร/คนขับเริ่มต้นขึ้นทันทีหลังเข้าแดชบอร์ด
    final cachedCars = await sync.readCachedCars();
    final cachedDrivers = await sync.readCachedVehicleDefaultDrivers();
    final cachedOpening = await sync.readCachedFuelOpeningStock();
    await applyCars(cachedCars);
    await applyDefaultDrivers(cachedDrivers);
    await applyOpeningStock(cachedOpening);

    if (_isOfflineCapableCategory && !widget.serverOnlineHint) {
      return;
    }

    final hadCarsCache = cachedCars.isNotEmpty;

    Future<void> refreshFromNetwork() async {
      try {
        final client = Supabase.instance.client;
        final rows = await client
            .from('app_settings')
            .select('cars, app_defaults, fuel_opening_stock')
            .eq('id', 'default')
            .limit(1);
        if (rows.isEmpty) {
          if (!hadCarsCache) {
            await applyDefaultDrivers(await sync.readCachedVehicleDefaultDrivers());
            await applyOpeningStock(await sync.readCachedFuelOpeningStock());
          }
          return;
        }
        final openingRaw = rows.first['fuel_opening_stock'];
        if (openingRaw is Map) {
          final opening =
              CountRecordOfflineSync.parseFuelOpeningStock(openingRaw);
          await sync.cacheFuelOpeningStock(opening);
          await applyOpeningStock(opening);
        } else if (!hadCarsCache) {
          await applyOpeningStock(await sync.readCachedFuelOpeningStock());
        }
        final raw = rows.first['cars'];
        final cars = <String>[
          if (raw is List)
            ...raw.map((e) => '$e').where((e) => e.trim().isNotEmpty),
        ];
        if (cars.isNotEmpty) {
          await sync.cacheCars(cars);
          await applyCars(cars);
        }
        final appDefaults = rows.first['app_defaults'];
        var defaults = await sync.readCachedVehicleDefaultDrivers();
        if (appDefaults is Map) {
          final parsed = CountRecordOfflineSync.parseVehicleDefaultDrivers(
            appDefaults['vehicleDefaultDrivers'],
          );
          if (parsed.isNotEmpty) {
            defaults = parsed;
            await sync.cacheVehicleDefaultDrivers(defaults);
          }
        }
        await applyDefaultDrivers(defaults);
      } catch (_) {
        if (hadCarsCache) return;
        await applyCars(await sync.readCachedCars());
        await applyDefaultDrivers(await sync.readCachedVehicleDefaultDrivers());
        await applyOpeningStock(await sync.readCachedFuelOpeningStock());
      }
    }

    if (hadCarsCache) {
      unawaited(refreshFromNetwork());
      return;
    }
    await refreshFromNetwork();
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

  /// งานรอง (suggestions / stock) — อ่านแคชเต็มชุดในเครื่องก่อน ไม่บังคับดึงตาราง
  Future<List<AppTransaction>> _transactionsPreferLocalCache() async {
    final local = await LocalDataCache.readTransactionsFullAny();
    if (local != null && local.isNotEmpty) return local;
    return widget.service.fetchTransactions(forceRefresh: false);
  }

  Future<void> _loadOtSuggestions() async {
    try {
      final txs = await _transactionsPreferLocalCache();
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
      final txs = await _transactionsPreferLocalCache();
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
  ];

  /// บันทึกรถดรัม — ช่วยกรอกรายละเอียดงาน (คำย่อยทั่วไข)
  static const List<String> _kVehicleDrumWorkQuickPhrases = [
    'ขนทรายล้าง',
    'ขนทรายถม',
  ];

  /// งานที่เลือกไว้ของรถคันนั้น — เก็บเป็นข้อความคั่นจุลภาคในช่องเดิม
  List<String> _macroWorkTags(_MacroVehicleDraft row) {
    if (row.isDisposed) return const [];
    return row.workDetailsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _setMacroWorkTags(_MacroVehicleDraft row, List<String> tags) {
    if (row.isDisposed) return;
    final next = tags.join(', ');
    setState(() {
      row.workDetailsController.text = next;
      row.workDetailsController.selection = TextSelection.collapsed(
        offset: next.length,
      );
    });
  }

  /// แตะชิปงาน — มีอยู่แล้วเอาออก ไม่มีก็ต่อท้าย (สลับงานระหว่างวันได้)
  void _toggleMacroWorkTag(_MacroVehicleDraft row, String tag) {
    if (row.isDisposed) return;
    final tags = _macroWorkTags(row);
    final idx = tags.indexOf(tag);
    if (idx >= 0) {
      tags.removeAt(idx);
      AppHaptics.tap();
    } else {
      tags.add(tag);
      AppHaptics.success();
    }
    _setMacroWorkTags(row, tags);
  }

  void _removeMacroWorkTag(_MacroVehicleDraft row, String tag) {
    if (row.isDisposed) return;
    final tags = _macroWorkTags(row)..remove(tag);
    AppHaptics.tap();
    _setMacroWorkTags(row, tags);
  }

  /// พิมพ์งานเองด้วยแป้นพิมพ์ภาษาไทย แล้วเพิ่มเป็นชิปใหม่
  Future<void> _addMacroCustomWorkTag(_MacroVehicleDraft row) async {
    if (row.isDisposed) return;
    final text = await showThaiTextPad(
      context: context,
      label: 'เพิ่มงานเอง (ภาษาไทย)',
      minLines: 1,
      maxLines: 2,
    );
    if (!mounted || text == null) return;
    final tag = text.trim().replaceAll(',', ' ').trim();
    if (tag.isEmpty) return;
    final tags = _macroWorkTags(row);
    if (tags.contains(tag)) return;
    tags.add(tag);
    AppHaptics.success();
    _setMacroWorkTags(row, tags);
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
      final rows = await _transactionsPreferLocalCache();
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

  /// นับ «จำนวนวันที่มาทำงาน» ต่อคนจากประวัติทั้งหมด (นับวันซ้ำเพียงครั้งเดียว)
  /// ไม่รวมแถว OT และไม่รวมลางาน — ใช้จัดอันดับพูลรายชื่อในกระดานเช็คชื่อ
  Future<void> _refreshAttendanceDaysWorked() async {
    try {
      final serverRows = await _transactionsPreferLocalCache();
      final rows = await CountRecordOfflineSync.instance
          .mergeAllTransactionsAsync(serverRows);
      final daysByEmp = <String, Set<String>>{};
      for (final t in rows) {
        if (!isLaborWorkAttendanceRow(t)) continue;
        final day = t.date.trim();
        if (day.isEmpty) continue;
        for (final raw in t.employeeIds) {
          final id = raw.trim();
          if (id.isEmpty) continue;
          daysByEmp.putIfAbsent(id, () => <String>{}).add(day);
        }
      }
      if (!mounted) return;
      setState(() {
        _attendanceDaysWorked = {
          for (final e in daysByEmp.entries) e.key: e.value.length,
        };
      });
    } catch (_) {}
  }

  Future<void> _setFuelStockBalance(FuelStockBalance balance) async {
    if (!mounted) return;
    setState(() => _fuelStock = balance);
    await LocalDataCache.writeFuelStockSnapshot(balance);
  }

  /// คงเหลือในถัง — snapshot-first (ไม่สแกน/ไม่ดึง DB ถ้ามีแคช)
  ///
  /// [forceNetwork] = true → ดึง transactions จากเซิร์ฟเวอร์แล้วคำนวณใหม่
  /// [allowNetworkFetch] = false → ไม่ยิงเครือข่าย; ใช้แคชในเครื่องเท่านั้น
  Future<void> _refreshFuelStock({
    bool forceNetwork = false,
    bool allowNetworkFetch = true,
  }) async {
    try {
      // อย่าเชื่อ snapshot เป็นคำตอบสุดท้าย — ต้องคิดจากยอดยกมา + รายการ
      // (snapshot ที่แคชตอนยังไม่มี opening จะค้างที่ 0)
      List<AppTransaction>? baseRows;
      if (forceNetwork) {
        baseRows = await widget.service.fetchTransactions(forceRefresh: true);
      } else {
        baseRows = await LocalDataCache.readTransactionsFullAny();
        if (baseRows == null && allowNetworkFetch) {
          baseRows = await widget.service.fetchTransactions();
        }
      }
      if (baseRows == null) {
        // ไม่มีแคชธุรกรรม — ใช้ snapshot ชั่วคราวถ้ามี
        if (!forceNetwork) {
          final snap = await LocalDataCache.readFuelStockSnapshot(
            LocalDataCache.fuelStockSnapshotTtl,
          );
          if (snap != null && mounted) {
            setState(() => _fuelStock = snap);
            return;
          }
        }
        final stale = await LocalDataCache.readFuelStockSnapshotAny();
        if (stale != null && mounted) {
          setState(() => _fuelStock = stale);
        }
        return;
      }
      final rows = await CountRecordOfflineSync.instance
          .mergeAllTransactionsAsync(baseRows);
      if (!mounted) return;
      final balance = computeFuelStockBalance(
        rows,
        openingDiesel: _fuelOpeningStock.diesel,
        openingBenzine: _fuelOpeningStock.benzine,
      );
      await _setFuelStockBalance(balance);
    } catch (_) {
      final stale = await LocalDataCache.readFuelStockSnapshotAny();
      if (stale != null && mounted) {
        setState(() => _fuelStock = stale);
      }
    }
  }

  /// หลังบันทึกน้ำมัน — อัปเดตเกจจาก delta (ไม่ยิงเครือข่าย)
  ///
  /// [reverseFirst] = แถวที่ต้องถอนผลจากยอดก่อน (เช่น อัปเดต StockIn ที่เปลี่ยนลิตร)
  Future<void> _applyLocalFuelStockAfterSave(
    List<AppTransaction> savedRows, {
    List<AppTransaction> reverseFirst = const [],
  }) async {
    var next = _fuelStock;
    var needRecompute = false;
    for (final t in reverseFirst) {
      final applied = applyFuelBalanceDelta(next, t, reverse: true);
      if (applied == null) {
        needRecompute = true;
        break;
      }
      next = applied;
    }
    if (!needRecompute) {
      for (final t in savedRows) {
        final applied = applyFuelBalanceDelta(next, t);
        if (applied == null) {
          needRecompute = true;
          break;
        }
        next = applied;
      }
    }
    if (needRecompute) {
      // VehicleUsage / กรณีซับซ้อน — คำนวณจากแคชในเครื่องเท่านั้น
      await _refreshFuelStock(allowNetworkFetch: false);
      return;
    }
    await _setFuelStockBalance(next);
  }

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
    SaveOperationFeedback.showSaving(context);
  }

  void _dismissSavingPopup() {
    if (!mounted) return;
    _releaseKeyboardFocus();
    SaveOperationFeedback.dismissSaving(context);
  }

  Future<void> _showSuccessPopupAndPopToHome(String message) async {
    if (!mounted) return;
    _releaseKeyboardFocus();
    await SaveOperationFeedback.showSuccessThenDismiss(
      context: context,
      message: message,
      holdAfterAnimation: const Duration(milliseconds: 1300),
      onAfterDismiss: () {
        if (!mounted) return;
        Navigator.of(context).pop();
      },
    );
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
      if (stayOnPage) {
        _dismissSavingPopup();
        savingDialogOpen = false;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _releaseKeyboardFocus();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (onStayOnPageCleared != null) {
          setState(onStayOnPageCleared);
          await WidgetsBinding.instance.endOfFrame;
        }
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(successMessage, style: GoogleFonts.kanit()),
          ),
        );
        await _loadModuleTransactions(preserveIncomeUtilitiesForm: true);
      } else {
        // dialog เดิม morph เป็น success ต่อเนื่อง — ไม่ปิดแล้วเปิดใหม่
        savingDialogOpen = false;
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
    if (_isAttendanceMode) {
      switch (_attendanceSection) {
        case AttendanceSection.sandYard:
          await _saveAttendanceSandYardEntry();
          break;
        case AttendanceSection.driver:
          await _saveAttendanceDriverEntry();
          break;
        case null:
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'เลือกเมนูย่อยเช็คชื่อก่อนบันทึก',
                style: GoogleFonts.kanit(),
              ),
            ),
          );
          break;
      }
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
        final qtyMorning =
            double.tryParse(_sandQtyMorningController.text.trim()) ?? 0;
        final qtyAfternoon =
            double.tryParse(_sandQtyAfternoonController.text.trim()) ?? 0;
        final drums =
            double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
        final total = qtyMorning + qtyAfternoon;
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

        // รวมเป็นแถวเดียว — แถวเครื่องเก่าที่เคยบันทึกไว้ถูกเคลียร์เป็น 0
        // เพื่อไม่ให้ยอดรวมนับซ้ำ
        await saveMachine(
          suffix: 's1',
          machineType: 'Old',
          description: 'ล้างทราย เครื่องร่อน (เก่า)',
          morning: 0,
          afternoon: 0,
        );
        await saveMachine(
          suffix: 's2',
          machineType: 'New',
          description: 'ล้างทราย เครื่องร่อน',
          morning: qtyMorning,
          afternoon: qtyAfternoon,
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

        _sandQtyMorningController.clear();
        _sandQtyAfternoonController.clear();
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
      requireSignature: false,
      stayOnPage: true,
      // คงแถวที่เพิ่งบันทึกไว้ให้ตรวจต่อ — _loadModuleTransactions จะ refill เมื่อ !_saving
      onStayOnPageCleared: null,
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
    for (final t in latestVehicleTripsByVehicle(pool, ymd: ymd)) {
      if ((t.vehicleId ?? '').trim() == vehicle) return t;
    }
    return null;
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

  /// คนขับประจำรถจากตั้งค่าเว็บ — เติมเฉพาะตอนแถวยังไม่มีคนขับ
  void _applyDefaultDriverForVehicleRow(_VehicleTripDraft row, String vehicle) {
    if (row.driverId.trim().isNotEmpty) return;
    final id = _defaultDriverIdForVehicle(vehicle);
    if (id == null || id.isEmpty) return;
    if (!_driverEmployees.any((e) => e.id == id)) return;
    row.driverId = id;
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
    _applyDefaultDriverForVehicleRow(row, vehicle);
    final existing = _findLatestVehicleTripForDay(vehicle);
    if (existing == null) {
      row.tripTxId = null;
      return;
    }
    final loaded = _vehicleTripDraftFromAppTransaction(existing);
    _mergeVehicleTripDraftFrom(row, loaded);
    _applyDefaultDriverForVehicleRow(row, vehicle);
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

  /// เขียนแถวแม็คโคร 1 คัน — ใช้ร่วมกันทั้งบันทึกรวมและปุ่ม «อัปเดตคันนี้»
  Future<void> _persistMacroRow(
    _MacroVehicleDraft row, {
    required List<String> macroCars,
    required String date,
    required int index,
  }) async {
    final vehicle = row.vehicleId.trim();
    final driver = row.driverId.trim();
    final details = row.isDisposed
        ? ''
        : row.workDetailsController.text.trim();
    final workType = row.workType;
    if (vehicle.isEmpty) {
      _failSave('ไม่พบชื่อรถแม็คโครในแถวบันทึก');
    }
    if (!macroCars.contains(vehicle)) {
      _failSave('เลือกรถได้เฉพาะรถแม็คโคร');
    }
    if (driver.isEmpty) {
      _failSave('กรุณาเลือกคนขับสำหรับ $vehicle');
    }
    if (!_isAllowedMacroDriverId(driver, vehicle)) {
      _failSave(
        'เลือกคนขับจากรายชื่อตำแหน่ง «คนขับรถแม็คโคร» '
        'หรือคนขับเริ่มต้นของรถคันนี้เท่านั้น',
      );
    }
    final dayLabel = workType == 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
    var txId = row.txId?.trim() ?? '';
    if (txId.isEmpty) {
      // ใช้แถวเดิมของคัน+วันถ้ามี — กันสร้าง *_macro_vehicle_* ซ้ำ
      AppTransaction? existing;
      for (final t in _moduleDayAllTransactions) {
        if (t.date.trim() != date.trim()) continue;
        if (!isMacroVehicleTransaction(t)) continue;
        if ((t.vehicleId ?? '').trim() != vehicle) continue;
        final ea = existing?.createdAt;
        final ta = t.createdAt;
        if (existing == null ||
            ta == null ||
            (ea != null && ta.isAfter(ea))) {
          existing = t;
        }
      }
      txId = existing?.id.trim() ?? '';
    }
    if (txId.isEmpty) {
      txId =
          '${DateTime.now().millisecondsSinceEpoch}_macro_vehicle_$index';
    }
    row.txId = txId;
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
  }

  String _selectedDateYmd() {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _saveMacroVehicleUsageEntries() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกการใช้รถแม็คโครสำเร็จ',
      saveActionLabel: 'บันทึกการใช้รถแม็คโคร',
      saveButtonLabel: 'บันทึก',
      requireSignature: false,
      stayOnPage: true,
      body: () async {
        final macroCars = _fuelMacroCars();
        if (macroCars.isEmpty) {
          _failSave('ยังไม่พบรถแม็คโครในตั้งค่าแอพ');
        }
        // เติมคนขับเริ่มต้นอีกครั้งก่อนบันทึก (กันกรณีโหลดพนักงาน/ตั้งค่าช้า)
        _syncMacroVehicleDraftsFromMacroCars();
        final activeRows = _macroVehicleDrafts.where((row) {
          final hasDetails = !row.isDisposed &&
              row.workDetailsController.text.trim().isNotEmpty;
          if (hasDetails) return true;
          final driver = row.driverId.trim();
          if (driver.isEmpty) return false;
          // คันที่มีแค่คนขับเริ่มต้นจากเว็บ — ยังไม่ถือว่าใช้งาน (รวมคันปักหมุด)
          final defId = _defaultDriverIdForVehicle(row.vehicleId);
          if (defId != null && defId == driver) return false;
          // ผู้ใช้เลือกคนขับเอง (ไม่ใช่ค่าเริ่มต้น) — บันทึกได้แม้ยังไม่กรอกรายละเอียด
          return true;
        }).toList();
        if (activeRows.isEmpty) {
          _failSave(
            'กรุณาระบุคนขับอย่างน้อย 1 คัน '
            '(หรือตั้งคนขับเริ่มต้นที่เว็บ: ตั้งค่า > รถ/เครื่องจักร)',
          );
        }
        final date = _selectedDateYmd();

        for (var i = 0; i < activeRows.length; i++) {
          await _persistMacroRow(
            activeRows[i],
            macroCars: macroCars,
            date: date,
            index: i,
          );
        }
      },
    );
  }

  /// อัปเดตเฉพาะรถคันเดียว — ใช้ตอนเปลี่ยนงานระหว่างวัน
  Future<void> _saveSingleMacroRow(_MacroVehicleDraft row) async {
    await _runSaveWithPopups(
      successMessage: 'อัปเดต ${row.vehicleId} แล้ว',
      saveActionLabel: 'อัปเดตการใช้รถแม็คโคร',
      saveButtonLabel: 'อัปเดตคันนี้',
      requireSignature: false,
      stayOnPage: true,
      body: () async {
        final macroCars = _fuelMacroCars();
        if (macroCars.isEmpty) {
          _failSave('ยังไม่พบรถแม็คโครในตั้งค่าแอพ');
        }
        await _persistMacroRow(
          row,
          macroCars: macroCars,
          date: _selectedDateYmd(),
          index: 0,
        );
      },
    );
  }

  List<AppTransaction> _dayFuelStockInRows([List<AppTransaction>? dayRows]) {
    final ymd = _quickYmd(_selectedDate);
    final source = dayRows ?? _moduleDayAllTransactions;
    final rows = source
        .where((t) => t.date.trim() == ymd && isFuelStockInRow(t))
        .toList();
    rows.sort((a, b) {
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return rows;
  }

  void _clearFuelStockInForm({bool composingNew = true}) {
    _fuelStockInTxId = null;
    _fuelStockInComposingNew = composingNew;
    _fuelStockInLitersController.clear();
    _fuelStockInPricePerLiterController.clear();
    _fuelStockInAmountController.clear();
    _fuelStockInTimeController.clear();
  }

  void _applyFuelStockInFromTx(AppTransaction t) {
    _fuelStockInComposingNew = false;
    _fuelStockInTxId = t.id;
    _persistOmitCreatedForIds.add(t.id);
    final liters = fuelTxLiters(t);
    _fuelStockInLitersController.text =
        liters > 0 ? formatFuelLiters(liters) : '';
    final price = t.unitPrice;
    _fuelStockInPricePerLiterController.text =
        price != null && price > 0 ? formatFuelLiters(price) : '';
    _fuelStockInAmountController.text =
        t.amount > 0 ? formatFuelLiters(t.amount) : '';
    _fuelStockInTimeController.text =
        _stripRecorderSuffix(t.workDetails ?? '').trim();
  }

  void _hydrateFuelStockInFromDay({
    List<AppTransaction>? dayRows,
    bool force = false,
  }) {
    if (_fuelStockInComposingNew && !force) return;
    final rows = _dayFuelStockInRows(dayRows);
    if (rows.isEmpty) {
      if (force) _clearFuelStockInForm(composingNew: false);
      return;
    }
    AppTransaction? target;
    final currentId = _fuelStockInTxId?.trim();
    if (currentId != null && currentId.isNotEmpty) {
      for (final r in rows) {
        if (r.id == currentId) {
          target = r;
          break;
        }
      }
    }
    target ??= rows.first;
    _applyFuelStockInFromTx(target);
  }

  String _fuelLookupVehicleIdForCarFill() {
    final v = _fuelCarFillVehicle;
    if (v == null) return '';
    if (v == FuelCarFillVehicle.other) {
      return _fuelCarFillOtherController.text.trim();
    }
    return fuelCarFillVehicleIdOf(v);
  }

  AppTransaction? _dayFuelCarFillLatest({String? vehicleId}) {
    return latestFuelCarFillForVehicle(
      dayYmd: _quickYmd(_selectedDate),
      transactions: _moduleDayAllTransactions,
      vehicleId: vehicleId ?? _fuelLookupVehicleIdForCarFill(),
    );
  }

  void _applyFuelCarFillFromTx(AppTransaction t) {
    _fuelCarFillTxId = t.id;
    _persistOmitCreatedForIds.add(t.id);
    final liters = fuelTxLiters(t);
    _fuelCarFillLitersController.text =
        liters > 0 ? formatFuelLiters(liters) : '';
    _fuelCarFillTimeController.text =
        _stripRecorderSuffix(t.workDetails ?? '').trim();
    final vid = (t.vehicleId ?? '').trim();
    if (!isKnownFuelCarFillVehicleId(vid) && vid.isNotEmpty) {
      _fuelCarFillVehicle = FuelCarFillVehicle.other;
      _fuelCarFillOtherController.text = vid;
    }
  }

  void _hydrateFuelCarFillForSelectedVehicle() {
    final vehicle = _fuelCarFillVehicle;
    if (vehicle == null) {
      _fuelCarFillTxId = null;
      _fuelCarFillLitersController.clear();
      _fuelCarFillTimeController.clear();
      return;
    }
    final hit = _dayFuelCarFillLatest();
    if (hit == null) {
      _fuelCarFillTxId = null;
      _fuelCarFillLitersController.clear();
      _fuelCarFillTimeController.clear();
      return;
    }
    _applyFuelCarFillFromTx(hit);
  }

  String _fuelCarFillSummaryForVehicle(FuelCarFillVehicle vehicle) {
    final vid = vehicle == FuelCarFillVehicle.other
        ? ''
        : fuelCarFillVehicleIdOf(vehicle);
    final hit = _dayFuelCarFillLatest(vehicleId: vid);
    if (hit == null) return '';
    final liters = fuelTxLiters(hit);
    final time = _stripRecorderSuffix(hit.workDetails ?? '').trim();
    final parts = <String>[
      if (liters > 0) '${formatFuelLiters(liters)} ลิตร',
      if (time.isNotEmpty) time,
    ];
    return parts.join(' · ');
  }

  AppTransaction? _dayFuelWithdrawLatest(FuelWithdrawPurpose purpose) {
    return latestFuelWithdrawForPurpose(
      dayYmd: _quickYmd(_selectedDate),
      transactions: _moduleDayAllTransactions,
      purpose: purpose,
    );
  }

  String? _fuelOtherDetailFromDescription(String description) {
    final plain = _stripRecorderSuffix(description);
    const marker = ' — ';
    final i = plain.indexOf(marker);
    if (i < 0) return null;
    var rest = plain.substring(i + marker.length).trim();
    final lit = RegExp(r'\s+\d').firstMatch(rest);
    if (lit != null) {
      rest = rest.substring(0, lit.start).trim();
    }
    return rest.isEmpty ? null : rest;
  }

  void _applyFuelWithdrawFromTx(AppTransaction t) {
    _fuelWithdrawTxId = t.id;
    _persistOmitCreatedForIds.add(t.id);
    final liters = fuelTxLiters(t);
    _fuelWithdrawLitersController.text =
        liters > 0 ? formatFuelLiters(liters) : '';
    _fuelWithdrawTimeController.text =
        _stripRecorderSuffix(t.workDetails ?? '').trim();
    final purpose = fuelWithdrawPurposeFromCode(t.workType) ??
        (isFuelTransferRow(t)
            ? FuelWithdrawPurpose.machine
            : FuelWithdrawPurpose.other);
    _fuelWithdrawPurpose = purpose == FuelWithdrawPurpose.car
        ? FuelWithdrawPurpose.other
        : purpose;
    if (_fuelWithdrawPurpose == FuelWithdrawPurpose.other) {
      _fuelWithdrawOtherController.text =
          _fuelOtherDetailFromDescription(t.description) ?? '';
    } else {
      _fuelWithdrawOtherController.clear();
    }
    _fuelWithdrawTransferInTxId = null;
    if (isFuelTransferRow(t)) {
      final pair = fuelMachineTransferPair(
        outTx: t,
        transactions: _moduleDayAllTransactions,
      );
      final inId = pair.inTx?.id.trim();
      if (inId != null && inId.isNotEmpty) {
        _fuelWithdrawTransferInTxId = inId;
        _persistOmitCreatedForIds.add(inId);
      }
    }
  }

  void _hydrateFuelWithdrawForSelectedPurpose() {
    final hit = _dayFuelWithdrawLatest(_fuelWithdrawPurpose);
    if (hit == null) {
      _fuelWithdrawTxId = null;
      _fuelWithdrawTransferInTxId = null;
      _fuelWithdrawLitersController.clear();
      _fuelWithdrawTimeController.clear();
      if (_fuelWithdrawPurpose != FuelWithdrawPurpose.other) {
        _fuelWithdrawOtherController.clear();
      }
      return;
    }
    _applyFuelWithdrawFromTx(hit);
  }

  String _fuelWithdrawSummaryForPurpose(FuelWithdrawPurpose purpose) {
    final hit = _dayFuelWithdrawLatest(purpose);
    if (hit == null) return '';
    final liters = fuelTxLiters(hit);
    final time = _stripRecorderSuffix(hit.workDetails ?? '').trim();
    final parts = <String>[
      if (liters > 0) '${formatFuelLiters(liters)} ลิตร',
      if (time.isNotEmpty) time,
    ];
    if (purpose == FuelWithdrawPurpose.other) {
      final detail = _fuelOtherDetailFromDescription(hit.description);
      if (detail != null && detail.isNotEmpty) parts.add(detail);
    }
    return parts.join(' · ');
  }

  /// เพิ่มน้ำมันเข้าถัง (รถน้ำมันมาเติม) — สร้างใหม่หรืออัปเดตรายการเดิม
  Future<void> _saveFuelStockInEntry() async {
    final liters =
        double.tryParse(_fuelStockInLitersController.text.trim()) ?? 0;
    final pricePerLiter =
        double.tryParse(_fuelStockInPricePerLiterController.text.trim()) ?? 0;
    final amount =
        double.tryParse(_fuelStockInAmountController.text.trim()) ?? 0;
    final time = _fuelStockInTimeController.text.trim();
    final existingId = _fuelStockInTxId?.trim();
    final isUpdate = existingId != null && existingId.isNotEmpty;
    // เพิ่มเข้าถัง = ดีเซลอย่างเดียว — ราคา/ยอดเงินกรอกทีหลังได้
    const fuelType = 'Diesel';
    await _runSaveWithPopups(
      successMessage: isUpdate
          ? 'อัปเดตเพิ่มน้ำมันเข้าถังสำเร็จ'
          : 'บันทึกเพิ่มน้ำมันเข้าถังสำเร็จ',
      saveActionLabel: isUpdate ? 'อัปเดตน้ำมันเข้าถัง' : 'เพิ่มน้ำมันเข้าถัง',
      saveButtonLabel: isUpdate ? 'อัปเดตรายการนี้' : 'บันทึกเพิ่มน้ำมัน',
      stayOnPage: true,
      onStayOnPageCleared: () {
        // คงค่าในช่องเพื่อแก้ต่อ — ตั้ง txId จากรายการที่เพิ่งบันทึก
        _fuelStockInComposingNew = false;
      },
      body: () async {
        if (liters <= 0) {
          _failSave(
            'กรุณาระบุจำนวนลิตรให้มากกว่า 0',
            field: 'จำนวนลิตรที่เติมเข้าถัง',
          );
        }
        if (time.isEmpty) {
          _failSave('กรุณาระบุเวลาที่เติม', field: 'เวลาที่เติม');
        }
        var priorLiters = 0.0;
        if (isUpdate) {
          for (final r in _dayFuelStockInRows()) {
            if (r.id == existingId) {
              priorLiters = fuelTxLiters(r);
              break;
            }
          }
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final txId = isUpdate
            ? existingId
            : '${DateTime.now().millisecondsSinceEpoch}_fuel_in';
        final tx = AppTransaction(
          id: txId,
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Fuel',
          subCategory: kFuelStockInSubCategory,
          description: _appendRecorder(
            'เพิ่มน้ำมันเข้าถัง: ${formatFuelLiters(liters)} ลิตร (ดีเซล)',
          ),
          amount: amount,
          note: _activeSignatureNote,
          quantity: liters,
          unit: 'L',
          unitPrice: pricePerLiter > 0 ? pricePerLiter : null,
          fuelType: fuelType,
          fuelMovement: 'stock_in',
          fuelTank: kFuelTankMain,
          workDetails: _appendRecorder(time),
        );
        await _persist(tx);
        _fuelStockInTxId = tx.id;
        _fuelStockInComposingNew = false;
        if (isUpdate && priorLiters > 0) {
          final oldTx = AppTransaction(
            id: txId,
            date: '$y-$m-$d',
            type: 'Expense',
            category: 'Fuel',
            subCategory: kFuelStockInSubCategory,
            description: '',
            amount: 0,
            quantity: priorLiters,
            unit: 'L',
            fuelType: fuelType,
            fuelMovement: 'stock_in',
            fuelTank: kFuelTankMain,
          );
          await _applyLocalFuelStockAfterSave([tx], reverseFirst: [oldTx]);
        } else {
          await _applyLocalFuelStockAfterSave([tx]);
        }
      },
    );
  }

  /// เบิกน้ำมัน — เติมเครื่องจักร = โอนหลัก→สำรอง; อื่นๆ หักถังหลัก
  Future<void> _saveFuelWithdrawEntry() async {
    final liters =
        double.tryParse(_fuelWithdrawLitersController.text.trim()) ?? 0;
    final time = _fuelWithdrawTimeController.text.trim();
    final purpose = _fuelWithdrawPurpose;
    final otherText = _fuelWithdrawOtherController.text.trim();
    const fuelType = 'Diesel';
    final isMachine = purpose == FuelWithdrawPurpose.machine;
    final existingId = _fuelWithdrawTxId?.trim();
    final isUpdate = existingId != null && existingId.isNotEmpty;
    await _runSaveWithPopups(
      successMessage: isUpdate
          ? (isMachine ? 'อัปเดตเติมถังสำรองสำเร็จ' : 'อัปเดตเบิกน้ำมันสำเร็จ')
          : (isMachine ? 'เติมถังสำรองสำเร็จ' : 'บันทึกเบิกน้ำมันสำเร็จ'),
      saveActionLabel: isMachine ? 'เติมถังสำรอง' : 'เบิกน้ำมันออกจากถังหลัก',
      saveButtonLabel: isUpdate ? 'อัปเดตรายการนี้' : 'บันทึกเบิกน้ำมัน',
      stayOnPage: true,
      onStayOnPageCleared: () {
        // คงค่าในช่องเพื่อแก้ต่อ — txId ตั้งจากรายการที่เพิ่งบันทึก
      },
      body: () async {
        if (liters <= 0) {
          _failSave(
            'กรุณาระบุจำนวนลิตรให้มากกว่า 0',
            field: 'จำนวนลิตรที่เบิกออก',
          );
        }
        if (time.isEmpty) {
          _failSave('กรุณาระบุเวลาที่เติม', field: 'เวลาที่เติม');
        }
        if (purpose == FuelWithdrawPurpose.other && otherText.isEmpty) {
          _failSave('กรุณาระบุรายละเอียดการเบิก', field: 'ระบุรายละเอียด');
        }
        var priorLiters = 0.0;
        String? priorXferNote;
        if (isUpdate) {
          for (final r in _moduleDayAllTransactions) {
            if (r.id == existingId) {
              priorLiters = fuelTxLiters(r);
              final n = (r.note ?? '').trim();
              if (n.startsWith('xfer:')) priorXferNote = n;
              break;
            }
          }
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final availableMain =
            _fuelStock.mainDiesel + (isUpdate ? priorLiters : 0);

        if (isMachine) {
          if (liters > availableMain + 1e-9) {
            _failSave(
              'ถังหลักมีไม่พอ (คงเหลือ ${formatFuelLiters(availableMain)} ลิตร)',
              field: 'จำนวนลิตรที่เบิกออก',
            );
          }
          final reserveAfterReverse =
              _fuelStock.reserveDiesel - (isUpdate ? priorLiters : 0);
          final reserveRoom =
              kFuelTankCapacityReserveLiters - reserveAfterReverse;
          if (liters > reserveRoom + 1e-9) {
            _failSave(
              'ถังสำรองว่างเหลือ ${formatFuelLiters(reserveRoom < 0 ? 0 : reserveRoom)} ลิตร',
              field: 'จำนวนลิตรที่เบิกออก',
            );
          }
          final ts = DateTime.now().millisecondsSinceEpoch;
          final existingInId = _fuelWithdrawTransferInTxId?.trim();
          final outId =
              isUpdate ? existingId : '${ts}_fuel_xfer_out';
          final inId = isUpdate &&
                  existingInId != null &&
                  existingInId.isNotEmpty
              ? existingInId
              : '${ts}_fuel_xfer_in';
          final pairNote = (isUpdate &&
                  priorXferNote != null &&
                  priorXferNote.isNotEmpty)
              ? priorXferNote
              : 'xfer:$ts';
          final outTx = AppTransaction(
            id: outId,
            date: date,
            type: 'Expense',
            category: 'Fuel',
            subCategory: kFuelTransferSubCategory,
            description: _appendRecorder(
              'เติมเครื่องจักร: โอนถังหลัก → สำรอง '
              '${formatFuelLiters(liters)} ลิตร',
            ),
            amount: 0,
            note: pairNote,
            quantity: liters,
            unit: 'L',
            fuelType: fuelType,
            fuelMovement: 'stock_out',
            fuelTank: kFuelTankMain,
            workType: 'machine',
            workDetails: _appendRecorder(time),
          );
          final inTx = AppTransaction(
            id: inId,
            date: date,
            type: 'Expense',
            category: 'Fuel',
            subCategory: kFuelTransferSubCategory,
            description: _appendRecorder(
              'รับเข้าถังสำรองจากถังหลัก: '
              '${formatFuelLiters(liters)} ลิตร',
            ),
            amount: 0,
            note: pairNote,
            quantity: liters,
            unit: 'L',
            fuelType: fuelType,
            fuelMovement: 'stock_in',
            fuelTank: kFuelTankReserve,
            workType: 'machine',
            workDetails: _appendRecorder(time),
          );
          await _persist(outTx);
          await _persist(inTx);
          _fuelWithdrawTxId = outTx.id;
          _fuelWithdrawTransferInTxId = inTx.id;
          if (isUpdate && priorLiters > 0) {
            final oldOut = AppTransaction(
              id: outId,
              date: date,
              type: 'Expense',
              category: 'Fuel',
              subCategory: kFuelTransferSubCategory,
              description: '',
              amount: 0,
              note: pairNote,
              quantity: priorLiters,
              unit: 'L',
              fuelType: fuelType,
              fuelMovement: 'stock_out',
              fuelTank: kFuelTankMain,
              workType: 'machine',
            );
            final oldIn = AppTransaction(
              id: inId,
              date: date,
              type: 'Expense',
              category: 'Fuel',
              subCategory: kFuelTransferSubCategory,
              description: '',
              amount: 0,
              note: pairNote,
              quantity: priorLiters,
              unit: 'L',
              fuelType: fuelType,
              fuelMovement: 'stock_in',
              fuelTank: kFuelTankReserve,
              workType: 'machine',
            );
            await _applyLocalFuelStockAfterSave(
              [outTx, inTx],
              reverseFirst: [oldOut, oldIn],
            );
          } else {
            await _applyLocalFuelStockAfterSave([outTx, inTx]);
          }
        } else {
          final label = fuelWithdrawPurposeLabelOf(purpose);
          final desc = purpose == FuelWithdrawPurpose.other
              ? 'เบิกน้ำมัน: $label — $otherText'
              : 'เบิกน้ำมัน: $label';
          if (liters > availableMain + 1e-9) {
            _failSave(
              'ถังหลักมีไม่พอ (คงเหลือ ${formatFuelLiters(availableMain)} ลิตร)',
              field: 'จำนวนลิตรที่เบิกออก',
            );
          }
          final txId = isUpdate
              ? existingId
              : '${DateTime.now().millisecondsSinceEpoch}_fuel_wd';
          final tx = AppTransaction(
            id: txId,
            date: date,
            type: 'Expense',
            category: 'Fuel',
            subCategory: kFuelWithdrawSubCategory,
            description: _appendRecorder(
              '$desc ${formatFuelLiters(liters)} ลิตร (ดีเซล · ถังหลัก)',
            ),
            amount: 0,
            note: _activeSignatureNote,
            quantity: liters,
            unit: 'L',
            fuelType: fuelType,
            fuelMovement: 'stock_out',
            fuelTank: kFuelTankMain,
            workType: fuelWithdrawPurposeCodeOf(purpose),
            workDetails: _appendRecorder(time),
          );
          await _persist(tx);
          _fuelWithdrawTxId = tx.id;
          _fuelWithdrawTransferInTxId = null;
          if (isUpdate && priorLiters > 0) {
            final oldTx = AppTransaction(
              id: txId,
              date: date,
              type: 'Expense',
              category: 'Fuel',
              subCategory: kFuelWithdrawSubCategory,
              description: '',
              amount: 0,
              quantity: priorLiters,
              unit: 'L',
              fuelType: fuelType,
              fuelMovement: 'stock_out',
              fuelTank: kFuelTankMain,
            );
            await _applyLocalFuelStockAfterSave([tx], reverseFirst: [oldTx]);
          } else {
            await _applyLocalFuelStockAfterSave([tx]);
          }
        }
      },
    );
  }

  /// เติมน้ำมันรถยนต์ — หักจากถังหลัก
  Future<void> _saveFuelCarFillEntry() async {
    final liters =
        double.tryParse(_fuelCarFillLitersController.text.trim()) ?? 0;
    final time = _fuelCarFillTimeController.text.trim();
    final vehicle = _fuelCarFillVehicle;
    final otherText = _fuelCarFillOtherController.text.trim();
    const fuelType = 'Diesel';
    final existingId = _fuelCarFillTxId?.trim();
    final isUpdate = existingId != null && existingId.isNotEmpty;
    await _runSaveWithPopups(
      successMessage: isUpdate
          ? 'อัปเดตเติมน้ำมันรถยนต์สำเร็จ'
          : 'บันทึกเติมน้ำมันรถยนต์สำเร็จ',
      saveActionLabel: 'เติมน้ำมันรถยนต์',
      saveButtonLabel:
          isUpdate ? 'อัปเดตรายการนี้' : 'บันทึกเติมน้ำมันรถยนต์',
      stayOnPage: true,
      onStayOnPageCleared: () {
        // คงค่าในช่องเพื่อแก้ต่อ — txId ตั้งจากรายการที่เพิ่งบันทึก
      },
      body: () async {
        if (vehicle == null) {
          _failSave('กรุณาเลือกรถยนต์', field: 'เลือกรถยนต์');
        }
        if (liters <= 0) {
          _failSave(
            'กรุณาระบุจำนวนลิตรให้มากกว่า 0',
            field: 'จำนวนลิตรที่เติม',
          );
        }
        if (time.isEmpty) {
          _failSave('กรุณาระบุเวลาที่เติม', field: 'เวลาที่เติม');
        }
        if (vehicle == FuelCarFillVehicle.other && otherText.isEmpty) {
          _failSave('กรุณาระบุชื่อรถ', field: 'ระบุชื่อรถ');
        }
        var priorLiters = 0.0;
        if (isUpdate) {
          for (final r in _moduleDayAllTransactions) {
            if (r.id == existingId) {
              priorLiters = fuelTxLiters(r);
              break;
            }
          }
        }
        final availableMain =
            _fuelStock.mainDiesel + (isUpdate ? priorLiters : 0);
        if (liters > availableMain + 1e-9) {
          _failSave(
            'ถังหลักมีไม่พอ (คงเหลือ ${formatFuelLiters(availableMain)} ลิตร)',
            field: 'จำนวนลิตรที่เติม',
          );
        }
        final selectedVehicle = vehicle;
        final vehicleId = fuelCarFillVehicleIdOf(
          selectedVehicle,
          otherText: otherText,
        );
        final vehicleLabel = selectedVehicle == FuelCarFillVehicle.other
            ? 'อื่นๆ: $otherText'
            : fuelCarFillVehicleLabelOf(selectedVehicle);
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final txId = isUpdate
            ? existingId
            : '${DateTime.now().millisecondsSinceEpoch}_fuel_car';
        final tx = AppTransaction(
          id: txId,
          date: date,
          type: 'Expense',
          category: 'Fuel',
          subCategory: kFuelWithdrawSubCategory,
          description: _appendRecorder(
            'เติมน้ำมันรถยนต์: $vehicleLabel '
            '${formatFuelLiters(liters)} ลิตร (ดีเซล · ถังหลัก)',
          ),
          amount: 0,
          note: _activeSignatureNote,
          quantity: liters,
          unit: 'L',
          fuelType: fuelType,
          fuelMovement: 'stock_out',
          fuelTank: kFuelTankMain,
          workType: fuelWithdrawPurposeCodeOf(FuelWithdrawPurpose.car),
          vehicleId: vehicleId,
          workDetails: _appendRecorder(time),
        );
        await _persist(tx);
        _fuelCarFillTxId = tx.id;
        if (isUpdate && priorLiters > 0) {
          final oldTx = AppTransaction(
            id: txId,
            date: date,
            type: 'Expense',
            category: 'Fuel',
            subCategory: kFuelWithdrawSubCategory,
            description: '',
            amount: 0,
            quantity: priorLiters,
            unit: 'L',
            fuelType: fuelType,
            fuelMovement: 'stock_out',
            fuelTank: kFuelTankMain,
          );
          await _applyLocalFuelStockAfterSave([tx], reverseFirst: [oldTx]);
        } else {
          await _applyLocalFuelStockAfterSave([tx]);
        }
      },
    );
  }

  Future<void> _saveFuelVehicleUsageEntries() async {
    await _runSaveWithPopups(
      successMessage: 'บันทึกการใช้น้ำมันรายรถสำเร็จ',
      saveActionLabel: 'บันทึกการใช้น้ำมันรายรถ',
      saveButtonLabel: 'บันทึก',
      requireSignature: false,
      stayOnPage: true,
      body: () async {
        final fuelCars = _fuelMacroCars();
        if (fuelCars.isEmpty) {
          _failSave('ยังไม่พบรถแม็คโครในตั้งค่าแอพ');
        }
        final activeRows = _fuelVehicleDrafts.where((row) {
          final liters = double.tryParse(row.liters.trim()) ?? 0;
          final hasTime = row.time.trim().isNotEmpty;
          return liters > 0 || hasTime || row.txId != null;
        }).toList();
        if (activeRows.isEmpty) {
          _failSave('กรุณาระบุปริมาณน้ำมันอย่างน้อย 1 คัน');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';

        final saved = <AppTransaction>[];
        for (var i = 0; i < activeRows.length; i++) {
          final row = activeRows[i];
          final vehicle = row.vehicleId.trim();
          final liters = double.tryParse(row.liters.trim()) ?? 0;
          if (vehicle.isEmpty) {
            _failSave('ไม่พบชื่อรถแม็คโครในแถวบันทึก');
          }
          if (!fuelCars.contains(vehicle)) {
            _failSave('เลือกรถได้เฉพาะรถแม็คโคร');
          }
          if (liters <= 0) {
            _failSave(
              'กรุณาระบุปริมาณน้ำมันให้มากกว่า 0 ($vehicle)',
              field: 'ใช้น้ำมัน (ลิตร)',
            );
          }
          if (row.time.trim().isEmpty) {
            _failSave('กรุณาระบุเวลาเติมน้ำมัน ($vehicle)');
          }
          row.fuelType = 'Diesel';
          final tank = normalizeFuelTank(row.fuelTank);
          final tankLabel = fuelTankIsReserve(tank)
              ? 'ปั่นไฟ/สำรอง'
              : 'พล่าม/หลัก';
          final txId =
              row.txId ??
              '${DateTime.now().millisecondsSinceEpoch}_fuel_out_$i';
          row.txId = txId;
          final tx = AppTransaction(
            id: txId,
            date: date,
            type: 'Expense',
            category: 'Fuel',
            subCategory: 'VehicleUsage',
            description: _appendRecorder(
              'ใช้น้ำมันรถ $vehicle: ${liters.toStringAsFixed(0)} ลิตร '
              '(ดีเซล · $tankLabel)',
            ),
            amount: 0,
            note: _activeSignatureNote,
            quantity: liters,
            unit: 'L',
            fuelType: row.fuelType,
            fuelMovement: 'stock_out',
            fuelTank: tank,
            vehicleId: vehicle,
            workDetails: _appendRecorder(row.time.trim()),
          );
          await _persist(tx);
          saved.add(tx);
        }
        await _applyLocalFuelStockAfterSave(saved);
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

  /// รวม workAssignments + sessionTimes สำหรับบทบาทที่ระบุ
  Map<String, List<String>> _attendanceBuildTimedAssignments({
    required Map<String, Set<String>> inBoxByRole,
    required Set<String> sessionRoles,
  }) {
    final assignments = <String, List<String>>{};
    for (final e in inBoxByRole.entries) {
      if (e.value.isNotEmpty) assignments[e.key] = e.value.toList();
    }
    // คนที่อยู่ในช่องแต่ยังไม่มีเซสชันเปิด → เปิดตอนบันทึก
    final now = _attendanceNowHHmm();
    var sessions = List<AttendanceWorkSession>.from(_attendanceSessions);
    for (final e in inBoxByRole.entries) {
      if (!sessionRoles.contains(e.key)) continue;
      for (final empId in e.value) {
        final hasOpen = sessions.any(
          (s) => s.role == e.key && s.empId == empId && s.isOpen,
        );
        if (!hasOpen) {
          sessions = AttendanceSessionTimes.openSession(
            sessions: sessions,
            role: e.key,
            empId: empId,
            startHHmm: now,
          );
        }
      }
    }
    _attendanceSessions = sessions;
    final encoded = AttendanceSessionTimes.encodeList(
      AttendanceSessionTimes.forRoles(sessions, sessionRoles),
    );
    if (encoded.isNotEmpty) {
      assignments[AttendanceSessionTimes.key] = encoded;
    }
    return assignments;
  }

  Set<String> _attendanceEmpIdsFromSessions(Set<String> roles) {
    return {
      for (final s in _attendanceSessions)
        if (roles.contains(s.role)) s.empId,
    };
  }

  Future<void> _saveAttendanceSandYardEntry() async {
    final work = _attendanceAssignments['att_work']!.toSet();
    final genLeave = _attendanceAssignments['att_leave']!.toSet();

    // snapshot คนขับไว้เผื่อต้องแยกแถวรวมเก่า
    final drvMacro = _attendanceAssignments['att_drv_macro']!.toSet();
    final drvDrum = _attendanceAssignments['att_drv_drum']!.toSet();
    final drvLeave = _attendanceAssignments['att_drv_leave']!.toSet();

    await _runSaveWithPopups(
      successMessage: 'บันทึกเช็คชื่อพนักงานท่าทรายสำเร็จ',
      saveActionLabel: 'บันทึกเช็คชื่อพนักงานท่าทราย',
      saveButtonLabel: 'บันทึกเช็คชื่อ',
      requireSignature: false,
      stayOnPage: true,
      body: () async {
        if (_employeesLoading) {
          _failSave('กำลังโหลดรายชื่อพนักงาน — รอสักครู่แล้วลองใหม่');
        }
        final sessionEmp = _attendanceEmpIdsFromSessions({
          AttendanceSessionTimes.roleWork,
        });
        final present = <String>{...work, ...sessionEmp};
        if (present.isEmpty && genLeave.isEmpty) {
          _failSave('กรุณาลากรายชื่อลงกล่องอย่างน้อย 1 คน');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final baseTs = DateTime.now().millisecondsSinceEpoch;

        await _attendanceMigrateLegacyIfNeeded(
          date: date,
          baseTs: baseTs,
          savingSand: true,
          sandPresent: present,
          sandLeave: genLeave,
          sandWork: work,
          drvMacro: drvMacro,
          drvDrum: drvDrum,
          drvLeave: drvLeave,
        );

        if (present.isNotEmpty) {
          final workType = <String, String>{
            for (final id in present) id: 'FullDay',
          };
          final assignments = _attendanceBuildTimedAssignments(
            inBoxByRole: {AttendanceSessionTimes.roleWork: work},
            sessionRoles: {AttendanceSessionTimes.roleWork},
          );
          final id = _attendanceLaborTxId ??
              _attendanceLegacyLaborTxId ??
              '${baseTs}_att_sand';
          if (_attendanceLaborTxId != null || _attendanceLegacyLaborTxId == id) {
            _persistOmitCreatedSessionIds.add(id);
          }
          _attendanceLaborTxId = id;
          if (_attendanceLegacyLaborTxId == id) {
            _attendanceLegacyLaborTxId = null;
          }
          await _persist(
            AppTransaction(
              id: id,
              date: date,
              type: 'Expense',
              category: 'Labor',
              subCategory: 'Attendance',
              laborStatus: 'Work',
              employeeIds: present.toList(),
              amount: 0,
              note: _activeSignatureNote,
              description: _appendRecorder(
                'เช็คชื่อพนักงานท่าทราย: มาทำงาน ${present.length} คน',
              ),
              workAssignments: assignments.isEmpty ? null : assignments,
              workTypeByEmployee: workType.isEmpty ? null : workType,
            ),
          );
        } else {
          await _attendanceDeleteRowIfAny(_attendanceLaborTxId);
          _attendanceLaborTxId = null;
        }

        if (genLeave.isNotEmpty) {
          final id = _attendanceLeaveTxId ??
              _attendanceLegacyLeaveTxId ??
              '${baseTs}_att_sand_leave';
          if (_attendanceLeaveTxId != null ||
              _attendanceLegacyLeaveTxId == id) {
            _persistOmitCreatedSessionIds.add(id);
          }
          _attendanceLeaveTxId = id;
          if (_attendanceLegacyLeaveTxId == id) {
            _attendanceLegacyLeaveTxId = null;
          }
          await _persist(
            AppTransaction(
              id: id,
              date: date,
              type: 'Leave',
              category: 'Leave',
              subCategory: 'Personal',
              laborStatus: 'Leave',
              employeeIds: genLeave.toList(),
              amount: 0,
              note: _activeSignatureNote,
              description: _appendRecorder(
                'เช็คชื่อพนักงานท่าทราย: ลางาน ${genLeave.length} คน',
              ),
              leaveReason: _attLeaveReasonSand,
              leaveDays: 1,
            ),
          );
        } else {
          await _attendanceDeleteRowIfAny(_attendanceLeaveTxId);
          _attendanceLeaveTxId = null;
        }

        await _refreshAttendanceDaysWorked();
      },
    );
  }

  Future<void> _saveAttendanceDriverEntry() async {
    final drvMacro = _attendanceAssignments['att_drv_macro']!.toSet();
    final drvDrum = _attendanceAssignments['att_drv_drum']!.toSet();
    final drvLeave = _attendanceAssignments['att_drv_leave']!.toSet();

    final work = _attendanceAssignments['att_work']!.toSet();
    final genLeave = _attendanceAssignments['att_leave']!.toSet();

    await _runSaveWithPopups(
      successMessage: 'บันทึกเช็คชื่อคนขับรถสำเร็จ',
      saveActionLabel: 'บันทึกเช็คชื่อคนขับรถ',
      saveButtonLabel: 'บันทึกเช็คชื่อ',
      requireSignature: false,
      stayOnPage: true,
      body: () async {
        if (_employeesLoading) {
          _failSave('กำลังโหลดรายชื่อพนักงาน — รอสักครู่แล้วลองใหม่');
        }
        final sessionEmp = _attendanceEmpIdsFromSessions({
          AttendanceSessionTimes.roleMacro,
          AttendanceSessionTimes.roleDrum,
        });
        final present = <String>{...drvMacro, ...drvDrum, ...sessionEmp};
        if (present.isEmpty && drvLeave.isEmpty) {
          _failSave('กรุณาลากรายชื่อลงกล่องอย่างน้อย 1 คน');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final baseTs = DateTime.now().millisecondsSinceEpoch;

        await _attendanceMigrateLegacyIfNeeded(
          date: date,
          baseTs: baseTs,
          savingSand: false,
          sandPresent: work,
          sandLeave: genLeave,
          sandWork: work,
          drvMacro: drvMacro,
          drvDrum: drvDrum,
          drvLeave: drvLeave,
        );

        if (present.isNotEmpty) {
          final workType = <String, String>{
            for (final id in present) id: 'FullDay',
          };
          final assignments = _attendanceBuildTimedAssignments(
            inBoxByRole: {
              AttendanceSessionTimes.roleMacro: drvMacro,
              AttendanceSessionTimes.roleDrum: drvDrum,
            },
            sessionRoles: {
              AttendanceSessionTimes.roleMacro,
              AttendanceSessionTimes.roleDrum,
            },
          );
          final id = _attendanceDriverLaborTxId ??
              _attendanceLegacyLaborTxId ??
              '${baseTs}_att_drv';
          if (_attendanceDriverLaborTxId != null ||
              _attendanceLegacyLaborTxId == id) {
            _persistOmitCreatedSessionIds.add(id);
          }
          _attendanceDriverLaborTxId = id;
          if (_attendanceLegacyLaborTxId == id) {
            _attendanceLegacyLaborTxId = null;
          }
          await _persist(
            AppTransaction(
              id: id,
              date: date,
              type: 'Expense',
              category: 'Labor',
              subCategory: 'Attendance',
              laborStatus: 'Work',
              employeeIds: present.toList(),
              amount: 0,
              note: _activeSignatureNote,
              description: _appendRecorder(
                'เช็คชื่อคนขับรถ: มาทำงาน ${present.length} คน',
              ),
              workAssignments: assignments.isEmpty ? null : assignments,
              workTypeByEmployee: workType.isEmpty ? null : workType,
            ),
          );
        } else {
          await _attendanceDeleteRowIfAny(_attendanceDriverLaborTxId);
          _attendanceDriverLaborTxId = null;
        }

        if (drvLeave.isNotEmpty) {
          final id = _attendanceDriverLeaveTxId ??
              _attendanceLegacyLeaveTxId ??
              '${baseTs}_att_drv_leave';
          if (_attendanceDriverLeaveTxId != null ||
              _attendanceLegacyLeaveTxId == id) {
            _persistOmitCreatedSessionIds.add(id);
          }
          _attendanceDriverLeaveTxId = id;
          if (_attendanceLegacyLeaveTxId == id) {
            _attendanceLegacyLeaveTxId = null;
          }
          await _persist(
            AppTransaction(
              id: id,
              date: date,
              type: 'Leave',
              category: 'Leave',
              subCategory: 'Personal',
              laborStatus: 'Leave',
              employeeIds: drvLeave.toList(),
              amount: 0,
              note: _activeSignatureNote,
              description: _appendRecorder(
                'เช็คชื่อคนขับรถ: ลางาน ${drvLeave.length} คน',
              ),
              leaveReason: _attLeaveReasonDriver,
              leaveDays: 1,
            ),
          );
        } else {
          await _attendanceDeleteRowIfAny(_attendanceDriverLeaveTxId);
          _attendanceDriverLeaveTxId = null;
        }
        await _refreshAttendanceDaysWorked();
      },
    );
  }

  Future<void> _attendanceDeleteRowIfAny(String? id) async {
    final rowId = id?.trim();
    if (rowId == null || rowId.isEmpty) return;
    await _deleteTransactionOfflineAware(rowId);
  }

  /// แยกแถวรวมเก่าเป็น 2 แถวครั้งเดียวเมื่อบันทึกกลุ่มใดกลุ่มหนึ่ง
  Future<void> _attendanceMigrateLegacyIfNeeded({
    required String date,
    required int baseTs,
    required bool savingSand,
    required Set<String> sandPresent,
    required Set<String> sandLeave,
    Set<String> sandWork = const {},
    required Set<String> drvMacro,
    required Set<String> drvDrum,
    required Set<String> drvLeave,
  }) async {
    final legacyLabor = _attendanceLegacyLaborTxId;
    final legacyLeave = _attendanceLegacyLeaveTxId;
    if (legacyLabor == null && legacyLeave == null) return;

    if (savingSand) {
      final otherPresent = <String>{
        ...drvMacro,
        ...drvDrum,
        ..._attendanceEmpIdsFromSessions({
          AttendanceSessionTimes.roleMacro,
          AttendanceSessionTimes.roleDrum,
        }),
      };
      if (_attendanceDriverLaborTxId == null && otherPresent.isNotEmpty) {
        final workType = <String, String>{
          for (final id in otherPresent) id: 'FullDay',
        };
        final assignments = _attendanceBuildTimedAssignments(
          inBoxByRole: {
            AttendanceSessionTimes.roleMacro: drvMacro,
            AttendanceSessionTimes.roleDrum: drvDrum,
          },
          sessionRoles: {
            AttendanceSessionTimes.roleMacro,
            AttendanceSessionTimes.roleDrum,
          },
        );
        final id = '${baseTs}_att_drv_mig';
        _attendanceDriverLaborTxId = id;
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Expense',
            category: 'Labor',
            subCategory: 'Attendance',
            laborStatus: 'Work',
            employeeIds: otherPresent.toList(),
            amount: 0,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'เช็คชื่อคนขับรถ: มาทำงาน ${otherPresent.length} คน',
            ),
            workAssignments: assignments.isEmpty ? null : assignments,
            workTypeByEmployee: workType.isEmpty ? null : workType,
          ),
        );
      }
      if (_attendanceDriverLeaveTxId == null && drvLeave.isNotEmpty) {
        final id = '${baseTs}_att_drv_leave_mig';
        _attendanceDriverLeaveTxId = id;
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Leave',
            category: 'Leave',
            subCategory: 'Personal',
            laborStatus: 'Leave',
            employeeIds: drvLeave.toList(),
            amount: 0,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'เช็คชื่อคนขับรถ: ลางาน ${drvLeave.length} คน',
            ),
            leaveReason: _attLeaveReasonDriver,
            leaveDays: 1,
          ),
        );
      }
    } else {
      final work = sandWork.isNotEmpty
          ? sandWork
          : _attendanceAssignments['att_work']!.toSet();
      final otherPresent = <String>{
        ...sandPresent,
        ..._attendanceEmpIdsFromSessions({AttendanceSessionTimes.roleWork}),
      };
      if (_attendanceLaborTxId == null && otherPresent.isNotEmpty) {
        final workType = <String, String>{
          for (final id in otherPresent) id: 'FullDay',
        };
        final assignments = _attendanceBuildTimedAssignments(
          inBoxByRole: {AttendanceSessionTimes.roleWork: work},
          sessionRoles: {AttendanceSessionTimes.roleWork},
        );
        final id = '${baseTs}_att_sand_mig';
        _attendanceLaborTxId = id;
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Expense',
            category: 'Labor',
            subCategory: 'Attendance',
            laborStatus: 'Work',
            employeeIds: otherPresent.toList(),
            amount: 0,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'เช็คชื่อพนักงานท่าทราย: มาทำงาน ${otherPresent.length} คน',
            ),
            workAssignments: assignments.isEmpty ? null : assignments,
            workTypeByEmployee: workType.isEmpty ? null : workType,
          ),
        );
      }
      if (_attendanceLeaveTxId == null && sandLeave.isNotEmpty) {
        final id = '${baseTs}_att_sand_leave_mig';
        _attendanceLeaveTxId = id;
        await _persist(
          AppTransaction(
            id: id,
            date: date,
            type: 'Leave',
            category: 'Leave',
            subCategory: 'Personal',
            laborStatus: 'Leave',
            employeeIds: sandLeave.toList(),
            amount: 0,
            note: _activeSignatureNote,
            description: _appendRecorder(
              'เช็คชื่อพนักงานท่าทราย: ลางาน ${sandLeave.length} คน',
            ),
            leaveReason: _attLeaveReasonSand,
            leaveDays: 1,
          ),
        );
      }
    }
  }

  /// ครึ่งวันจาก workDetails ของรายการลา (`leave_half:morning|afternoon`)
  String? _leaveHalfPartFromTx(AppTransaction t) {
    final wd = (t.workDetails ?? '').trim();
    if (wd.contains(_leaveHalfMorningMeta)) return 'morning';
    if (wd.contains(_leaveHalfAfternoonMeta)) return 'afternoon';
    final days = t.leaveDays;
    if (days != null && (days - 0.5).abs() < 1e-6) {
      // ครึ่งวันเก่าไม่มี meta — ถือว่าซ้อนกับครึ่งใดก็ได้
      return 'any';
    }
    return null;
  }

  /// ตรวจคนเดิมมีช่วงลาซ้อนกับรายการใหม่ — คืนข้อความ error หรือ null
  String? _leaveOverlapConflictMessage({
    required List<String> empIds,
    required DateTime start,
    required DateTime end,
    required bool isHalfDay,
    required String halfPart,
    String? excludeTxId,
  }) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (endDay.isBefore(startDay)) return null;

    final sources = _moduleDayAllTransactions.isNotEmpty
        ? _moduleDayAllTransactions
        : _moduleDayTransactions;

    for (final empId in empIds) {
      final emp = _employeesById[empId];
      final name = emp != null ? _employeeUiDisplayName(emp) : empId;
      for (var d = startDay;
          !d.isAfter(endDay);
          d = d.add(const Duration(days: 1))) {
        final ymd = _quickYmd(d);
        for (final t in sources) {
          if (excludeTxId != null && t.id == excludeTxId) continue;
          if (!t.employeeIds.contains(empId)) continue;
          if (!laborLeaveCoversCalendarDay(t, ymd)) continue;

          final existingHalf = _leaveHalfPartFromTx(t);
          if (isHalfDay) {
            // คนละครึ่งของวันเดียวกันได้
            if (existingHalf != null &&
                existingHalf != 'any' &&
                existingHalf != halfPart) {
              continue;
            }
          } else if (existingHalf != null && existingHalf != 'any') {
            // ลาเต็มวันซ้อนครึ่งวัน → บล็อก
          }

          return 'มีรายการลาของ $name ครอบคลุมวันที่ ${_formatDate(d)} แล้ว — ไม่บันทึกซ้ำ';
        }
      }
    }
    return null;
  }

  Future<void> _saveLaborLeaveEntry() async {
    // เก็บค่าก่อน async — โหลดรายการวันอาจล้าง controller ระหว่างลายเซ็น/บันทึก
    final leaveEmpIds = _selectedLeaveEmpIds.toList();
    final reason = _leaveReasonController.text.trim();
    // จำนวนวันมาจากช่วงวันที่เลือกในปฏิทินเสมอ
    final leaveRangeDays = _leaveRangeDays;
    final leaveIsHalfDay = _leaveIsHalfDay;
    final leaveHalfPart = _leaveHalfPart;
    final leaveTypeChoice = _leaveTypeChoice;
    final leaveStartDate = _leaveStartDate;
    final leaveEndDate = _leaveEndDate;
    final existingLeaveTxId = _laborLeaveTxId;
    await _runSaveWithPopups(
      successMessage: existingLeaveTxId != null
          ? 'บันทึกการแก้ไขลางานแล้ว'
          : 'บันทึกลางานสำเร็จ',
      saveActionLabel: existingLeaveTxId != null
          ? 'แก้ไขลางาน'
          : 'บันทึกลางาน',
      saveButtonLabel: existingLeaveTxId != null ? 'บันทึกการแก้ไข' : 'บันทึก',
      stayOnPage: true,
      onStayOnPageCleared: () {
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
        _leaveEndDate = _leaveStartDate;
      },
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
        final days = leaveRangeDays.toDouble();
        if (leaveIsHalfDay) {
          if (leaveHalfPart != 'morning' && leaveHalfPart != 'afternoon') {
            _failSave('กรุณาเลือกลาครึ่งเช้าหรือครึ่งบ่าย');
          }
        } else if (days <= 0) {
          _failSave('กรุณาเลือกช่วงวันลาให้ถูกต้อง', field: 'ช่วงวันลา');
        }
        final overlap = _leaveOverlapConflictMessage(
          empIds: leaveEmpIds,
          start: leaveStartDate,
          end: leaveIsHalfDay ? leaveStartDate : leaveEndDate,
          isHalfDay: leaveIsHalfDay,
          halfPart: leaveHalfPart,
          excludeTxId: existingLeaveTxId,
        );
        if (overlap != null) {
          _failSave(overlap, field: 'ช่วงวันลา');
        }
        final effectiveDays = leaveIsHalfDay ? 0.5 : days;
        final halfTh = leaveIsHalfDay
            ? (leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย')
            : '';
        final halfMeta = leaveIsHalfDay
            ? (leaveHalfPart == 'morning'
                  ? _leaveHalfMorningMeta
                  : _leaveHalfAfternoonMeta)
            : '';
        final y = leaveStartDate.year.toString().padLeft(4, '0');
        final m = leaveStartDate.month.toString().padLeft(2, '0');
        final d = leaveStartDate.day.toString().padLeft(2, '0');
        final ymd = '$y-$m-$d';
        final id =
            existingLeaveTxId ?? '${DateTime.now().millisecondsSinceEpoch}_leave';
        if (existingLeaveTxId != null) {
          _persistOmitCreatedSessionIds.add(existingLeaveTxId);
        }
        _laborLeaveTxId = id;
        final typeTh = leaveTypeChoice == 'Sick' ? 'ป่วย' : 'กิจ';
        final descCore = reason.isEmpty ? 'ลา$typeTh' : 'ลา$typeTh: $reason';
        final rangeTh = leaveEndDate.isAfter(leaveStartDate)
            ? ' (${_formatDate(leaveStartDate)} - ${_formatDate(leaveEndDate)}'
                  ' รวม ${effectiveDays.round()} วัน)'
            : '';
        final desc = leaveIsHalfDay
            ? '$descCore (ครึ่งวัน — $halfTh)'
            : '$descCore$rangeTh';
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
        // ออฟไลน์ส่ง LINE ไม่ได้ — ข้ามไปแทนที่จะยิงทิ้งแล้วล้มเงียบ
        if (!_lastPersistQueued) {
          unawaited(notifyLeaveLineAfterSaved(saved, _employees));
        }
      },
    );
  }

  bool _isLaborAdvanceTransaction(AppTransaction t) {
    final sc = (t.subCategory ?? '').trim().toLowerCase();
    final ls = (t.laborStatus ?? '').trim().toLowerCase();
    return t.category == 'Labor' && (sc == 'advance' || ls == 'advance');
  }

  List<AppTransaction> _advanceTxsOnSelectedDay() {
    final ymd = _quickYmd(_selectedDate);
    return [
      for (final t in _moduleDayTransactions)
        if (t.date.startsWith(ymd) && _isLaborAdvanceTransaction(t)) t,
    ];
  }

  Set<String> _advanceEmpIdsAlreadyRequestedOnSelectedDay() {
    final ids = <String>{};
    for (final t in _advanceTxsOnSelectedDay()) {
      ids.addAll(t.employeeIds);
    }
    return ids;
  }

  String? _validateLaborAdvanceForm() {
    if (_selectedAdvanceEmpIds.isEmpty) {
      return 'กรุณาเลือกพนักงาน';
    }
    final blocked = _selectedAdvanceEmpIds.where((id) {
      final e = _employeesById[id];
      return e != null && isExcludedFromAdvanceEmployeePicker(e);
    }).toList();
    if (blocked.isNotEmpty) {
      return 'ไม่สามารถเบิกให้คนขับรถหรือรับจ้างรายวันได้';
    }
    final already = _advanceEmpIdsAlreadyRequestedOnSelectedDay();
    final dupes = _selectedAdvanceEmpIds.where(already.contains).toList();
    if (dupes.isNotEmpty) {
      final names = dupes.map((id) {
        final e = _employeesById[id];
        return e != null ? _employeeUiDisplayName(e) : id;
      }).join(', ');
      return 'ส่งคำขอเบิกเงินวันนี้ไปแล้ว — $names';
    }
    final per =
        double.tryParse(_advanceAmountPerPersonController.text.trim()) ?? 0;
    if (per <= 0) {
      return 'กรุณากรอกจำนวนเงินที่ขอเบิกต่อคนให้มากกว่า 0';
    }
    if (_advancePaymentMethod == AdvanceGmMeta.transfer) {
      if (_advanceBank.trim().isEmpty) {
        return 'กรุณาเลือกธนาคาร';
      }
      if (_advanceAccountController.text.trim().isEmpty) {
        return 'กรุณากรอกเลขบัญชี';
      }
    }
    return null;
  }

  Future<bool> _confirmAdvanceRequestSummary() async {
    _releaseKeyboardFocus();
    AppHaptics.tap();
    final per =
        double.tryParse(_advanceAmountPerPersonController.text.trim()) ?? 0;
    final n = _selectedAdvanceEmpIds.length;
    final total = per * n;
    final slotTh = _advancePayoutSlot == AdvanceGmMeta.evening
        ? 'ช่วงเย็น'
        : 'ช่วงกลางวัน';
    final payTh = _advancePaymentMethod == AdvanceGmMeta.transfer
        ? 'เงินโอน'
        : 'เงินสด';
    final names = _selectedAdvanceEmpIds.map((id) {
      final e = _employeesById[id];
      return e != null ? _employeeUiDisplayName(e) : id;
    }).toList();
    String money(num v) =>
        v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final lines = <String>[
      'วันที่ ${_formatDate(_selectedDate)}',
      'พนักงาน ${names.length} คน',
      ...names.map((n) => '· $n'),
      'จำนวนต่อคน ${money(per)} บาท',
      'รวม ${money(total)} บาท',
      'รับเงิน: $slotTh · $payTh',
      if (_advancePaymentMethod == AdvanceGmMeta.transfer) ...[
        'ธนาคาร ${_advanceBank.trim()}',
        'เลขบัญชี ${_advanceAccountController.text.trim()}',
      ],
    ];
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.receipt_long_rounded,
          size: 36,
          color: Color(0xFFE65100),
        ),
        title: Text(
          'สรุปคำขอเบิกเงิน',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Text(
            lines.join('\n'),
            style: GoogleFonts.kanit(fontSize: 15, height: 1.45),
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'แก้ไข',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ยืนยันส่งคำขอ',
              style: GoogleFonts.kanit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _saveLaborAdvanceEntry() async {
    final preErr = _validateLaborAdvanceForm();
    if (preErr != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(preErr, style: GoogleFonts.kanit()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final confirmed = await _confirmAdvanceRequestSummary();
    if (!confirmed || !mounted) return;

    await _runSaveWithPopups(
      successMessage: 'ส่งคำขอเบิกเงินแล้ว',
      saveActionLabel: 'คำขอเบิกเงิน',
      saveButtonLabel: 'ส่งคำขอเบิกเงิน',
      body: () async {
        final err = _validateLaborAdvanceForm();
        if (err != null) _failSave(err);
        final per =
            double.tryParse(_advanceAmountPerPersonController.text.trim()) ?? 0;
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
        final ymd = _quickYmd(_selectedDate);
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
      saveButtonLabel: _dailyEventTxId != null && _dailyEventTxId!.isNotEmpty
          ? 'อัปเดตเหตุการณ์'
          : 'บันทึกเหตุการณ์',
      stayOnPage: true,
      // คงฟอร์มไว้ให้ตรวจ/แก้ต่อ — hydrate ตอนโหลดวันจะเติมเมื่อ !_saving
      onStayOnPageCleared: null,
      body: () async {
        final text = _dailyEventDescController.text.trim();
        if (text.isEmpty) {
          _failSave('กรุณาระบุรายละเอียดเหตุการณ์');
        }
        final y = _selectedDate.year.toString().padLeft(4, '0');
        final m = _selectedDate.month.toString().padLeft(2, '0');
        final d = _selectedDate.day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final id = (_dailyEventTxId != null && _dailyEventTxId!.trim().isNotEmpty)
            ? _dailyEventTxId!.trim()
            : '${DateTime.now().millisecondsSinceEpoch}_event';
        _dailyEventTxId = id;
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

  void _applyDailyEventToForm(AppTransaction t) {
    _dailyEventTxId = t.id;
    _dailyEventDescController.text = _stripRecorderSuffix(t.description);
    final et = (t.eventType ?? '').trim();
    _dailyEventType = et.isEmpty ? 'info' : et;
    final ep = (t.eventPriority ?? '').trim();
    _dailyEventPriority = ep.isEmpty ? 'normal' : ep;
    _persistOmitCreatedForIds.add(t.id);
  }

  void _hydrateDailyEventFromTransactions(List<AppTransaction> txs) {
    AppTransaction? best;
    for (final t in txs) {
      if (t.category != 'DailyLog') continue;
      if ((t.subCategory ?? '').trim() != 'Event') continue;
      if (t.description.trim().isEmpty) continue;
      best = t;
      break; // matched เรียงใหม่สุดก่อน
    }
    if (best == null) {
      _dailyEventTxId = null;
      _dailyEventDescController.clear();
      _dailyEventType = 'info';
      _dailyEventPriority = 'normal';
      return;
    }
    _applyDailyEventToForm(best);
  }

  void _loadDailyEventIntoForm(AppTransaction t) {
    _applyDailyEventToForm(t);
    _scheduleUiRefresh();
  }

  void _startNewDailyEvent() {
    setState(() {
      _dailyEventTxId = null;
      _dailyEventDescController.clear();
      _dailyEventType = 'info';
      _dailyEventPriority = 'normal';
    });
  }

  String _dailyEventTypeLabel(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'warning':
        return 'เตือน';
      case 'problem':
        return 'ปัญหา';
      case 'success':
        return 'สำเร็จ';
      case 'complaint':
        return 'ข้อร้องเรียน';
      case 'request':
        return 'ความต้องการ';
      default:
        return 'ข้อมูล';
    }
  }

  /// จำนวนวันลาจากช่วงวันที่เลือก (นับรวมวันแรกและวันสุดท้าย)
  int get _leaveRangeDays {
    final diff = _leaveEndDate.difference(_leaveStartDate).inDays;
    return diff < 0 ? 1 : diff + 1;
  }

  void _syncLeaveDaysFromRange() {
    if (_leaveIsHalfDay) {
      _leaveDaysController.text = '0.5';
      return;
    }
    _leaveDaysController.text = '$_leaveRangeDays';
  }

  /// เลือกช่วงวันลาจากปฏิทิน — แสดงเฉพาะเดือนปัจจุบัน + ตัวอักษรใหญ่
  Future<void> _pickLeaveDateRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final last = DateTime(now.year, now.month + 1, 0);
    DateTime clampDay(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(first)) return first;
      if (day.isAfter(last)) return last;
      return day;
    }

    var rangeStart = clampDay(_leaveStartDate);
    var rangeEnd = clampDay(
      _leaveEndDate.isBefore(_leaveStartDate) ? _leaveStartDate : _leaveEndDate,
    );
    if (rangeEnd.isBefore(rangeStart)) rangeEnd = rangeStart;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: rangeStart, end: rangeEnd),
      firstDate: first,
      lastDate: last,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'เลือกวันเริ่มลา — วันสุดท้าย (เดือนนี้)',
      saveText: 'ตกลง',
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            textTheme: base.textTheme.copyWith(
              bodyLarge: GoogleFonts.kanit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              bodyMedium: GoogleFonts.kanit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              titleLarge: GoogleFonts.kanit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              titleSmall: GoogleFonts.kanit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              labelLarge: GoogleFonts.kanit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerHeadlineStyle: GoogleFonts.kanit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A2433),
              ),
              headerHelpStyle: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
              weekdayStyle: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
              ),
              dayStyle: GoogleFonts.kanit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A2433),
              ),
              rangeSelectionBackgroundColor:
                  const Color(0xFF1565C0).withValues(alpha: 0.16),
              todayForegroundColor: const WidgetStatePropertyAll(
                Color(0xFF1565C0),
              ),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return const Color(0xFF1A2433);
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF1565C0);
                }
                return null;
              }),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _leaveStartDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _leaveEndDate = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
      // ลาหลายวันจะไม่ใช่ครึ่งวันแล้ว
      if (_leaveEndDate.isAfter(_leaveStartDate)) _leaveIsHalfDay = false;
      _syncLeaveDaysFromRange();
    });
  }

  Future<void> _pickDate() async {
    // ใช้แคชเต็มชุดเพื่อทำจุดทั้งเดือน — แถววันเดียวไม่พอ
    final txs = await LocalDataCache.readTransactionsFullAny() ??
        _moduleDayAllTransactions;
    if (!mounted) return;
    final picked = await showDailyRecordDayPicker(
      context: context,
      initialDate: _selectedDate,
      transactions: txs,
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
    if (!_blockingModuleBootstrap) {
      return const SizedBox.shrink();
    }
    final showEmployeesLine = _showsEmployeeLoadingUi && _employeesLoading;
    final showTxnLine = _moduleDayLoading;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: AnimatedOpacity(
          duration: Duration(milliseconds: reduceMotion ? 1 : 220),
          curve: Curves.easeOutCubic,
          opacity: 1,
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
      await _deleteTransactionOfflineAware(
        t.id,
        ymd: t.date.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ลบรายการจากฐานข้อมูลแล้ว',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
      await _loadModuleTransactions(
        preserveIncomeUtilitiesForm: _isIncomeUtilitiesEntryMode,
        forceRefresh: !_isOfflineCapableCategory,
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
                      _persistOmitCreatedSessionIds.add(t.id);
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
    final nameCtrl = TextEditingController(text: (t.projectId ?? '').trim());
    final addrCtrl = TextEditingController(text: (t.location ?? '').trim());
    final detailCtrl = TextEditingController(text: (t.workDetails ?? '').trim());
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
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'ชื่อ',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addrCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'ที่อยู่',
                  labelStyle: GoogleFonts.kanit(),
                ),
                style: GoogleFonts.kanit(fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailCtrl,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'รายละเอียด (ไม่บังคับ)',
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
                  final name = nameCtrl.text.trim();
                  final addr = addrCtrl.text.trim();
                  final detail = detailCtrl.text.trim();
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
                    projectId: name.isEmpty ? null : name,
                    location: addr.isEmpty ? null : addr,
                    workDetails: detail.isEmpty ? null : detail,
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
      nameCtrl.dispose();
      addrCtrl.dispose();
      detailCtrl.dispose();
    });
  }

  Future<void> _openSuperAdminWizardIncomeEditor(AppTransaction t) async {
    final amtCtrl = TextEditingController(text: _strNum(t.amount));
    final descCtrl = TextEditingController(
      text: _stripRecorderSuffix(t.description),
    );
    final nameCtrl = TextEditingController(text: (t.projectId ?? '').trim());
    final addrCtrl = TextEditingController(text: (t.location ?? '').trim());
    final detailCtrl = TextEditingController(text: (t.workDetails ?? '').trim());
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
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'ชื่อ',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addrCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'ที่อยู่',
                      labelStyle: GoogleFonts.kanit(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: detailCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'รายละเอียด (ไม่บังคับ)',
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
                      final name = nameCtrl.text.trim();
                      final addr = addrCtrl.text.trim();
                      final detail = detailCtrl.text.trim();
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
                        projectId: name.isEmpty ? null : name,
                        location: addr.isEmpty ? null : addr,
                        workDetails: detail.isEmpty ? null : detail,
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
      nameCtrl.dispose();
      addrCtrl.dispose();
      detailCtrl.dispose();
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
                ..._iuPartyMetaHistoryLines(t),
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
    final isEditingThis = _laborLeaveTxId == t.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isEditingThis ? const Color(0xFFE3F2FD) : const Color(0xFFF5FAFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isEditingThis
                ? const Color(0xFF1565C0)
                : const Color(0xFFBBDEFB),
            width: isEditingThis ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _saving ? null : () => _loadLeaveForEdit(t),
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
      ),
    );
  }

  void _loadLeaveForEdit(AppTransaction t) {
    final wd = (t.workDetails ?? '').trim();
    final halfFromMeta =
        wd == _leaveHalfMorningMeta || wd == _leaveHalfAfternoonMeta;
    final halfFromDays =
        t.leaveDays != null && (t.leaveDays! - 0.5).abs() < 1e-6;
    final isHalf = halfFromMeta || halfFromDays;
  final halfPart = wd == _leaveHalfAfternoonMeta ? 'afternoon' : 'morning';
    final startParts = t.date.trim().split('-');
    DateTime startDate = _leaveStartDate;
    if (startParts.length == 3) {
      final y = int.tryParse(startParts[0]);
      final m = int.tryParse(startParts[1]);
      final d = int.tryParse(startParts[2]);
      if (y != null && m != null && d != null) {
        startDate = DateTime(y, m, d);
      }
    }
    _persistOmitCreatedForIds.add(t.id);
    setState(() {
      _laborLeaveTxId = t.id;
      _selectedLeaveEmpIds
        ..clear()
        ..addAll(t.employeeIds);
      _leaveTypeChoice =
          (t.subCategory ?? '').trim() == 'Sick' ? 'Sick' : 'Personal';
      _leaveIsHalfDay = isHalf;
      _leaveHalfPart = halfPart;
      _leaveReasonController.text = resolvedLeaveReason(t);
      _leaveDaysController.text = isHalf
          ? '0.5'
          : (t.leaveDays != null ? _strNum(t.leaveDays) : '1');
      _leaveStartDate = startDate;
      // สร้างช่วงวันกลับจากจำนวนวันที่บันทึกไว้ (นับรวมวันแรก)
      final savedDays = isHalf ? 1 : (t.leaveDays ?? 1).round();
      _leaveEndDate = savedDays > 1
          ? startDate.add(Duration(days: savedDays - 1))
          : startDate;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'โหลดรายการเพื่อแก้ไข — กดบันทึกการแก้ไขเมื่อเสร็จ',
          style: GoogleFonts.kanit(),
        ),
        duration: const Duration(seconds: 3),
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
                      AppHaptics.tap();
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
                                  ? 'แตะรายการเพื่อโหลดแก้ไข — หนึ่งแถวต่อหนึ่งรายการบันทึก'
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
    if (_isAttendanceMode && _attendanceSection != null) {
      return Theme(
        data: _quickFormTheme(context),
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 550) {
              _handleQuickInputBack();
            }
          },
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _handleQuickInputBack();
            },
            child: _buildAttendanceFullscreenShell(),
          ),
        ),
      );
    }
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
            _handleQuickInputBack();
          }
        },
        child: PopScope(
          // เมนูย่อยน้ำมัน/เช็คชื่อ — ปุ่มย้อนกลับของระบบให้กลับหน้าเลือกเมนูก่อน
          canPop: !(
            (_isFuelMode && _fuelSubMode != null) ||
            (_isAttendanceMode && _attendanceSection != null) ||
            _hasUnsavedModuleChanges
          ),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _handleQuickInputBack();
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
                              if (canPop ||
                                  _fuelSubMode != null ||
                                  _attendanceSection != null)
                                IconButton(
                                  onPressed: _handleQuickInputBack,
                                  iconSize: 28,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(52, 52),
                                    padding: const EdgeInsets.all(12),
                                    tapTargetSize:
                                        MaterialTapTargetSize.padded,
                                  ),
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: SoftSyncIndicator(visible: _softModuleRefreshing),
                ),
              ),
            ],
          ),
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
    _iuPartyNameController.clear();
    _iuPartyAddressController.clear();
    _iuPartyDetailController.clear();
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

  String? _iuOptionalPartyName() {
    final s = _iuPartyNameController.text.trim();
    return s.isEmpty ? null : s;
  }

  String? _iuOptionalPartyAddress() {
    final s = _iuPartyAddressController.text.trim();
    return s.isEmpty ? null : s;
  }

  String? _iuOptionalPartyDetail() {
    final s = _iuPartyDetailController.text.trim();
    return s.isEmpty ? null : s;
  }

  List<Widget> _iuPartyFieldWidgets(
    InputDecoration Function(String label, IconData icon) deco,
  ) {
    return [
      TextField(
        controller: _iuPartyNameController,
        decoration: deco('ชื่อ', Icons.person_outline_rounded),
        style: GoogleFonts.kanit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1D2A3A),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _iuPartyAddressController,
        decoration: deco('ที่อยู่', Icons.home_outlined),
        minLines: 1,
        maxLines: 3,
        style: GoogleFonts.kanit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1D2A3A),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _iuPartyDetailController,
        decoration: deco('รายละเอียด (ไม่บังคับ)', Icons.notes_outlined),
        minLines: 1,
        maxLines: 4,
        style: GoogleFonts.kanit(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1D2A3A),
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  List<Widget> _iuPartyMetaHistoryLines(AppTransaction t) {
    final name = (t.projectId ?? '').trim();
    final addr = (t.location ?? '').trim();
    final detail = (t.workDetails ?? '').trim();
    final lines = <Widget>[];
    if (name.isNotEmpty) {
      lines.add(
        Text(
          'ชื่อ: $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    if (addr.isNotEmpty) {
      lines.add(
        Text(
          'ที่อยู่: $addr',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    if (detail.isNotEmpty) {
      lines.add(
        Text(
          detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    return lines;
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
        final ymd = _quickYmd(_selectedDate);
        final id = '${DateTime.now().millisecondsSinceEpoch}_utils';
        await _persist(
          AppTransaction(
            id: id,
            date: ymd,
            type: 'Expense',
            category: 'Utilities',
            subCategory: sub,
            description: _appendRecorder(sub),
            amount: amt,
            projectId: _iuOptionalPartyName(),
            location: _iuOptionalPartyAddress(),
            workDetails: _iuOptionalPartyDetail(),
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
            projectId: _iuOptionalPartyName(),
            location: _iuOptionalPartyAddress(),
            workDetails: _iuOptionalPartyDetail(),
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
          ..._iuPartyFieldWidgets(deco),
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
          const SizedBox(height: 10),
          ..._iuPartyFieldWidgets(deco),
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
    final total =
        (double.tryParse(_sandQtyMorningController.text) ?? 0) +
        (double.tryParse(_sandQtyAfternoonController.text) ?? 0);
    final drums = double.tryParse(_sandDrumsObtainedController.text) ?? 0;
    const Color sandBorder = Color(0xFF1D4ED8);
    const Color sandFill = Color(0xFFEFF6FF);
    const Color sandLabel = Color(0xFF1E3A8A);
    const Color sandChipFg = Color(0xFF1E40AF);
    const Color sandChipBg = Color(0xFFDBEAFE);
    const Color sandChipSide = Color(0xFF93C5FD);

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
      required TextEditingController controller,
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
            sandMachineColumn(
              controller: controller,
              label: 'จำนวนคิวที่ร่อน',
              operatorNames: _sandOperatorNames,
              accent: sandBorder,
              fill: sandFill,
              labelTint: sandLabel,
              chipFg: sandChipFg,
              chipBg: sandChipBg,
              chipSide: sandChipSide,
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
          periodRow(
            title: 'ช่วงเช้า',
            icon: Icons.wb_sunny_outlined,
            iconColor: const Color(0xFF1F9CF0),
            controller: _sandQtyMorningController,
          ),
          const SizedBox(height: 12),
          periodRow(
            title: 'ช่วงบ่าย',
            icon: Icons.wb_twilight_outlined,
            iconColor: const Color(0xFF2FB6B0),
            controller: _sandQtyAfternoonController,
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
    try {
      if (controller.text != normalized) {
        controller.text = normalized;
      }
    } catch (_) {
      return;
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

  TimeOfDay? _parseFuelTimeOfDay(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'[:.]'));
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatFuelTimeOfDay(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// เลือกเวลาแบบ 24 ชม. — คอลัมน์ชั่วโมง / นาที แยกชัด
  Future<TimeOfDay?> _pickFuelTimeOfDay({TimeOfDay? initial}) {
    return showFuelTimePickerDialog(context, initial: initial);
  }

  Future<void> _pickFuelTime(_FuelVehicleDraft row) async {
    final initial = _parseFuelTimeOfDay(row.timeController.text) ??
        _parseFuelTimeOfDay(row.time) ??
        TimeOfDay.now();
    final t = await _pickFuelTimeOfDay(initial: initial);
    if (t == null || !mounted) return;
    final value = _formatFuelTimeOfDay(t);
    setState(() {
      row.time = value;
      row.timeController.text = value;
    });
  }

  /// แถวที่โหลดเข้าฟอร์มรถดรัมได้ (เว็บ Daily Wizard / เลกาซี category Vehicle)
  bool _isVehicleTripHydrateSource(AppTransaction t) =>
      isVehicleTripHydrateSource(t);

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

    // ดึงค่าจาก "บันทึกและนับจำนวน > จำนวนเที่ยวรถ" ให้สอดคล้องกัน:
    // แยกช่วงเช้า/บ่ายตามเวลาที่กดนับจริง (lapTimes) ไม่ใช่เทไว้ช่องเช้าอย่างเดียว
    final split = vehicleTripPeriodSplit(t);
    d.tripMorning = _strNum(split.morning);
    d.tripAfternoon = _strNum(split.afternoon);
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
      // ใช้ค่ามาตรฐานคิวต่อเที่ยว (3 คิว) เมื่อบันทึกไม่ได้ระบุ เช่น มาจากตัวนับเที่ยว
      final cpt = cptVal > 0
          ? cptVal.toDouble()
          : (defaultCubicPerTripForVehicleName(d.vehicleId) ?? 3);
      d.cubicPerTrip = _strNum(cpt);
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
    // แยกเช้า/บ่ายให้สอดคล้องกับตัวนับ «จำนวนเที่ยวรถ» (lapTimes)
    final split = vehicleTripPeriodSplit(t);
    final tm = split.morning;
    final ta = split.afternoon;
    final totalTripCount = (t.perCarTrips ?? t.tripCount ?? (tm + ta))
        .toDouble();
    // คิวต่อเที่ยว: ใช้ค่าที่บันทึก ถ้าไม่มี (เช่น มาจากตัวนับ) ใช้ค่ามาตรฐาน 3 คิว
    var cpt = (t.cubicPerTrip ?? 0).toDouble();
    if (!isLump && cpt <= 0) {
      cpt = defaultCubicPerTripForVehicleName((t.vehicleId ?? '').trim()) ?? 3;
    }
    var cubic = (t.perCarCubic ?? t.totalCubic ?? 0).toDouble();
    if (!isLump && cubic <= 0) {
      cubic = totalTripCount * cpt;
    }
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

  /// ปุ่มแตะเลือกบนการ์ดแม็คโคร — ใหญ่ กดง่าย มีสถานะติ๊กถูก
  Widget _macroPickButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    bool starred = false,
    VoidCallback? onRemove,
  }) {
    const accent = _macroAccent;
    return AnimatedScale(
      scale: selected ? 1.03 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: Material(
        color: selected ? _macroAccentTint : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : const Color(0xFFE0E6ED),
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: accent,
                    ),
                  )
                else if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
                  ),
                if (starred)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: Color(0xFFFFA000),
                    ),
                  ),
                Text(
                  label,
                  style: GoogleFonts.kanit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? _macroAccentInk
                        : const Color(0xFF37474F),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onRemove,
                    child: const Icon(
                      Icons.cancel_rounded,
                      size: 19,
                      color: Color(0xFFD14343),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _macroSectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.kanit(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF78909C),
      ),
    ),
  );

  Widget _buildMacroVehicleRow({
    required _MacroVehicleDraft row,
    required String vehicleName,
    required int displayIndex,
  }) {
    final isSaved = row.txId != null && row.txId!.trim().isNotEmpty;
    final hasDriver = row.driverId.trim().isNotEmpty;
    final tags = _macroWorkTags(row);
    final hasDetails = tags.isNotEmpty;
    final isFilled = hasDriver && (isSaved || hasDetails);
    final defaultDriverId = _defaultDriverIdForVehicle(vehicleName);
    final drivers = [..._macroSelectableDriversFor(vehicleName)]
      ..sort((a, b) {
        if (a.id == defaultDriverId) return -1;
        if (b.id == defaultDriverId) return 1;
        return 0;
      });
    final customTags =
        tags.where((t) => !_kMacroWorkQuickPhrases.contains(t)).toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFilled || isSaved
            ? _macroAccent.withValues(alpha: 0.05)
            : const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFilled || isSaved
              ? _macroAccent
              : _macroAccent.withValues(alpha: 0.35),
          width: isFilled || isSaved ? 1.8 : 1,
        ),
        boxShadow: [
          if (isFilled || isSaved)
            BoxShadow(
              color: _macroAccent.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _macroAccentTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  size: 30,
                  color: _macroAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รถแม็คโคร คันที่ $displayIndex',
                      style: GoogleFonts.kanit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF607D8B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: _macroAccentInk,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSaved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Text(
                    'บันทึกแล้ว',
                    style: GoogleFonts.kanit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ),
              if (isSaved || hasDriver || hasDetails)
                IconButton(
                  onPressed: () => _handleMacroVehicleRowDelete(row),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFD14343),
                  tooltip: isSaved ? 'ลบรายการที่บันทึก' : 'ล้างแถว',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _macroSectionLabel('คนขับ — แตะเลือก'),
          if (drivers.isEmpty)
            Text(
              'ยังไม่พบพนักงานตำแหน่ง «คนขับรถแม็คโคร» '
              'และยังไม่ได้ตั้งคนขับเริ่มต้นของรถคันนี้บนเว็บ',
              style: GoogleFonts.kanit(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFD14343),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in drivers)
                  _macroPickButton(
                    label: e.nickname.isNotEmpty ? e.nickname : e.name,
                    selected: row.driverId == e.id,
                    starred: e.id == defaultDriverId,
                    icon: Icons.person_outline_rounded,
                    onTap: () {
                      AppHaptics.tap();
                      row.driverId = row.driverId == e.id ? '' : e.id;
                      _scheduleUiRefresh();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 12),
          _macroSectionLabel('ช่วงเวลาทำงาน'),
          Row(
            children: [
              Expanded(
                child: _macroPickButton(
                  label: 'เต็มวัน',
                  icon: Icons.wb_sunny_rounded,
                  selected: row.workType != 'HalfDay',
                  onTap: () {
                    AppHaptics.tap();
                    row.workType = 'FullDay';
                    _scheduleUiRefresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _macroPickButton(
                  label: 'ครึ่งวัน',
                  icon: Icons.brightness_4_rounded,
                  selected: row.workType == 'HalfDay',
                  onTap: () {
                    AppHaptics.tap();
                    row.workType = 'HalfDay';
                    _scheduleUiRefresh();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _macroSectionLabel('งานวันนี้ — แตะเลือกได้หลายงาน แตะซ้ำเพื่อเอาออก'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final phrase in _kMacroWorkQuickPhrases)
                _macroPickButton(
                  label: phrase,
                  selected: tags.contains(phrase),
                  onTap: () => _toggleMacroWorkTag(row, phrase),
                ),
              for (final tag in customTags)
                _macroPickButton(
                  label: tag,
                  selected: true,
                  onTap: () => _toggleMacroWorkTag(row, tag),
                  onRemove: () => _removeMacroWorkTag(row, tag),
                ),
              _macroPickButton(
                label: 'งานอื่น',
                icon: Icons.add_rounded,
                selected: false,
                onTap: () => unawaited(_addMacroCustomWorkTag(row)),
              ),
            ],
          ),
          if (tags.length > 1) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _macroAccentTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _macroAccent.withValues(alpha: 0.45)),
              ),
              child: Text(
                'ลำดับงาน: ${tags.join(' → ')}',
                style: GoogleFonts.kanit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _macroAccentInk,
                  height: 1.3,
                ),
              ),
            ),
          ],
          if (isSaved) ...[
            const SizedBox(height: 12),
            _SmoothPressable(
              enabled: !_saving,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _saveSingleMacroRow(row),
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  'อัปเดตคันนี้',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: _macroAccent,
                  side: BorderSide(
                    color: _macroAccent.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroVehicleFormCard() {
    final macroCars = _fuelMacroCars();
    final pinnedCars = _fuelPinnedMacroCars(macroCars);
    final extraCars = _fuelExtraMacroCars(macroCars);
    bool rowHasData(String car) {
      final r = _macroDraftForVehicle(car);
      if (r == null) return false;
      final saved = r.txId != null && r.txId!.trim().isNotEmpty;
      return saved || r.driverId.trim().isNotEmpty;
    }

    // นับเฉพาะรถที่แสดง (3 คันหลัก + คันเพิ่มเติมที่มีข้อมูล)
    final relevantCars = <String>[
      ...pinnedCars,
      ...extraCars.where(rowHasData),
    ];
    var savedCount = 0;
    var filledCount = 0;
    for (final car in relevantCars) {
      final row = _macroDraftForVehicle(car);
      if (row == null) continue;
      if (row.txId != null && row.txId!.trim().isNotEmpty) savedCount++;
      if (row.driverId.trim().isNotEmpty) filledCount++;
    }
    final totalShown = relevantCars.length;
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
                color: _macroAccent.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (macroCars.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3F3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF5C2C2)),
                  ),
                  child: Text(
                    'ยังไม่พบรายการรถแม็คโครในตั้งค่าแอพ',
                    style: GoogleFonts.kanit(
                      color: const Color(0xFFD14343),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else ...[
                if (_macroDriverEmployees.isEmpty &&
                    !_macroVehicleDrafts.any(
                      (r) => _macroSelectableDriversFor(r.vehicleId).isNotEmpty,
                    ))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'ยังไม่พบพนักงานที่ตำแหน่งเป็น "คนขับรถแม็คโคร" '
                      'และยังไม่ได้ตั้งคนขับเริ่มต้นของรถแม็คโครบนเว็บ '
                      '(ตั้งค่า > รถ/เครื่องจักร)',
                      style: GoogleFonts.kanit(
                        color: const Color(0xFFD14343),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ...List.generate(pinnedCars.length, (index) {
                  final car = pinnedCars[index];
                  final row = _macroDraftForVehicle(car);
                  if (row == null) return const SizedBox.shrink();
                  return _buildMacroVehicleRow(
                    row: row,
                    vehicleName: car,
                    displayIndex: index + 1,
                  );
                }),
                if (extraCars.isNotEmpty)
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      initiallyExpanded: _macroExtraVehiclesExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() => _macroExtraVehiclesExpanded = expanded);
                      },
                      title: Text(
                        'เพิ่มเติม (${extraCars.length} คัน)',
                        style: GoogleFonts.kanit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _macroAccent,
                        ),
                      ),
                      children: [
                        for (var i = 0; i < extraCars.length; i++)
                          Builder(
                            builder: (context) {
                              final car = extraCars[i];
                              final row = _macroDraftForVehicle(car);
                              if (row == null) return const SizedBox.shrink();
                              return _buildMacroVehicleRow(
                                row: row,
                                vehicleName: car,
                                displayIndex: pinnedCars.length + i + 1,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _macroAccentTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: savedCount > 0 || filledCount > 0
                          ? _macroAccent.withValues(alpha: 0.45)
                          : _macroAccent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    'บันทึกแล้ว $savedCount/$totalShown คัน · กรอกแล้ว $filledCount คัน',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _SmoothPressable(
                enabled: !_saving && macroCars.isNotEmpty,
                child: FilledButton.icon(
                  onPressed: _saving || macroCars.isEmpty
                      ? null
                      : _saveQuickEntry,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'กำลังบันทึก...' : 'บันทึกการใช้รถแม็คโคร',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFuelVehicleRow({
    required _FuelVehicleDraft row,
    required String vehicleName,
    int? displayIndex,
  }) {
    final liters = double.tryParse(row.liters.trim()) ?? 0;
    final isFilled = liters > 0 && row.time.trim().isNotEmpty;
    final isSaved = row.txId != null && row.txId!.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFilled || isSaved
            ? const Color(0xFFF3FAFF)
            : const Color(0xFFFAFCFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFilled || isSaved
              ? const Color(0xFF90CAF9)
              : const Color(0xFFDCE8F5),
          width: isFilled || isSaved ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF1565C0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displayIndex != null)
                      Text(
                        'รถแม็คโคร คันที่ $displayIndex',
                        style: GoogleFonts.kanit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF607D8B),
                        ),
                      ),
                    if (displayIndex != null) const SizedBox(height: 2),
                    Text(
                      vehicleName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.kanit(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0D47A1),
                        height: 1.2,
                      ),
                    ),
                    if (_fuelDriverLabelForVehicle(vehicleName).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: Color(0xFF546E7A),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'คนขับ: ${_fuelDriverLabelForVehicle(vehicleName)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF37474F),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isSaved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Text(
                    'บันทึกแล้ว',
                    style: GoogleFonts.kanit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_gas_station_outlined,
                    size: 16,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'น้ำมันดีเซล',
                    style: GoogleFonts.kanit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6D4C00),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'หักจากถัง',
            style: GoogleFonts.kanit(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF546E7A),
            ),
          ),
          const SizedBox(height: 6),
          _buildFuelTankChoiceChips(
            selected: row.fuelTank,
            onChanged: (tank) => setState(() => row.fuelTank = tank),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: row.litersController,
                  readOnly: true,
                  onTap: () => _openNumericPad(
                    controller: row.litersController,
                    label: 'ใช้น้ำมัน (ลิตร)',
                    onChanged: (v) {
                      row.liters = v;
                      _scheduleUiRefresh();
                    },
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
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.timeController,
                  readOnly: true,
                  onTap: () => _pickFuelTime(row),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'เวลาที่เติม',
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ปุ่มย้อนกลับ — เมนูย่อยน้ำมัน/เช็คชื่อกลับหน้าเลือกก่อน
  Future<void> _handleQuickInputBack() async {
    // กลับจากฟอร์มย่อย / กระดาน — ถ้ายังมีข้อมูลค้างให้ถามก่อน
    if ((_isFuelMode && _fuelSubMode != null) ||
        (_isAttendanceMode && _attendanceSection != null)) {
      if (_hasUnsavedModuleChanges) {
        final discard = await _confirmDiscardUnsavedChanges();
        if (!discard || !mounted) return;
        // ยอมทิ้ง — เคลียร์ dirty ก่อน ไม่งั้น PopScope กันออกต่อ
        _captureModuleFormBaseline();
      }
      _releaseKeyboardFocus();
      setState(() {
        if (_isFuelMode) _fuelSubMode = null;
        if (_isAttendanceMode) _attendanceSection = null;
      });
      // baseline หลังออกจากเมนูย่อย เพื่อให้กดกลับอีกครั้งออกหน้าแรกได้
      _captureModuleFormBaseline();
      return;
    }
    if (_hasUnsavedModuleChanges) {
      final discard = await _confirmDiscardUnsavedChanges();
      if (!discard || !mounted) return;
      // ต้อง sync baseline ก่อน pop — canPop ยัง false อยู่ถ้า dirty ค้าง
      _captureModuleFormBaseline();
    }
    if (!mounted) return;
    // ใช้ pop ตรงๆ — maybePop จะติด PopScope.canPop=false แล้ววนถามซ้ำ
    Navigator.of(context).pop();
  }

  /// เมนูที่เตือนเมื่อกดย้อนกลับทั้งที่ยังไม่ได้บันทึก
  static const Set<String> _kUnsavedGuardCategories = {
    'เช็คชื่อ',
    'การใช้รถแม็คโคร',
    'น้ำมัน',
    'ลางาน',
  };

  bool get _guardsUnsavedChanges =>
      _kUnsavedGuardCategories.contains(widget.initialCategory?.trim());

  /// ลายเซ็นของฟอร์มตอนที่ตรงกับข้อมูลที่บันทึกไว้แล้ว
  String? _savedModuleSignature;

  /// ย่อสถานะฟอร์มเป็นข้อความเพื่อเทียบว่าผู้ใช้แก้อะไรไปหลังโหลดล่าสุด
  /// แถวที่ยังว่างไม่ถูกนับ — รายชื่อรถโหลดช้ากว่าฟอร์มได้ ไม่ควรกลายเป็น «แก้แล้ว»
  String _moduleFormSignature() {
    final buf = StringBuffer();
    void put(String key, Object? value) => buf.write('$key=$value;');

    if (_isAttendanceMode) {
      final buckets = _attendanceAssignments.keys.toList()..sort();
      for (final bucket in buckets) {
        final ids = _attendanceAssignments[bucket]!.toList()..sort();
        if (ids.isEmpty) continue;
        put(bucket, ids.join(','));
      }
      return buf.toString();
    }

    if (_isMacroVehicleMode) {
      for (final row in _macroVehicleDrafts) {
        final details = row.isDisposed
            ? ''
            : row.workDetailsController.text.trim();
        if (row.driverId.trim().isEmpty && details.isEmpty) continue;
        put(row.vehicleId, '${row.driverId}|${row.workType}|$details');
      }
      return buf.toString();
    }

    if (_isFuelMode) {
      for (final row in _fuelVehicleDrafts) {
        final liters = row.litersController.text.trim();
        final time = row.timeController.text.trim();
        if (liters.isEmpty && time.isEmpty) continue;
        put(row.vehicleId, '${row.fuelType}|${row.fuelTank}|$liters|$time');
      }
      put(
        'stockIn',
        [
          _fuelStockInLitersController.text.trim(),
          _fuelStockInPricePerLiterController.text.trim(),
          _fuelStockInAmountController.text.trim(),
          _fuelStockInTimeController.text.trim(),
        ].join('|'),
      );
      put(
        'withdraw',
        [
          _fuelWithdrawLitersController.text.trim(),
          _fuelWithdrawTimeController.text.trim(),
          _fuelWithdrawOtherController.text.trim(),
          _fuelWithdrawPurpose.name,
        ].join('|'),
      );
      put(
        'carFill',
        [
          _fuelCarFillLitersController.text.trim(),
          _fuelCarFillTimeController.text.trim(),
          _fuelCarFillOtherController.text.trim(),
          _fuelCarFillVehicle?.name ?? '',
        ].join('|'),
      );
      return buf.toString();
    }

    if (_isLaborLeaveMode) {
      final ids = _selectedLeaveEmpIds.toList()..sort();
      put('emp', ids.join(','));
      put('reason', _leaveReasonController.text.trim());
      put('days', _leaveDaysController.text.trim());
      put('type', _leaveTypeChoice);
      put('half', '$_leaveIsHalfDay|$_leaveHalfPart');
      put('range', '${_quickYmd(_leaveStartDate)}~${_quickYmd(_leaveEndDate)}');
    }
    return buf.toString();
  }

  void _captureModuleFormBaseline() {
    if (!_guardsUnsavedChanges) return;
    _savedModuleSignature = _moduleFormSignature();
  }

  bool get _hasUnsavedModuleChanges {
    if (!_guardsUnsavedChanges || _saving) return false;
    final baseline = _savedModuleSignature;
    if (baseline == null) return false;
    return baseline != _moduleFormSignature();
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    _releaseKeyboardFocus();
    AppHaptics.tap();
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 36,
          color: Color(0xFFF08A24),
        ),
        title: Text(
          'ยังไม่ได้บันทึก',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'ข้อมูลที่กรอกไว้จะหายถ้าออกตอนนี้',
          style: GoogleFonts.kanit(fontSize: 15.5),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'อยู่ต่อ',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'ออกโดยไม่บันทึก',
              style: GoogleFonts.kanit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  /// เนื้อหาเมนู «น้ำมัน» — เลือกเมนูย่อยก่อน แล้วค่อยแสดงฟอร์ม
  Widget _buildFuelModeBody() {
    final mode = _fuelSubMode;
    final child = mode == null
        ? FuelSubModePicker(
            mainDieselLiters: _fuelStock.mainDiesel,
            reserveDieselLiters: _fuelStock.reserveDiesel,
            dateLabel: _formatDate(_selectedDate),
            onSelect: (selected) {
              setState(() {
                _fuelSubMode = selected;
                if (selected == FuelSubMode.stockIn) {
                  _hydrateFuelStockInFromDay();
                } else if (selected == FuelSubMode.withdraw) {
                  _hydrateFuelWithdrawForSelectedPurpose();
                } else if (selected == FuelSubMode.carFill) {
                  _hydrateFuelCarFillForSelectedVehicle();
                }
              });
            },
          )
        : switch (mode) {
            FuelSubMode.stockIn => _buildFuelStockInFormCard(),
            FuelSubMode.withdraw => _buildFuelWithdrawFormCard(),
            FuelSubMode.carFill => _buildFuelCarFillFormCard(),
            FuelSubMode.macroUsage => _buildFuelFormCard(),
          };
    return AnimatedSwitcher(
      duration: Duration(
        milliseconds: DevicePerf.isConstrainedDevice ? 140 : 240,
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey('fuel_sub_${mode?.name ?? 'pick'}'),
        child: child,
      ),
    );
  }

  /// แบนเนอร์คงเหลือ 2 ถัง — ใช้ร่วมทุกฟอร์มย่อยของน้ำมัน
  Widget _buildFuelStockBanner({
    double? pendingMainDelta,
    double? pendingReserveDelta,
    @Deprecated('Use pendingMainDelta') double? pendingDelta,
  }) {
    final mainDelta = pendingMainDelta ?? pendingDelta;
    final main = _fuelStock.mainDiesel;
    final reserve = _fuelStock.reserveDiesel;
    final mainPreview = main + (mainDelta ?? 0);
    final reservePreview = reserve + (pendingReserveDelta ?? 0);
    final overMain = mainPreview > kFuelTankCapacityMainLiters;
    final overReserve = reservePreview > kFuelTankCapacityReserveLiters;
    final negMain = mainPreview < 0;
    final negReserve = reservePreview < 0;
    final warn = overMain || overReserve || negMain || negReserve;

    Widget line(String title, double current, double capacity, double? pending) {
      final preview = current + (pending ?? 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title ${formatFuelLiters(current)} / '
            '${formatFuelLiters(capacity)} ลิตร',
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          if (pending != null && pending != 0) ...[
            const SizedBox(height: 2),
            Text(
              'หลังบันทึก: ${formatFuelLiters(preview)} ลิตร',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: warn
                    ? const Color(0xFFD14343)
                    : const Color(0xFF37474F),
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFF3F3) : const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: warn ? const Color(0xFFF5C2C2) : const Color(0xFFBFD8F4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('ถังหลัก', main, kFuelTankCapacityMainLiters, mainDelta),
          const SizedBox(height: 8),
          line(
            'ถังสำรอง',
            reserve,
            kFuelTankCapacityReserveLiters,
            pendingReserveDelta,
          ),
          if (overMain || overReserve) ...[
            const SizedBox(height: 4),
            Text(
              'เกินความจุถัง',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: const Color(0xFFD14343),
              ),
            ),
          ],
          if (negMain || negReserve) ...[
            const SizedBox(height: 4),
            Text(
              'เบิกมากกว่าน้ำมันที่มีในถัง',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: const Color(0xFFD14343),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFuelTimeInto(TextEditingController controller) async {
    final initial =
        _parseFuelTimeOfDay(controller.text) ?? TimeOfDay.now();
    final t = await _pickFuelTimeOfDay(initial: initial);
    if (t == null || !mounted) return;
    setState(() => controller.text = _formatFuelTimeOfDay(t));
  }

  void _recalcFuelStockInAmount() {
    final liters =
        double.tryParse(_fuelStockInLitersController.text.trim()) ?? 0;
    final price =
        double.tryParse(_fuelStockInPricePerLiterController.text.trim()) ?? 0;
    if (liters <= 0 || price <= 0) return;
    final total = liters * price;
    _fuelStockInAmountController.text = total % 1 == 0
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
  }

  Widget _buildFuelStockInFormCard() {
    final liters =
        double.tryParse(_fuelStockInLitersController.text.trim()) ?? 0;
    final dayRows = _dayFuelStockInRows();
    final editing = _fuelStockInTxId != null && _fuelStockInTxId!.isNotEmpty;
    var priorLiters = 0.0;
    if (editing) {
      for (final r in dayRows) {
        if (r.id == _fuelStockInTxId) {
          priorLiters = fuelTxLiters(r);
          break;
        }
      }
    }
    // แก้รายการเดิม: แสดงเฉพาะส่วนต่างจากค่าที่บันทึกไว้
    final pendingMain = editing ? (liters - priorLiters) : liters;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            editing ? 'แก้ไขน้ำมันเข้าถัง' : 'เพิ่มน้ำมันเข้าถัง',
            style: GoogleFonts.kanit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            editing
                ? 'โหลดรายการของวันนี้แล้ว — แก้ค่าแล้วกดอัปเดต '
                    '(หรือล้างฟอร์มเพื่อเพิ่มรายการใหม่)'
                : 'รถน้ำมันมาเติมดีเซลเข้าถังหลัก — กรอกจำนวนลิตรและเวลา '
                    '(ราคาใส่ทีหลังได้)',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _buildFuelStockBanner(
            pendingMainDelta: pendingMain == 0 ? null : pendingMain,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Text(
                'ดีเซล',
                style: GoogleFonts.kanit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _fuelStockInLitersController,
            readOnly: true,
            onTap: () => _openNumericPad(
              controller: _fuelStockInLitersController,
              label: 'จำนวนลิตรที่เติมเข้าถัง',
              allowDecimal: true,
              maxDecimalPlaces: 2,
              onChanged: (_) {
                _recalcFuelStockInAmount();
                _scheduleUiRefresh();
              },
            ),
            style: GoogleFonts.kanit(
              color: const Color(0xFF1D2A3A),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(
              labelText: 'จำนวนลิตรที่เติมเข้าถัง',
              prefixIcon: Icon(Icons.opacity_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _fuelStockInPricePerLiterController,
                  readOnly: true,
                  onTap: () => _openNumericPad(
                    controller: _fuelStockInPricePerLiterController,
                    label: 'ราคาต่อลิตร (บาท) — ไม่บังคับ',
                    allowDecimal: true,
                    maxDecimalPlaces: 2,
                    onChanged: (_) {
                      _recalcFuelStockInAmount();
                      _scheduleUiRefresh();
                    },
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'ราคาต่อลิตร (ไม่บังคับ)',
                    helperText: 'กรอกทีหลังได้',
                    prefixIcon: Icon(Icons.price_change_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _fuelStockInTimeController,
                  readOnly: true,
                  onTap: () => _pickFuelTimeInto(_fuelStockInTimeController),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'เวลาที่เติม',
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fuelStockInAmountController,
            readOnly: true,
            onTap: () => _openNumericPad(
              controller: _fuelStockInAmountController,
              label: 'จำนวนเงินรวม (บาท) — ไม่บังคับ',
              allowDecimal: true,
              maxDecimalPlaces: 2,
              onChanged: (_) => _scheduleUiRefresh(),
            ),
            style: GoogleFonts.kanit(
              color: const Color(0xFF1D2A3A),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(
              labelText: 'จำนวนเงินรวม (ไม่บังคับ)',
              helperText:
                  'มีราคาแล้วจะคำนวณให้อัตโนมัติ — ว่างไว้ก่อนได้',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 16),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelStockInEntry,
              icon: Icon(
                editing ? Icons.save_outlined : Icons.add_circle_outline,
              ),
              label: Text(
                editing ? 'อัปเดตรายการนี้' : 'บันทึกเพิ่มน้ำมัน',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
                backgroundColor: const Color(0xFF2E7D32),
              ),
            ),
          ),
          if (editing || dayRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(_clearFuelStockInForm),
              child: Text(
                'ล้างฟอร์ม (รายการใหม่)',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: const Color(0xFF546E7A),
                ),
              ),
            ),
          ],
          if (dayRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'รายการรับเข้าวันนี้',
              style: GoogleFonts.kanit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            ...dayRows.map((row) {
              final selected = row.id == _fuelStockInTxId;
              final rowLiters = fuelTxLiters(row);
              final rowTime =
                  _stripRecorderSuffix(row.workDetails ?? '').trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _applyFuelStockInFromTx(row)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFE1E8F0),
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${formatFuelLiters(rowLiters)} ลิตร'
                              '${rowTime.isEmpty ? '' : ' · $rowTime'}'
                              '${row.amount > 0 ? ' · ฿${formatFuelLiters(row.amount)}' : ''}',
                              style: GoogleFonts.kanit(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF334155),
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle,
                              size: 20,
                              color: Color(0xFF2E7D32),
                            )
                          else
                            Text(
                              'แก้ไข',
                              style: GoogleFonts.kanit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFuelTankChoiceChips({
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    Widget chip(String tank, String label, String hint) {
      final on = normalizeFuelTank(selected) == tank;
      return Expanded(
        child: Material(
          color: on ? const Color(0xFFE3F2FD) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(tank),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: on ? const Color(0xFF1565C0) : const Color(0xFFE1E8F0),
                  width: on ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.kanit(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: on
                          ? const Color(0xFF0D47A1)
                          : const Color(0xFF546E7A),
                    ),
                  ),
                  Text(
                    hint,
                    style: GoogleFonts.kanit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF78909C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(kFuelTankMain, 'ถังหลัก', 'เติมที่พล่าม'),
        const SizedBox(width: 8),
        chip(kFuelTankReserve, 'ถังสำรอง', 'เครื่องปั่นไฟ'),
      ],
    );
  }

  Widget _buildFuelWithdrawFormCard() {
    final liters =
        double.tryParse(_fuelWithdrawLitersController.text.trim()) ?? 0;
    final dayKey = _quickYmd(_selectedDate);
    final reconcile = fuelMachineReconcileForDay(
      dayKey,
      _moduleDayAllTransactions,
    );
    final editing =
        _fuelWithdrawTxId != null && _fuelWithdrawTxId!.isNotEmpty;

    Widget purposeTile(FuelWithdrawPurpose purpose, IconData icon) {
      final isSelected = _fuelWithdrawPurpose == purpose;
      final label = purpose == FuelWithdrawPurpose.other
          ? 'อื่นๆ (ระบุ)'
          : fuelWithdrawPurposeLabelOf(purpose);
      final summary = _fuelWithdrawSummaryForPurpose(purpose);
      return Material(
        color: isSelected ? const Color(0xFFFFF3E0) : const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _fuelWithdrawPurpose = purpose;
              _hydrateFuelWithdrawForSelectedPurpose();
            });
            // อื่นๆ: เปิดแป้นพิมพ์ภาษาไทยเมื่อช่องยังว่าง
            if (purpose == FuelWithdrawPurpose.other &&
                _fuelWithdrawOtherController.text.trim().isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(
                  _openThaiTextPad(
                    controller: _fuelWithdrawOtherController,
                    label: 'ระบุรายละเอียด (ภาษาไทย)',
                    onChanged: () => _scheduleUiRefresh(),
                    minLines: 2,
                    maxLines: 3,
                  ),
                );
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFEF6C00)
                    : const Color(0xFFE1E8F0),
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFFEF6C00)
                      : const Color(0xFF90A4AE),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.kanit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? const Color(0xFF8A4B00)
                              : const Color(0xFF546E7A),
                        ),
                      ),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          style: GoogleFonts.kanit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF78909C),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: Color(0xFFEF6C00),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'เบิกน้ำมัน',
            style: GoogleFonts.kanit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFEF6C00),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'เติมเครื่องจักร = โอนเข้าถังสำรอง · '
            'ปั่นไฟ/อื่นๆ = หักจากถังหลัก '
            '(รถยนต์ใช้เมนูเติมน้ำมันรถยนต์)',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _buildFuelStockBanner(
            pendingMainDelta: liters > 0 ? -liters : 0,
            pendingReserveDelta:
                _fuelWithdrawPurpose == FuelWithdrawPurpose.machine &&
                        liters > 0
                    ? liters
                    : 0,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _fuelWithdrawLitersController,
                  readOnly: true,
                  onTap: () => _openNumericPad(
                    controller: _fuelWithdrawLitersController,
                    label: 'จำนวนลิตรที่เบิกออก',
                    allowDecimal: true,
                    maxDecimalPlaces: 2,
                    onChanged: (_) => _scheduleUiRefresh(),
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'จำนวนลิตรที่เบิกออก',
                    prefixIcon: Icon(Icons.opacity_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _fuelWithdrawTimeController,
                  readOnly: true,
                  onTap: () => _pickFuelTimeInto(_fuelWithdrawTimeController),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'เวลาที่เติม',
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'เอาไปใช้ทำอะไร',
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          purposeTile(
            FuelWithdrawPurpose.machine,
            Icons.precision_manufacturing_outlined,
          ),
          const SizedBox(height: 8),
          purposeTile(FuelWithdrawPurpose.generator, Icons.bolt_outlined),
          const SizedBox(height: 8),
          purposeTile(
            FuelWithdrawPurpose.mayor,
            Icons.account_balance_outlined,
          ),
          const SizedBox(height: 8),
          purposeTile(FuelWithdrawPurpose.other, Icons.more_horiz_rounded),
          if (_fuelWithdrawPurpose == FuelWithdrawPurpose.other) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _fuelWithdrawOtherController,
              readOnly: true,
              onTap: () => _openThaiTextPad(
                controller: _fuelWithdrawOtherController,
                label: 'ระบุรายละเอียด (ภาษาไทย)',
                onChanged: () => _scheduleUiRefresh(),
                minLines: 2,
                maxLines: 3,
              ),
              style: GoogleFonts.kanit(
                color: const Color(0xFF1D2A3A),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'ระบุรายละเอียด (ภาษาไทย)',
                helperText: 'กดช่องนี้เพื่อเปิดแป้นพิมพ์ภาษาไทย',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
          ],
          if (_fuelWithdrawPurpose == FuelWithdrawPurpose.machine) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2EAF4)),
              ),
              child: Text(
                'เบิกเพื่อเครื่องจักรวันนี้ '
                '${formatFuelLiters(reconcile.machineWithdraw)} ลิตร · '
                'ลงบันทึกแม็คโครแล้ว '
                '${formatFuelLiters(reconcile.vehicleUsage)} ลิตร · '
                'คงค้าง ${formatFuelLiters(reconcile.remaining)} ลิตร',
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                  color: const Color(0xFF37474F),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelWithdrawEntry,
              icon: Icon(
                editing ? Icons.edit_outlined : Icons.output_rounded,
              ),
              label: Text(
                editing ? 'อัปเดตรายการนี้' : 'บันทึกเบิกน้ำมัน',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
                backgroundColor: const Color(0xFFEF6C00),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelCarFillFormCard() {
    final liters =
        double.tryParse(_fuelCarFillLitersController.text.trim()) ?? 0;
    final editing =
        _fuelCarFillTxId != null && _fuelCarFillTxId!.isNotEmpty;

    Widget vehicleTile(FuelCarFillVehicle vehicle, IconData icon) {
      final isSelected = _fuelCarFillVehicle == vehicle;
      final label = vehicle == FuelCarFillVehicle.other
          ? 'อื่นๆ (ระบุ)'
          : fuelCarFillVehicleLabelOf(vehicle);
      final summary = _fuelCarFillSummaryForVehicle(vehicle);
      return Material(
        color: isSelected ? const Color(0xFFF3E5F5) : const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _fuelCarFillVehicle = vehicle;
              _hydrateFuelCarFillForSelectedVehicle();
            });
            if (vehicle == FuelCarFillVehicle.other &&
                _fuelCarFillOtherController.text.trim().isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(
                  _openThaiTextPad(
                    controller: _fuelCarFillOtherController,
                    label: 'ระบุชื่อรถ (ภาษาไทย)',
                    onChanged: () {
                      _hydrateFuelCarFillForSelectedVehicle();
                      _scheduleUiRefresh();
                    },
                    minLines: 1,
                    maxLines: 2,
                  ),
                );
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6A1B9A)
                    : const Color(0xFFE1E8F0),
                width: isSelected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFF6A1B9A)
                      : const Color(0xFF90A4AE),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.kanit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? const Color(0xFF4A148C)
                              : const Color(0xFF546E7A),
                        ),
                      ),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          style: GoogleFonts.kanit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF78909C),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: Color(0xFF6A1B9A),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'เติมน้ำมันรถยนต์',
            style: GoogleFonts.kanit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'หักจากถังหลัก — เลือกรถแล้วระบุจำนวนลิตรและเวลา',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _buildFuelStockBanner(pendingMainDelta: liters > 0 ? -liters : 0),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _fuelCarFillLitersController,
                  readOnly: true,
                  onTap: () => _openNumericPad(
                    controller: _fuelCarFillLitersController,
                    label: 'จำนวนลิตรที่เติม',
                    allowDecimal: true,
                    maxDecimalPlaces: 2,
                    onChanged: (_) => _scheduleUiRefresh(),
                  ),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'จำนวนลิตรที่เติม',
                    prefixIcon: Icon(Icons.opacity_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _fuelCarFillTimeController,
                  readOnly: true,
                  onTap: () => _pickFuelTimeInto(_fuelCarFillTimeController),
                  style: GoogleFonts.kanit(
                    color: const Color(0xFF1D2A3A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'เวลาที่เติม',
                    prefixIcon: Icon(Icons.access_time_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'เลือกรถยนต์',
            style: GoogleFonts.kanit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          vehicleTile(FuelCarFillVehicle.mighty, Icons.directions_car_outlined),
          const SizedBox(height: 8),
          vehicleTile(
            FuelCarFillVehicle.taplien,
            Icons.airport_shuttle_outlined,
          ),
          const SizedBox(height: 8),
          vehicleTile(FuelCarFillVehicle.ahming, Icons.local_taxi_outlined),
          const SizedBox(height: 8),
          vehicleTile(FuelCarFillVehicle.other, Icons.more_horiz_rounded),
          if (_fuelCarFillVehicle == FuelCarFillVehicle.other) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _fuelCarFillOtherController,
              readOnly: true,
              onTap: () => _openThaiTextPad(
                controller: _fuelCarFillOtherController,
                label: 'ระบุชื่อรถ (ภาษาไทย)',
                onChanged: () {
                  _hydrateFuelCarFillForSelectedVehicle();
                  _scheduleUiRefresh();
                },
                minLines: 1,
                maxLines: 2,
              ),
              style: GoogleFonts.kanit(
                color: const Color(0xFF1D2A3A),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'ระบุชื่อรถ (ภาษาไทย)',
                helperText: 'กดช่องนี้เพื่อเปิดแป้นพิมพ์ภาษาไทย',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SmoothPressable(
            enabled: !_saving,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveFuelCarFillEntry,
              icon: Icon(
                editing
                    ? Icons.edit_outlined
                    : Icons.directions_car_filled_rounded,
              ),
              label: Text(
                editing ? 'อัปเดตรายการนี้' : 'บันทึกเติมน้ำมันรถยนต์',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
                backgroundColor: const Color(0xFF6A1B9A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelFormCard() {
    final fuelCars = _fuelMacroCars();
    final pinnedCars = _fuelPinnedMacroCars(fuelCars);
    final extraCars = _fuelExtraMacroCars(fuelCars);
    final dayKey = _quickYmd(_selectedDate);
    final coverage = fuelVehicleCoverageForDay(dayKey, _moduleDayAllTransactions);
    final litersLabel = coverage.liters % 1 == 0
        ? coverage.liters.toStringAsFixed(0)
        : coverage.liters.toStringAsFixed(2);
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
            'บันทึกการใช้น้ำมันรถแม็คโคร',
            style: GoogleFonts.kanit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F5FAF),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'กรอกเฉพาะคันที่เติมน้ำมันวันนี้ — แต่ละแถวคือรถ 1 คันจากตั้งค่าแอพ',
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          if (fuelCars.isEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF5C2C2)),
              ),
              child: Text(
                'ยังไม่พบรายการรถแม็คโครในตั้งค่าแอพ',
                style: GoogleFonts.kanit(
                  color: const Color(0xFFD14343),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...List.generate(pinnedCars.length, (index) {
              final car = pinnedCars[index];
              final row = _fuelDraftForVehicle(car);
              if (row == null) return const SizedBox.shrink();
              return _buildFuelVehicleRow(
                row: row,
                vehicleName: car,
                displayIndex: index + 1,
              );
            }),
            if (extraCars.isNotEmpty) ...[
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  initiallyExpanded: _fuelExtraVehiclesExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _fuelExtraVehiclesExpanded = expanded);
                  },
                  title: Text(
                    'เพิ่มเติม (${extraCars.length} คัน)',
                    style: GoogleFonts.kanit(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1565C0),
                    ),
                  ),
                  children: [
                    for (final car in extraCars)
                      Builder(
                        builder: (context) {
                          final row = _fuelDraftForVehicle(car);
                          if (row == null) return const SizedBox.shrink();
                          return _buildFuelVehicleRow(
                            row: row,
                            vehicleName: car,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: coverage.liters > 0 || coverage.usedCount > 0
                      ? const Color(0xFFBFD8F4)
                      : const Color(0xFFE2EAF4),
                ),
              ),
              child: Text(
                'วันนี้ใช้รถ ${coverage.usedCount} คัน · เติมน้ำมัน ${coverage.fueledCount} คัน · รวม $litersLabel ลิตร',
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _SmoothPressable(
            enabled: !_saving && fuelCars.isNotEmpty,
            child: FilledButton.icon(
              onPressed: _saving || fuelCars.isEmpty
                  ? null
                  : _saveFuelVehicleUsageEntries,
              icon: const Icon(Icons.local_gas_station_outlined),
              label: Text(
                'บันทึกการใช้น้ำมัน',
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
        _laborAssignments[canon] ??= <String>{};
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
      macroDriverPoolIds: _macroDriverIdsFromVehicleUsageToday(),
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
              ? _buildFuelModeBody()
              : _isHomeSandMode
              ? _buildHomeSandFormCard()
              : _isLaborLeaveMode
              ? _buildLaborLeaveFormCard()
              : _isLaborAdvanceMode
              ? _buildLaborAdvanceFormCard()
              : _isAttendanceMode
              ? _buildAttendanceFormCard()
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
                macroDriverPoolIds: _macroDriverIdsFromVehicleUsageToday(),
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
    final days = _leaveIsHalfDay ? 0.5 : _leaveRangeDays.toDouble();
    final summaryDuration = _leaveIsHalfDay
        ? 'ครึ่งวัน (${_leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย'})'
        : '$_leaveRangeDays วัน';
    final leaveRangeLabel = _leaveEndDate.isAfter(_leaveStartDate)
        ? '${_formatDate(_leaveStartDate)} - ${_formatDate(_leaveEndDate)}'
        : 'เริ่ม ${_formatDate(_leaveStartDate)}';
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
          if (_laborLeaveTxId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF90CAF9)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'กำลังแก้ไขรายการเดิม — กดบันทึกการแก้ไขเมื่อเสร็จ',
                      style: GoogleFonts.kanit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _laborLeaveTxId = null;
                            _selectedLeaveEmpIds.clear();
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
                            _leaveEndDate = _leaveStartDate;
                          }),
                    child: Text(
                      'ยกเลิก',
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                    // ครึ่งวัน = วันเดียวเสมอ
                    _leaveEndDate = _leaveStartDate;
                    _leaveHalfPart = 'morning';
                  }
                  _syncLeaveDaysFromRange();
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
            'ช่วงวันลา',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: const Color(0xFF314C6D),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickLeaveDateRange,
            icon: const Icon(Icons.calendar_month_outlined, size: 22),
            label: Text(
              _leaveEndDate.isAfter(_leaveStartDate)
                  ? '${_formatDate(_leaveStartDate)} → ${_formatDate(_leaveEndDate)}'
                  : _formatDate(_leaveStartDate),
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: const Color(0xFF00695C),
              side: const BorderSide(color: Color(0xFF80CBC4), width: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF80CBC4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  size: 20,
                  color: Color(0xFF00695C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _leaveIsHalfDay
                        ? 'รวม 0.5 วัน (ครึ่งวัน — '
                              '${_leaveHalfPart == 'morning' ? 'ครึ่งเช้า' : 'ครึ่งบ่าย'})'
                        : 'รวม $_leaveRangeDays วัน',
                    style: GoogleFonts.kanit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF00695C),
                    ),
                  ),
                ),
              ],
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
            'แสดงเฉพาะตำแหน่ง: พนักงานท่าทราย, คนขับรถแม็คโคร',
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
                    'ยังไม่พบพนักงานท่าทราย/คนขับรถแม็คโคร — '
                    'ตรวจตำแหน่งงานที่ ตั้งค่า > พนักงาน',
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
          _AnimatedInputField(
            controller: _leaveReasonController,
            decoration: const InputDecoration(
              labelText: 'เหตุผลการลา (ไม่บังคับ)',
              prefixIcon: Icon(Icons.note_alt_outlined),
              hintText: 'ไม่ใส่ก็บันทึกได้',
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
                    'สรุป: ${_selectedLeaveEmpIds.length} คน · '
                    '$leaveRangeLabel · $summaryDuration',
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
    final alreadyRequested = _advanceEmpIdsAlreadyRequestedOnSelectedDay();
    final alreadyNames = alreadyRequested.map((id) {
      final e = _employeesById[id];
      return e != null ? _employeeUiDisplayName(e) : id;
    }).toList()
      ..sort();
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
                  if (alreadyNames.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: Text(
                        'ส่งคำขอวันนี้แล้ว: ${alreadyNames.join(', ')} '
                        '— ไม่สามารถส่งซ้ำสำหรับคนเหล่านี้',
                        style: GoogleFonts.kanit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFBF360C),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  stepLabel(
                    '1',
                    'เลือกพนักงาน',
                    'เลือกได้หลายคน — เฉพาะพนักงานท่าทรายและคนขับรถแม็คโคร',
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
                                    'ยังไม่พบพนักงานท่าทราย/คนขับรถแม็คโคร — '
                                    'ตรวจตำแหน่งงานที่ ตั้งค่า > พนักงาน',
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
                              final requested = alreadyRequested.contains(id);
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
                                      requested ? '$name · ขอแล้ว' : name,
                                      style: GoogleFonts.kanit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: requested
                                            ? const Color(0xFF9E9E9E)
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                                selected: selected,
                                selectedColor: advPrimary.withValues(
                                  alpha: 0.2,
                                ),
                                side: BorderSide(
                                  color: requested
                                      ? const Color(0xFFBDBDBD)
                                      : selected
                                      ? advPrimary
                                      : const Color(0xFFE0E0E0),
                                  width: selected ? 1.8 : 1,
                                ),
                                onSelected: requested
                                    ? null
                                    : (_) {
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

  // ─────────────────── เช็คชื่อ (Attendance) ───────────────────
  bool _attendanceIsDriver(Employee e) =>
      _isDriverEmployee(e) || _isMacroExcavatorDriverEmployee(e);

  /// พูล «#รายชื่อพนักงาน» — เฉพาะตำแหน่ง «พนักงานท่าทราย» (รองรับสะกด ท่า/ทำ)
  bool _isSandYardAttendanceEmployee(Employee e) {
    const titles = {'พนักงานท่าทราย', 'พนักงานทำทราย', 'ท่าทราย'};
    for (final p in _employeePositionTokens(e)) {
      if (titles.contains(p.replaceAll(' ', ''))) return true;
    }
    return false;
  }

  /// เรียงพูล: คนที่มาทำงานบ่อยสุดขึ้นก่อน — เท่ากันเรียงตามชื่อกันลิสต์สลับที่
  int _compareAttendancePoolOrder(Employee a, Employee b) {
    final na = _attendanceDaysWorked[a.id] ?? 0;
    final nb = _attendanceDaysWorked[b.id] ?? 0;
    if (na != nb) return nb.compareTo(na);
    return _employeeUiDisplayName(a).compareTo(_employeeUiDisplayName(b));
  }

  Set<String> _attendanceExclusionGroup(String bucketId) {
    if (_attGeneralPresenceIds.contains(bucketId)) return _attGeneralPresenceIds;
    return _attDriverIds;
  }

  void _attendanceApplyTimedEnter(String bucketId, String empId) {
    final role = AttendanceSessionTimes.roleForBucket(bucketId);
    final now = _attendanceNowHHmm();
    if (role == null) {
      // ลางาน — ปิดเซสชันงานที่เปิดอยู่
      _attendanceSessions = AttendanceSessionTimes.closeOpenForEmp(
        sessions: _attendanceSessions,
        empId: empId,
        roles: AttendanceSessionTimes.timedRoles,
        endHHmm: now,
      );
      return;
    }
    _attendanceSessions = AttendanceSessionTimes.openSession(
      sessions: _attendanceSessions,
      role: role,
      empId: empId,
      startHHmm: now,
    );
  }

  void _attendanceApplyTimedLeave(String bucketId, String empId) {
    final role = AttendanceSessionTimes.roleForBucket(bucketId);
    if (role == null) return;
    _attendanceSessions = AttendanceSessionTimes.closeOpenForEmp(
      sessions: _attendanceSessions,
      empId: empId,
      roles: {role},
      endHHmm: _attendanceNowHHmm(),
    );
  }

  void _attendanceAssignEmp(
    String bucketId,
    String empId,
    Set<String> pickedPool,
  ) {
    AppHaptics.success();
    setState(() {
      for (final id in _attendanceExclusionGroup(bucketId)) {
        _attendanceAssignments[id]?.remove(empId);
      }
      _attendanceAssignments[bucketId]?.add(empId);
      _attendanceBucketExpanded[bucketId] = true;
      pickedPool.remove(empId);
      _attendanceJustDroppedIds.add(empId);
      _attendanceApplyTimedEnter(bucketId, empId);
    });
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() => _attendanceJustDroppedIds.remove(empId));
    });
  }

  void _attendanceRemoveEmp(String bucketId, String empId) {
    AppHaptics.tap();
    setState(() {
      _attendanceApplyTimedLeave(bucketId, empId);
      _attendanceAssignments[bucketId]?.remove(empId);
      if (_attendanceAssignments[bucketId]?.isEmpty ?? true) {
        _attendanceBucketExpanded[bucketId] = false;
      }
    });
  }

  void _attendanceDeleteClosedSession(int index) {
    AppHaptics.tap();
    setState(() {
      _attendanceSessions = AttendanceSessionTimes.removeSessionAt(
        sessions: _attendanceSessions,
        index: index,
      );
    });
  }

  void _attendanceMovePicked(String bucketId, Set<String> pickedPool) {
    if (pickedPool.isEmpty) return;
    AppHaptics.success();
    final moved = pickedPool.toList();
    setState(() {
      final group = _attendanceExclusionGroup(bucketId);
      for (final empId in moved) {
        for (final id in group) {
          _attendanceAssignments[id]?.remove(empId);
        }
        _attendanceAssignments[bucketId]?.add(empId);
        _attendanceJustDroppedIds.add(empId);
        _attendanceApplyTimedEnter(bucketId, empId);
      }
      _attendanceBucketExpanded[bucketId] = true;
      pickedPool.clear();
    });
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        for (final id in moved) {
          _attendanceJustDroppedIds.remove(id);
        }
      });
    });
  }

  String _attendanceActiveChipLabel(String empId, String bucketId) {
    final emp = _employeesById[empId];
    final name = emp == null ? empId : _employeeUiDisplayName(emp);
    final role = AttendanceSessionTimes.roleForBucket(bucketId);
    if (role == null) return name;
    for (final s in _attendanceSessions) {
      if (s.role == role && s.empId == empId && s.isOpen) {
        return '$name · ${s.labelRange}';
      }
    }
    return name;
  }

  /// ช่องดรอปย่อยในการ์ดเช็คชื่อ (ว่าง = แสดง label, มีคน = ชิป)
  Widget _attendanceZone(
    _AttZoneDef z,
    Color color,
    Set<String> pickedPool, {
    bool expand = false,
  }) {
    final ids = _attendanceAssignments[z.bucketId] ?? <String>{};
    final role = AttendanceSessionTimes.roleForBucket(z.bucketId);
    final closedIndexes = <int>[];
    if (role != null) {
      for (var i = 0; i < _attendanceSessions.length; i++) {
        final s = _attendanceSessions[i];
        if (s.role == role && !s.isOpen) closedIndexes.add(i);
      }
    }
    final canMove = pickedPool.isNotEmpty;
    final hasContent = ids.isNotEmpty || closedIndexes.isNotEmpty;
    final Widget body = DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          _attendanceAssignEmp(z.bucketId, d.data, pickedPool),
      builder: (context, cand, _) {
        final hovering = cand.isNotEmpty;
        final child = Material(
          color: hovering
              ? color.withValues(alpha: 0.14)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: canMove
                ? () => _attendanceMovePicked(z.bucketId, pickedPool)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: double.infinity,
              constraints: BoxConstraints(minHeight: expand ? 0 : 56),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hovering
                      ? color.withValues(alpha: 0.85)
                      : color.withValues(alpha: 0.28),
                  width: hovering ? 1.6 : 1,
                ),
              ),
              child: !hasContent
                  ? Center(
                      child: Text(
                        z.subLabel ?? 'วางที่นี่',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.kanit(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  : _attendanceZoneChips(
                      ids: ids,
                      color: color,
                      bucketId: z.bucketId,
                      closedIndexes: closedIndexes,
                      scrollable: expand,
                    ),
            ),
          ),
        );
        if (!expand) return child;
        return SizedBox.expand(child: child);
      },
    );
    return expand ? Expanded(child: body) : body;
  }

  /// ชิปรายชื่อในช่องดรอป — เลื่อนได้เมื่อช่องมีความสูงคงที่ กันชื่อล้นกล่อง
  Widget _attendanceZoneChips({
    required Set<String> ids,
    required Color color,
    required String bucketId,
    required List<int> closedIndexes,
    required bool scrollable,
  }) {
    final chips = <Widget>[];
    for (final empId in ids) {
      final label = _attendanceActiveChipLabel(empId, bucketId);
      chips.add(
        LongPressDraggable<String>(
          data: empId,
          delay: _attDragDelay,
          onDragStarted: () => AppHaptics.tap(),
          feedback: Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            child: Chip(
              label: Text(
                label,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              backgroundColor: color.withValues(alpha: 0.92),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: InputChip(
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              label: Text(
                label,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              onDeleted: null,
            ),
          ),
          child: AnimatedScale(
            scale: _attendanceJustDroppedIds.contains(empId) ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: InputChip(
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              label: Text(
                label,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              deleteIcon: const Icon(Icons.cancel_rounded, size: 20),
              onDeleted: () => _attendanceRemoveEmp(bucketId, empId),
            ),
          ),
        ),
      );
    }
    for (final index in closedIndexes) {
      final s = _attendanceSessions[index];
      final emp = _employeesById[s.empId];
      final name = emp == null ? s.empId : _employeeUiDisplayName(emp);
      final label = '$name · ${s.labelRange}';
      chips.add(
        InputChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          avatar: Icon(Icons.schedule_rounded, size: 18, color: color),
          label: Text(
            label,
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: const Color(0xFF334155),
            ),
          ),
          backgroundColor: color.withValues(alpha: 0.10),
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
          onDeleted: () => _attendanceDeleteClosedSession(index),
        ),
      );
    }
    final wrap = Wrap(spacing: 8, runSpacing: 8, children: chips);
    if (!scrollable) return wrap;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: wrap,
    );
  }

  /// การ์ดกลุ่ม (ทำงาน / ลางาน / แม็คโคร / ดรัม)
  Widget _attendanceGroupedCard({
    required String title,
    required Color color,
    String? subheader,
    required List<_AttZoneDef> zones,
    required Set<String> pickedPool,
    bool equalHeightZones = false,
  }) {
    final count = zones.fold<int>(
      0,
      (sum, z) => sum + (_attendanceAssignments[z.bucketId]?.length ?? 0),
    );
    final zoneWidgets = <Widget>[];
    for (var i = 0; i < zones.length; i++) {
      if (i > 0) zoneWidgets.add(const SizedBox(height: 8));
      zoneWidgets.add(
        _attendanceZone(
          zones[i],
          color,
          pickedPool,
          expand: equalHeightZones,
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: color),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: const Color(0xFF0F172A),
                      height: 1.2,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.kanit(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (subheader != null && subheader.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                subheader,
                style: GoogleFonts.kanit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: equalHeightZones
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: zoneWidgets,
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: zoneWidgets,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// คอลัมน์พูลรายชื่อ (#รายชื่อพนักงาน / #รายชื่อพนักงานขับรถ)
  Widget _attendancePoolColumn({
    required String hashtag,
    required List<Employee> people,
    required Set<String> pickedPool,
    required Set<String> poolBucketIds,
    required String emptyText,
    required ScrollController scrollController,
    Color accent = const Color(0xFF7C4DFF),
  }) {
    final assignedHere = <String>{
      for (final id in poolBucketIds)
        ...(_attendanceAssignments[id] ?? const <String>{}),
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            color: const Color(0xFF475569),
            child: Text(
              people.isEmpty ? hashtag : '$hashtag · ${people.length} คน',
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: DragTarget<String>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (d) {
                final empId = d.data;
                setState(() {
                  for (final id in poolBucketIds) {
                    _attendanceAssignments[id]?.remove(empId);
                  }
                  pickedPool.remove(empId);
                });
              },
              builder: (context, cand, _) {
                final hovering = cand.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  color: hovering
                      ? accent.withValues(alpha: 0.08)
                      : const Color(0xFFF8FAFD),
                  child: people.isEmpty
                      ? Center(
                          child: Text(
                            emptyText,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.kanit(
                              fontSize: 14.5,
                              color: Colors.black45,
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          radius: const Radius.circular(8),
                          child: SingleChildScrollView(
                            controller: scrollController,
                            // เลื่อนดูรายชื่อแบบลื่นๆ (เด้งปลายรายการเหมือนเลื่อนการ์ดในเกม)
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(right: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: people.map((e) {
                                final id = e.id;
                                final selected = pickedPool.contains(id);
                                final placed = assignedHere.contains(id);
                                final name = _employeeUiDisplayName(e);
                                return LongPressDraggable<String>(
                                  data: id,
                                  delay: _attDragDelay,
                                  onDragStarted: () => AppHaptics.tap(),
                                  feedback: Material(
                                    elevation: 6,
                                    borderRadius: BorderRadius.circular(14),
                                    color: Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1565C0),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        name,
                                        style: GoogleFonts.kanit(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: _attendanceNameChip(
                                      name: name,
                                      selected: selected,
                                      placed: placed,
                                      accent: accent,
                                    ),
                                  ),
                                  child: _attendanceNameChip(
                                    name: name,
                                    selected: selected,
                                    placed: placed,
                                    accent: accent,
                                    onTap: () => setState(() {
                                      if (selected) {
                                        pickedPool.remove(id);
                                      } else {
                                        pickedPool.add(id);
                                      }
                                    }),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceNameChip({
    required String name,
    required bool selected,
    required bool placed,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.18)
          : placed
          ? const Color(0xFFE8F5E9)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent
                  : placed
                  ? const Color(0xFF81C784)
                  : const Color(0xFFCBD5E1),
              width: selected || placed ? 1.6 : 1,
            ),
          ),
          child: Text(
            name,
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceFormCard() {
    // หน้าเลือกเมนูย่อย — กระดานเต็มจออยู่ที่ _buildAttendanceFullscreenShell
    final workN = _attendanceAssignments['att_work']?.length ?? 0;
    final leaveN = _attendanceAssignments['att_leave']?.length ?? 0;
    final macroN = _attendanceAssignments['att_drv_macro']?.length ?? 0;
    final drumN = _attendanceAssignments['att_drv_drum']?.length ?? 0;
    final drvLeaveN = _attendanceAssignments['att_drv_leave']?.length ?? 0;

    final sandSummary = workN + leaveN == 0
        ? 'ยังไม่มีรายชื่อวันนี้ — แตะเพื่อเริ่มเช็คชื่อ'
        : 'ทำงาน $workN · ลา $leaveN';
    final driverSummary = macroN + drumN + drvLeaveN == 0
        ? 'ยังไม่มีรายชื่อวันนี้ — แตะเพื่อเริ่มเช็คชื่อ'
        : 'แม็คโคร $macroN · ดรัม $drumN · ลา $drvLeaveN';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3ECF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _employeeDataLoadProgressBanner(),
          AttendanceSubModePicker(
            sandYardSummary: sandSummary,
            driverSummary: driverSummary,
            onSelect: (section) {
              AppHaptics.confirm();
              setState(() => _attendanceSection = section);
            },
          ),
        ],
      ),
    );
  }

  String _attendanceSectionTitle(AttendanceSection section) {
    return switch (section) {
      AttendanceSection.sandYard => 'เช็คชื่อพนักงานท่าทราย',
      AttendanceSection.driver => 'เช็คชื่อคนขับรถ',
    };
  }

  String _attendanceSectionSaveLabel(AttendanceSection section) {
    return switch (section) {
      AttendanceSection.sandYard => 'บันทึกเช็คชื่อพนักงานท่าทราย',
      AttendanceSection.driver => 'บันทึกเช็คชื่อคนขับรถ',
    };
  }

  String _attendanceBoardSummary(AttendanceSection section) {
    if (section == AttendanceSection.sandYard) {
      final work = _attendanceAssignments['att_work']?.length ?? 0;
      final leave = _attendanceAssignments['att_leave']?.length ?? 0;
      return 'ทำงาน $work · ลา $leave';
    }
    final macro = _attendanceAssignments['att_drv_macro']?.length ?? 0;
    final drum = _attendanceAssignments['att_drv_drum']?.length ?? 0;
    final leave = _attendanceAssignments['att_drv_leave']?.length ?? 0;
    return 'แม็คโคร $macro · ดรัม $drum · ลา $leave';
  }

  Widget _buildAttendanceFullscreenShell() {
    final section = _attendanceSection!;
    final y = _selectedDate.year + 543;
    final dateLabel =
        '${_selectedDate.day}/${_selectedDate.month}/$y';
    final canSave = !_saving && !_employeesLoading;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _handleQuickInputBack,
                    iconSize: 28,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      padding: const EdgeInsets.all(12),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: const Color(0xFF0F5FAF),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _attendanceSectionTitle(section),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.kanit(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F5FAF),
                          ),
                        ),
                        Text(
                          dateLabel,
                          style: GoogleFonts.kanit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            if (_employeesLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _employeeDataLoadProgressBanner(),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: section == AttendanceSection.sandYard
                    ? _buildAttendanceSandYardBoard()
                    : _buildAttendanceDriverBoard(),
              ),
            ),
            Material(
              elevation: 8,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _attendanceBoardSummary(section),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.kanit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SmoothPressable(
                        enabled: canSave,
                        child: FilledButton.icon(
                          onPressed: canSave ? _saveQuickEntry : null,
                          icon: const Icon(Icons.how_to_reg_outlined),
                          label: Text(
                            _saving
                                ? 'กำลังบันทึก...'
                                : _attendanceSectionSaveLabel(section),
                            style: GoogleFonts.kanit(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
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
    );
  }

  Widget _buildAttendanceSandYardBoard() {
    const genPresenceIds = _attGeneralPresenceIds;
    final assignedGeneral = <String>{
      for (final id in genPresenceIds)
        ...(_attendanceAssignments[id] ?? const <String>{}),
    };
    final generalPeople = _employees
        .where(
          (e) =>
              !e.inactive &&
              _isSandYardAttendanceEmployee(e) &&
              !assignedGeneral.contains(e.id),
        )
        .toList()
      ..sort(_compareAttendancePoolOrder);

    const workColor = Color(0xFF2FB6A6);
    const leaveColor = Color(0xFFEF5D6E);
    const poolAccent = Color(0xFF7C4DFF);

    final workCard = _attendanceGroupedCard(
      title: '#ทำงาน',
      color: workColor,
      zones: const [_AttZoneDef(bucketId: 'att_work', subLabel: 'วางชื่อที่นี่')],
      pickedPool: _attendanceGeneralPicked,
      equalHeightZones: true,
    );
    final leaveCard = _attendanceGroupedCard(
      title: '#ลางาน',
      color: leaveColor,
      zones: const [_AttZoneDef(bucketId: 'att_leave', subLabel: 'ลางาน')],
      pickedPool: _attendanceGeneralPicked,
      equalHeightZones: true,
    );
    final pool = _attendancePoolColumn(
      hashtag: '#รายชื่อพนักงานท่าทราย',
      people: generalPeople,
      pickedPool: _attendanceGeneralPicked,
      poolBucketIds: genPresenceIds,
      emptyText:
          'ไม่มีพนักงานท่าทราย — ตรวจตำแหน่งงานที่ ตั้งค่า > พนักงาน',
      accent: poolAccent,
      scrollController: _attendanceGeneralPoolScroll,
    );

    return _attendanceFullscreenBoardLayout(
      pool: pool,
      cards: [
        _AttBoardCard(
          child: workCard,
          height: _attWorkCardHeight,
          flex: 3,
          onResize: _resizeAttWorkCard,
          onResizeEnd: _saveAttWorkCardHeight,
        ),
        _AttBoardCard(child: leaveCard, height: 220, flex: 2),
      ],
    );
  }

  Widget _buildAttendanceDriverBoard() {
    final assignedDriver = <String>{
      for (final id in _attDriverIds)
        ...(_attendanceAssignments[id] ?? const <String>{}),
    };
    final driverPeople = _employees
        .where(
          (e) =>
              !e.inactive &&
              _isMacroExcavatorDriverEmployee(e) &&
              !assignedDriver.contains(e.id),
        )
        .toList()
      ..sort(_compareAttendancePoolOrder);

    const macroColor = Color(0xFFEF6C00);
    const drumColor = Color(0xFF6C6FE6);
    const leaveColor = Color(0xFFEF5D6E);

    final macroCard = _attendanceGroupedCard(
      title: 'ขับรถแม็คโคร',
      color: macroColor,
      zones: const [
        _AttZoneDef(bucketId: 'att_drv_macro', subLabel: 'ขับรถแม็คโคร'),
      ],
      pickedPool: _attendanceDriverPicked,
      equalHeightZones: true,
    );
    final drumCard = _attendanceGroupedCard(
      title: 'ขับรถดรัม',
      color: drumColor,
      zones: const [
        _AttZoneDef(bucketId: 'att_drv_drum', subLabel: 'ขับรถดรัม'),
      ],
      pickedPool: _attendanceDriverPicked,
      equalHeightZones: true,
    );
    final leaveCard = _attendanceGroupedCard(
      title: '#ลางาน',
      color: leaveColor,
      zones: const [
        _AttZoneDef(bucketId: 'att_drv_leave', subLabel: 'ลางาน'),
      ],
      pickedPool: _attendanceDriverPicked,
      equalHeightZones: true,
    );

    final pool = _attendancePoolColumn(
      hashtag: '#รายชื่อคนขับรถแม็คโคร',
      people: driverPeople,
      pickedPool: _attendanceDriverPicked,
      poolBucketIds: _attDriverIds,
      emptyText:
          'ไม่มีพนักงานตำแหน่งคนขับรถแม็คโคร — ตรวจตำแหน่งงานที่ ตั้งค่า > พนักงาน',
      accent: const Color(0xFF00897B),
      scrollController: _attendanceDriverPoolScroll,
    );

    return _attendanceFullscreenBoardLayout(
      pool: pool,
      cards: [
        _AttBoardCard(child: macroCard, height: 240),
        _AttBoardCard(child: drumCard, height: 240),
        _AttBoardCard(child: leaveCard, height: 220),
      ],
    );
  }

  Widget _attendanceFullscreenBoardLayout({
    required Widget pool,
    required List<_AttBoardCard> cards,
  }) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820 || size.width > size.height;
    const gap = 10.0;

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 34, child: pool),
          const SizedBox(width: gap),
          Expanded(
            flex: 66,
            child: Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  Expanded(flex: cards[i].flex, child: cards[i].child),
                ],
              ],
            ),
          ),
        ],
      );
    }

    // ชิปชื่อใหญ่ขึ้น — เผื่อความสูงพูลและการ์ดตามไปด้วย
    final poolH = (size.height * 0.38).clamp(300.0, 460.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: poolH, child: pool),
        const SizedBox(height: gap),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (context, index) => const SizedBox(height: gap),
            itemBuilder: (context, i) {
              final card = cards[i];
              final body = SizedBox(height: card.height, child: card.child);
              final onResize = card.onResize;
              if (onResize == null) return body;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  _attendanceCardResizeHandle(card, onResize),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// จับลากขอบล่างการ์ดเพื่อย่อ-ขยาย (เก็บค่าไว้ใช้ครั้งหน้า)
  Widget _attendanceCardResizeHandle(
    _AttBoardCard card,
    ValueChanged<double> onResize,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onResize(card.height + d.delta.dy),
      onVerticalDragEnd: (_) {
        AppHaptics.tap();
        final done = card.onResizeEnd;
        if (done != null) unawaited(done());
      },
      child: Semantics(
        label: 'ปรับความสูงกล่อง',
        child: SizedBox(
          height: 26,
          child: Center(
            child: Container(
              width: 64,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFB6C2D2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
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
          if (savedToday > 0) ...[
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
            const SizedBox(height: 8),
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
            if (_dailyEventTxId != null && _dailyEventTxId!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_note_rounded,
                      size: 20,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'กำลังแก้ไขเหตุการณ์ที่มีอยู่ — กดอัปเดตเพื่อบันทึก หรือเพิ่มใหม่ด้านล่าง',
                        style: GoogleFonts.kanit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFBF360C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                icon: Icon(
                  _dailyEventTxId != null && _dailyEventTxId!.isNotEmpty
                      ? Icons.update_rounded
                      : Icons.save_outlined,
                ),
                label: Text(
                  _saving
                      ? 'กำลังบันทึก...'
                      : (_dailyEventTxId != null &&
                                _dailyEventTxId!.isNotEmpty
                            ? 'อัปเดตเหตุการณ์'
                            : 'บันทึกเหตุการณ์'),
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
            if (_dailyEventTxId != null && _dailyEventTxId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _startNewDailyEvent,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  'เพิ่มเหตุการณ์ใหม่',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            _buildDailyEventSavedTodaySection(),
          ],
        ),
      ),
    );
  }

  Widget _dailyEventSavedDetailCard(AppTransaction t) {
    final desc = _stripRecorderSuffix(t.description).trim();
    final typeLabel = _dailyEventTypeLabel(t.eventType);
    final pri = ((t.eventPriority ?? '').trim() == 'urgent') ? 'ด่วน' : 'ปกติ';
    final created = t.createdAt;
    final timeHint = created != null
        ? 'บันทึกในระบบ ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
        : null;
    final isCurrent = t.id == _dailyEventTxId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFFFF8E1) : const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? const Color(0xFFFFB74D) : const Color(0xFFFFE0B2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$typeLabel • $pri${isCurrent ? ' • กำลังแก้ไข' : ''}',
            style: GoogleFonts.kanit(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE65100),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc.isEmpty ? '(ไม่มีรายละเอียด)' : desc,
            style: GoogleFonts.kanit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D2A3A),
              height: 1.3,
            ),
          ),
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

  Widget _buildDailyEventSavedTodaySection() {
    final saved = _moduleDayTransactions
        .where(
          (t) =>
              t.category == 'DailyLog' &&
              (t.subCategory ?? '').trim() == 'Event' &&
              t.description.trim().isNotEmpty,
        )
        .toList();
    if (saved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'ยังไม่มีเหตุการณ์ในวันที่เลือก — กรอกด้านบนแล้วกดบันทึก',
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
          'เหตุการณ์วันนี้ (${saved.length} รายการ) — แตะเพื่อแก้ไข',
          style: GoogleFonts.kanit(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFE65100),
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
                  _loadDailyEventIntoForm(t);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'โหลดเหตุการณ์มาแก้ไขด้านบนแล้ว',
                        style: GoogleFonts.kanit(),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: _dailyEventSavedDetailCard(t),
              ),
            ),
          ),
        ),
      ],
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
        AppHaptics.tap();
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
      AppHaptics.tap();
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
    AppHaptics.tap();
    setState(() => _digits += k);
  }

  void _clear() {
    AppHaptics.tap();
    setState(() => _digits = '');
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    AppHaptics.tap();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _confirm() {
    Navigator.of(widget.dialogContext).pop(_digits);
  }

  @override
  Widget build(BuildContext context) {
    final ls = widget.landscape;
    final keyH = ls ? 68.0 : 86.0;
    final gap = ls ? 10.0 : 12.0;
    final radius = ls ? 14.0 : 16.0;
    const accent = Color(0xFF1565C0);
    const ink = Color(0xFF142033);
    const muted = Color(0xFF64748B);

    final keyStyle = GoogleFonts.kanit(
      fontSize: ls ? 32.0 : 40.0,
      fontWeight: FontWeight.w800,
      color: ink,
      height: 1,
    );
    final labelStyle = GoogleFonts.kanit(
      fontSize: ls ? 15.0 : 17.0,
      fontWeight: FontWeight.w700,
      color: muted,
    );
    final previewStyle = GoogleFonts.kanit(
      fontSize: ls ? 40.0 : 48.0,
      fontWeight: FontWeight.w800,
      color: accent,
      height: 1.05,
      letterSpacing: 0.5,
    );

    Widget cell(Widget child) => Expanded(child: child);

    Widget pressKey({
      required VoidCallback? onTap,
      required Color bg,
      required Widget child,
      Color? borderColor,
      SoftPressDepthShadow? depth,
    }) {
      return SoftPressButton(
        onTap: onTap,
        size: SoftPressSize.large,
        borderRadius: radius,
        isDarkSurface: false,
        liftWhenIdle: true,
        idleLiftY: -1.5,
        // haptic อยู่ใน _tapDigit / _clear / _backspace แล้ว
        hapticOnDown: false,
        hitPadding: EdgeInsets.zero,
        depthShadow: depth ??
            SoftPressDepthShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offsetY: 3,
              pressedBlurRadius: 3,
              pressedOffsetY: 1,
            ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? const Color(0xFFE2E8F0),
            ),
          ),
          child: SizedBox(
            height: keyH,
            child: Center(child: child),
          ),
        ),
      );
    }

    Widget digitKey(String d) => pressKey(
          onTap: () => _tapDigit(d),
          bg: Colors.white,
          child: Text(d, style: keyStyle),
        );

    Widget auxKey({
      required Color bg,
      required Color border,
      required VoidCallback? onTap,
      required Widget child,
      required Color shadowColor,
    }) {
      return pressKey(
        onTap: onTap,
        bg: bg,
        borderColor: border,
        depth: SoftPressDepthShadow(
          color: shadowColor.withValues(alpha: 0.18),
          blurRadius: 10,
          offsetY: 3,
          pressedBlurRadius: 3,
          pressedOffsetY: 1,
        ),
        child: child,
      );
    }

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          ls ? 12 : 14,
          ls ? 10 : 14,
          ls ? 12 : 14,
          ls ? 10 : 14,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFEEF3F9)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD5E0EC)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: ls ? 12 : 14,
                  vertical: ls ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE7F4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.label,
                      maxLines: ls ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                    SizedBox(height: ls ? 4 : 6),
                    Text(
                      _digits.isEmpty ? '0' : _digits,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: previewStyle,
                    ),
                  ],
                ),
              ),
              SizedBox(height: ls ? 10 : 14),
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
                      bg: const Color(0xFFFFF1F1),
                      border: const Color(0xFFF5C2C2),
                      shadowColor: const Color(0xFFD64545),
                      onTap: _clear,
                      child: Text(
                        'ล้าง',
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w800,
                          fontSize: ls ? 18.0 : 22.0,
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
                      bg: const Color(0xFFE8F1FF),
                      border: const Color(0xFFBFD8F4),
                      shadowColor: accent,
                      onTap: _backspace,
                      child: Icon(
                        Icons.backspace_outlined,
                        size: ls ? 28 : 32,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: ls ? 10 : 12),
              SoftPressButton(
                onTap: _confirm,
                size: SoftPressSize.large,
                borderRadius: 16,
                isDarkSurface: true,
                liftWhenIdle: true,
                idleLiftY: -2,
                hitPadding: EdgeInsets.zero,
                useConfirmHaptic: true,
                depthShadow: SoftPressDepthShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offsetY: 4,
                  pressedBlurRadius: 4,
                  pressedOffsetY: 1,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    height: ls ? 62 : 72,
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: ls ? 26 : 30,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'เสร็จสิ้น',
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w800,
                            fontSize: ls ? 20.0 : 24.0,
                            color: Colors.white,
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

enum _LaborEmpPoolKind { allEmployees, sandSieve, excavatorMac, nightWatch, generalLabor }

const _sandSievePoolCategoryIds = {
  'wash_old',
  'wash_new',
  'sand_watch',
};
const _excavatorMacPoolCategoryIds = {'macro_driver', 'dig_haul'};
const _nightWatchPoolCategoryIds = {'night_shift'};

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
    required this.macroDriverPoolIds,
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
  final Set<String> macroDriverPoolIds;
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
                    widget.poolKind == _LaborEmpPoolKind.excavatorMac &&
                            widget.macroDriverPoolIds.isEmpty
                        ? 'ยังไม่มีคนขับจากบันทึกการใช้รถแม็คโครวันนี้ — บันทึกที่เมนู «การใช้รถแม็คโคร» ก่อน'
                        : 'ไม่มีพนักงานในกลุ่มนี้ (หรือจัดลงกล่องงานหมดแล้ว)',
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
            .where(
              (e) {
                if (widget.poolKind == _LaborEmpPoolKind.excavatorMac) {
                  return widget.macroDriverPoolIds.contains(e.id);
                }
                if (widget.poolKind == _LaborEmpPoolKind.allEmployees) {
                  return true;
                }
                return widget.laborEmpPoolKind(e) == widget.poolKind;
              },
            )
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
        case _LaborEmpPoolKind.allEmployees:
          return List<_LaborWorkCategory>.from(widget.categories);
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
      final showGeneralOnly = widget.poolKind == _LaborEmpPoolKind.generalLabor ||
          widget.poolKind == _LaborEmpPoolKind.allEmployees;
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
                      kind: _LaborEmpPoolKind.allEmployees,
                      icon: Icons.grid_view_rounded,
                      title: 'พนักงานทั้งหมด',
                      subtitle: 'เลือกลงกล่องงานได้ทุกประเภท',
                    ),
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
                      subtitle: widget.macroDriverPoolIds.isEmpty
                          ? 'ยังไม่มีคนขับจากบันทึกใช้รถแม็คโครวันนี้'
                          : 'จากบันทึกการใช้รถแม็คโคร ${widget.macroDriverPoolIds.length} คน',
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
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
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
  /// main | reserve — default ถังสำรอง (ปั่นไฟ)
  String fuelTank = kFuelTankReserve;
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

/// นิยามช่องดรอปย่อยในกระดานเช็คชื่อ
class _AttZoneDef {
  const _AttZoneDef({required this.bucketId, this.subLabel});

  final String bucketId;
  final String? subLabel;
}

/// การ์ดหนึ่งใบบนกระดานเช็คชื่อ — จอกว้างใช้ [flex], จอสูงใช้ [height]
class _AttBoardCard {
  const _AttBoardCard({
    required this.child,
    required this.height,
    this.flex = 1,
    this.onResize,
    this.onResizeEnd,
  });

  final Widget child;
  final double height;
  final int flex;
  final ValueChanged<double>? onResize;
  final Future<void> Function()? onResizeEnd;
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
              AppHaptics.confirm();
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
