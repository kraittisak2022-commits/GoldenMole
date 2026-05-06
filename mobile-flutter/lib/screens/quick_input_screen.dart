import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';

class QuickInputScreen extends StatefulWidget {
  const QuickInputScreen({
    super.key,
    required this.service,
    required this.employeeService,
    this.initialCategory,
    this.appBarTitle,
  });

  final TransactionService service;
  final EmployeeService employeeService;

  /// ตั้งหมวดหมู่เริ่มต้นเมื่อเปิดจากการ์ดหน้าแรก
  final String? initialCategory;
  final String? appBarTitle;

  @override
  State<QuickInputScreen> createState() => _QuickInputScreenState();
}

class _QuickInputScreenState extends State<QuickInputScreen> {
  static const Color _accent = Color(0xFF1565C0);
  static const Color _bg = Color(0xFFFDFEFF);
  static const String _employeeUsageKey = 'quick_input_employee_usage';

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
  Map<String, int> _employeeUsage = const {};
  String? _selectedEmployeeId;

  DateTime _selectedDate = DateTime.now();
  bool _saving = false;
  List<String> _otDescSuggestions = const [];
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
  bool get _isLaborMode => (widget.initialCategory ?? '').contains('บันทึกการทำงาน');
  bool get _isOtMode => (widget.initialCategory ?? '').contains('OT');

