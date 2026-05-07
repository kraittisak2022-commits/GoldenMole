import 'dart:async';

import 'package:flutter/material.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  late final TransactionService _txService;
  int _bodyPage = 0;
  DateTime _selectedDay = DateTime.now();
  DateTime _clock = DateTime.now();
  Timer? _ticker;
  late Future<_HomePayload> _homeFuture;

  @override
  void initState() {
    super.initState();
    _txService = TransactionService(Supabase.instance.client);
    _homeFuture = _loadHome();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _clock = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<_HomePayload> _loadHome() async {
    final results = await Future.wait([
      widget.dashboardService.fetchSummary(),
      _txService.fetchRecentTransactions(limit: 60),
    ]);
    final summary = results[0] as DashboardSummary;
    final recent = results[1] as List<AppTransaction>;
    return _HomePayload(summary: summary, recent: recent);
  }

  void _refreshHome() {
    setState(() {
      _homeFuture = _loadHome();
    });
  }

  String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatBuddhistDateButton(DateTime d) {
    const wk = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final be = d.year + 543;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${wk[d.weekday - 1]} $dd/$mm/$be';
  }

  bool _hasEntryForDay(
    List<AppTransaction> list,
    String category,
    String dayKey,
  ) {
    return list.any(
      (t) => transactionMatchesDailyModule(t, dayKey, category),
    );
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
      setState(
        () => _selectedDay = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
        ),
      );
    }
  }

  void _openQuickInput(_DailyModuleDef m) {
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
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved);
          final fade = Tween<double>(begin: 0, end: 1).animate(curved);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
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
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            snapshot.data == null) {
                          final loadingLabel = _bodyPage == 0
                              ? 'กำลังโหลดแดชบอร์ด'
                              : 'กำลังโหลดภาพรวม';
                          return PageLoadingView(label: loadingLabel);
                        }
                        if (snapshot.hasError) {
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
                        final data = snapshot.data;
                        if (data == null) {
                          return const PageLoadingView(
                            label: 'กำลังโหลดข้อมูล',
                          );
                        }
                        if (_bodyPage == 0) {
                          return _DailyHomeContent(
                            currentAdmin: widget.currentAdmin,
                            data: data,
                            selectedDay: _selectedDay,
                            clock: _clock,
                            onPullRefresh: _pullRefresh,
                            onPickDay: _pickDay,
                            dateKey: _dateKey,
                            formatBuddhistDateButton:
                                _formatBuddhistDateButton,
                            hasEntryForDay: _hasEntryForDay,
                            onOpenModule: _openQuickInput,
                          );
                        }
                        return _MetricsContent(
                          data: data,
                          currentAdmin: widget.currentAdmin,
                          onRetry: _refreshHome,
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
    setState(() => _homeFuture = _loadHome());
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
  const _HomePayload({required this.summary, required this.recent});

  final DashboardSummary summary;
  final List<AppTransaction> recent;
}

class _DailyHomeContent extends StatelessWidget {
  const _DailyHomeContent({
    required this.currentAdmin,
    required this.data,
    required this.selectedDay,
    required this.clock,
    required this.onPullRefresh,
    required this.onPickDay,
    required this.dateKey,
    required this.formatBuddhistDateButton,
    required this.hasEntryForDay,
    required this.onOpenModule,
  });

  final AdminUser currentAdmin;
  final _HomePayload data;
  final DateTime selectedDay;
  final DateTime clock;
  final Future<void> Function() onPullRefresh;
  final VoidCallback onPickDay;
  final String Function(DateTime) dateKey;
  final String Function(DateTime) formatBuddhistDateButton;
  final bool Function(List<AppTransaction> list, String category, String dayKey)
  hasEntryForDay;
  final void Function(_DailyModuleDef m) onOpenModule;

  @override
  Widget build(BuildContext context) {
    final dayKey = dateKey(selectedDay);
    final lastLabel = data.recent.isNotEmpty
        ? _formatThaiDateFromYmd(data.recent.first.date)
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeHeaderCompact(
            currentAdmin: currentAdmin,
            appName: data.summary.appName,
            currentTime:
                '${clock.hour.toString().padLeft(2, '0')}:${clock.minute.toString().padLeft(2, '0')}',
            lastLabel: lastLabel,
            selectedDateLabel: formatBuddhistDateButton(selectedDay),
            onPickDay: onPickDay,
            onRefresh: onPullRefresh,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: LayoutBuilder(
                key: ValueKey(formatBuddhistDateButton(selectedDay)),
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final cross = w >= 420 ? 3 : 2;
                  const gap = 8.0;
                  final rows = (_kDailyModules.length / cross).ceil();
                  final cellWidth = (w - (gap * (cross - 1))) / cross;
                  final cellHeight =
                      (constraints.maxHeight - (gap * (rows - 1))) / rows;
                  final ratio =
                      cellHeight <= 0 ? 1.0 : (cellWidth / cellHeight);
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _kDailyModules.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      childAspectRatio: ratio,
                    ),
                    itemBuilder: (context, index) {
                      final m = _kDailyModules[index];
                      final done = hasEntryForDay(
                        data.recent,
                        m.category,
                        dayKey,
                      );
                      return RecordModuleCard(
                        title: m.title,
                        icon: m.icon,
                        tileColor: m.color,
                        showLightStyle: index.isOdd,
                        recordedForSelectedDay: done,
                        onTap: () => onOpenModule(m),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHeaderCompact extends StatelessWidget {
  const _HomeHeaderCompact({
    required this.currentAdmin,
    required this.appName,
    required this.currentTime,
    required this.lastLabel,
    required this.selectedDateLabel,
    required this.onPickDay,
    required this.onRefresh,
  });

  final AdminUser currentAdmin;
  final String appName;
  final String currentTime;
  final String lastLabel;
  final String selectedDateLabel;
  final VoidCallback onPickDay;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      appName,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_pin, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    currentAdmin.displayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
              InkWell(
                onTap: onPickDay,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
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
