import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../models/employee.dart';
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
import '../widgets/app_locale_scope.dart';
import '../widgets/app_logo.dart';
import '../widgets/page_loading_view.dart';
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

/// เมนูที่นับในชิป «บันทึกครบ X/Y เมนู» — บันทึกการร่อนทราย, น้ำมัน, ค่าแรง, เหตุการณ์, การใช้รถแม็คโคร
/// และเมนู **ทรายที่ล้างที่บ้าน** เมื่อวันนั้นในบันทึกการทำงานมีคนในกล่อง canvas งานที่บ้าน (`washHome` และคีย์รวมย้อนหลัง)
bool _laborWorkRecordAssignsWashHome(Iterable<AppTransaction> dayTransactions) {
  for (final t in dayTransactions) {
    if (t.category != 'Labor') continue;
    final wa = t.workAssignments;
    if (wa == null || wa.isEmpty) continue;
    for (final key in [
      'washHome',
      'wash_home',
      'wash_yard_house',
      'sift_home',
    ]) {
      final ids = wa[key];
      if (ids != null && ids.isNotEmpty) return true;
    }
  }
  return false;
}

List<_DailyModuleDef> _dailyHeaderCountedModules(
  List<AppTransaction> dayTransactions,
) {
  const core = {
    'บันทึกการร่อนทราย',
    'น้ำมัน',
    'ค่าแรง',
    'เหตุการณ์',
    'การใช้รถแม็คโคร',
  };
  final needHomeSand = _laborWorkRecordAssignsWashHome(dayTransactions);
  return _kDailyModules.where((m) {
    if (core.contains(m.category)) return true;
    if (m.category == 'ทรายที่ล้างที่บ้าน' && needHomeSand) return true;
    return false;
  }).toList(growable: false);
}

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

class _DashboardScreenState extends State<DashboardScreen> {
  static const _kNavRailExpandedPrefKey = 'dashboard_nav_rail_expanded_v1';
  static const _kNavRailWidth = 72.0;

  late final TransactionService _txService;
  int _bodyPage = 0;
  DateTime _selectedDay = DateTime.now();
  bool _serverOnline = true;
  late Future<_HomePayload> _homeFuture;
  _HomePayload? _lastHomePayload;
  /// แถบเมนูซ้าย (ไอคอนสควอร์เคิล): true = แสดง, false = ซ่อน — ปัดจากซ้ายไปขวาที่ขอบจอเพื่อเปิด
  bool _navRailOpen = true;
  double _edgeSwipeAccum = 0;
  Timer? _navRailIntroTimer;

  @override
  void initState() {
    super.initState();
    MobileErrorScreenTracker.set(page: 'หน้าหลัก (แดชบอร์ด)');
    _txService = TransactionService(Supabase.instance.client);
    _homeFuture = _futureWithSnapshot(_loadHome());
    _navRailOpen = true;
    _scheduleNavRailIntroHide();
  }

