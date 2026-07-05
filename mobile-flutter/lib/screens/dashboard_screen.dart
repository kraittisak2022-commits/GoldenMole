import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_sync_snapshot.dart';
import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../models/employee.dart';
import '../services/count_record_offline_sync.dart';
import '../services/local_data_cache.dart';
import '../services/dashboard_service.dart';
import '../services/employee_service.dart';
import '../services/project_service.dart';
import '../services/transaction_service.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import '../l10n/daily_status_translator.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/device_perf.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../utils/record_success_speaker.dart';
import '../widgets/app_locale_scope.dart';
import '../widgets/app_logo.dart';
import '../widgets/count_record_counters.dart';
import '../widgets/count_record_menu_shell.dart';
import '../widgets/count_record_tutorial.dart';
import '../widgets/dashboard_loading_view.dart';
import '../widgets/menu_panel_transition.dart';
import '../widgets/record_module_card.dart';
import 'app_settings_screen.dart';
import 'calendar_screen.dart';
import 'employees_screen.dart';
import 'mobile_error_report_hub_screen.dart';
import 'projects_screen.dart';
import 'quick_input_screen.dart';
import 'transactions_screen.dart';

class _DailyModuleDef {
  const _DailyModuleDef({
    required this.title,
    required this.icon,
    required this.category,
    required this.quickInputTitle,
    required this.color,
  });

  final String title;
  final IconData icon;
  final String category;
  final String quickInputTitle;
  final Color color;
}

const List<_DailyModuleDef> _kDailyModules = [
  _DailyModuleDef(
    title: 'บันทึกการร่อนทราย',
    icon: Icons.water_drop_outlined,
    category: 'บันทึกการร่อนทราย',
    quickInputTitle: 'บันทึกการร่อนทราย',
    color: Color(0xFFFF2D97),
  ),
  _DailyModuleDef(
    title: 'บันทึกรถดรัมและจำนวนเที่ยว',
    icon: Icons.fire_truck_outlined,
    category: 'จำนวนเที่ยวรถ',
    quickInputTitle: 'บันทึกรถดรัมและจำนวนเที่ยว',
    color: Color(0xFF00D4F5),
  ),
  _DailyModuleDef(
    title: 'การใช้รถแม็คโคร',
    icon: Icons.front_loader,
    category: 'การใช้รถแม็คโคร',
    quickInputTitle: 'บันทึกการใช้รถแม็คโคร',
    color: Color(0xFFFFA020),
  ),
  _DailyModuleDef(
    title: 'น้ำมัน',
    icon: Icons.oil_barrel_outlined,
    category: 'น้ำมัน',
    quickInputTitle: 'บันทึกน้ำมัน',
    color: Color(0xFFFFAB00),
  ),
  _DailyModuleDef(
    title: 'ทรายที่ล้างที่บ้าน',
    icon: Icons.waves_outlined,
    category: 'ทรายที่ล้างที่บ้าน',
    quickInputTitle: 'ทรายที่ล้างที่บ้าน',
    color: Color(0xFF3D6CFF),
  ),
  _DailyModuleDef(
    title: 'เหตุการณ์',
    icon: Icons.warning_amber_rounded,
    category: 'เหตุการณ์',
    quickInputTitle: 'เหตุการณ์สำคัญประจำวัน',
    color: Color(0xFFFF7A1A),
  ),
  _DailyModuleDef(
    title: 'บันทึกการทำงาน',
    icon: Icons.payments_outlined,
    category: 'ค่าแรง',
    quickInputTitle: 'บันทึกการทำงาน',
    color: Color(0xFF9145FF),
  ),
  _DailyModuleDef(
    title: 'การทำงานล่วงเวลา (OT)',
    icon: Icons.groups_2_outlined,
    category: 'OT',
    quickInputTitle: 'บันทึกการทำงานล่วงเวลา',
    color: Color(0xFFFF3D6B),
  ),
  _DailyModuleDef(
    title: 'ลางาน',
    icon: Icons.event_busy_outlined,
    category: 'ลางาน',
    quickInputTitle: 'บันทึกลางาน',
    color: Color(0xFF00A896),
  ),
  _DailyModuleDef(
    title: 'เบิกเงิน',
    icon: Icons.savings_outlined,
    category: 'เบิกเงิน',
    quickInputTitle: 'ส่งคำขอเบิกเงิน',
    color: Color(0xFFFF8500),
  ),
  _DailyModuleDef(
    title: 'รายรับ-รายจ่าย',
    icon: Icons.account_balance_wallet_outlined,
    category: 'รายจ่ายรายรับ',
    quickInputTitle: 'รายรับ-รายจ่าย',
    color: Color(0xFF6370E8),
  ),
];

/// หมวดเมนูที่บันทึกออฟไลน์ได้ (ผ่าน «บันทึกและนับจำนวน»)
const _kOfflineCapableModuleCategories = {
  'จำนวนเที่ยวรถ',
  'บันทึกการร่อนทราย',
};

bool _isOfflineCapableModule(String category) =>
    _kOfflineCapableModuleCategories.contains(category);

