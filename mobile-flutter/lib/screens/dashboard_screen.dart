import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../services/dashboard_service.dart';
import '../services/employee_service.dart';
import '../services/project_service.dart';
import '../services/transaction_service.dart';
import '../utils/daily_module_transactions.dart';
import '../widgets/app_logo.dart';
import '../widgets/page_loading_view.dart';
import '../widgets/record_module_card.dart';
import 'app_settings_screen.dart';
import 'calendar_screen.dart';
import 'employees_screen.dart';
import 'projects_screen.dart';
import 'quick_input_screen.dart';
import 'transactions_screen.dart';

String _formatThaiDateFromYmd(String ymd) {
  try {
    final p = ymd.split('-');
    if (p.length != 3) return ymd;
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    const months = [
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
    final be = d.year + 543;
    return '${d.day} ${months[d.month - 1]} $be';
  } catch (_) {
    return ymd;
  }
}

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
    color: Color(0xFFFF4FA3),
  ),
  _DailyModuleDef(
    title: 'บันทึกรถและจำนวนเที่ยวรถ',
    icon: Icons.local_shipping_outlined,
    category: 'จำนวนเที่ยวรถ',
    quickInputTitle: 'บันทึกรถและเที่ยว',
    color: Color(0xFF00B8D9),
  ),
  _DailyModuleDef(
    title: 'น้ำมัน',
    icon: Icons.oil_barrel_outlined,
    category: 'น้ำมัน',
    quickInputTitle: 'บันทึกน้ำมัน',
    color: Color(0xFFFF9800),
  ),
  _DailyModuleDef(
    title: 'ทรายที่ล้างที่บ้าน',
    icon: Icons.waves_outlined,
    category: 'ทรายที่ล้างที่บ้าน',
    quickInputTitle: 'ทรายที่ล้างที่บ้าน',
    color: Color(0xFF4A6FFF),
  ),
  _DailyModuleDef(
    title: 'บันทึกการทำงาน',
    icon: Icons.payments_outlined,
    category: 'ค่าแรง',
    quickInputTitle: 'บันทึกการทำงาน',
    color: Color(0xFF7E3FF2),
  ),
  _DailyModuleDef(
    title: 'การทำงานล่วงเวลา (OT)',
    icon: Icons.groups_2_outlined,
    category: 'OT',
    quickInputTitle: 'บันทึกการทำงานล่วงเวลา',
    color: Color(0xFFFF4D6D),
  ),
  _DailyModuleDef(
    title: 'ลางาน',
    icon: Icons.event_busy_outlined,
    category: 'ลางาน',
    quickInputTitle: 'บันทึกลางาน',
    color: Color(0xFF00897B),
  ),
  _DailyModuleDef(
    title: 'เบิกเงิน',
    icon: Icons.savings_outlined,
    category: 'เบิกเงิน',
    quickInputTitle: 'ส่งคำขอเบิกเงิน',
    color: Color(0xFFFF6F00),
  ),
];

/// เมนูที่ไม่นับในชิป «บันทึกครบ X/Y เมนู» — ลางาน, เบิกเงิน (บันทึกแยก)
bool _isExpandOnlyDailyModule(_DailyModuleDef m) =>
    m.category == 'ลางาน' || m.category == 'เบิกเงิน';

