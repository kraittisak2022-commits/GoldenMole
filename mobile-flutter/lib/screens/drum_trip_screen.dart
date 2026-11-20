import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/count_record_offline_sync.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../theme/daily_palette.dart';
import '../utils/advance_line_notify.dart';
import '../utils/app_haptics.dart';
import '../utils/count_record_vehicle_defaults.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/drum_trip_summary.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../utils/save_error_message.dart';
import '../utils/vehicle_catalog.dart';
import '../widgets/daily_record_day_picker.dart';
import '../widgets/drum_trip_widgets.dart';
import '../widgets/save_operation_feedback.dart';
import '../widgets/soft_sync_indicator.dart';

class _VehicleTripDraft {
  _VehicleTripDraft() : workDetailsController = TextEditingController();

  String? tripTxId;
  String vehicleId = '';
  String driverId = '';
  String billingMode = 'PerTrip'; // PerTrip | LumpSum
  String morningText = '';
  String afternoonText = '';
  String cubicPerTripText = '';
  String lumpSumCubicText = '';
  String workType = 'FullDay'; // FullDay | HalfDay | Hourly
  String hourlyHoursText = '';
  bool isCountRecordSynced = false;
  final TextEditingController workDetailsController;

  bool get isEditingSaved => (tripTxId ?? '').trim().isNotEmpty;

  bool get hasAnyInput {
    final lumpFilled =
        billingMode == 'LumpSum' && lumpSumCubicText.trim().isNotEmpty;
    return vehicleId.trim().isNotEmpty ||
        driverId.trim().isNotEmpty ||
        workDetailsController.text.trim().isNotEmpty ||
        hourlyHoursText.trim().isNotEmpty ||
        morningText.trim().isNotEmpty ||
        afternoonText.trim().isNotEmpty ||
        cubicPerTripText.trim().isNotEmpty ||
        lumpFilled;
  }

  VehicleTripRowStatus get status => resolveVehicleTripRowStatus(
        vehicleId: vehicleId,
        driverId: driverId,
        billingMode: billingMode,
        morningTrips: parseVehicleTripNumber(morningText),
        afternoonTrips: parseVehicleTripNumber(afternoonText),
        cubicPerTrip: parseVehicleTripNumber(cubicPerTripText),
        lumpSumTotalCubic: parseVehicleTripNumber(lumpSumCubicText),
        workType: workType,
        hourlyHours: parseVehicleTripNumber(hourlyHoursText),
        isEditingSaved: isEditingSaved,
      );

  void dispose() {
    workDetailsController.dispose();
  }
}

/// หน้าบันทึกรถดรัมและจำนวนเที่ยว (UX/UI ระดับ Pro — กดไว แยกสีประจำคัน คำนวณคิวอัตโนมัติ)
class DrumTripScreen extends StatefulWidget {
  const DrumTripScreen({
    super.key,
    required this.service,
    required this.employeeService,
    required this.currentAdmin,
    this.appBarTitle = 'บันทึกรถดรัมและจำนวนเที่ยว',
    required this.selectedDateForModule,
    this.serverOnlineHint = true,
  });

  final TransactionService service;
  final EmployeeService employeeService;
  final AdminUser currentAdmin;
  final String appBarTitle;
  final DateTime selectedDateForModule;
  final bool serverOnlineHint;

  @override
  State<DrumTripScreen> createState() => _DrumTripScreenState();
}

class _DrumTripScreenState extends State<DrumTripScreen> {
  static const List<String> _thaiMonthsShort = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  final Object _remoteListenerKey = Object();
  final ScrollController _scrollController = ScrollController();

  late DateTime _selectedDate;
  bool _loadingDay = true;
  bool _saving = false;
  bool _hasUnsavedEdits = false;

  VehicleCatalog _vehicleCatalog = VehicleCatalog.empty;
  Map<String, String> _vehicleDefaultDrivers = const {};
  List<Employee> _employees = const [];
  List<AppTransaction> _allHistoryTransactions = const [];
  List<AppTransaction> _dayTransactions = const [];

