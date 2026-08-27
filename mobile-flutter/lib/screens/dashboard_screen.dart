import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../models/employee.dart';
import '../services/count_record_offline_sync.dart';
import '../services/count_record_work_mode_store.dart';
import '../services/local_data_cache.dart';
import '../services/dashboard_service.dart';
import '../services/employee_service.dart';
import '../services/project_service.dart';
import '../services/transaction_service.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import '../l10n/daily_status_translator.dart';
import '../utils/app_haptics.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/device_perf.dart';
import '../utils/touch_profile.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../utils/record_success_speaker.dart';
import '../widgets/app_logo.dart';
import '../widgets/count_record_counters.dart';
import '../widgets/count_record_day_picker.dart';
import '../widgets/daily_record_day_picker.dart';
import '../widgets/count_record_menu_shell.dart';
import '../widgets/count_record_tutorial.dart';
import '../widgets/count_record_work_mode_picker.dart';
import '../widgets/dashboard_loading_view.dart';
import '../widgets/app_page_route.dart';
import '../widgets/menu_panel_transition.dart';
import '../widgets/record_module_card.dart';
import '../widgets/soft_press_button.dart';
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
    title: 'เช็คชื่อ',
    icon: Icons.how_to_reg_outlined,
    category: 'เช็คชื่อ',
    quickInputTitle: 'เช็คชื่อประจำวัน',
    color: Color(0xFF2FB6A6),
  ),
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
  /// ตั้งปลุกที่เที่ยงคืน — สลับ `_selectedDay` เป็นวันใหม่เมื่อแอปค้างข้ามคืน
  Timer? _midnightRolloverTimer;
  /// debounce Realtime — กันยิงถี่ตอนมีหลายแถวเปลี่ยนพร้อมกัน
  Timer? _remoteRefreshDebounce;
  /// poll สำรองเมื่อ Realtime พลาด (เท่าเว็บ ~12 วิ)
  Timer? _pollFallbackTimer;
  static const Duration _remoteRefreshDebounceDelay =
      Duration(milliseconds: 300);
  static const Duration _pollFallbackInterval = Duration(minutes: 5);

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
        _scheduleRemoteRefresh();
      },
    );
  }

  /// Realtime จากเครื่องอื่น → ดึงเน็ต (รวมตอนเปิดเมนูนับจำนวน)
  void _scheduleRemoteRefresh() {
    _remoteRefreshDebounce?.cancel();
    _remoteRefreshDebounce = Timer(_remoteRefreshDebounceDelay, () {
      if (!mounted) return;
      unawaited(_refreshHomeSilently(tryNetwork: true));
    });
  }

  void _startPollFallback() {
    _pollFallbackTimer?.cancel();
    // Soft poll: respect cache TTL — Realtime handles live updates; avoid force full-table IO.
    _pollFallbackTimer = Timer.periodic(_pollFallbackInterval, (_) {
      if (!mounted || !_serverOnline) return;
      unawaited(_refreshHomeSilently(tryNetwork: true, forceNetwork: false));
    });
  }

  void _stopPollFallback() {
    _pollFallbackTimer?.cancel();
    _pollFallbackTimer = null;
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
  Future<void> _refreshHomeSilently({
    bool tryNetwork = true,
    bool forceNetwork = true,
  }) async {
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
        networkRefresh: forceNetwork,
        includeFullLedger: forceNetwork,
      ).timeout(const Duration(seconds: 12));
      if (mounted) _applyPayloadQuietly(fresh);
    } catch (_) {
      // คงข้อมูลแคชบนจอ — ไม่กระพริบหรือสลับโหมดกะทันหัน
    }
  }

  /// โหลดข้อมูลใหม่ในพื้นหลัง — ไม่รีเซ็ตหน้าที่ผู้ใช้อยู่ (เมนูย่อยนับจำนวน ฯลฯ)
  /// ดึงจากเซิร์ฟเวอร์เสมอ เพื่อรับการแก้จากเครื่องอื่น (แม้เปิดเมนูนับจำนวนอยู่)
  Future<void> _refreshHomeDataInPlace() async {
    await _refreshHomeSilently(tryNetwork: true, forceNetwork: false);
    if (!mounted) return;
    unawaited(
      _hydrateFullLedger(
        dayKey: _dateKey(_selectedDay),
        forceRefresh: false,
      ),
    );
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
    _startPollFallback();
    _scheduleMidnightRollover();
  }

  /// ตั้ง Timer ให้ปลุกหลังเที่ยงคืน (+1 วิ) เพื่อสลับวันอัตโนมัติ
  void _scheduleMidnightRollover() {
    _midnightRolloverTimer?.cancel();
    _midnightRolloverTimer = null;
    if (!mounted) return;
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now) + const Duration(seconds: 1);
    _midnightRolloverTimer = Timer(delay, () {
      if (!mounted) return;
      _handleDayRollover();
    });
  }

  /// เมื่อวันปฏิทินเปลี่ยน — สลับ `_selectedDay` เป็นวันนี้ + toast + refresh
  void _handleDayRollover() {
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_dateKey(_selectedDay) != _dateKey(today)) {
      setState(() => _selectedDay = today);
      _configureTransactionRealtime();
      unawaited(_refreshHomeSilently(tryNetwork: _serverOnline));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'ขึ้นวันใหม่แล้ว — เปลี่ยนเป็นวันปัจจุบันให้อัตโนมัติ',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
    _scheduleMidnightRollover();
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
    _midnightRolloverTimer?.cancel();
    _remoteRefreshDebounce?.cancel();
    _stopPollFallback();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // เช็คว่าข้ามวันระหว่างพักเบื้องหลังไหม — สลับเป็นวันนี้ + ตั้ง timer ใหม่
      _handleDayRollover();
      _startPollFallback();
      unawaited(_syncCountRecordQueueThenRefresh());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopPollFallback();
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
      forceProbe: false,
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
    bool includeFullLedger = true,
  }) async {
    final employeeService = EmployeeService(client);
    final futures = <Future<dynamic>>[
      widget.dashboardService.fetchSummary(forceRefresh: networkRefresh),
      _txService.fetchTransactionsForDate(
        dayKey,
        forceRefresh: networkRefresh,
      ),
      employeeService.fetchEmployees(forceRefresh: networkRefresh),
    ];
    if (includeFullLedger) {
      futures.add(_txService.fetchTransactions(forceRefresh: networkRefresh));
    }
    final results = await Future.wait(futures);
    final summary = results[0] as DashboardSummary;
    final dayRows = results[1] as List<AppTransaction>;
    final employees = results[2] as List<Employee>;
    final List<AppTransaction> allRows;
    if (includeFullLedger) {
      allRows = results[3] as List<AppTransaction>;
    } else {
      // First paint / soft poll: never wait on full-table fetch or file decode.
      final prior = _lastHomePayload?.allTransactions;
      allRows = (prior != null && prior.isNotEmpty)
          ? prior
          : const <AppTransaction>[];
    }
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

      final payload = await _loadHomeFromNetwork(
        client: client,
        dayKey: dayKey,
        networkRefresh: forceRefresh,
        includeFullLedger: false,
      ).timeout(const Duration(seconds: 12));
      unawaited(
        _hydrateFullLedger(dayKey: dayKey, forceRefresh: forceRefresh),
      );
      return payload;
    } catch (_) {
      CountRecordOfflineSync.instance.noteServerUnreachable();
      _applyServerReachability(false, force: forceRefresh);
      return _loadHomeOfflineOrEmpty(dayKey);
    }
  }

  /// เติม ledger เต็มชุดหลังขึ้นจอแล้ว — ไม่บล็อกสปินเนอร์ครั้งแรก
  Future<void> _hydrateFullLedger({
    required String dayKey,
    required bool forceRefresh,
  }) async {
    try {
      final allRows = await _txService.fetchTransactions(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      if (_dateKey(_selectedDay) != dayKey) return;
      final base = _lastHomePayload;
      if (base == null) return;
      final composed = await _composeHomePayload(
        summary: base.summary,
        dayRows: base.dayTransactions,
        allRows: allRows,
        employees: base.employees,
        dayKey: dayKey,
      );
      if (!mounted) return;
      if (_dateKey(_selectedDay) != dayKey) return;
      _applyPayloadQuietly(composed);
    } catch (_) {}
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
    final picked = await showDailyRecordDayPicker(
      context: context,
      initialDate: _selectedDay,
      transactions: _lastHomePayload?.allTransactions ?? const [],
    );
    if (picked != null) {
      _applySelectedDay(picked);
    }
  }

  /// ปฏิทินในหน้าบันทึกและนับจำนวน — แสดงวันที่มีเที่ยว/ร่อนทราย
  Future<void> _pickCountRecordDay() async {
    final picked = await showCountRecordDayPicker(
      context: context,
      initialDate: _selectedDay,
      transactions: _lastHomePayload?.allTransactions ?? const [],
    );
    if (picked != null) {
      _applySelectedDay(picked);
    }
  }

  void _applySelectedDay(DateTime picked) {
    if (!mounted) return;
    final next = DateTime(picked.year, picked.month, picked.day);
    if (_dateKey(_selectedDay) == _dateKey(next)) return;
    setState(() => _selectedDay = next);
    _configureTransactionRealtime();
    unawaited(_refreshHomeSilently(tryNetwork: _serverOnline));
  }

  /// สลับวันที่เลือกเป็นวันนี้ — เรียกเมื่อกดนับขณะดูวันอื่นใน «บันทึกและนับจำนวน»
  void _forceCountRecordToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_dateKey(_selectedDay) == _dateKey(today)) return;
    if (!mounted) return;
    setState(() => _selectedDay = today);
    _configureTransactionRealtime();
    unawaited(_refreshHomeSilently(tryNetwork: _serverOnline));
  }

  void _openQuickInput(_DailyModuleDef m) {
    AppHaptics.confirm();
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
    final style = page is QuickInputScreen
        ? AppTransitionStyle.modalUp
        : AppTransitionStyle.drillDown;
    return Navigator.of(context).push<T>(
      AppPageRoute<T>(page: page, style: style),
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
        onLogout: widget.onLogout,
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
                                        onRequireToday: _forceCountRecordToday,
                                        onPickDay: _pickDay,
                                        onPickCountRecordDay: _pickCountRecordDay,
                                        dateKey: _dateKey,
                                        formatBuddhistDateButton:
                                            _formatBuddhistDateButton,
                                        onOpenModule: _openQuickInput,
                                        onOpenSettings: () =>
                                            _openAppSettingsScreen(client),
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

  /// แถบนำทางล่าง — ซ่อนเป็นค่าเริ่มต้น เหลือขีดจับ; ปัดขึ้น/แตะเพื่อแสดง
  /// กดเมนูแล้วหุบกลับทันที
  Widget _buildBottomNav(SupabaseClient client) {
    final l10n = AppLocalizations.of(context);
    return _AutoHideBottomNav(
      builder: (collapse) => _ProBottomNav(
        l10n: l10n,
        selectedIndex: _bodyPage == 0 ? 0 : -1,
        onHome: () {
          collapse();
          setState(() => _bodyPage = 0);
        },
        onCalendar: () {
          collapse();
          _openCalendarScreen(client);
        },
      ),
    );
  }

}

const _kDailyMenuDetailCategories = {
  'ลางาน',
  'บันทึกการร่อนทราย',
  'จำนวนเที่ยวรถ',
  'การใช้รถแม็คโคร',
  'น้ำมัน',
  'ค่าแรง',
  'เช็คชื่อ',
  'OT',
};

/// เมนูรอง — ซ่อนไว้ด้านล่างจนกว่าจะกดขยาย
const _kCollapsedDailyMenuCategories = {
  'ค่าแรง', // บันทึกการทำงาน
  'OT',
  'รายจ่ายรายรับ', // รายรับ-รายจ่าย
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
    required this.onRequireToday,
    required this.onPickDay,
    required this.onPickCountRecordDay,
    required this.dateKey,
    required this.formatBuddhistDateButton,
    required this.onOpenModule,
    required this.onOpenSettings,
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
  /// สลับวันที่เลือกเป็นวันนี้เมื่อกดนับขณะดูวันอื่น
  final VoidCallback onRequireToday;
  final VoidCallback onPickDay;
  final VoidCallback onPickCountRecordDay;
  final String Function(DateTime) dateKey;
  final String Function(DateTime) formatBuddhistDateButton;
  final void Function(_DailyModuleDef m) onOpenModule;
  final VoidCallback onOpenSettings;
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
  CountRecordWorkMode? _workMode;
  /// เปิดการ์ดเมนูรอง (OT / รายรับ-รายจ่าย / บันทึกการทำงาน)
  bool _moreMenusExpanded = false;
  static const _kPanelShadowColor = Color(0x12000000);
  static const _kMoreMenusBarHeight = 40.0;

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
      unawaited(_loadDayWorkMode());
      _scheduleCountRecordTutorialIfNeeded();
    }
  }

  Future<void> _loadDayWorkMode() async {
    final key = widget.dateKey(widget.selectedDay);
    final mode = await CountRecordWorkModeStore.load(key);
    if (!mounted) return;
    setState(() => _workMode = mode);
  }

  Future<void> _selectWorkMode(CountRecordWorkMode mode) async {
    final key = widget.dateKey(widget.selectedDay);
    setState(() => _workMode = mode);
    await CountRecordWorkModeStore.save(key, mode);
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
      if (widget.countAndRecordMenuOpen) {
        unawaited(_loadDayWorkMode());
      }
    }
    if (oldWidget.countAndRecordMenuOpen != widget.countAndRecordMenuOpen) {
      _syncErrorTrackerStep();
      if (widget.countAndRecordMenuOpen) {
        unawaited(_loadDayWorkMode());
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
          AppLocale.th,
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
          // อย่าใส่ workMode ใน key — สลับโหมดนับอยู่ใน AnimatedSwitcher ชั้นใน
          // ถ้าสลับทั้ง LayoutBuilder จะซ้อนแผงเก่า+ใหม่ที่ใช้ GlobalKey เดียวกัน
          child: LayoutBuilder(
            key: ValueKey(
              '${widget.formatBuddhistDateButton(widget.selectedDay)}_'
              'menu_${widget.countAndRecordMenuOpen}_'
              'more_$_moreMenusExpanded',
            ),
            builder: (context, constraints) {
              if (widget.countAndRecordMenuOpen) {
                final modeSelected = _workMode != null;
                void onBackToHome() {
                  widget.onCountAndRecordMenuOpenChanged(false);
                  unawaited(widget.onCountRecordDataChanged());
                }

                void onBack() {
                  if (modeSelected) {
                    setState(() => _workMode = null);
                  } else {
                    onBackToHome();
                  }
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
                    // ValueKey คง Element ใต้ Flex เดียวกันตอนหมุนจอ
                    // (ห้ามใช้ GlobalKey ใน LayoutBuilder — จะย้าย RenderObject กลาง layout)
                    expandedChild: CountRecordCounterPanel(
                      key: ValueKey('count_panel_${modeKey}_$dayKeyStr'),
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
                      onRequireToday: widget.onRequireToday,
                    ),
                  );
                }

                Widget buildCounterBody() {
                  if (_workMode == null) {
                    return CountRecordWorkModePicker(
                      onSelect: (mode) => unawaited(_selectWorkMode(mode)),
                    );
                  }

                  final mode = _workMode!;
                  if (mode == CountRecordWorkMode.trip) {
                    return counterCell(
                      modeKey: 'trip',
                      title: 'จำนวนเที่ยวรถ',
                      icon: Icons.fire_truck_outlined,
                      iconColor: const Color(0xFF1565C0),
                      backgroundColor: const Color(0xFFE3F2FD),
                      borderColor: const Color(0xFF90CAF9),
                      counterMode: CounterMode.trip,
                    );
                  }
                  if (mode == CountRecordWorkMode.sand) {
                    return counterCell(
                      modeKey: 'sand',
                      title: 'การร่อนทราย',
                      icon: Icons.water_drop_outlined,
                      iconColor: const Color(0xFFAD1457),
                      backgroundColor: const Color(0xFFFCE4EC),
                      borderColor: const Color(0xFFF48FB1),
                      counterMode: CounterMode.sand,
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
                  // Flex ทิศทางเดียว — หมุนจอแค่อัปเดต direction ไม่สลับ Column/Row
                  // จึงไม่ dispose State ของแผงนับ
                  return Flex(
                    direction: portrait ? Axis.vertical : Axis.horizontal,
                    children: [
                      Expanded(
                        key: const ValueKey('count_trip_slot'),
                        child: tripCell,
                      ),
                      SizedBox(
                        height: portrait ? 10 : 0,
                        width: portrait ? 0 : 10,
                      ),
                      Expanded(
                        key: const ValueKey('count_sand_slot'),
                        child: sandCell,
                      ),
                    ],
                  );
                }

                final backLabel =
                    modeSelected ? 'เลือกงานใหม่' : 'กลับเมนูหลัก';
                final d = widget.selectedDay;
                final dayShort =
                    '${d.day.toString().padLeft(2, '0')}/'
                    '${d.month.toString().padLeft(2, '0')}/'
                    '${d.year + 543}';

                return CountRecordMenuShell(
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
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
                          const Spacer(),
                          SoftPressButton(
                            onTap: _openCountRecordTutorial,
                            size: SoftPressSize.small,
                            borderRadius: 20,
                            isDarkSurface: false,
                            liftWhenIdle: true,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.school_outlined,
                                color: Color(0xFF1565C0),
                                size: 22,
                              ),
                            ),
                          ),
                          SoftPressButton(
                            onTap: onBack,
                            size: SoftPressSize.small,
                            borderRadius: 12,
                            isDarkSurface: false,
                            liftWhenIdle: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD9E1EC)),
                              ),
                              child: Text(
                                backLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4A5A70),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SoftPressButton(
                            onTap: onBackToHome,
                            size: SoftPressSize.small,
                            borderRadius: 12,
                            isDarkSurface: false,
                            liftWhenIdle: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD9E1EC)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.home_outlined,
                                    size: 18,
                                    color: Color(0xFF4A5A70),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'หน้าแรก',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF4A5A70),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SoftPressButton(
                        onTap: widget.onPickCountRecordDay,
                        size: SoftPressSize.small,
                        borderRadius: 14,
                        isDarkSurface: false,
                        liftWhenIdle: true,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F7F9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFA9DCE4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: Color(0xFF0D98A5),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'วันที่ $dayShort · แตะเพื่อเปลี่ยนวัน',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.kanit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0A6270),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF4A5A70),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: MenuPanelTransition.duration(
                            lite: useLiteAnimations,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: MenuPanelTransition.build,
                          // ห้ามซ้อน previous ใน Stack — แผง trip/sand ใช้ GlobalKey
                          // คง State ตอนหมุนจอ ถ้าซ้อนแผงเก่า+ใหม่จะชนกัน
                          layoutBuilder: (current, _) =>
                              current ?? const SizedBox.shrink(),
                          child: KeyedSubtree(
                            key: ValueKey(_workMode?.name ?? 'pick'),
                            child: buildCounterBody(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                );
              }

              final primaryModules = _kDailyModules
                  .where(
                    (m) => !_kCollapsedDailyMenuCategories
                        .contains(m.category),
                  )
                  .toList(growable: false);
              final secondaryModules = _kDailyModules
                  .where(
                    (m) => _kCollapsedDailyMenuCategories
                        .contains(m.category),
                  )
                  .toList(growable: false);
              final visibleModules = _moreMenusExpanded
                  ? <_DailyModuleDef>[
                      ...primaryModules,
                      ...secondaryModules,
                    ]
                  : primaryModules;
              final gridItemCount = visibleModules.length + 1;
              final gap = TouchProfile.of(context).gridGap;
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
              // ช่วง AnimatedSize / กลับจากเมนูย่อย maxHeight อาจเป็นเศษส่วนเล็กมาก
              // ทำให้ clamp(1.0, panelH) พังเมื่อ panelH < 1
              final panelH = !rawMaxH.isFinite
                  ? 120.0 + _kMoreMenusBarHeight
                  : rawMaxH < 1.0
                      ? 1.0 + _kMoreMenusBarHeight
                      : rawMaxH;
              final availRaw = panelH - _kMoreMenusBarHeight;
              final availH = availRaw < 1.0 ? 1.0 : availRaw;
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: RepaintBoundary(
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
                        cacheExtent: menuScrolls
                            ? (cellHeight * cacheRows + gap * 2)
                            : 0,
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
                                key: const ValueKey(
                                  'mod_count_record_root',
                                ),
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
                            allTransactionsForStock:
                                widget.data.allTransactions,
                          );
                          final card = RecordModuleCard(
                            title: l10n.moduleTitle(m.category),
                            icon: m.icon,
                            tileColor: m.color,
                            showLightStyle: index.isOdd,
                            fillStatus: fill,
                            completeStatusLabelOverride:
                                translateDailyCardStatus(
                              rawStatus,
                              AppLocale.th,
                            ),
                            statusMaxLines:
                                _kDailyMenuDetailCategories
                                        .contains(m.category)
                                    ? 3
                                    : 2,
                            onTap: () => widget.onOpenModule(m),
                          );
                          if (_gridEntranceCompleted) {
                            return RepaintBoundary(
                              key: ValueKey('mod_${m.category}'),
                              child: card,
                            );
                          }
                          return _StaggerMenuTile(
                            parent: _entranceController,
                            index: globalIndex >= 0
                                ? globalIndex
                                : index,
                            lite: useLiteAnimations,
                            child: card,
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _kMoreMenusBarHeight,
                    child: Center(
                      child: SoftPressButton(
                        onTap: () {
                          AppHaptics.tap();
                          setState(
                            () => _moreMenusExpanded = !_moreMenusExpanded,
                          );
                        },
                        size: SoftPressSize.small,
                        borderRadius: 20,
                        isDarkSurface: false,
                        liftWhenIdle: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _moreMenusExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 20,
                                color: const Color(0xFF4A5A70),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _moreMenusExpanded
                                    ? 'ซ่อนเมนูเพิ่มเติม'
                                    : 'แสดงเมนูเพิ่มเติม',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFF4A5A70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                                onOpenSettings: widget.onOpenSettings,
                              ),
                            ),
                          ),
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

  static const _cardDepthShadow = SoftPressDepthShadow(
    color: Color(0x0A000000),
    blurRadius: 10,
    offsetY: 3,
    pressedBlurRadius: 4,
    pressedOffsetY: 1,
  );

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
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _buildContent(),
      ),
    );

    if (expanded) {
      return shell;
    }

    return SoftPressButton(
      onTap: onTap,
      size: SoftPressSize.medium,
      borderRadius: 22,
      isDarkSurface: false,
      liftWhenIdle: true,
      depthShadow: _cardDepthShadow,
      child: shell,
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

class _TopSettingsButton extends StatelessWidget {
  const _TopSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).navSettings;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SoftPressButton(
          onTap: onTap,
          size: SoftPressSize.small,
          borderRadius: 12,
          liftWhenIdle: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF4F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCE6EE)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.settings_outlined,
                color: Color(0xFF0D98A5),
                size: 22,
              ),
            ),
          ),
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
    required this.onOpenSettings,
  });

  final String appName;
  final String lastLabel;
  final String selectedDateLabel;
  final VoidCallback onPickDay;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenSettings;

  static const _teal = Color(0xFF0D98A5);
  static const _tealMid = Color(0xFF0A7A88);
  static const _tealDark = Color(0xFF0A6270);
  static const _ink = Color(0xFF142033);
  static const _muted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const changeDayHint = 'แตะเพื่อเปลี่ยนวัน';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _DailyHomeContentState._kPanelShadowColor,
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF3FAFB)],
            ),
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xFFD7E8ED)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF00C4D4), _teal, _tealMid],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _teal.withValues(alpha: 0.22),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _teal.withValues(alpha: 0.14),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: AppLogo(size: 40),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.dailyLogTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  color: _ink,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SoftPressButton(
                          onTap: () => onRefresh(),
                          size: SoftPressSize.small,
                          borderRadius: 12,
                          liftWhenIdle: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F8FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFDCE6EE),
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF546E7A),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TopSettingsButton(onTap: onOpenSettings),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SoftPressButton(
                      onTap: onPickDay,
                      size: SoftPressSize.medium,
                      borderRadius: 18,
                      isDarkSurface: false,
                      liftWhenIdle: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE6F7F9), Color(0xFFF7FCFD)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFA9DCE4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _teal.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [_teal, _tealMid],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _teal.withValues(alpha: 0.28),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: Icon(
                                    Icons.calendar_month_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedDateLabel,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        color: _tealDark,
                                        height: 1.2,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      changeDayHint,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                        color: _muted.withValues(alpha: 0.95),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: _teal,
                                size: 28,
                              ),
                            ],
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
                      ],
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
  });

  final IconData icon;
  final String label;
  static const Color iconColor = Color(0xFF415268);

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