/// เมนูที่นับในชิป «บันทึกครบ X/Y เมนู» — ไม่รวม OT, ลางาน, เบิกเงิน (บันทึกแยก ไม่บังคับในสรุปวัน)
bool _dailyModuleCountsTowardHeaderTotals(_DailyModuleDef m) =>
    m.category != 'OT' && !_isExpandOnlyDailyModule(m);

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
  late final TransactionService _txService;
  int _bodyPage = 0;
  DateTime _selectedDay = DateTime.now();
  bool _serverOnline = true;
  late Future<_HomePayload> _homeFuture;
  _HomePayload? _lastHomePayload;

  @override
  void initState() {
    super.initState();
    _txService = TransactionService(Supabase.instance.client);
    _homeFuture = _futureWithSnapshot(_loadHome());
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
  void dispose() => super.dispose();

  Future<_HomePayload> _loadHome({bool forceRefresh = false}) async {
    try {
      final results = await Future.wait([
        widget.dashboardService.fetchSummary(forceRefresh: forceRefresh),
        _txService.fetchTransactionsForDate(
          _dateKey(_selectedDay),
          forceRefresh: forceRefresh,
        ),
      ]);
      final summary = results[0] as DashboardSummary;
      final dayRows = results[1] as List<AppTransaction>;
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
      return _HomePayload(summary: summary, dayTransactions: dayTransactions);
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
            ? const Duration(milliseconds: 340)
            : const Duration(milliseconds: 380),
        reverseTransitionDuration: isQuickInput
            ? const Duration(milliseconds: 260)
            : const Duration(milliseconds: 260),
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
    final wide = MediaQuery.sizeOf(context).width >= 640;

    return Scaffold(
      backgroundColor: const Color(0xFFF3FBFC),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) _sideNavBar(client: client),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide) _mobileTopBar(client: client),
                  Expanded(
                    child: FutureBuilder<_HomePayload>(
                      future: _homeFuture,
                      builder: (context, snapshot) {
                        final merged = snapshot.data ?? _lastHomePayload;
                        final waiting =
                            snapshot.connectionState ==
                            ConnectionState.waiting;
                        if (waiting && merged == null) {
                          final loadingLabel = _bodyPage == 0
                              ? 'กำลังโหลดแดชบอร์ด'
                              : 'กำลังโหลดภาพรวม';
                          return PageLoadingView(label: loadingLabel);
                        }
                        if (snapshot.hasError && merged == null) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'โหลดข้อมูลไม่สำเร็จ\n${snapshot.error}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _refreshHome,
                                    child: const Text('ลองอีกครั้ง'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final data = merged;
                        if (data == null) {
                          return const PageLoadingView(
                            label: 'กำลังโหลดข้อมูล',
                          );
                        }
                        final showRefreshBar = waiting && merged != null;
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
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
                ],
              ),
            ),
          ],
        ),
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

  Widget _sideNavBar({required SupabaseClient client}) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            const SizedBox(height: 12),
            _SideIcon(
              icon: Icons.home_outlined,
              selected: _bodyPage == 0,
              onTap: () => setState(() => _bodyPage = 0),
            ),
            _SideIcon(
              icon: Icons.calendar_month_outlined,
              selected: false,
              onTap: () => _openCalendarScreen(client),
            ),
            _SideIcon(
              icon: Icons.settings_outlined,
              selected: false,
              onTap: () => _openAppSettingsScreen(client),
            ),
            const Spacer(),
            _SideIcon(
              icon: Icons.logout,
              selected: false,
              onTap: widget.onLogout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _mobileTopBar({required SupabaseClient client}) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'หน้าแรก',
              onPressed: () => setState(() => _bodyPage = 0),
              icon: const Icon(Icons.home_outlined),
            ),
            IconButton(
              tooltip: 'ปฏิทิน',
              onPressed: () => _openCalendarScreen(client),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'ตั้งค่าแอพ',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _openAppSettingsScreen(client),
            ),
            IconButton(
              tooltip: 'ออกจากระบบ',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SideIcon extends StatelessWidget {
  const _SideIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// ให้ตรง seed ธีมแอป (main.dart)
  static const Color _accent = Color(0xFF11A8BA);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          foregroundColor: selected ? _accent : Colors.black54,
          side: BorderSide(
            color: selected ? _accent : _accent.withValues(alpha: 0.35),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 22),
      ),
    );
  }
}

class _HomePayload {
  const _HomePayload({required this.summary, required this.dayTransactions});

  final DashboardSummary summary;
  final List<AppTransaction> dayTransactions;
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
  static const _kPanelShadowColor = Color(0x12000000);