  @override
  void initState() {
    super.initState();
    _categoryController = TextEditingController(
      text: widget.initialCategory?.trim().isNotEmpty == true
          ? widget.initialCategory!.trim()
          : 'ค่าแรง',
    );
    _loadEmployees();
    _loadAppCars();
    _loadOtSuggestions();
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
      final prefs = await SharedPreferences.getInstance();
      final usageRaw = prefs.getString(_employeeUsageKey);
      final usage = <String, int>{};
      if (usageRaw != null && usageRaw.isNotEmpty) {
        final entries = usageRaw.split('|');
        for (final e in entries) {
          final pair = e.split(':');
          if (pair.length == 2) {
            usage[pair[0]] = int.tryParse(pair[1]) ?? 0;
          }
        }
      }
      final list = await widget.employeeService.fetchEmployees();
      list.sort((a, b) {
        final ua = usage[a.id] ?? 0;
        final ub = usage[b.id] ?? 0;
        if (ua != ub) return ub.compareTo(ua);
        return (a.nickname.isNotEmpty ? a.nickname : a.name).compareTo(
          b.nickname.isNotEmpty ? b.nickname : b.name,
        );
      });
      if (!mounted) return;
      setState(() {
        _employeeUsage = usage;
        _employees = list;
        _driverEmployees = list.where((e) {
          final pos = (e.position ?? '').toLowerCase();
          return pos.contains('คนขับ') || pos.contains('driver');
        }).toList();
      });
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

  Future<void> _rememberEmployeeUsage(String employeeId) async {
    if (employeeId.isEmpty) return;
    final next = Map<String, int>.from(_employeeUsage);
    next[employeeId] = (next[employeeId] ?? 0) + 1;
    final serialized = next.entries.map((e) => '${e.key}:${e.value}').join('|');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_employeeUsageKey, serialized);
    if (!mounted) return;
    setState(() => _employeeUsage = next);
    await _loadEmployees();
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
    setState(() => _saving = true);

    try {
      final description = _appendRecorder(_descriptionController.text.trim());

      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final entry = AppTransaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: '$y-$m-$d',
        type: 'Expense',
        category: _categoryController.text.trim(),
        description: description,
        amount: double.parse(_amountController.text.trim()),
      );

      await widget.service.upsertTransaction(entry);
      await _rememberSelectedRecorder();
      _amountController.clear();
      _descriptionController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSandWashEntry() async {
    setState(() => _saving = true);
    try {
      final s1m = double.tryParse(_sand1MorningController.text.trim()) ?? 0;
      final s1a = double.tryParse(_sand1AfternoonController.text.trim()) ?? 0;
      final s2m = double.tryParse(_sand2MorningController.text.trim()) ?? 0;
      final s2a = double.tryParse(_sand2AfternoonController.text.trim()) ?? 0;
      final drums = double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
      final total = s1m + s1a + s2m + s2a;
      if (total <= 0 && drums <= 0) {
        throw 'กรุณากรอกอย่างน้อยจำนวนคิวทรายหรือจำนวนถัง';
      }

      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final date = '$y-$m-$d';
      final commonCategory = _categoryController.text.trim().isEmpty
          ? 'บันทึกการร่อนทราย'
          : _categoryController.text.trim();
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
        if (morning + afternoon <= 0) return;
        final tx = AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_$suffix',
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
          sandMorningStart: morningStart.isEmpty ? null : morningStart,
          sandAfternoonStart: afternoonStart.isEmpty ? null : afternoonStart,
          sandEveningEnd: eveningEnd.isEmpty ? null : eveningEnd,
        );
        await widget.service.upsertTransaction(tx);
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

      if (total <= 0 && drums > 0) {
        await widget.service.upsertTransaction(
          AppTransaction(
            id: '${DateTime.now().millisecondsSinceEpoch}_drums',
            date: date,
            type: 'Expense',
            category: commonCategory,
            subCategory: commonSub,
            description: _appendRecorder('จำนวนถังที่ได้วันนี้'),
            amount: 0,
            drumsObtained: drums,
            drumsWashedAtHome: 0,
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
      await _rememberSelectedRecorder();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกล้างทรายสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveHomeSandEntry() async {
    setState(() => _saving = true);
    try {
      final drums = double.tryParse(_sandDrumsObtainedController.text.trim()) ?? 0;
      final drumsHome =
          double.tryParse(_drumsWashedAtHomeController.text.trim()) ?? 0;
      if (drums <= 0 && drumsHome <= 0) {
        throw 'กรุณากรอกจำนวนถังอย่างน้อย 1 ค่า';
      }
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_home_sand',
          date: '$y-$m-$d',
          type: 'Expense',
          category: _categoryController.text.trim(),
          subCategory: 'Sand',
          description: _appendRecorder('ทรายที่ล้างที่บ้าน'),
          amount: 0,
          drumsObtained: drums,
          drumsWashedAtHome: drumsHome,
        ),
      );
      _sandDrumsObtainedController.clear();
      _drumsWashedAtHomeController.clear();
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกทรายที่ล้างที่บ้านสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveVehicleTripEntry() async {
    setState(() => _saving = true);
    try {
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
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_veh',
          date: date,
          type: 'Expense',
          category: 'Vehicle',
          description:
              _appendRecorder(
                'รถ: $vehicle (${details.isEmpty ? '-' : details}) [${_vehicleWorkType == 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}]',
              ),
          amount: vehicleWage + driverWage,
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
        await widget.service.upsertTransaction(
          AppTransaction(
            id: '${DateTime.now().millisecondsSinceEpoch}_trip',
            date: date,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            description:
                _appendRecorder(
                  '$vehicle: ${totalTrips.toStringAsFixed(0)} เที่ยว × ${cubicPerTrip.toStringAsFixed(0)} คิว',
                ),
            amount: 0,
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
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกรถและเที่ยวรถสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFuelStockInEntry() async {
    setState(() => _saving = true);
    try {
      final liters = double.tryParse(_fuelLitersController.text.trim()) ?? 0;
      final amount = double.tryParse(_fuelAmountController.text.trim()) ?? 0;
      if (amount <= 0) throw 'กรุณาระบุราคาซื้อน้ำมัน';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final unit = _fuelUnitController.text.trim() == 'แกลลอน' ? 'gallon' : 'L';
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_fuel_in',
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Fuel',
          description:
              _appendRecorder(
                'ซื้อน้ำมัน ${_fuelType == 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${liters.toStringAsFixed(0)} ${_fuelUnitController.text} ${amount.toStringAsFixed(0)} บาท',
              ),
          amount: amount,
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
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกซื้อน้ำมันสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFuelVehicleUsageEntry() async {
    setState(() => _saving = true);
    try {
      final vehicle = _fuelVehicleController.text.trim();
      final liters = double.tryParse(_fuelVehicleLitersController.text.trim()) ?? 0;
      if (vehicle.isEmpty) throw 'กรุณาระบุรถ';
      if (liters <= 0) throw 'กรุณาระบุปริมาณน้ำมัน';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_fuel_out',
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Fuel',
          subCategory: 'VehicleUsage',
          description:
              _appendRecorder(
                'ใช้น้ำมันรถ $vehicle: ${liters.toStringAsFixed(0)} ลิตร (${_fuelVehicleType == 'Diesel' ? 'ดีเซล' : 'เบนซิน'})',
              ),
          amount: 0,
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
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกการใช้น้ำมันรายรถสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveLaborEntry() async {
    setState(() => _saving = true);
    try {
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
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_labor',
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Labor',
          subCategory: 'Attendance',
          laborStatus: 'Work',
          employeeIds: _selectedLaborEmpIds.toList(),
          workType: _laborWorkType,
          amount: total,
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
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกค่าแรงสำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOtEntry() async {
    setState(() => _saving = true);
    try {
      if (_selectedLaborEmpIds.isEmpty) throw 'กรุณาเลือกพนักงาน';
      final rate = double.tryParse(_otRateController.text.trim()) ?? 0;
      final hours = double.tryParse(_otHoursController.text.trim()) ?? 0;
      if (rate <= 0) throw 'กรุณาระบุค่า OT';
      if (hours <= 0) throw 'กรุณาระบุชั่วโมง OT';
      final y = _selectedDate.year.toString().padLeft(4, '0');
      final m = _selectedDate.month.toString().padLeft(2, '0');
      final d = _selectedDate.day.toString().padLeft(2, '0');
      final total = rate * hours * _selectedLaborEmpIds.length;
      await widget.service.upsertTransaction(
        AppTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}_ot',
          date: '$y-$m-$d',
          type: 'Expense',
          category: 'Labor',
          subCategory: 'OT',
          laborStatus: 'OT',
          employeeIds: _selectedLaborEmpIds.toList(),
          amount: total,
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
      await _rememberSelectedRecorder();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึก OT สำเร็จ')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
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
      setState(() => _selectedDate = picked);
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

  Employee? get _selectedRecorder {
    if (_selectedEmployeeId == null || _selectedEmployeeId!.isEmpty) return null;
    for (final e in _employees) {
      if (e.id == _selectedEmployeeId) return e;
    }
    return null;
  }

  String get _selectedRecorderName {
    final e = _selectedRecorder;
    if (e == null) return '';
    return e.nickname.isNotEmpty ? e.nickname : e.name;
  }

  String _normalizePersonName(String raw) {
    final noParen = raw.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ');
    return noParen.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  List<Employee> get _recorderEmployees {
    final dedup = <String, Employee>{};
    for (final e in _employees) {
      final display = e.nickname.isNotEmpty ? e.nickname : e.name;
      final key = _normalizePersonName(display);
      if (!dedup.containsKey(key)) {
        dedup[key] = e;
      }
    }
    if (_selectedRecorder != null) {
      final selected = _selectedRecorder!;
      final key = _normalizePersonName(
        selected.nickname.isNotEmpty ? selected.nickname : selected.name,
      );
      dedup[key] ??= selected;
    }
    return dedup.values.toList();
  }

  String _appendRecorder(String text) {
    final recorder = _selectedRecorderName;
    if (recorder.isEmpty) return text;
    final base = text.trim();
    return base.isEmpty ? 'ผู้กรอก: $recorder' : '$base (ผู้กรอก: $recorder)';
  }

  Future<void> _rememberSelectedRecorder() async {
    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
      await _rememberEmployeeUsage(_selectedEmployeeId!);
    }
  }

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

  Widget _buildRecorderPickerCard() {
    final selectedName = _selectedRecorderName;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  size: 18,
                  color: Color(0xFF1565C0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ผู้กรอกข้อมูล',
                  style: GoogleFonts.kanit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D2736),
                  ),
                ),
              ),
              if (selectedName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF6EE),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFCFE9D8)),
                  ),
                  child: Text(
                    selectedName,
                    style: GoogleFonts.kanit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B8E4B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('recorder-${_selectedEmployeeId ?? 'none'}-${_employees.length}'),
            initialValue: _selectedEmployeeId,
            decoration: const InputDecoration(
              hintText: 'เลือกพนักงานผู้กรอกข้อมูล',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            borderRadius: BorderRadius.circular(14),
            dropdownColor: Colors.white,
            elevation: 2,
            style: GoogleFonts.kanit(color: const Color(0xFF1D2736)),
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text('ไม่ระบุ', style: GoogleFonts.kanit(color: Colors.black54)),
              ),
              ..._recorderEmployees.map((e) {
                final name = e.nickname.isNotEmpty ? e.nickname : e.name;
                final count = _employeeUsage[e.id] ?? 0;
                return DropdownMenuItem<String>(
                  value: e.id,
                  child: Text(
                    count > 0 ? '$name • บันทึก $count ครั้ง' : name,
                    style: GoogleFonts.kanit(color: Colors.black87),
                  ),
                );
              }),
            ],
            onChanged: (v) => setState(() => _selectedEmployeeId = v),
          ),
        ],
      ),
    );
  }

  ThemeData _quickFormTheme(BuildContext context) {
    final base = Theme.of(context);
    const primary = Color(0xFF0F9EA8);
    return base.copyWith(
      useMaterial3: true,
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
        labelStyle: GoogleFonts.kanit(color: const Color(0xFF6A7280)),
        hintStyle: GoogleFonts.kanit(color: const Color(0xFFA0A8B5)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        prefixIconColor: const Color(0xFF8A95A5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE7EBF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.3),
        ),
      ),
      textTheme: GoogleFonts.kanitTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFF202939),
        displayColor: const Color(0xFF202939),
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
                                _buildRecorderPickerCard(),
                                const SizedBox(height: 14),
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
          labelStyle: GoogleFonts.kanit(color: const Color(0xFF5A6B7F)),
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
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        decoration: deco(label, Icons.numbers),
      );
    }

    Widget machineCard({
      required String title,
      required Color color,
      required TextEditingController morning,
      required TextEditingController afternoon,
      required double subtotal,
    }) {
      final active = subtotal > 0;
      return AnimatedContainer(
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
            color: active ? color.withValues(alpha: 0.45) : const Color(0xFFDCEAF7),
            width: active ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (active ? color : Colors.black).withValues(
                alpha: active ? 0.14 : 0.02,
              ),
              blurRadius: active ? 14 : 8,
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
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.settings_input_component_rounded, size: 14, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D2A3A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: numberField(controller: morning, label: 'เช้า (คิว)')),
                const SizedBox(width: 8),
                Expanded(child: numberField(controller: afternoon, label: 'บ่าย (คิว)')),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                'รวม ${subtotal.toStringAsFixed(0)} คิว',
                key: ValueKey(subtotal.toStringAsFixed(0)),
                textAlign: TextAlign.right,
                style: GoogleFonts.kanit(
                  color: color.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w700,
                ),
              ),
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
          machineCard(
            title: 'เครื่องร่อน 1 (เก่า)',
            color: const Color(0xFF42A5F5),
            morning: _sand1MorningController,
            afternoon: _sand1AfternoonController,
            subtotal: s1,
          ),
          const SizedBox(height: 12),
          machineCard(
            title: 'เครื่องร่อน 2 (ใหม่)',
            color: const Color(0xFF26C6DA),
            morning: _sand2MorningController,
            afternoon: _sand2AfternoonController,
            subtotal: s2,
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
                      'ช่วงเวลาการทำงาน',
                      style: GoogleFonts.kanit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D2736),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                const SizedBox(height: 10),
                _AnimatedInputField(
                  controller: _sandMorningStartController,
                  style: GoogleFonts.kanit(color: const Color(0xFF1D2A3A)),
                  textInputAction: TextInputAction.next,
                  readOnly: true,
                  onTap: () => _pickSandTime(
                    controller: _sandMorningStartController,
                    hour: 7,
                    minute: 20,
                  ),
                  decoration: deco('ช่วงเช้า เริ่มงาน (07.20)', Icons.wb_sunny_outlined),
                ),
                const SizedBox(height: 8),
                _AnimatedInputField(
                  controller: _sandAfternoonStartController,
                  style: GoogleFonts.kanit(color: const Color(0xFF1D2A3A)),
                  textInputAction: TextInputAction.next,
                  readOnly: true,
                  onTap: () => _pickSandTime(
                    controller: _sandAfternoonStartController,
                    hour: 13,
                    minute: 0,
                  ),
                  decoration: deco('ช่วงบ่าย เริ่มงาน (13.00)', Icons.wb_twilight_outlined),
                ),
                const SizedBox(height: 8),
                _AnimatedInputField(
                  controller: _sandEveningEndController,
                  style: GoogleFonts.kanit(color: const Color(0xFF1D2A3A)),
                  textInputAction: TextInputAction.done,
                  readOnly: true,
                  onTap: () => _pickSandTime(
                    controller: _sandEveningEndController,
                    hour: 16,
                    minute: 20,
                  ),
                  decoration: deco(
                    'ช่วงเย็น หยุดล้าง (16.20)',
                    Icons.nightlight_round_outlined,
                  ),
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
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF26C6DA), Color(0xFF1565C0)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.26),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                    : const Icon(Icons.waves, color: Colors.white),
                label: Text(
                  _saving ? 'กำลังบันทึก...' : 'บันทึกล้างทราย',
                  style: GoogleFonts.kanit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(50),
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
        transform: Matrix4.identity()..scale(_pressed ? 0.995 : (_focused ? 1.01 : 1.0)),
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
            style: widget.style,
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