/// เมนูบนหน้าแรกที่แสดงตอนไม่มีเน็ต — โหมดออฟไลน์จะจางเมนูอื่น แต่ยังแสดงกริดเดิม

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.currentAdmin,
    required this.dashboardService,
    required this.onLogout,
  });

  final AdminUser currentAdmin;
  final DashboardService dashboardService;
  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late final TransactionService _txService;
  int _bodyPage = 0;
  DateTime _selectedDay = DateTime.now();
  bool _serverOnline = true;
  bool _countAndRecordMenuOpen = false;
  late Future<_HomePayload> _homeFuture;
  _HomePayload? _lastHomePayload;
  Timer? _offlineDebounceTimer;

  void _applyServerReachability(bool online, {bool force = false}) {
    if (!mounted) return;
    if (online) {
      _offlineDebounceTimer?.cancel();
      _offlineDebounceTimer = null;
      if (!_serverOnline) {
        setState(() => _serverOnline = true);
      }
      return;
    }
    if (!_serverOnline) return;
    if (force) {
      _offlineDebounceTimer?.cancel();
      _offlineDebounceTimer = null;
      setState(() => _serverOnline = false);
      return;
    }
    _offlineDebounceTimer ??= Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _offlineDebounceTimer = null;
      setState(() => _serverOnline = false);
    });
  }

  void _onSyncStateChanged() {
    if (!mounted) return;
    final sync = CountRecordOfflineSync.instance.syncState.value;
    final online = sync.isEffectivelyOnline;
    if (online) {
      _applyServerReachability(true);
    } else {
      _applyServerReachability(false, force: true);
    }
  }

  void _configureTransactionRealtime() {
    CountRecordOfflineSync.instance.configureTransactionRealtime(
      dateYmd: _dateKey(_selectedDay),
      onRemoteChange: () {
        if (!mounted) return;
        unawaited(_refreshHomeDataInPlace());
      },
    );
  }

  void _applyPayloadQuietly(_HomePayload next) {
    if (!mounted) return;
    final prev = _lastHomePayload;
    if (prev != null &&
        identical(prev.dayTransactions, next.dayTransactions) &&
        identical(prev.allTransactions, next.allTransactions) &&
        identical(prev.employees, next.employees) &&
        prev.summary == next.summary) {
      return;
    }
    setState(() {
      _lastHomePayload = next;
      _homeFuture = SynchronousFuture<_HomePayload>(next);
    });
  }

  /// อัปเดตข้อมูลแบบเงียบ — ไม่สลับ FutureBuilder เข้า waiting (กันแถบโหลดกระพริบ)
  Future<void> _refreshHomeSilently({bool tryNetwork = true}) async {
    if (!mounted) return;
    final dayKey = _dateKey(_selectedDay);

    final offlinePayload = await _loadHomeOfflineOrEmpty(dayKey);
    if (mounted) _applyPayloadQuietly(offlinePayload);

    if (!tryNetwork) return;

    final client = Supabase.instance.client;
    final online = await CountRecordOfflineSync.instance.isOnline(
      client,
      forceProbe: false,
    );
    if (!mounted) return;

    if (!online) {
      _applyServerReachability(false);
      return;
    }

    _applyServerReachability(true);
    try {
      await CountRecordOfflineSync.instance
          .uploadPendingImmediately(_txService, client)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final fresh = await _loadHomeFromNetwork(
        client: client,
        dayKey: dayKey,
        networkRefresh: true,
      ).timeout(const Duration(seconds: 12));
      if (mounted) _applyPayloadQuietly(fresh);
    } catch (_) {
      // คงข้อมูลแคชบนจอ — ไม่กระพริบหรือสลับโหมดกะทันหัน
    }
  }

  /// โหลดข้อมูลใหม่ในพื้นหลัง — ไม่รีเซ็ตหน้าที่ผู้ใช้อยู่ (เมนูย่อยนับจำนวน ฯลฯ)
  Future<void> _refreshHomeDataInPlace() async {
    if (_countAndRecordMenuOpen) {
      await _refreshAfterCountRecordChange();
      return;
    }
    await _refreshHomeSilently(tryNetwork: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MobileErrorScreenTracker.set(
      page: 'หน้าหลัก (แดชบอร์ด)',
      pageId: MobileScreenIds.pageDashboard,
      stepId: MobileScreenIds.stepDashboardHome,
    );
    _txService = TransactionService(Supabase.instance.client);
    _homeFuture = _futureWithSnapshot(_loadHome(cacheFirst: true));
    unawaited(_warmHomeFromCache());
    CountRecordOfflineSync.instance.startAutoSync(
      service: _txService,
      client: Supabase.instance.client,
      onSynced: _onCountRecordOfflineSynced,
      onServerReachabilityChanged: (online) {
        if (online) {
          _applyServerReachability(true);
        } else {
          _applyServerReachability(false, force: true);
        }
      },
    );
    CountRecordOfflineSync.instance.syncState.addListener(_onSyncStateChanged);
    _configureTransactionRealtime();
  }

  /// โหลดแคชในเครื่องทันที — แสดงแดชบอร์ดได้เร็วโดยไม่รอเน็ต
  Future<void> _warmHomeFromCache() async {
    final cached = await _loadHomeFromLocalCache(_dateKey(_selectedDay));
    if (cached != null && mounted) {
      _applyPayloadQuietly(cached);
    }
  }

  /// เก็บ payload ชุดล่าสุดเพื่อโชว์แบบไม่เป็นหน้าว่างตอนดึงรีเฟรช
  Future<_HomePayload> _futureWithSnapshot(Future<_HomePayload> future) async {
    try {
      final next = await future;
      if (mounted) setState(() => _lastHomePayload = next);
      return next;
    } catch (_) {
      rethrow;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CountRecordOfflineSync.instance.syncState
        .removeListener(_onSyncStateChanged);
    CountRecordOfflineSync.instance.stopAutoSync();
    _offlineDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCountRecordQueueThenRefresh());
    }
  }

  void _onCountRecordOfflineSynced() {
    if (!mounted) return;
    CountRecordOfflineSync.instance.noteServerReachable();
    _applyServerReachability(true);
    unawaited(_refreshHomeDataInPlace());
  }

  Future<void> _syncCountRecordQueueThenRefresh() async {
    try {
      await CountRecordOfflineSync.instance.uploadPendingImmediately(
        _txService,
        Supabase.instance.client,
      );
    } catch (_) {}
    if (!mounted) return;
    final online = await CountRecordOfflineSync.instance.isOnline(
      Supabase.instance.client,
      forceProbe: true,
    );
    if (online) {
      CountRecordOfflineSync.instance.noteServerReachable();
      _applyServerReachability(true);
    }
    await _refreshHomeDataInPlace();
  }

  Future<_HomePayload> _composeHomePayload({
    required DashboardSummary summary,
    required List<AppTransaction> dayRows,
    required List<AppTransaction> allRows,
    required List<Employee> employees,
    required String dayKey,
  }) async {
    final seen = dayRows.map((e) => e.id).toSet();
    final overlappingLeave = allRows.where(
      (t) => laborLeaveCoversCalendarDay(t, dayKey) && !seen.contains(t.id),
    );
    final dayTransactions = await CountRecordOfflineSync.instance.mergeForDayAsync(
      dayKey,
      <AppTransaction>[...dayRows, ...overlappingLeave],
    );
    final allTransactions =
        await CountRecordOfflineSync.instance.mergeAllTransactionsAsync(allRows);
    return _HomePayload(
      summary: summary,
      dayTransactions: dayTransactions,
      allTransactions: allTransactions,
      employees: employees,
    );
  }

  Future<_HomePayload?> _loadHomeFromLocalCache(String dayKey) async {
    final results = await Future.wait<dynamic>([
      LocalDataCache.readDashboardAny(),
      LocalDataCache.readTransactionsForDayAny(dayKey),
      LocalDataCache.readEmployeesAny(),
      LocalDataCache.readTransactionsFullAny(),
    ]);
    final summary = results[0] as DashboardSummary?;
    final dayRows = results[1] as List<AppTransaction>? ?? const [];
    final employees = results[2] as List<Employee>? ?? const [];
    final allRows = results[3] as List<AppTransaction>? ?? dayRows;
    if (summary == null && dayRows.isEmpty && employees.isEmpty) {
      return null;
    }
    if (employees.isNotEmpty) {
      unawaited(CountRecordOfflineSync.instance.cacheEmployees(employees));
    }
    return _composeHomePayload(
      summary: summary ??
          const DashboardSummary(
            employeeCount: 0,
            transactionCount: 0,
            projectCount: 0,
            totalRevenue: 0,
            totalExpense: 0,
            appName: 'Construction Management',
          ),
      dayRows: dayRows,
      allRows: allRows,
      employees: employees,
      dayKey: dayKey,
    );
  }

  Future<_HomePayload> _loadHomeOfflineOrEmpty(String dayKey) async {
    final cached = await _loadHomeFromLocalCache(dayKey);
    if (cached != null) return cached;
    return _composeHomePayload(
      summary: const DashboardSummary(
        employeeCount: 0,
        transactionCount: 0,
        projectCount: 0,
        totalRevenue: 0,
        totalExpense: 0,
        appName: 'Construction Management',
      ),
      dayRows: const [],
      allRows: const [],
      employees: const [],
      dayKey: dayKey,
    );
  }

  Future<_HomePayload> _loadHomeFromNetwork({
    required SupabaseClient client,
    required String dayKey,
    required bool networkRefresh,
  }) async {
    final employeeService = EmployeeService(client);
    final results = await Future.wait([
      widget.dashboardService.fetchSummary(forceRefresh: networkRefresh),
      _txService.fetchTransactionsForDate(
        dayKey,
        forceRefresh: networkRefresh,
      ),
      employeeService.fetchEmployees(forceRefresh: networkRefresh),
      _txService.fetchTransactions(forceRefresh: networkRefresh),
    ]);
    final summary = results[0] as DashboardSummary;
    final dayRows = results[1] as List<AppTransaction>;
    final employees = results[2] as List<Employee>;
    final allRows = results[3] as List<AppTransaction>;
    unawaited(CountRecordOfflineSync.instance.cacheEmployees(employees));
    unawaited(
      CountRecordOfflineSync.instance.loadDropdownCatalog(
        client: client,
        employeeService: employeeService,
        widgetEmployees: employees,
        serverOnlineHint: true,
        forceNetwork: networkRefresh,
      ),
    );
    return _composeHomePayload(
      summary: summary,
      dayRows: dayRows,
      allRows: allRows,
      employees: employees,
      dayKey: dayKey,
    );
  }

  Future<_HomePayload> _loadHome({
    bool forceRefresh = false,
    bool cacheFirst = false,
  }) async {
    final client = Supabase.instance.client;
    final dayKey = _dateKey(_selectedDay);

    if (cacheFirst && !forceRefresh) {
      final cached = await _loadHomeFromLocalCache(dayKey);
      if (cached != null && mounted) {
        setState(() => _lastHomePayload = cached);
      }
    }

    final online = await CountRecordOfflineSync.instance.isOnline(
      client,
      forceProbe: forceRefresh,
    );

    if (mounted) {
      if (online) {
        _applyServerReachability(true);
      } else {
        _applyServerReachability(false, force: forceRefresh);
      }
    }

    if (!online) {
      CountRecordOfflineSync.instance.noteServerUnreachable();
      return _loadHomeOfflineOrEmpty(dayKey);
    }

    try {
      try {
        await CountRecordOfflineSync.instance
            .uploadPendingImmediately(
              _txService,
              client,
            )
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
      CountRecordOfflineSync.instance.noteServerReachable();

      return await _loadHomeFromNetwork(
        client: client,
        dayKey: dayKey,
        networkRefresh: forceRefresh,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      CountRecordOfflineSync.instance.noteServerUnreachable();
      _applyServerReachability(false, force: forceRefresh);
      return _loadHomeOfflineOrEmpty(dayKey);
    }
  }

  void _refreshHome() {
    unawaited(_refreshHomeSilently(tryNetwork: true));
  }

  /// อัปเดตข้อมูลหลังบันทึก/ลบในเมนูนับจำนวน — ทำงานเบื้องหลัง
  /// ไม่ปิดเมนูย่อย ไม่โหลดทั้งหน้า และไม่โชว์แถบรีเฟรช
  Future<void> _refreshAfterCountRecordChange() async {
    if (!mounted) return;
    final base = _lastHomePayload;
    if (base == null) return;
    final dayKey = _dateKey(_selectedDay);
    // อ่านสถานะวันล่าสุดจากแคชในเครื่อง (CountRecordOfflineSync อัปเดตหลังบันทึก/ลบ)
    // เพื่อไม่ให้ข้อมูลเก่าที่ค้างใน payload เดิมโผล่กลับมา
    final cachedDay =
        await LocalDataCache.readTransactionsForDayAny(dayKey);
    final dayTransactions =
        await CountRecordOfflineSync.instance.mergeForDayAsync(
      dayKey,
      cachedDay ?? base.dayTransactions,
    );
    final allTransactions =
        await CountRecordOfflineSync.instance.mergeAllTransactionsAsync(
      base.allTransactions,
    );
    if (!mounted) return;
    final next = _HomePayload(
      summary: base.summary,
      dayTransactions: dayTransactions,
      allTransactions: allTransactions,
      employees: base.employees,
    );
    _applyPayloadQuietly(next);
  }

  String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatBuddhistDateButton(DateTime d) {
    const weekdays = [
      'วันจันทร์',
      'วันอังคาร',
      'วันพุธ',
      'วันพฤหัสบดี',
      'วันศุกร์',
      'วันเสาร์',
      'วันอาทิตย์',
    ];
    const months = [
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    final be = d.year + 543;
    return '${weekdays[d.weekday - 1]} ที่ ${d.day} เดือน${months[d.month - 1]} พ.ศ.$be';
  }

  Future<void> _pickDay() async {
    final first = DateTime(2020);
    final last = DateTime.now().add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      if (!mounted) return;
      final pickedDate = picked;
      setState(() {
        _selectedDay = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
        );
      });
      _configureTransactionRealtime();
      unawaited(_refreshHomeSilently(tryNetwork: _serverOnline));
    }
  }

  void _openQuickInput(_DailyModuleDef m) {
    if (!_serverOnline && !_isOfflineCapableModule(m.category)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'ไม่มีเน็ต — ใช้เมนู «บันทึกการร่อนทราย» «บันทึกรถดรัม» หรือ «บันทึกและนับจำนวน»',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    _openWithAnimation(
      QuickInputScreen(
        service: _txService,
        employeeService: EmployeeService(Supabase.instance.client),
        currentAdmin: widget.currentAdmin,
        initialCategory: m.category,
        appBarTitle: m.quickInputTitle,
        selectedDateForModule: DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day,
        ),
        serverOnlineHint: _serverOnline,
      ),
    ).then((_) => unawaited(_refreshHomeSilently(tryNetwork: _serverOnline)));
  }

  Future<T?> _openWithAnimation<T>(Widget page) {
    final isQuickInput = page is QuickInputScreen;
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: isQuickInput
            ? const Duration(milliseconds: 280)
            : const Duration(milliseconds: 220),
        reverseTransitionDuration: isQuickInput
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 160),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: isQuickInput ? Curves.easeOutCubic : Curves.easeOutQuart,
            reverseCurve: Curves.easeInCubic,
          );
          final slide = Tween<Offset>(
            begin: isQuickInput
                ? const Offset(0, 0.028)
                : const Offset(0.02, 0.012),
            end: Offset.zero,
          ).animate(curved);
          final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
          // หน้า Quick Input ไม่ย่อ/ขยาย — ลดงาน GPU บนเครื่องรุ่นเล็ก
          if (isQuickInput) {
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child),
            );
          }
          final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAppSettingsScreen(SupabaseClient client) async {
    await _openWithAnimation(
      AppSettingsScreen(
        currentAdmin: widget.currentAdmin,
        onOpenEmployees: () => _openWithAnimation(
          EmployeesScreen(service: EmployeeService(client)),
        ),
        onOpenTransactions: () => _openWithAnimation(
          TransactionsScreen(service: TransactionService(client)),
        ),
        onOpenProjects: () =>
            _openWithAnimation(ProjectsScreen(service: ProjectService(client))),
        onOpenMobileAndroidHub: () => _openWithAnimation(
          MobileErrorReportHubScreen(currentAdmin: widget.currentAdmin),
        ),
      ),
    );
  }

  Future<void> _openCalendarScreen(SupabaseClient client) async {
    await _openWithAnimation(
      CalendarScreen(
        transactionService: TransactionService(client),
        employeeService: EmployeeService(client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBFC),
      body: LayoutBuilder(
        builder: (context, bodyConstraints) {
          final rawBody = bodyConstraints.maxWidth.isFinite &&
                  bodyConstraints.maxWidth > 0
              ? bodyConstraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final mqW = MediaQuery.sizeOf(context).width;
          final safeMq =
              (mqW.isFinite && mqW > 0) ? mqW : 360.0;
          final bodyW =
              rawBody > safeMq ? safeMq : rawBody;
          return SafeArea(
            bottom: false,
            child: SizedBox(
              width: bodyW,
              child: ClipRect(
                child: FutureBuilder<_HomePayload>(
                  future: _homeFuture,
                  builder: (context, snapshot) {
                              final merged = snapshot.data ?? _lastHomePayload;
                              final waiting =
                                  snapshot.connectionState ==
                                  ConnectionState.waiting;
                              final data = merged;
                              final Widget body;
                              if ((waiting && data == null) || data == null) {
                                body = const DashboardLoadingView(
                                  key: ValueKey('dashboard_loading'),
                                );
                              } else if (snapshot.hasError) {
                                final l10n = AppLocalizations.of(context);
                                body = Center(
                                  key: const ValueKey('dashboard_error'),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${l10n.loadFailed}\n${snapshot.error}',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge,
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                          onPressed: _refreshHome,
                                          child: Text(l10n.retry),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else {
                                final reconnectingUi = _serverOnline &&
                                    CountRecordOfflineSync
                                        .instance
                                        .uploadInFlight;
                                body = _bodyPage == 0
                                    ? _DailyHomeContent(
                                        key: const ValueKey('dashboard_home'),
                                        currentAdmin: widget.currentAdmin,
                                        data: data,
                                        serverOnline: _serverOnline,
                                        serverReconnecting: reconnectingUi,
                                        countAndRecordMenuOpen:
                                            _countAndRecordMenuOpen,
                                        onCountAndRecordMenuOpenChanged: (open) {
                                          setState(
                                            () =>
                                                _countAndRecordMenuOpen = open,
                                          );
                                        },
                                        selectedDay: _selectedDay,
                                        onPullRefresh: _pullRefresh,
                                        onCountRecordDataChanged:
                                            _refreshAfterCountRecordChange,
                                        onPickDay: _pickDay,
                                        dateKey: _dateKey,
                                        formatBuddhistDateButton:
                                            _formatBuddhistDateButton,
                                        onOpenModule: _openQuickInput,
                                        txService: _txService,
                                        employeeService:
                                            EmployeeService(client),
                                      )
                                    : _MetricsContent(
                                        key: const ValueKey('dashboard_metrics'),
                                        data: data,
                                        currentAdmin: widget.currentAdmin,
                                        onRetry: _refreshHome,
                                      );
                              }
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 340),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeIn,
                                child: body,
                              );
                            },
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(client),
    );
  }

  Future<void> _pullRefresh() async {
    await CountRecordOfflineSync.instance.syncNow();
    await _refreshHomeSilently(tryNetwork: true);
  }

  /// แถบนำทางล่างแบบ Material 3 — หน้าแรก / ปฏิทิน / ตั้งค่า / ออกจากระบบ
  Widget _buildBottomNav(SupabaseClient client) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE7ECF3))),
      ),
      child: NavigationBar(
        height: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFD5F2F5),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: 0,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          switch (index) {
            case 0:
              setState(() => _bodyPage = 0);
            case 1:
              _openCalendarScreen(client);
            case 2:
              _openAppSettingsScreen(client);
            case 3:
              _confirmLogout();
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(
              Icons.home_rounded,
              color: Color(0xFF0D98A5),
            ),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            label: l10n.navCalendar,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.navSettings,
          ),
          NavigationDestination(
            icon: const Icon(Icons.logout_rounded),
            label: l10n.navLogout,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.navLogout),
        content: Text(l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.navLogout),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onLogout();
    }
  }
}