  /// เปิดหน้าบันทึกประจำวัน — แสดงแถบเมนู 3 วินาที แล้วเก็บซ่อน (ปัดขอบซ้ายเปิดได้อีก)
  void _scheduleNavRailIntroHide() {
    _navRailIntroTimer?.cancel();
    _navRailIntroTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_navRailOpen) return;
      setState(() => _navRailOpen = false);
      _persistNavRailOpen(false);
    });
  }

  Future<void> _persistNavRailOpen(bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kNavRailExpandedPrefKey, value);
    } catch (_) {}
  }

  void _toggleNavRail() {
    _navRailIntroTimer?.cancel();
    setState(() => _navRailOpen = !_navRailOpen);
    _persistNavRailOpen(_navRailOpen);
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
    _navRailIntroTimer?.cancel();
    super.dispose();
  }

  Future<_HomePayload> _loadHome({bool forceRefresh = false}) async {
    try {
      final employeeService = EmployeeService(Supabase.instance.client);
      final results = await Future.wait([
        widget.dashboardService.fetchSummary(forceRefresh: forceRefresh),
        _txService.fetchTransactionsForDate(
          _dateKey(_selectedDay),
          forceRefresh: forceRefresh,
        ),
        employeeService.fetchEmployees(forceRefresh: forceRefresh),
      ]);
      final summary = results[0] as DashboardSummary;
      final dayRows = results[1] as List<AppTransaction>;
      final employees = results[2] as List<Employee>;
      final dayKey = _dateKey(_selectedDay);
      final allRows =
          await _txService.fetchTransactions(forceRefresh: forceRefresh);
      final seen = dayRows.map((e) => e.id).toSet();
      final overlappingLeave = allRows.where(
        (t) =>
            laborLeaveCoversCalendarDay(t, dayKey) && !seen.contains(t.id),
      );
      final dayTransactions = <AppTransaction>[
        ...dayRows,
        ...overlappingLeave,
      ];
      if (mounted && !_serverOnline) {
        setState(() => _serverOnline = true);
      }
      return _HomePayload(
        summary: summary,
        dayTransactions: dayTransactions,
        allTransactions: allRows,
        employees: employees,
      );
    } catch (_) {
      if (mounted && _serverOnline) {
        setState(() => _serverOnline = false);
      }
      rethrow;
    }
  }

  void _refreshHome() {
    setState(() {
      _homeFuture = _futureWithSnapshot(_loadHome(forceRefresh: true));
    });
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
        _homeFuture = _futureWithSnapshot(_loadHome(forceRefresh: false));
      });
    }
  }

  void _openQuickInput(_DailyModuleDef m) {
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
      ),
    ).then((_) => _refreshHome());
  }

  Future<T?> _openWithAnimation<T>(Widget page) {
    final isQuickInput = page is QuickInputScreen;
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: isQuickInput
            ? const Duration(milliseconds: 135)
            : const Duration(milliseconds: 175),
        reverseTransitionDuration: isQuickInput
            ? const Duration(milliseconds: 95)
            : const Duration(milliseconds: 115),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: isQuickInput ? Curves.easeOutCubic : Curves.easeOutQuart,
            reverseCurve: Curves.easeInCubic,
          );
          final slide = Tween<Offset>(
            begin: isQuickInput
                ? const Offset(0.012, 0.02)
                : const Offset(0.03, 0.015),
            end: Offset.zero,
          ).animate(curved);
          final fade = Tween<double>(begin: 0, end: 1).animate(curved);
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
            child: SizedBox(
              width: bodyW,
              child: ClipRect(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: _navRailOpen ? _kNavRailWidth : 0,
                      child: _navRailOpen
                          ? ClipRect(
                              child: _squircleNavRail(client: client),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: FutureBuilder<_HomePayload>(
                              future: _homeFuture,
                              builder: (context, snapshot) {
                              final merged = snapshot.data ?? _lastHomePayload;
                              final waiting =
                                  snapshot.connectionState ==
                                  ConnectionState.waiting;
                              if (waiting && merged == null) {
                                final l10n = AppLocalizations.of(context);
                                final loadingLabel = _bodyPage == 0
                                    ? l10n.loadingDashboard
                                    : l10n.loadingData;
                                return PageLoadingView(label: loadingLabel);
                              }
                              if (snapshot.hasError && merged == null) {
                                final l10n = AppLocalizations.of(context);
                                return Center(
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
                              }
                              final data = merged;
                              if (data == null) {
                                return PageLoadingView(
                                  label: AppLocalizations.of(context)
                                      .loadingData,
                                );
                              }
                              final showRefreshBar =
                                  waiting && merged != null;
                              final shell = _bodyPage == 0
                                  ? _DailyHomeContent(
                                      currentAdmin: widget.currentAdmin,
                                      data: data,
                                      serverOnline: _serverOnline,
                                      selectedDay: _selectedDay,
                                      onPullRefresh: _pullRefresh,
                                      onPickDay: _pickDay,
                                      dateKey: _dateKey,
                                      formatBuddhistDateButton:
                                          _formatBuddhistDateButton,
                                      onOpenModule: _openQuickInput,
                                    )
                                  : _MetricsContent(
                                      data: data,
                                      currentAdmin: widget.currentAdmin,
                                      onRetry: _refreshHome,
                                    );
                              if (!showRefreshBar) return shell;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  shell,
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        progressIndicatorTheme:
                                            ProgressIndicatorThemeData(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                      child: const LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                          if (!_navRailOpen)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 36,
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (_) => _edgeSwipeAccum = 0,
                                onPointerMove: (e) {
                                  if (e.delta.dx > 0) {
                                    _edgeSwipeAccum += e.delta.dx;
                                    if (_edgeSwipeAccum >= 56) {
                                      _edgeSwipeAccum = 0;
                                      HapticFeedback.lightImpact();
                                      _toggleNavRail();
                                    }
                                  }
                                },
                                onPointerUp: (_) => _edgeSwipeAccum = 0,
                                onPointerCancel: (_) =>
                                    _edgeSwipeAccum = 0,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Material(
                                    elevation: 4,
                                    shadowColor: Colors.black26,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(16),
                                    ),
                                    color: Colors.white,
                                    child: InkWell(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                        right: Radius.circular(16),
                                      ),
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        _toggleNavRail();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 6,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right,
                                          color: Color(0xFF546E7A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
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
        },
      ),
    );
  }

  Future<void> _pullRefresh() async {
    setState(
      () => _homeFuture = _futureWithSnapshot(
        _loadHome(forceRefresh: true),
      ),
    );
    await _homeFuture;
  }

  Widget _squircleNavRail({required SupabaseClient client}) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          _SquircleNavIcon(
            icon: Icons.home_outlined,
            selected: _bodyPage == 0,
            tooltip: l10n.navHome,
            onTap: () => setState(() => _bodyPage = 0),
          ),
          const SizedBox(height: 8),
          _SquircleNavIcon(
            icon: Icons.calendar_month_outlined,
            selected: false,
            tooltip: l10n.navCalendar,
            onTap: () => _openCalendarScreen(client),
          ),
          const SizedBox(height: 8),
          _SquircleNavIcon(
            icon: Icons.settings_outlined,
            selected: false,
            tooltip: l10n.navSettings,
            onTap: () => _openAppSettingsScreen(client),
          ),
          Expanded(
            child: Center(
              child: Tooltip(
                message: l10n.navHideMenu,
                child: Material(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(22),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _toggleNavRail();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      child: Icon(
                        Icons.chevron_left,
                        size: 22,
                        color: Color(0xFF546E7A),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _SquircleNavIcon(
            icon: Icons.logout,
            selected: false,
            tooltip: l10n.navLogout,
            onTap: widget.onLogout,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SquircleNavIcon extends StatelessWidget {
  const _SquircleNavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  static const Color _teal = Color(0xFF00897B);
  static const Color _inactiveBorder = Color(0xFFE0E0E0);
  static const Color _inactiveIcon = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? _teal : _inactiveBorder;
    final iconColor = selected ? _teal : _inactiveIcon;
    final core = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: selected ? 2 : 1.2,
              ),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: core);
    }
    return core;
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
    required this.currentAdmin,
    required this.data,
    required this.serverOnline,
    required this.selectedDay,
    required this.onPullRefresh,
    required this.onPickDay,
    required this.dateKey,
    required this.formatBuddhistDateButton,
    required this.onOpenModule,
  });

  final AdminUser currentAdmin;
  final _HomePayload data;
  final bool serverOnline;
  final DateTime selectedDay;
  final Future<void> Function() onPullRefresh;
  final VoidCallback onPickDay;
  final String Function(DateTime) dateKey;
  final String Function(DateTime) formatBuddhistDateButton;
  final void Function(_DailyModuleDef m) onOpenModule;

  @override
  State<_DailyHomeContent> createState() => _DailyHomeContentState();
}

class _DailyHomeContentState extends State<_DailyHomeContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final bool _reduceMotion;
  bool _countAndRecordMenuOpen = false;
  /// After the grid entrance animation finishes, drop stagger transforms so
  /// scrolling does not composite Fade+Slide+Scale on every tile each frame.
  bool _gridEntranceCompleted = false;
  static const _kPanelShadowColor = Color(0x12000000);

  _DailyModuleDef _moduleByCategory(String category) => _kDailyModules.firstWhere(
    (m) => m.category == category,
  );

  void _onEntranceStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && !_gridEntranceCompleted) {
      setState(() => _gridEntranceCompleted = true);
    }
  }

  @override
  void initState() {
    super.initState();
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
    final modulesForHeaderTotals = _dailyHeaderCountedModules(
      widget.data.dayTransactions,
    );
    final doneCount = modulesForHeaderTotals
        .where(
          (m) =>
              menuStatusByCategory[m.category] ==
              DailyModuleFillStatus.complete,
        )
        .length;
    final incompleteCount = modulesForHeaderTotals
        .where(
          (m) =>
              menuStatusByCategory[m.category] ==
              DailyModuleFillStatus.incomplete,
        )
        .length;
    final headerTotalMenuCount = modulesForHeaderTotals.length;
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
          duration: Duration(milliseconds: useLiteAnimations ? 70 : 115),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: LayoutBuilder(
            key: ValueKey(
              widget.formatBuddhistDateButton(widget.selectedDay),
            ),
            builder: (context, constraints) {
              if (_countAndRecordMenuOpen) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'บันทึกและนับจำนวน',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A2433),
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () =>
                                setState(() => _countAndRecordMenuOpen = false),
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
                            child: const Text(
                              'กลับเมนูหลัก',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _CountRecordMenuCard(
                                title: 'จำนวนเที่ยวรถ',
                                subtitle: 'บันทึกเที่ยวรถดรัมและสรุปเที่ยว',
                                icon: Icons.fire_truck_outlined,
                                iconColor: const Color(0xFF1D8FE1),
                                backgroundColor: const Color(0xFFF2F8FF),
                                borderColor: const Color(0xFFD2E7FF),
                                onTap: () => widget.onOpenModule(
                                  _moduleByCategory('จำนวนเที่ยวรถ'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CountRecordMenuCard(
                                title: 'การร่อนทราย',
                                subtitle: 'บันทึกผลร่อนทรายและจำนวนคิว',
                                icon: Icons.water_drop_outlined,
                                iconColor: const Color(0xFFE91E8F),
                                backgroundColor: const Color(0xFFFFF2FA),
                                borderColor: const Color(0xFFFFD6EB),
                                onTap: () => widget.onOpenModule(
                                  _moduleByCategory('บันทึกการร่อนทราย'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final visibleModules = _kDailyModules;
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
              // Defensive: some ancestors can report an absurd finite maxWidth.
              final w =
                  layoutW > safeMq ? safeMq : layoutW;
              final rawMaxH = constraints.maxHeight;
              // clamp(lower, upper) throws when maxHeight < 120 (e.g. tight layout / animation frame).
              final availH = !rawMaxH.isFinite
                  ? 120.0
                  : rawMaxH <= 0
                      ? 1.0
                      : rawMaxH;
              final rows =
                  (visibleModules.length / cross).ceil().clamp(1, 12);
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
                  physics: menuScrolls
                      ? const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        )
                      : const NeverScrollableScrollPhysics(),
                  addAutomaticKeepAlives: true,
                  addRepaintBoundaries: true,
                  cacheExtent:
                      menuScrolls ? (cellHeight * cacheRows + gap * 2) : 0,
                  itemCount: visibleModules.length + 1,
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    mainAxisExtent: cellHeight,
                  ),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final card = _CountRecordEntryCard(
                        onTap: () =>
                            setState(() => _countAndRecordMenuOpen = true),
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
                    final card = RecordModuleCard(
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
                    serverOnline: widget.serverOnline,
                    selectedDateLabel: l10n.formatSelectedDate(
                      widget.selectedDay,
                    ),
                    doneCount: doneCount,
                    incompleteMenuCount: incompleteCount,
                    totalCount: headerTotalMenuCount,
                    onPickDay: widget.onPickDay,
                    onRefresh: widget.onPullRefresh,
                    locale: localeScope.locale,
                    onLocaleChanged: localeScope.onLocaleChanged,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
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
            ],
          ),
        ),
      ],
    );
  }
}

class _CountRecordEntryCard extends StatelessWidget {
  const _CountRecordEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F8FE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD8E6F7)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                      ? constraints.maxWidth
                      : 108.0;
              final maxH =
                  constraints.maxHeight.isFinite && constraints.maxHeight > 0
                      ? constraints.maxHeight
                      : maxW;
              // ใช้สูตรเดียวกับ RecordModuleCard เพื่อให้ icon ใหญ่เท่ากัน
              final scaleRef = maxW < maxH ? maxW : maxH;
              final iconSize = (scaleRef * 0.5).clamp(40.0, 66.0);
              final pad = (scaleRef * 0.1).clamp(8.0, 14.0);
              final titleSize = (scaleRef * 0.11).clamp(11.5, 14.5);
              final subtitleSize = (scaleRef * 0.09).clamp(10.0, 12.0);
              final textMaxWidth = maxW - (pad * 2);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: iconSize,
                          color: const Color(0xFF1565C0),
                        ),
                        SizedBox(height: pad * 0.5),
                        SizedBox(
                          width: textMaxWidth,
                          child: Text(
                            'บันทึกและนับจำนวน',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1D2A3A),
                              height: 1.18,
                            ),
                          ),
                        ),
                        SizedBox(height: pad * 0.28),
                        SizedBox(
                          width: textMaxWidth,
                          child: Text(
                            'จำนวนเที่ยวรถ / การร่อนทราย',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: subtitleSize,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7788),
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: pad * 0.5,
                    right: pad * 0.5,
                    child: const Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              );
            },
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
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
        ),
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
    required this.serverOnline,
    required this.selectedDateLabel,
    required this.doneCount,
    required this.incompleteMenuCount,
    required this.totalCount,
    required this.onPickDay,
    required this.onRefresh,
    required this.locale,
    required this.onLocaleChanged,
  });

  final String appName;
  final String lastLabel;
  final bool serverOnline;
  final String selectedDateLabel;
  final int doneCount;
  final int incompleteMenuCount;
  final int totalCount;
  final VoidCallback onPickDay;
  final Future<void> Function() onRefresh;
  final AppLocale locale;
  final ValueChanged<AppLocale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7ECF3)),
        boxShadow: [
          BoxShadow(
            color: _DailyHomeContentState._kPanelShadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppLogo(size: 40),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dailyLogTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A2433),
                      ),
                    ),
                    Text(
                      appName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6B7788), fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: LayoutBuilder(
                  builder: (context, dateConstraints) {
                    final raw = dateConstraints.maxWidth;
                    final slot = (raw.isFinite && raw > 0)
                        ? raw
                        : (MediaQuery.sizeOf(context).width * 0.35)
                            .clamp(96.0, 280.0);
                    return Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: slot),
                        child: _PressScaleButton(
                          child: InkWell(
                            onTap: onPickDay,
                            borderRadius: BorderRadius.circular(20),
                            child: Ink(
                              padding: EdgeInsets.symmetric(
                                horizontal: slot < 200 ? 8 : 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F8FC),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD9E1EC),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: Color(0xFF00A8C4),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      selectedDateLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.start,
                                      style: const TextStyle(
                                        color: Color(0xFF00A8C4),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
                    color: Color(0xFF3A4A5E),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                l10n.languageLabel,
                style: const TextStyle(
                  color: Color(0xFF6B7788),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<AppLocale>(
                  segments: [
                    ButtonSegment(
                      value: AppLocale.th,
                      label: Text(
                        AppLocale.th.shortLabel,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    ButtonSegment(
                      value: AppLocale.zh,
                      label: Text(
                        AppLocale.zh.shortLabel,
                        style: const TextStyle(fontSize: 13),
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
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderStatChip(
                icon: Icons.today_rounded,
                label: doneCount >= totalCount
                    ? l10n.headerMenusComplete(totalCount)
                    : incompleteMenuCount > 0
                        ? l10n.headerMenusProgress(
                            doneCount,
                            incompleteMenuCount,
                            totalCount,
                          )
                        : l10n.headerMenusSimple(doneCount, totalCount),
              ),
              _HeaderStatChip(
                icon: Icons.access_time_filled_rounded,
                label: '${l10n.latestPrefix} $lastLabel',
              ),
              _LiveClockChip(l10n: l10n),
              _HeaderStatChip(
                icon: serverOnline
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                label: serverOnline ? l10n.serverOnline : l10n.serverOffline,
                iconColor: serverOnline
                    ? const Color(0xFF1E8E56)
                    : const Color(0xFFC25050),
              ),
            ],
          ),
        ],
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