/// แถบนำทางล่างที่พับซ่อนเป็นค่าเริ่มต้น
///
/// ขีดจับอยู่ตลอด — ลากตามนิ้วปัดขึ้นกาง / ปัดลงหุบ (ทั้งขีดจับและตัวแถบ)
/// กดปุ่มเมนูแล้วหุบกลับทันที
class _AutoHideBottomNav extends StatefulWidget {
  const _AutoHideBottomNav({
    required this.builder,
  });

  final Widget Function(VoidCallback collapse) builder;

  @override
  State<_AutoHideBottomNav> createState() => _AutoHideBottomNavState();
}

class _AutoHideBottomNavState extends State<_AutoHideBottomNav>
    with SingleTickerProviderStateMixin {
  static const _handleHeight = 22.0;
  static const _flingVelocity = 120.0;
  static final _spring = SpringDescription(
    mass: 1,
    stiffness: 340,
    damping: 28,
  );

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 260),
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _navExtent(BuildContext context) {
    final nav = TouchProfile.of(context).navBarHeight;
    final inset = MediaQuery.paddingOf(context).bottom;
    return (nav + inset).clamp(1.0, double.infinity);
  }

  bool get _preferLiteMotion {
    final mq = MediaQuery.maybeOf(context);
    return (mq?.disableAnimations ?? false) ||
        DevicePerf.isConstrainedDevice;
  }

  void _settleTo(double target, {double velocity = 0}) {
    final clamped = target.clamp(0.0, 1.0);
    if (_preferLiteMotion) {
      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return;
    }
    final sim = SpringSimulation(
      _spring,
      _controller.value,
      clamped,
      velocity,
    );
    _controller.animateWith(sim);
  }

  void _collapse() => _settleTo(0.0);

  void _reveal() => _settleTo(1.0);

  void _toggle() {
    if (_controller.value < 0.5) {
      _reveal();
    } else {
      _collapse();
    }
  }

  void _onDragStart(DragStartDetails _) {
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final extent = _navExtent(context);
    final dy = details.primaryDelta ?? 0;
    // ปัดขึ้น (dy < 0) → กาง (value ↑); ปัดลง → หุบ
    _controller.value = (_controller.value - dy / extent).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final extent = _navExtent(context);
    final pxVel = details.primaryVelocity ?? 0;
    // แปลง px/s → หน่วย 0–1 ต่อวินาที (เครื่องหมาย: ลบ = ปัดขึ้น = กาง)
    final unitVel = -pxVel / extent;

    late final double target;
    if (pxVel.abs() >= _flingVelocity) {
      target = pxVel < 0 ? 1.0 : 0.0;
    } else {
      target = _controller.value > 0.5 ? 1.0 : 0.0;
    }
    _settleTo(target, velocity: unitVel);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value.clamp(0.0, 1.0);
        final handleH = _handleHeight + bottomInset * (1.0 - t);

        Widget nav = widget.builder(_collapse);
        if (t < 1.0) {
          nav = Opacity(opacity: t, child: nav);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFA9DCE4)),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: handleH,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFA9DCE4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: t,
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: nav,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// แถบนำทางล่างเต็มความกว้าง — พื้นเดียว ไม่มีกล่องสีล้อมแท็บ
class _ProBottomNav extends StatelessWidget {
  const _ProBottomNav({
    required this.l10n,
    required this.selectedIndex,
    required this.onHome,
    required this.onCalendar,
  });

  final AppLocalizations l10n;
  final int selectedIndex;
  final VoidCallback onHome;
  final VoidCallback onCalendar;

  static const _teal = Color(0xFF0D98A5);
  static const _idle = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final profile = TouchProfile.of(context);
    final navHeight = profile.navBarHeight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _teal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: navHeight,
          child: Row(
            children: [
              _navItem(
                index: 0,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: l10n.navHome,
                onTap: onHome,
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: Color(0xFFE3EEF3),
              ),
              _navItem(
                index: 1,
                icon: Icons.calendar_month_outlined,
                selectedIcon: Icons.calendar_month_rounded,
                label: l10n.navCalendar,
                onTap: onCalendar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required VoidCallback onTap,
  }) {
    final selected = selectedIndex == index;
    final color = selected ? _teal : _idle;

    return Expanded(
      child: SoftPressButton(
        onTap: onTap,
        size: SoftPressSize.small,
        borderRadius: 0,
        isDarkSurface: false,
        showHighlight: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.kanit(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: color,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