  final List<_VehicleTripDraft> _drafts = [_VehicleTripDraft()];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.selectedDateForModule.year,
      widget.selectedDateForModule.month,
      widget.selectedDateForModule.day,
    );
    MobileErrorScreenTracker.set(
      page: widget.appBarTitle,
      pageId: MobileScreenIds.pageQuickInput,
      module: 'จำนวนเที่ยวรถ',
      stepId: MobileScreenIds.quickInputStep('จำนวนเที่ยวรถ'),
    );
    CountRecordOfflineSync.instance.addRemoteChangeListener(
      _remoteListenerKey,
      _onRemoteChanged,
    );
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    CountRecordOfflineSync.instance.removeRemoteChangeListener(
      _remoteListenerKey,
    );
    _scrollController.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _onRemoteChanged() {
    if (!mounted || _saving) return;
    unawaited(_loadDayTransactions(forceRefresh: false));
  }

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatThaiDate(DateTime d) {
    final be = d.year + 543;
    return '${d.day} ${_thaiMonthsShort[d.month - 1]} $be';
  }

  String _recorderSuffix() {
    final name = widget.currentAdmin.displayName.trim().isNotEmpty
        ? widget.currentAdmin.displayName.trim()
        : widget.currentAdmin.username.trim();
    return name.isEmpty ? '' : ' (บันทึกโดย $name)';
  }

  String _appendRecorder(String text) {
    final trimmed = text.trim();
    final suffix = _recorderSuffix();
    if (trimmed.isEmpty || suffix.isEmpty) return trimmed;
    if (trimmed.contains('(บันทึกโดย ')) return trimmed;
    return '$trimmed$suffix';
  }

  String _stripRecorder(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\s*\(บันทึกโดย [^)]+\)\s*$'), '').trim();
  }

  /// คัดเฉพาะพนักงานตำแหน่งคนขับรถดั๊มที่ยังใช้งานอยู่เท่านั้น
  List<Employee> get _activeDrivers => filterDrumTripDrivers(_employees);

  Map<String, Employee> get _employeesById => {
        for (final e in _employees) e.id: e,
      };

  List<String> get _drumCars {
    final raw = <String>[];
    final seen = <String>{};

    void addIfDrum(String name) {
      final t = name.trim();
      if (t.isEmpty || !isVehicleTripDrumCarName(t)) return;
      final compact = compactVehicleLabel(t);
      if (seen.add(compact)) raw.add(t);
    }

    for (final name in _vehicleCatalog.names) {
      addIfDrum(name);
    }
    for (final t in _dayTransactions) {
      if (transactionMatchesVehicleTripModuleList(t)) {
        addIfDrum(transactionVehicleLabel(t));
      }
    }
    for (final t in _allHistoryTransactions) {
      if (transactionMatchesVehicleTripModuleList(t)) {
        addIfDrum(transactionVehicleLabel(t));
      }
    }
    return sortCountRecordVehicles(
      cars: raw,
      tripHistory: _allHistoryTransactions,
    );
  }

  List<AppTransaction> get _savedTripsForDay {
    final ymd = _ymd(_selectedDate);
    return latestVehicleTripsByVehicle(_dayTransactions, ymd: ymd)
        .where(transactionMatchesVehicleTripModuleList)
        .toList();
  }

  List<String> get _workDetailSuggestions {
    final freq = <String, int>{};
    for (final t in _allHistoryTransactions) {
      if (!transactionMatchesVehicleTripModuleList(t)) continue;
      final cleaned = _stripRecorder(t.workDetails)
          .replaceAll(RegExp(r'\s*\([^)]*ชม\.\)\s*$'), '')
          .trim();
      if (cleaned.isEmpty || cleaned.length > 36) continue;
      freq[cleaned] = (freq[cleaned] ?? 0) + 1;
    }
    final list = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.map((e) => e.key).take(6).toList();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loadingDay = true);
    try {
      final cachedCatalog =
          await CountRecordOfflineSync.instance.readCachedVehicleCatalog();
      final cachedDefaults = await CountRecordOfflineSync.instance
          .readCachedVehicleDefaultDrivers();
      if (mounted) {
        setState(() {
          _vehicleCatalog = cachedCatalog;
          _vehicleDefaultDrivers = {
            ...cachedDefaults,
            ...cachedCatalog.defaultDriversByName,
          };
        });
      }

      final results = await Future.wait<dynamic>([
        widget.employeeService.fetchEmployees(),
        widget.service.fetchTransactions(),
        CountRecordOfflineSync.instance
            .fetchAndCacheVehicleCatalog(Supabase.instance.client),
      ]);

      final employees = results[0] as List<Employee>;
      final history = results[1] as List<AppTransaction>;
      final freshCatalog = results[2] as VehicleCatalog;

      if (mounted) {
        setState(() {
          _employees = employees;
          _allHistoryTransactions = history;
          if (freshCatalog.rows.isNotEmpty) {
            _vehicleCatalog = freshCatalog;
            _vehicleDefaultDrivers = {
              ..._vehicleDefaultDrivers,
              ...freshCatalog.defaultDriversByName,
            };
          }
        });
      }
      await _loadDayTransactions(forceRefresh: false);
    } catch (_) {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _loadDayTransactions({required bool forceRefresh}) async {
    if (mounted) setState(() => _loadingDay = true);
    final ymd = _ymd(_selectedDate);
    try {
      final serverRows = await widget.service.fetchTransactionsForDate(
        ymd,
        forceRefresh: forceRefresh,
      );
      final merged = await CountRecordOfflineSync.instance.mergeForDayAsync(
        ymd,
        serverRows,
      );
      if (!mounted) return;
      setState(() {
        _dayTransactions = merged;
        _loadingDay = false;
      });
    } catch (_) {
      try {
        final offlineOnly = await CountRecordOfflineSync.instance
            .mergeForDayAsync(ymd, const []);
        if (!mounted) return;
        setState(() {
          _dayTransactions = offlineOnly;
          _loadingDay = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingDay = false);
      }
    }
  }

  Future<void> _changeDate(DateTime newDate) async {
    final normalized = DateTime(newDate.year, newDate.month, newDate.day);
    if (normalized == _selectedDate) return;
    if (_hasUnsavedEdits) {
      final discard = await _confirmDiscardUnsaved();
      if (discard != true || !mounted) return;
    }
    setState(() {
      _selectedDate = normalized;
      _resetDraftsToSingleEmpty();
      _hasUnsavedEdits = false;
    });
    await _loadDayTransactions(forceRefresh: false);
  }

  Future<void> _pickDateFromCalendar() async {
    AppHaptics.tap();
    final picked = await showDailyRecordDayPicker(
      context: context,
      initialDate: _selectedDate,
      transactions: _allHistoryTransactions,
    );
    if (picked != null && mounted) {
      await _changeDate(picked);
    }
  }

  void _resetDraftsToSingleEmpty() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts
      ..clear()
      ..add(_VehicleTripDraft());
  }

  void _selectVehicleForDraft(int index, String carName) {
    final draft = _drafts[index];
    final existing = _findSavedTripByVehicle(carName);
    setState(() {
      _hasUnsavedEdits = true;
      if (existing != null) {
        _hydrateDraftFromTransaction(draft, existing);
      } else {
        draft.tripTxId = null;
        draft.isCountRecordSynced = false;
        draft.vehicleId = carName;
        final defaultDriver = resolveCountRecordDefaultDriverId(
          vehicleId: carName,
          drivers: _activeDrivers,
          tripHistory: _allHistoryTransactions,
          vehicleDefaultDrivers: _vehicleDefaultDrivers,
        );
        if (defaultDriver != null && defaultDriver.isNotEmpty) {
          draft.driverId = defaultDriver;
        }
        if (draft.cubicPerTripText.trim().isEmpty) {
          draft.cubicPerTripText = formatVehicleTripNumber(
            defaultCubicPerTripForDrumVehicle(carName),
          );
        }
      }
    });
  }

  AppTransaction? _findSavedTripByVehicle(String carName) {
    for (final t in _savedTripsForDay) {
      if (transactionVehicleMatches(t, carName)) return t;
    }
    return null;
  }

  void _hydrateDraftFromTransaction(
    _VehicleTripDraft draft,
    AppTransaction tx,
  ) {
    final split = vehicleTripPeriodSplit(tx);
    final billing =
        (tx.tripBillingMode ?? '').trim() == 'LumpSum' ? 'LumpSum' : 'PerTrip';
    final totalCubic = tx.totalCubic ?? tx.perCarCubic ?? 0;
    final cubicPerTrip = tx.cubicPerTrip ??
        defaultCubicPerTripForDrumVehicle(transactionVehicleLabel(tx));
    final cleanDetails = _stripRecorder(tx.workDetails)
        .replaceAll(RegExp(r'\s*\([^)]*ชม\.\)\s*$'), '')
        .trim();

    draft.tripTxId = tx.id;
    draft.vehicleId = transactionVehicleLabel(tx);
    draft.driverId = (tx.driverId ?? '').trim();
    draft.billingMode = billing;
    draft.morningText =
        split.morning > 0 ? formatVehicleTripNumber(split.morning) : '';
    draft.afternoonText =
        split.afternoon > 0 ? formatVehicleTripNumber(split.afternoon) : '';
    draft.cubicPerTripText =
        cubicPerTrip > 0 ? formatVehicleTripNumber(cubicPerTrip) : '';
    draft.lumpSumCubicText = billing == 'LumpSum' && totalCubic > 0
        ? formatVehicleTripNumber(totalCubic)
        : '';
    draft.workType = (tx.workType == 'HalfDay' || tx.workType == 'Hourly')
        ? tx.workType!
        : 'FullDay';
    draft.hourlyHoursText = (tx.otHours != null && tx.otHours! > 0)
        ? formatVehicleTripNumber(tx.otHours!)
        : '';
    draft.workDetailsController.text = cleanDetails;
    draft.isCountRecordSynced = isCountRecordVehicleTrip(tx);
  }

  void _editSavedTransaction(AppTransaction tx) {
    final vehicleLabel = transactionVehicleLabel(tx);
    final existingIdx = _drafts.indexWhere(
      (d) =>
          d.tripTxId == tx.id ||
          (d.vehicleId.trim().isNotEmpty &&
              vehicleIdsLikelyMatch(d.vehicleId, vehicleLabel)),
    );
    setState(() {
      _hasUnsavedEdits = true;
      if (existingIdx >= 0) {
        _hydrateDraftFromTransaction(_drafts[existingIdx], tx);
      } else if (_drafts.length == 1 && !_drafts.first.hasAnyInput) {
        _hydrateDraftFromTransaction(_drafts.first, tx);
      } else {
        final next = _VehicleTripDraft();
        _hydrateDraftFromTransaction(next, tx);
        _drafts.add(next);
      }
    });
    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _addDraftCard() {
    AppHaptics.tap();
    setState(() {
      _drafts.add(_VehicleTripDraft());
    });
  }

  void _removeDraftCard(int index) {
    if (_drafts.length <= 1) return;
    AppHaptics.tap();
    setState(() {
      final removed = _drafts.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _showProNumericPad({
    required String title,
    required String unit,
    required String initialValue,
    required ValueChanged<String> onApply,
    bool allowDecimal = true,
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProNumericPadSheet(
        title: title,
        unit: unit,
        initialValue: initialValue,
        allowDecimal: allowDecimal,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _hasUnsavedEdits = true;
        onApply(result);
      });
    }
  }

  Future<void> _confirmAndDeleteSaved(AppTransaction tx) async {
    final vehicleLabel = transactionVehicleLabel(tx);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ลบรายการรถดรัม?',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'ต้องการลบข้อมูล "$vehicleLabel" วันที่ ${_formatThaiDate(_selectedDate)} ใช่หรือไม่?',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('ยกเลิก', style: GoogleFonts.kanit()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('ลบรายการ', style: GoogleFonts.kanit()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    SaveOperationFeedback.showSaving(context);
    try {
      final ymd = _ymd(_selectedDate);
      final queuedOffline = await CountRecordOfflineSync.instance.delete(
        service: widget.service,
        client: Supabase.instance.client,
        id: tx.id,
        ymd: ymd,
        dayServerRows: _dayTransactions,
        serverOnlineHint: widget.serverOnlineHint,
      );
      if (!mounted) return;
      setState(() {
        _drafts.removeWhere((d) => d.tripTxId == tx.id);
        if (_drafts.isEmpty) _drafts.add(_VehicleTripDraft());
      });
      await _loadDayTransactions(forceRefresh: !queuedOffline);
      if (!mounted) return;
      AppHaptics.success();
      await SaveOperationFeedback.showSuccessStayOnPage(
        context: context,
        message: queuedOffline
            ? 'ลบรายการแล้ว (รอซิงก์เมื่อออนไลน์)'
            : 'ลบรายการ "$vehicleLabel" สำเร็จ',
      );
    } catch (e) {
      if (!mounted) return;
      final fields = extractSaveErrorReportFields(e);
      await SaveOperationFeedback.showError(
        context: context,
        title: 'ลบไม่สำเร็จ',
        message: fields.cause,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAllDrafts() async {
    if (_saving) return;
    final activeRows = _drafts.where((d) => d.hasAnyInput).toList();
    if (activeRows.isEmpty) {
      _showValidationError('กรุณาเลือกรถดรัมและกรอกข้อมูลอย่างน้อย 1 คัน');
      return;
    }

    final seenVehicles = <String>{};
    for (final row in activeRows) {
      final vehicle = row.vehicleId.trim();
      final driver = row.driverId.trim();
      if (vehicle.isEmpty) {
        _showValidationError('กรุณาเลือกรถดรัมให้ครบทุกการ์ด');
        return;
      }
      if (driver.isEmpty) {
        _showValidationError('กรุณาเลือกคนขับสำหรับ "$vehicle"');
        return;
      }
      if (!seenVehicles.add(compactVehicleLabel(vehicle))) {
        _showValidationError('พบรถ "$vehicle" ซ้ำในฟอร์ม — แก้ไขที่การ์ดเดิมแทน');
        return;
      }

      final morning = parseVehicleTripNumber(row.morningText);
      final afternoon = parseVehicleTripNumber(row.afternoonText);
      final totalTrips = morning + afternoon;
      final cubicPerTrip = parseVehicleTripNumber(row.cubicPerTripText);
      final lumpCubic = parseVehicleTripNumber(row.lumpSumCubicText);
      final hourlyHours = parseVehicleTripNumber(row.hourlyHoursText);

      if (row.workType == 'Hourly' && hourlyHours <= 0) {
        _showValidationError('กรุณาระบุชั่วโมงทำงานสำหรับ "$vehicle"');
        return;
      }
      if (row.billingMode == 'LumpSum') {
        if (lumpCubic <= 0) {
          _showValidationError(
            'กรุณาระบุปริมาณรวม (เหมา) ให้มากกว่า 0 สำหรับ "$vehicle"',
          );
          return;
        }
      } else {
        if (totalTrips <= 0) {
          _showValidationError(
            'กรุณาระบุจำนวนเที่ยว (เช้าหรือบ่าย) สำหรับ "$vehicle"',
          );
          return;
        }
        if (cubicPerTrip <= 0) {
          _showValidationError('กรุณาระบุคิวต่อเที่ยวสำหรับ "$vehicle"');
          return;
        }
      }
    }

    AppHaptics.confirm();
    setState(() => _saving = true);
    SaveOperationFeedback.showSaving(context);

    try {
      final ymd = _ymd(_selectedDate);
      List<AppTransaction> serverDayRows;
      try {
        serverDayRows = await widget.service.fetchTransactionsForDate(
          ymd,
          forceRefresh: true,
        );
      } catch (_) {
        serverDayRows = List<AppTransaction>.from(_dayTransactions);
      }

      final existingById = {for (final t in serverDayRows) t.id: t};

      for (final row in activeRows) {
        final vehicle = row.vehicleId.trim();
        final selfId = row.tripTxId?.trim();
        for (final t in serverDayRows) {
          if (!isVehicleTripHydrateSource(t)) continue;
          if (selfId != null && selfId.isNotEmpty && t.id == selfId) continue;
          if (transactionVehicleMatches(t, vehicle)) {
            throw Exception(
              'มีบันทึกรถ "$vehicle" ในวันนี้แล้ว — แตะที่ชื่อรถหรือปุ่มแก้ไขเพื่อโหลดมาอัปเดต',
            );
          }
        }
      }

      final lineItems = <VehicleTripLineItem>[];
      var anyOffline = false;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (var i = 0; i < activeRows.length; i++) {
        final row = activeRows[i];
        final vehicle = row.vehicleId.trim();
        final driver = row.driverId.trim();
        final details = row.workDetailsController.text.trim();
        final morning = parseVehicleTripNumber(row.morningText);
        final afternoon = parseVehicleTripNumber(row.afternoonText);
        final totalTrips = morning + afternoon;
        final hourlyHours = parseVehicleTripNumber(row.hourlyHoursText);
        final workType =
            (row.workType == 'HalfDay' || row.workType == 'Hourly')
                ? row.workType
                : 'FullDay';

        final detailsWithHours = workType == 'Hourly'
            ? (details.isEmpty
                ? 'งานรายชั่วโมง ${formatVehicleTripNumber(hourlyHours)} ชม.'
                : '$details (${formatVehicleTripNumber(hourlyHours)} ชม.)')
            : details;

        final isExisting = (row.tripTxId ?? '').trim().isNotEmpty;
        final tripId = isExisting ? row.tripTxId!.trim() : '${nowMs}_trip_$i';
        row.tripTxId = tripId;

        final existingTx = existingById[tripId];
        final lapAssignments = existingTx?.workAssignments;
        final driverEmp = _employeesById[driver];
        final driverName =
            driverEmp != null ? driverDisplayLabel(driverEmp) : driver;

        late AppTransaction tx;
        if (row.billingMode == 'LumpSum') {
          final lumpCubic = parseVehicleTripNumber(row.lumpSumCubicText);
          tx = AppTransaction(
            id: tripId,
            date: ymd,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            description: _appendRecorder(
              '$vehicle: เหมา ${formatVehicleTripNumber(lumpCubic)} คิว • เช้า ${formatVehicleTripNumber(morning)} เที่ยว บ่าย ${formatVehicleTripNumber(afternoon)} เที่ยว',
            ),
            amount: 0,
            vehicleId: vehicle,
            driverId: driver,
            tripBillingMode: 'LumpSum',
            tripCount: totalTrips,
            tripMorning: morning,
            tripAfternoon: afternoon,
            cubicPerTrip: 0,
            totalCubic: lumpCubic,
            perCarTrips: totalTrips,
            perCarCubic: lumpCubic,
            workDetails: _appendRecorder(detailsWithHours),
            workType: workType,
            otHours: workType == 'Hourly' ? hourlyHours : null,
            workAssignments: lapAssignments,
          );
          lineItems.add(
            VehicleTripLineItem(
              vehicle: vehicle,
              driverName: driverName,
              billingLabel: 'เหมา',
              detailLine:
                  'รวม ${formatVehicleTripNumber(lumpCubic)} คิว · เช้า ${formatVehicleTripNumber(morning)} / บ่าย ${formatVehicleTripNumber(afternoon)} เที่ยว',
            ),
          );
        } else {
          final cubicPerTrip = parseVehicleTripNumber(row.cubicPerTripText);
          final totalCubic = totalTrips * cubicPerTrip;
          tx = AppTransaction(
            id: tripId,
            date: ymd,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            description: _appendRecorder(
              '$vehicle: ${formatVehicleTripNumber(totalTrips)} เที่ยว × ${formatVehicleTripNumber(cubicPerTrip)} คิว',
            ),
            amount: 0,
            vehicleId: vehicle,
            driverId: driver,
            tripBillingMode: 'PerTrip',
            tripCount: totalTrips,
            tripMorning: morning,
            tripAfternoon: afternoon,
            cubicPerTrip: cubicPerTrip,
            totalCubic: totalCubic,
            perCarTrips: totalTrips,
            perCarCubic: totalCubic,
            workDetails: _appendRecorder(detailsWithHours),
            workType: workType,
            otHours: workType == 'Hourly' ? hourlyHours : null,
            workAssignments: lapAssignments,
          );
          lineItems.add(
            VehicleTripLineItem(
              vehicle: vehicle,
              driverName: driverName,
              billingLabel: 'คิดเป็นเที่ยว',
              detailLine:
                  'เช้า ${formatVehicleTripNumber(morning)} / บ่าย ${formatVehicleTripNumber(afternoon)} · รวม ${formatVehicleTripNumber(totalTrips)} เที่ยว × ${formatVehicleTripNumber(cubicPerTrip)} คิว = ${formatVehicleTripNumber(totalCubic)} คิว',
            ),
          );
        }

        final stamped = stampVehicleAndDriverNames(
          tx,
          catalog: _vehicleCatalog,
          employees: _employees,
        );

        final queuedOffline = await CountRecordOfflineSync.instance.persist(
          service: widget.service,
          client: Supabase.instance.client,
          transaction: stamped,
          omitCreatedAt: isExisting,
          dayServerRows: serverDayRows,
          serverOnlineHint: widget.serverOnlineHint,
        );
        if (queuedOffline) anyOffline = true;
      }

      AdvanceLineNotifyStatus? lineStatus;
      try {
        lineStatus = await notifyVehicleTripLineAfterSaved(
          dateYmd: ymd,
          items: lineItems,
        );
      } catch (_) {}

      await _loadDayTransactions(forceRefresh: !anyOffline);
      if (!mounted) return;
      setState(() {
        _resetDraftsToSingleEmpty();
        _hasUnsavedEdits = false;
      });
      AppHaptics.success();

      final baseMsg = anyOffline
          ? 'บันทึกออฟไลน์สำเร็จ (จะซิงก์อัตโนมัติ)'
          : 'บันทึกรถดรัมและจำนวนเที่ยวสำเร็จ';
      final fullMsg = lineStatus != null && !anyOffline
          ? '$baseMsg · ${lineStatus.successSuffixTh()}'
          : baseMsg;

      await SaveOperationFeedback.showSuccessStayOnPage(
        context: context,
        message: fullMsg,
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.warn();
      final fields = extractSaveErrorReportFields(
        e,
        context: const SaveErrorContext(
          page: 'บันทึกรถดรัมและจำนวนเที่ยว',
          action: 'บันทึกรถดรัมและจำนวนเที่ยว',
          button: 'บันทึกรถดรัม',
        ),
      );
      await SaveOperationFeedback.showError(
        context: context,
        title: 'บันทึกไม่สำเร็จ',
        message: fields.cause,
        subtitle: buildSaveErrorPopupSubtitle(fields),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showValidationError(String message) {
    AppHaptics.warn();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFB45309),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool?> _confirmDiscardUnsaved() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'ยังไม่ได้บันทึกข้อมูล',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'มีข้อมูลที่กำลังกรอกค้างอยู่ ต้องการออกโดยไม่บันทึกใช่หรือไม่?',
          style: GoogleFonts.kanit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('อยู่หน้านี้ต่อ', style: GoogleFonts.kanit()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('ออกโดยไม่บันทึก', style: GoogleFonts.kanit()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    final cars = _drumCars;
    final savedTrips = _savedTripsForDay;
    final savedCarNames = {
      for (final t in savedTrips) transactionVehicleLabel(t),
    };
    final overview = VehicleTripDayOverview.fromTransactions(
      _dayTransactions,
      ymd: _ymd(_selectedDate),
      fleetTotal: cars.length,
    );

    final readyCount =
        _drafts.where((d) => isVehicleTripStatusReady(d.status)).length;
    final hasEditingRow = _drafts.any((d) => d.isEditingSaved);
    final saveLabel = buildVehicleTripSaveButtonLabel(
      readyCount: readyCount,
      hasEditingRow: hasEditingRow,
    );

    return PopScope(
      canPop: !_hasUnsavedEdits,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscardUnsaved();
        if (discard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.card,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 4,
          leading: IconButton(
            icon:
                Icon(Icons.arrow_back_ios_new_rounded, color: c.ink, size: 20),
            onPressed: () async {
              if (!_hasUnsavedEdits) {
                Navigator.of(context).pop();
                return;
              }
              final discard = await _confirmDiscardUnsaved();
              if (discard == true && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            widget.appBarTitle,
            style: GoogleFonts.kanit(
              color: c.ink,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            _DateNavPill(
              label: _formatThaiDate(_selectedDate),
              onPrev: () => _changeDate(
                _selectedDate.subtract(const Duration(days: 1)),
              ),
              onTapDate: _pickDateFromCalendar,
              onNext: () => _changeDate(
                _selectedDate.add(const Duration(days: 1)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: c.hairline),
          ),
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => _loadDayTransactions(forceRefresh: true),
              color: c.brand,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 112),
                children: [
                  VehicleTripOverviewHeader(
                    overview: overview,
                    dateLabel: _formatThaiDate(_selectedDate),
                  ),
                  const SizedBox(height: 16),

                  // ── ส่วนฟอร์มกรอกข้อมูลรถ ──────────────────────────────────
                  Row(
                    children: [
                      Text(
                        'กรอกข้อมูลรถดรัม',
                        style: GoogleFonts.kanit(
                          color: c.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addDraftCard,
                        style: TextButton.styleFrom(
                          foregroundColor: c.brand,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 17,
                        ),
                        label: Text(
                          'เพิ่มอีกคัน',
                          style: GoogleFonts.kanit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  for (var i = 0; i < _drafts.length; i++) ...[
                    _buildDraftCard(
                      index: i,
                      cars: cars,
                      savedCarNames: savedCarNames,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── รายการที่บันทึกแล้ววันนี้ ──────────────────────────────
                  if (savedTrips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 17,
                          color: c.statusComplete,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'บันทึกแล้ววันนี้ (${savedTrips.length} คัน)',
                          style: GoogleFonts.kanit(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    for (final tx in savedTrips) ...[
                      VehicleTripSavedCard(
                        transaction: tx,
                        driverName: _resolveDriverDisplayName(tx),
                        allCars: cars,
                        isBeingEdited: _drafts.any((d) => d.tripTxId == tx.id),
                        onEdit: () => _editSavedTransaction(tx),
                        onDelete: () => _confirmAndDeleteSaved(tx),
                      ),
                      const SizedBox(height: 9),
                    ],
                  ],
                ],
              ),
            ),

            // แถบซิงก์นุ่มลอยด้านบน
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SoftSyncIndicator(visible: _loadingDay),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.hairline)),
              boxShadow: [
                BoxShadow(
                  color: c.shadowLift,
                  blurRadius: 14,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addDraftCard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.ink,
                    side: BorderSide(color: c.hairline),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: Text(
                    'เพิ่มคัน',
                    style: GoogleFonts.kanit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _saveAllDrafts,
                    style: FilledButton.styleFrom(
                      backgroundColor: readyCount > 0 ? c.brand : c.inkMuted,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(
                      hasEditingRow
                          ? Icons.save_as_rounded
                          : Icons.check_circle_rounded,
                      size: 19,
                    ),
                    label: Text(
                      _saving ? 'กำลังบันทึก…' : saveLabel,
                      style: GoogleFonts.kanit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftCard({
    required int index,
    required List<String> cars,
    required Set<String> savedCarNames,
  }) {
    final draft = _drafts[index];
    final otherDraftCars = <String>{
      for (var j = 0; j < _drafts.length; j++)
        if (j != index && _drafts[j].vehicleId.trim().isNotEmpty)
          _drafts[j].vehicleId.trim(),
    };
    final orderedDrivers = orderDriversForVehicle(
      vehicleId: draft.vehicleId,
      drivers: _activeDrivers,
      tripHistory: _allHistoryTransactions,
      vehicleDefaultDrivers: _vehicleDefaultDrivers,
    );
    final defaultDriverId = resolveCountRecordDefaultDriverId(
      vehicleId: draft.vehicleId,
      drivers: _activeDrivers,
      tripHistory: _allHistoryTransactions,
      vehicleDefaultDrivers: _vehicleDefaultDrivers,
    );

    AppTransaction? savedTxForDraft;
    if (draft.isEditingSaved) {
      for (final t in _savedTripsForDay) {
        if (t.id == draft.tripTxId) {
          savedTxForDraft = t;
          break;
        }
      }
    }

    return VehicleTripEditorCard(
      index: index,
      totalRows: _drafts.length,
      vehicleId: draft.vehicleId,
      driverId: draft.driverId,
      billingMode: draft.billingMode,
      morningText: draft.morningText,
      afternoonText: draft.afternoonText,
      cubicPerTripText: draft.cubicPerTripText,
      lumpSumCubicText: draft.lumpSumCubicText,
      workType: draft.workType,
      hourlyHoursText: draft.hourlyHoursText,
      workDetailsController: draft.workDetailsController,
      allCars: cars,
      savedCarNames: savedCarNames,
      otherDraftCarNames: otherDraftCars,
      drivers: orderedDrivers,
      defaultDriverId: defaultDriverId,
      status: draft.status,
      isEditingSaved: draft.isEditingSaved,
      isCountRecordSynced: draft.isCountRecordSynced,
      workDetailSuggestions: _workDetailSuggestions,
      onSelectVehicle: (car) => _selectVehicleForDraft(index, car),
      onSelectDriver: (id) {
        setState(() {
          draft.driverId = id;
          _hasUnsavedEdits = true;
        });
      },
      onSelectBillingMode: (mode) {
        setState(() {
          draft.billingMode = mode;
          _hasUnsavedEdits = true;
        });
      },
      onStepMorning: (delta) {
        setState(() {
          draft.morningText = stepVehicleTripCount(draft.morningText, delta);
          _hasUnsavedEdits = true;
        });
      },
      onTapMorningPad: () => _showProNumericPad(
        title: 'จำนวนเที่ยวช่วงเช้า',
        unit: 'เที่ยว',
        initialValue: draft.morningText,
        onApply: (v) => draft.morningText = v,
      ),
      onStepAfternoon: (delta) {
        setState(() {
          draft.afternoonText =
              stepVehicleTripCount(draft.afternoonText, delta);
          _hasUnsavedEdits = true;
        });
      },
      onTapAfternoonPad: () => _showProNumericPad(
        title: 'จำนวนเที่ยวช่วงบ่าย',
        unit: 'เที่ยว',
        initialValue: draft.afternoonText,
        onApply: (v) => draft.afternoonText = v,
      ),
      onSelectCubicPreset: (preset) {
        setState(() {
          draft.cubicPerTripText = preset;
          _hasUnsavedEdits = true;
        });
      },
      onTapCubicPad: () => _showProNumericPad(
        title: 'คิวต่อเที่ยว',
        unit: 'คิว',
        initialValue: draft.cubicPerTripText,
        onApply: (v) => draft.cubicPerTripText = v,
      ),
      onTapLumpSumPad: () => _showProNumericPad(
        title: 'ปริมาณรวมแบบเหมา',
        unit: 'คิว',
        initialValue: draft.lumpSumCubicText,
        onApply: (v) => draft.lumpSumCubicText = v,
      ),
      onSelectWorkType: (type) {
        setState(() {
          draft.workType = type;
          _hasUnsavedEdits = true;
        });
      },
      onSelectHourlyPreset: (hours) {
        setState(() {
          draft.hourlyHoursText = hours;
          _hasUnsavedEdits = true;
        });
      },
      onTapHourlyPad: () => _showProNumericPad(
        title: 'ชั่วโมงทำงาน',
        unit: 'ชม.',
        initialValue: draft.hourlyHoursText,
        onApply: (v) => draft.hourlyHoursText = v,
      ),
      onToggleQuickPhrase: (phrase) {
        setState(() {
          draft.workDetailsController.text = toggleVehicleTripWorkPhrase(
            draft.workDetailsController.text,
            phrase,
          );
          _hasUnsavedEdits = true;
        });
      },
      onWorkDetailsChanged: (_) {
        setState(() => _hasUnsavedEdits = true);
      },
      onRemoveRow: _drafts.length > 1 ? () => _removeDraftCard(index) : null,
      onDeleteSavedRecord: savedTxForDraft != null
          ? () => _confirmAndDeleteSaved(savedTxForDraft!)
          : null,
    );
  }

  String _resolveDriverDisplayName(AppTransaction tx) {
    final explicit = (tx.driverName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final id = (tx.driverId ?? '').trim();
    if (id.isEmpty) return '';
    final emp = _employeesById[id];
    if (emp != null) return driverDisplayLabel(emp);
    return id;
  }
}

class _DateNavPill extends StatelessWidget {
  const _DateNavPill({
    required this.label,
    required this.onPrev,
    required this.onTapDate,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onTapDate;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: c.brandSurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.brandBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
            onTap: onPrev,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 19,
                color: c.brandDateInk,
              ),
            ),
          ),
          InkWell(
            onTap: onTapDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: c.brandDateInk,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: GoogleFonts.kanit(
                      color: c.brandDateInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
            onTap: onNext,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: c.brandDateInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProNumericPadSheet extends StatefulWidget {
  const _ProNumericPadSheet({
    required this.title,
    required this.unit,
    required this.initialValue,
    required this.allowDecimal,
  });

  final String title;
  final String unit;
  final String initialValue;
  final bool allowDecimal;

  @override
  State<_ProNumericPadSheet> createState() => _ProNumericPadSheetState();
}

class _ProNumericPadSheetState extends State<_ProNumericPadSheet> {
  late String _buffer;

  @override
  void initState() {
    super.initState();
    _buffer = normalizeVehicleTripNumericInput(widget.initialValue);
  }

  void _append(String key) {
    AppHaptics.tap();
    setState(() {
      if (key == '.') {
        if (!widget.allowDecimal || _buffer.contains('.')) return;
        _buffer = _buffer.isEmpty ? '0.' : '$_buffer.';
        return;
      }
      if (_buffer == '0') {
        _buffer = key;
      } else if (_buffer.length < 7) {
        _buffer += key;
      }
    });
  }

  void _backspace() {
    AppHaptics.tap();
    if (_buffer.isEmpty) return;
    setState(() {
      _buffer = _buffer.substring(0, _buffer.length - 1);
    });
  }

  void _clear() {
    AppHaptics.tap();
    setState(() => _buffer = '');
  }

  void _submit() {
    AppHaptics.confirm();
    final parsed = parseVehicleTripNumber(_buffer);
    Navigator.of(context).pop(
      parsed > 0 ? formatVehicleTripNumber(parsed) : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DailyPalette.of(context);
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [widget.allowDecimal ? '.' : 'C', '0', '⌫'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.viewPaddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: c.grabber,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                widget.title,
                style: GoogleFonts.kanit(
                  color: c.ink,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clear,
                child: Text(
                  'ล้างค่า',
                  style: GoogleFonts.kanit(
                    color: c.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.brandBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _buffer.isEmpty ? '0' : _buffer,
                  style: GoogleFonts.kanit(
                    color: _buffer.isEmpty ? c.inkMuted : c.brand,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.unit,
                  style: GoogleFonts.kanit(
                    color: c.inkSubtle,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final row in keys) ...[
            Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: c.chipSurface,
                      borderRadius: BorderRadius.circular(13),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(13),
                        onTap: () {
                          final k = row[i];
                          if (k == '⌫') {
                            _backspace();
                          } else if (k == 'C') {
                            _clear();
                          } else {
                            _append(k);
                          }
                        },
                        child: SizedBox(
                          height: 52,
                          child: Center(
                            child: row[i] == '⌫'
                                ? Icon(
                                    Icons.backspace_outlined,
                                    size: 20,
                                    color: c.ink,
                                  )
                                : Text(
                                    row[i],
                                    style: GoogleFonts.kanit(
                                      color: c.ink,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'ตกลง',
                style: GoogleFonts.kanit(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