const _kDailyMenuDetailCategories = {
  'ลางาน',
  'บันทึกการร่อนทราย',
  'จำนวนเที่ยวรถ',
  'การใช้รถแม็คโคร',
  'น้ำมัน',
  'ทรายที่ล้างที่บ้าน',
  'ค่าแรง',
  'OT',
};

class _HomePayload {
  const _HomePayload({
    required this.summary,
    required this.dayTransactions,
    required this.allTransactions,
    required this.employees,
  });

  final DashboardSummary summary;
  final List<AppTransaction> dayTransactions;
  final List<AppTransaction> allTransactions;
  final List<Employee> employees;
}

class _DailyHomeContent extends StatefulWidget {
  const _DailyHomeContent({
    super.key,
    required this.currentAdmin,
    required this.data,
    required this.serverOnline,
    this.serverReconnecting = false,
    required this.countAndRecordMenuOpen,
    required this.onCountAndRecordMenuOpenChanged,
    required this.selectedDay,
    required this.onPullRefresh,
    required this.onCountRecordDataChanged,
    required this.onPickDay,
    required this.dateKey,
    required this.formatBuddhistDateButton,
    required this.onOpenModule,
    required this.txService,
    required this.employeeService,
  });

  final AdminUser currentAdmin;
  final _HomePayload data;
  final bool serverOnline;
  final bool serverReconnecting;
  final bool countAndRecordMenuOpen;
  final ValueChanged<bool> onCountAndRecordMenuOpenChanged;
  final DateTime selectedDay;
  final Future<void> Function() onPullRefresh;
  final Future<void> Function() onCountRecordDataChanged;
  final VoidCallback onPickDay;
  final String Function(DateTime) dateKey;
  final String Function(DateTime) formatBuddhistDateButton;
  final void Function(_DailyModuleDef m) onOpenModule;
  final TransactionService txService;
  final EmployeeService employeeService;