  @override
  void initState() {
    super.initState();
    _reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _reduceMotion ? 340 : 760),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _DailyHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay) {
      _entranceController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useLiteAnimations = _reduceMotion;
    final dayKey = widget.dateKey(widget.selectedDay);
    final lastLabel = widget.data.dayTransactions.isNotEmpty
        ? _formatThaiDateFromYmd(widget.data.dayTransactions.first.date)
        : '—';

    final menuStatusByCategory = <String, DailyModuleFillStatus>{
      for (final m in _kDailyModules)
        m.category: resolveDailyModuleFillStatus(
          dayKey,
          m.category,
          widget.data.dayTransactions,
        ),
    };
    final modulesForHeaderTotals = _kDailyModules
        .where(_dailyModuleCountsTowardHeaderTotals)
        .toList(growable: false);
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
                    selectedDateLabel: widget.formatBuddhistDateButton(
                      widget.selectedDay,
                    ),
                    doneCount: doneCount,
                    incompleteMenuCount: incompleteCount,
                    totalCount: headerTotalMenuCount,
                    onPickDay: widget.onPickDay,
                    onRefresh: widget.onPullRefresh,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FadeTransition(
                  opacity: panelAnim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(panelAnim),
                    child: DecoratedBox(
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
                          duration: Duration(milliseconds: useLiteAnimations ? 140 : 260),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: LayoutBuilder(
                            key: ValueKey(
                              widget.formatBuddhistDateButton(widget.selectedDay),
                            ),
                            builder: (context, constraints) {
                              final visibleModules = _kDailyModules;
                              const cross = 3;
                              const gap = 10.0;
                              const sideInset = 2.0;
                              final availH = constraints.maxHeight
                                  .clamp(120.0, constraints.maxHeight);
                              final rows =
                                  (visibleModules.length / cross).ceil().clamp(1, 12);
                              final w = constraints.maxWidth;
                              final usableWidth = w - (sideInset * 2);
                              final cellWidth =
                                  (usableWidth - (gap * (cross - 1))) / cross;
                              final fitCellHeight =
                                  (availH - (gap * (rows - 1))) / rows;
                              final preferredCellHeight = (cellWidth / 0.76).clamp(
                                150.0,
                                220.0,
                              );
                              final totalNeeded =
                                  (preferredCellHeight * rows) +
                                  (gap * (rows - 1));
                              final menuScrolls = totalNeeded > availH + 0.5;
                              final cellHeight = menuScrolls
                                  ? preferredCellHeight
                                  : (preferredCellHeight > fitCellHeight
                                      ? fitCellHeight
                                      : preferredCellHeight);
                              final contentHeight =
                                  (cellHeight * rows) + (gap * (rows - 1));
                              final topInset = menuScrolls
                                  ? 6.0
                                  : ((availH - contentHeight) / 2)
                                      .clamp(0.0, 24.0);
                              return GridView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  sideInset,
                                  topInset,
                                  sideInset,
                                  menuScrolls ? 10 : 0,
                                ),
                                physics: menuScrolls
                                    ? const ClampingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                itemCount: visibleModules.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cross,
                                  mainAxisSpacing: gap,
                                  crossAxisSpacing: gap,
                                  mainAxisExtent: cellHeight,
                                ),
                                itemBuilder: (context, index) {
                                  final m = visibleModules[index];
                                  final fill =
                                      menuStatusByCategory[m.category] ??
                                          DailyModuleFillStatus.pending;
                                  final globalIndex =
                                      _kDailyModules.indexOf(m);
                                  return _StaggerMenuTile(
                                    parent: _entranceController,
                                    index:
                                        globalIndex >= 0 ? globalIndex : index,
                                    lite: useLiteAnimations,
                                    child: RecordModuleCard(
                                      title: m.title,
                                      icon: m.icon,
                                      tileColor: m.color,
                                      showLightStyle: index.isOdd,
                                      fillStatus: fill,
                                      onTap: () => widget.onOpenModule(m),
                                    ),
                                  );
                                },
                              );
                            },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'บันทึกประจำวัน',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A2433),
                      ),
                    ),
                    Text(
                      appName,
                      style: const TextStyle(color: Color(0xFF6B7788), fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PressScaleButton(
                child: InkWell(
                  onTap: onPickDay,
                  borderRadius: BorderRadius.circular(20),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF0D7284),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          selectedDateLabel,
                          style: const TextStyle(
                            color: Color(0xFF0D7284),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _PressScaleButton(
                child: IconButton(
                  onPressed: () => onRefresh(),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF3A4A5E),
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderStatChip(
                icon: Icons.today_rounded,
                label: doneCount >= totalCount
                    ? 'วันนี้บันทึกครบทุกเมนูแล้ว ($totalCount เมนู)'
                    : incompleteMenuCount > 0
                        ? 'วันนี้ครบ $doneCount · ไม่ครบ $incompleteMenuCount · รวม $totalCount เมนู'
                        : 'วันนี้บันทึกครบ $doneCount/$totalCount เมนู',
              ),
              _HeaderStatChip(
                icon: Icons.access_time_filled_rounded,
                label: 'ล่าสุด $lastLabel',
              ),
              const _LiveClockChip(),
              _HeaderStatChip(
                icon: serverOnline
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                label: serverOnline
                    ? 'เซิร์ฟเวอร์: ออนไลน์'
                    : 'เซิร์ฟเวอร์: ออฟไลน์',
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

class _LiveClockChip extends StatelessWidget {
  const _LiveClockChip();

  @override
  Widget build(BuildContext context) {
    final stream = Stream<DateTime>.periodic(
      const Duration(seconds: 30),
      (_) => DateTime.now(),
    );
    return StreamBuilder<DateTime>(
      stream: stream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        return _HeaderStatChip(
          icon: Icons.schedule_rounded,
          label: 'เวลา $hh:$mm น.',
        );
      },
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
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF415268),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
        duration: const Duration(milliseconds: 130),
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
            Text(
              'สรุปภาพรวม',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
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