  @override
  State<_DailyHomeContent> createState() => _DailyHomeContentState();
}

class _DailyHomeContentState extends State<_DailyHomeContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final bool _reduceMotion;
  /// After the grid entrance animation finishes, drop stagger transforms so
  /// scrolling does not composite Fade+Slide+Scale on every tile each frame.
  bool _gridEntranceCompleted = false;
  bool _countRecordTutorialScheduled = false;
  static const _kPanelShadowColor = Color(0x12000000);

  void _onEntranceStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && !_gridEntranceCompleted) {
      setState(() => _gridEntranceCompleted = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncErrorTrackerStep();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final lowSpec = DevicePerf.isConstrainedDevice;
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: _reduceMotion
            ? 120
            : (lowSpec ? 220 : 340),
      ),
    );
    _entranceController.addStatusListener(_onEntranceStatus);
    _entranceController.forward();
    if (widget.countAndRecordMenuOpen) {
      _scheduleCountRecordTutorialIfNeeded();
    }
  }

  void _scheduleCountRecordTutorialIfNeeded() {
    if (_countRecordTutorialScheduled) return;
    _countRecordTutorialScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.countAndRecordMenuOpen) return;
      unawaited(CountRecordTutorial.showIfFirstTime(context));
    });
  }

  void _openCountRecordTutorial() {
    unawaited(
      CountRecordTutorial.show(
        context,
        markCompleteOnFinish: false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _DailyHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay) {
      _gridEntranceCompleted = false;
      _entranceController
        ..reset()
        ..forward();
    }
    if (oldWidget.countAndRecordMenuOpen != widget.countAndRecordMenuOpen) {
      _syncErrorTrackerStep();
      if (widget.countAndRecordMenuOpen) {
        _scheduleCountRecordTutorialIfNeeded();
      }
    }
  }

  void _syncErrorTrackerStep() {
    if (widget.countAndRecordMenuOpen) {
      MobileErrorScreenTracker.set(
        page: 'หน้าหลัก (แดชบอร์ด)',
        pageId: MobileScreenIds.pageDashboard,
        module: 'บันทึกและนับจำนวน',
        stepId: MobileScreenIds.stepDashboardCountRecordMenu,
      );
    } else {
      MobileErrorScreenTracker.set(
        page: 'หน้าหลัก (แดชบอร์ด)',
        pageId: MobileScreenIds.pageDashboard,
        stepId: MobileScreenIds.stepDashboardHome,
      );
    }
  }

  @override
  void dispose() {
    _entranceController.removeStatusListener(_onEntranceStatus);
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useLiteAnimations = _reduceMotion;
    final l10n = AppLocalizations.of(context);
    final localeScope = AppLocaleScope.of(context);
    final offlineMode = !widget.serverOnline;
    final reconnecting = widget.serverReconnecting;
    final dayKey = widget.dateKey(widget.selectedDay);
    final lastLabel = widget.data.dayTransactions.isNotEmpty
        ? l10n.formatShortDateFromYmd(
            widget.data.dayTransactions.first.date,
          )
        : '—';

    final menuStatusByCategory = <String, DailyModuleFillStatus>{
      for (final m in _kDailyModules)
        m.category: resolveDailyModuleFillStatus(
          dayKey,
          m.category,
          widget.data.dayTransactions,
        ),
    };
    final countRecordFill = resolveCountRecordMenuFillStatus(
      dayKey,
      widget.data.dayTransactions,
    );
    final countRecordStatusLabel = countRecordMenuStatusLabel(
      dayKey,
      widget.data.dayTransactions,
    );
    Widget buildCountRecordEntryCard({bool showLightStyle = false}) {
      return RecordModuleCard(
        title: 'บันทึกและนับจำนวน',
        icon: Icons.timer_outlined,
        tileColor: const Color(0xFF1565C0),
        showLightStyle: showLightStyle,
        fillStatus: countRecordFill,
        completeStatusLabelOverride: translateDailyCardStatus(
          countRecordStatusLabel,
          localeScope.locale,
        ),
        statusMaxLines: 2,
        onTap: () {
          widget.onCountAndRecordMenuOpenChanged(true);
          unawaited(RecordSuccessSpeaker.instance.warmUp());
        },
      );
    }
    final headerAnim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.46, curve: Curves.easeOutCubic),
    );
    final panelAnim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.16, 0.78, curve: Curves.easeOutCubic),
    );
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final constrained = DevicePerf.isConstrainedDevice;
    final cacheRows = constrained ? 1.0 : (isAndroid ? 3.5 : 2.0);

    final dailyMenuPanel = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE7ECF3)),
        boxShadow: [
          BoxShadow(
            color: _kPanelShadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: AnimatedSwitcher(
          duration: MenuPanelTransition.duration(lite: useLiteAnimations),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: MenuPanelTransition.build,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [
              ...previous,
              ?current,
            ],
          ),
          child: LayoutBuilder(
            key: ValueKey(
              '${widget.formatBuddhistDateButton(widget.selectedDay)}_'
              'menu_${widget.countAndRecordMenuOpen}',
            ),
            builder: (context, constraints) {
              if (widget.countAndRecordMenuOpen) {
                void backToMainMenu() {
                  widget.onCountAndRecordMenuOpenChanged(false);
                  unawaited(widget.onCountRecordDataChanged());
                }

                final dayKeyStr = widget.dateKey(widget.selectedDay);
                final portrait =
                    MediaQuery.orientationOf(context) == Orientation.portrait;

                Widget counterCell({
                  required String title,
                  required IconData icon,
                  required Color iconColor,
                  required Color backgroundColor,
                  required Color borderColor,
                  required CounterMode counterMode,
                  required String modeKey,
                }) {
                  return _CountRecordMenuCard(
                    title: title,
                    subtitle: '',
                    icon: icon,
                    iconColor: iconColor,
                    backgroundColor: backgroundColor,
                    borderColor: borderColor,
                    expanded: true,
                    onTap: () {},
                    expandedChild: CountRecordCounterPanel(
                      key: ValueKey('counter_${modeKey}_$dayKeyStr'),
                      mode: counterMode,
                      service: widget.txService,
                      employeeService: widget.employeeService,
                      currentAdmin: widget.currentAdmin,
                      dateYmd: dayKeyStr,
                      dayTransactions: widget.data.dayTransactions,
                      employees: widget.data.employees,
                      tripHistoryTransactions: widget.data.allTransactions,
                      embedded: true,
                      serverOnline: widget.serverOnline,
                      onDataChanged: () {
                        unawaited(widget.onCountRecordDataChanged());
                      },
                    ),
                  );
                }

                final tripCell = counterCell(
                  modeKey: 'trip',
                  title: 'จำนวนเที่ยวรถ',
                  icon: Icons.fire_truck_outlined,
                  iconColor: const Color(0xFF1565C0),
                  backgroundColor: const Color(0xFFE3F2FD),
                  borderColor: const Color(0xFF90CAF9),
                  counterMode: CounterMode.trip,
                );
                final sandCell = counterCell(
                  modeKey: 'sand',
                  title: 'การร่อนทราย',
                  icon: Icons.water_drop_outlined,
                  iconColor: const Color(0xFFAD1457),
                  backgroundColor: const Color(0xFFFCE4EC),
                  borderColor: const Color(0xFFF48FB1),
                  counterMode: CounterMode.sand,
                );

                return CountRecordMenuShell(
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'บันทึกและนับจำนวน',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF1A2433),
                                        ),
                                  ),
                                ),
                                if (offlineMode)
                                  const _CountRecordPendingBadge(),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (offlineMode || reconnecting)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: Container(
                                key: ValueKey(
                                  reconnecting ? 'reconnecting' : 'offline',
                                ),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: reconnecting
                                      ? const Color(0xFFFFF8E1)
                                      : const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: reconnecting
                                        ? const Color(0xFFFFE082)
                                        : const Color(0xFFFFCC80),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      reconnecting
                                          ? Icons.sync_rounded
                                          : Icons.cloud_off_outlined,
                                      size: 16,
                                      color: reconnecting
                                          ? const Color(0xFFF57F17)
                                          : const Color(0xFFE65100),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      reconnecting
                                          ? 'กำลังซิงก์'
                                          : 'โหมดออฟไลน์',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: reconnecting
                                            ? const Color(0xFFF57F17)
                                            : const Color(0xFFE65100),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'สอนใช้งาน',
                            onPressed: _openCountRecordTutorial,
                            icon: const Icon(Icons.school_outlined),
                            color: const Color(0xFF1565C0),
                            visualDensity: VisualDensity.compact,
                          ),
                          TextButton(
                            onPressed: backToMainMenu,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4A5A70),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: const Size(0, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFD9E1EC)),
                              ),
                            ),
                            child: Text(
                              offlineMode ? 'กลับเลือกเมนู' : 'กลับเมนูหลัก',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: portrait
                            ? Column(
                                children: [
                                  Expanded(child: tripCell),
                                  const SizedBox(height: 10),
                                  Expanded(child: sandCell),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: tripCell),
                                  const SizedBox(width: 10),
                                  Expanded(child: sandCell),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                );
              }

              final visibleModules = _kDailyModules;
              final gridItemCount = visibleModules.length + 1;
              const gap = 10.0;
              const sideInset = 2.0;
              final mq = MediaQuery.sizeOf(context);
              final mqW = mq.width;
              final mqH = mq.height;
              final isLandscape = mqW > mqH;
              final cross = isLandscape
                  ? (mqW >= 900
                        ? 5
                        : mqW >= 640
                        ? 4
                        : 3)
                  : 3;
              final safeMq =
                  (mqW.isFinite && mqW > 0) ? mqW : 360.0;
              final rawW = constraints.maxWidth;
              final layoutW = rawW.isFinite && rawW > 0
                  ? rawW
                  : safeMq;
              final w =
                  layoutW > safeMq ? safeMq : layoutW;
              final rawMaxH = constraints.maxHeight;
              final availH = !rawMaxH.isFinite
                  ? 120.0
                  : rawMaxH <= 0
                      ? 1.0
                      : rawMaxH;
              final rows =
                  (gridItemCount / cross).ceil().clamp(1, 12);
              final usableWidth = w - (sideInset * 2);
              final cellWidth =
                  (usableWidth - (gap * (cross - 1))) / cross;
              final fitCellHeight =
                  (availH - (gap * (rows - 1))) / rows;
              // แนวตั้ง: การ์ดจัตุรัส | แนวนอน: สี่เหลี่ยมผืนผ้าเต็มความสูงที่เหลือ
              final preferredCellHeight = isLandscape
                  ? fitCellHeight.clamp(64.0, 108.0)
                  : cellWidth.clamp(96.0, 200.0);
              final totalNeeded =
                  (preferredCellHeight * rows) + (gap * (rows - 1));
              final menuScrolls = isLandscape
                  ? totalNeeded > availH + 0.5
                  : totalNeeded > availH + 0.5;
              final cellHeight = isLandscape
                  ? (menuScrolls
                        ? preferredCellHeight
                        : fitCellHeight.clamp(64.0, 120.0))
                  : (menuScrolls
                        ? preferredCellHeight
                        : (preferredCellHeight > fitCellHeight
                              ? fitCellHeight
                              : preferredCellHeight));
              final contentHeight =
                  (cellHeight * rows) + (gap * (rows - 1));
              final topInset = menuScrolls
                  ? 6.0
                  : ((availH - contentHeight) / 2).clamp(0.0, 24.0);
              return RepaintBoundary(
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    sideInset,
                    topInset,
                    sideInset,
                    menuScrolls ? 10 : 0,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  addAutomaticKeepAlives: true,
                  addRepaintBoundaries: true,
                  cacheExtent:
                      menuScrolls ? (cellHeight * cacheRows + gap * 2) : 0,
                  itemCount: gridItemCount,
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    mainAxisExtent: cellHeight,
                  ),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final card = buildCountRecordEntryCard(
                        showLightStyle: index.isOdd,
                      );
                      if (_gridEntranceCompleted) {
                        return RepaintBoundary(
                          key: ValueKey('mod_count_record_root'),
                          child: card,
                        );
                      }
                      return _StaggerMenuTile(
                        parent: _entranceController,
                        index: 0,
                        lite: useLiteAnimations,
                        child: card,
                      );
                    }
                    final moduleIndex = index - 1;
                    final m = visibleModules[moduleIndex];
                    final fill =
                        menuStatusByCategory[m.category] ??
                            DailyModuleFillStatus.pending;
                    final globalIndex = _kDailyModules.indexOf(m);
                    final rawStatus = dailyModuleCardStatusLabel(
                      moduleCategory: m.category,
                      dayKey: dayKey,
                      dayTransactions: widget.data.dayTransactions,
                      employees: widget.data.employees,
                      allTransactionsForStock: widget.data.allTransactions,
                    );
                    final moduleOfflineLocked = offlineMode &&
                        !_isOfflineCapableModule(m.category);
                    final card = Opacity(
                      opacity: moduleOfflineLocked ? 0.38 : 1.0,
                      child: RecordModuleCard(
                        title: l10n.moduleTitle(m.category),
                        icon: m.icon,
                        tileColor: m.color,
                        showLightStyle: index.isOdd,
                        fillStatus: fill,
                        completeStatusLabelOverride: translateDailyCardStatus(
                          rawStatus,
                          localeScope.locale,
                        ),
                        statusMaxLines:
                            _kDailyMenuDetailCategories.contains(m.category)
                            ? 3
                            : 2,
                        onTap: moduleOfflineLocked
                            ? () {
                                ScaffoldMessenger.maybeOf(context)
                                    ?.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'ไม่มีเน็ต — ใช้เมนู «บันทึกและนับจำนวน» เท่านั้น',
                                    ),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            : () => widget.onOpenModule(m),
                      ),
                    );
                    if (_gridEntranceCompleted) {
                      return RepaintBoundary(
                        key: ValueKey('mod_${m.category}'),
                        child: card,
                      );
                    }
                    return _StaggerMenuTile(
                      parent: _entranceController,
                      index:
                          globalIndex >= 0 ? globalIndex : index,
                      lite: useLiteAnimations,
                      child: card,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFFF8FAFC))),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: Duration(
                  milliseconds: useLiteAnimations ? 180 : 300,
                ),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: widget.countAndRecordMenuOpen
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FadeTransition(
                            opacity: headerAnim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.08),
                                end: Offset.zero,
                              ).animate(headerAnim),
                              child: _HomeHeaderCompact(
                                appName: widget.data.summary.appName,
                                lastLabel: lastLabel,
                                selectedDateLabel: l10n.formatSelectedDate(
                                  widget.selectedDay,
                                ),
                                onPickDay: widget.onPickDay,
                                onRefresh: widget.onPullRefresh,
                                locale: localeScope.locale,
                                onLocaleChanged: localeScope.onLocaleChanged,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: widget.onPullRefresh,
                  color: const Color(0xFF11A8BA),
                  child: _gridEntranceCompleted
                      ? dailyMenuPanel
                      : FadeTransition(
                          opacity: panelAnim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.05),
                              end: Offset.zero,
                            ).animate(panelAnim),
                            child: dailyMenuPanel,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// จำนวนรายการรอซิงก์ — แสดงข้างหัวข้อ «บันทึกและนับจำนวน» ตอนโหมดออฟไลน์
class _CountRecordPendingBadge extends StatefulWidget {
  const _CountRecordPendingBadge();

  @override
  State<_CountRecordPendingBadge> createState() =>
      _CountRecordPendingBadgeState();
}

class _CountRecordPendingBadgeState extends State<_CountRecordPendingBadge> {
  @override
  void initState() {
    super.initState();
    // บังคับโหลดคิวจากดิสก์ครั้งแรก — จากนั้นฟังค่าผ่าน notifier ไม่ต้อง polling
    unawaited(CountRecordOfflineSync.instance.pendingCount());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CountRecordOfflineSync.instance.pendingCountListenable,
      builder: (context, pending, _) {
        if (pending <= 0) return const SizedBox.shrink();
        return _buildBadge(pending);
      },
    );
  }

  Widget _buildBadge(int pending) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFFFCC80)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: Color(0xFFE65100),
              ),
              const SizedBox(width: 4),
              Text(
                'รอซิงก $pending',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountRecordMenuCard extends StatelessWidget {
  const _CountRecordMenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
    this.expanded = false,
    this.expandedChild,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;
  final bool expanded;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) {
    final shell = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: expanded ? iconColor : borderColor,
          width: expanded ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _buildContent(),
      ),
    );

    if (expanded) {
      return shell;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: shell,
      ),
    );
  }

  Widget _buildContent() {
    if (expanded && expandedChild != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            color: iconColor,
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: expandedChild!),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Icon(icon, color: iconColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A2433),
              height: 1.14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5C7088),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 14,
                color: Color(0xFF6B7280),
              ),
              SizedBox(width: 4),
              Text(
                'แตะเพื่อบันทึก',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaggerMenuTile extends StatelessWidget {
  const _StaggerMenuTile({
    required this.parent,
    required this.index,
    required this.lite,
    required this.child,
  });

  final Animation<double> parent;
  final int index;
  final bool lite;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (0.22 + (index * 0.05)).clamp(0.0, 0.82);
    final end = (start + (lite ? 0.18 : 0.28)).clamp(0.0, 1.0);
    final fade = CurvedAnimation(
      parent: parent,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, lite ? 0.03 : 0.07),
          end: Offset.zero,
        ).animate(fade),
        child: ScaleTransition(
          scale: Tween<double>(begin: lite ? 0.985 : 0.96, end: 1).animate(fade),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _HomeHeaderCompact extends StatelessWidget {
  const _HomeHeaderCompact({
    required this.appName,
    required this.lastLabel,
    required this.selectedDateLabel,
    required this.onPickDay,
    required this.onRefresh,
    required this.locale,
    required this.onLocaleChanged,
  });

  final String appName;
  final String lastLabel;
  final String selectedDateLabel;
  final VoidCallback onPickDay;
  final Future<void> Function() onRefresh;
  final AppLocale locale;
  final ValueChanged<AppLocale> onLocaleChanged;

  static const _teal = Color(0xFF0D98A5);
  static const _tealDark = Color(0xFF0A6270);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3ECF2)),
        boxShadow: [
          BoxShadow(
            color: _DailyHomeContentState._kPanelShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00C4D4), _teal],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: AppLogo(size: 36),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.dailyLogTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF152535),
                                letterSpacing: -0.3,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF7A8FA0),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<AppLocale>(
                        segments: [
                          ButtonSegment(
                            value: AppLocale.th,
                            label: Text(
                              AppLocale.th.shortLabel,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          ButtonSegment(
                            value: AppLocale.zh,
                            label: Text(
                              AppLocale.zh.shortLabel,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        selected: {locale},
                        onSelectionChanged: (next) {
                          if (next.isEmpty) return;
                          onLocaleChanged(next.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          ),
                          minimumSize: const WidgetStatePropertyAll(
                            Size(28, 32),
                          ),
                        ),
                      ),
                      _PressScaleButton(
                        child: IconButton(
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => onRefresh(),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF546E7A),
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PressScaleButton(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPickDay,
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFE8F8FA), Color(0xFFF4FCFD)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFB8E4EA)),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _teal.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.calendar_month_rounded,
                                    color: _teal,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedDateLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: _tealDark,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: _teal,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeaderStatChip(
                        icon: Icons.access_time_filled_rounded,
                        label: '${l10n.latestPrefix} $lastLabel',
                      ),
                      _LiveClockChip(l10n: l10n),
                      ValueListenableBuilder<AppSyncSnapshot>(
                        valueListenable:
                            CountRecordOfflineSync.instance.syncState,
                        builder: (context, sync, _) {
                          IconData icon;
                          Color iconColor;
                          String label;
                          if (sync.isSyncing) {
                            icon = Icons.sync_rounded;
                            iconColor = const Color(0xFFF9A825);
                            label = sync.headerStatusLabel;
                          } else if (sync.network == NetworkLinkState.unlink) {
                            icon = Icons.wifi_off_rounded;
                            iconColor = const Color(0xFF78909C);
                            label = sync.headerStatusLabel;
                          } else if (sync.server == ServerReachState.offline) {
                            icon = Icons.cloud_off_rounded;
                            iconColor = const Color(0xFFC25050);
                            label = sync.headerStatusLabel;
                          } else if (sync.pendingCount > 0) {
                            icon = Icons.cloud_upload_outlined;
                            iconColor = const Color(0xFF1565C0);
                            label = sync.headerStatusLabel;
                          } else {
                            icon = Icons.cloud_done_rounded;
                            iconColor = const Color(0xFF1E8E56);
                            label = l10n.serverOnline;
                          }
                          return _HeaderStatChip(
                            icon: icon,
                            label: label,
                            iconColor: iconColor,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveClockChip extends StatefulWidget {
  const _LiveClockChip({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_LiveClockChip> createState() => _LiveClockChipState();
}

class _LiveClockChipState extends State<_LiveClockChip> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final suffix = widget.l10n.timeSuffix;
    final clock = suffix.isEmpty ? '$hh:$mm' : '$hh:$mm $suffix';
    return _HeaderStatChip(
      icon: Icons.schedule_rounded,
      label: '${widget.l10n.timePrefix} $clock',
    );
  }
}

class _HeaderStatChip extends StatelessWidget {
  const _HeaderStatChip({
    required this.icon,
    required this.label,
    this.iconColor = const Color(0xFF415268),
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final mqW = MediaQuery.sizeOf(context).width;
        final cap = c.maxWidth.isFinite && c.maxWidth > 0
            ? c.maxWidth
            : (mqW.isFinite && mqW > 0 ? mqW : 360.0);
        final labelMax = (cap - 44).clamp(48.0, 260.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFD),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCE4EF)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 15),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMax),
                  child: Text(
                    label,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF415268),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
}

class _PressScaleButton extends StatefulWidget {
  const _PressScaleButton({required this.child});

  final Widget child;

  @override
  State<_PressScaleButton> createState() => _PressScaleButtonState();
}

class _PressScaleButtonState extends State<_PressScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 48),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.96 : 1,
        child: widget.child,
      ),
    );
  }
}

class _MetricsContent extends StatelessWidget {
  const _MetricsContent({
    super.key,
    required this.data,
    required this.currentAdmin,
    required this.onRetry,
  });

  final _HomePayload data;
  final AdminUser currentAdmin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Supabase.instance.client;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'สรุปภาพรวม',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'ผู้ใช้งาน: ${currentAdmin.displayName} (${currentAdmin.role})',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        _MetricTile(
          title: 'พนักงานทั้งหมด',
          value: '${data.summary.employeeCount}',
          icon: Icons.groups_2_outlined,
        ),
        _MetricTile(
          title: 'รายการธุรกรรม',
          value: '${data.summary.transactionCount}',
          icon: Icons.receipt_long_outlined,
        ),
        _MetricTile(
          title: 'โครงการที่ดิน',
          value: '${data.summary.projectCount}',
          icon: Icons.location_city_outlined,
        ),
        _MetricTile(
          title: 'รายรับรวม',
          value: '${data.summary.totalRevenue.toStringAsFixed(2)} บาท',
          icon: Icons.trending_up_outlined,
        ),
        _MetricTile(
          title: 'รายจ่ายรวม',
          value: '${data.summary.totalExpense.toStringAsFixed(2)} บาท',
          icon: Icons.trending_down_outlined,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TransactionsScreen(service: TransactionService(client)),
              ),
            );
          },
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('จัดการธุรกรรม'),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF11A8BA)),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
