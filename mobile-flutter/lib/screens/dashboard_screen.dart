import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../models/app_transaction.dart';
import '../models/dashboard_summary.dart';
import '../services/dashboard_service.dart';
import '../services/employee_service.dart';
import '../services/project_service.dart';
import '../services/transaction_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/page_loading_view.dart';
import '../widgets/record_module_card.dart';
import 'app_settings_screen.dart';
import 'calendar_screen.dart';
import 'employees_screen.dart';
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
    color: Color(0xFFE56DB1),
  ),
  _DailyModuleDef(
    title: 'บันทึกรถและจำนวนเที่ยวรถ',
    icon: Icons.local_shipping_outlined,
    category: 'จำนวนเที่ยวรถ',
    quickInputTitle: 'บันทึกรถและเที่ยว',
    color: Color(0xFF33C6B8),
  ),
  _DailyModuleDef(
    title: 'น้ำมัน',
    icon: Icons.oil_barrel_outlined,
    category: 'น้ำมัน',
    quickInputTitle: 'บันทึกน้ำมัน',
    color: Color(0xFFF3A62C),
  ),
  _DailyModuleDef(
    title: 'ทรายที่ล้างที่บ้าน',
    icon: Icons.waves_outlined,
    category: 'ทรายที่ล้างที่บ้าน',
    quickInputTitle: 'ทรายที่ล้างที่บ้าน',
    color: Color(0xFF6C7CF3),
  ),
  _DailyModuleDef(
    title: 'บันทึกการทำงาน',
    icon: Icons.payments_outlined,
    category: 'ค่าแรง',
    quickInputTitle: 'บันทึกการทำงาน',
    color: Color(0xFF8C5FD3),
  ),
  _DailyModuleDef(
    title: 'การทำงานล่วงเวลา (OT)',
    icon: Icons.groups_2_outlined,
    category: 'OT',
    quickInputTitle: 'บันทึกการทำงานล่วงเวลา',
    color: Color(0xFFE95D6A),
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
    final be = d.year + 543;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/$be';
  }

  bool _hasEntryForDay(
    List<AppTransaction> list,
    String category,
    String dayKey,
  ) {
    return list.any((t) => t.date == dayKey && t.category == category);
  }

  Future<void> _pickDay() async {
    final first = DateTime(2020);
    final last = DateTime.now().add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: first,
      lastDate: last,
      locale: const Locale('th', 'TH'),
    );
    if (picked != null) {
      setState(
        () => _selectedDay = DateTime(picked.year, picked.month, picked.day),
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
                    child: _bodyPage == 0
                        ? _DailyHomeBody(
                            currentAdmin: widget.currentAdmin,
                            homeFuture: _homeFuture,
                            selectedDay: _selectedDay,
                            clock: _clock,
                            onRetry: _refreshHome,
                            onPullRefresh: _pullRefresh,
                            onPickDay: _pickDay,
                            dateKey: _dateKey,
                            formatBuddhistDateButton: _formatBuddhistDateButton,
                            hasEntryForDay: _hasEntryForDay,
                            onOpenModule: _openQuickInput,
                          )
                        : _MetricsBody(
                            homeFuture: _homeFuture,
                            currentAdmin: widget.currentAdmin,
                            onRetry: _refreshHome,
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

class _DailyHomeBody extends StatelessWidget {
  const _DailyHomeBody({
    required this.currentAdmin,
    required this.homeFuture,
    required this.selectedDay,
    required this.clock,
    required this.onRetry,
    required this.onPullRefresh,
    required this.onPickDay,
    required this.dateKey,
    required this.formatBuddhistDateButton,
    required this.hasEntryForDay,
    required this.onOpenModule,
  });

  final AdminUser currentAdmin;
  final Future<_HomePayload> homeFuture;
  final DateTime selectedDay;
  final DateTime clock;
  final VoidCallback onRetry;
  final Future<void> Function() onPullRefresh;
  final VoidCallback onPickDay;
  final String Function(DateTime) dateKey;
  final String Function(DateTime) formatBuddhistDateButton;
  final bool Function(List<AppTransaction> list, String category, String dayKey)
  hasEntryForDay;
  final void Function(_DailyModuleDef m) onOpenModule;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomePayload>(
      future: homeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PageLoadingView(label: 'กำลังโหลดแดชบอร์ด');
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
                    style: GoogleFonts.kanit(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text('ลองอีกครั้ง', style: GoogleFonts.kanit()),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
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
                    final ratio = cellHeight <= 0
                        ? 1.0
                        : (cellWidth / cellHeight);
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
      },
    );
  }

  static String _formatThaiDateFromYmd(String ymd) {
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11A8BA), Color(0xFF3DBECC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF11A8BA).withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppLogo(size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'บันทึกประจำวัน',
                  style: GoogleFonts.kanit(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  'รีเฟรช',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.88),
                  foregroundColor: const Color(0xFF17374C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$appName • ${currentAdmin.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPickDay,
                icon: const Icon(Icons.calendar_today_outlined, size: 15),
                label: Text(
                  selectedDateLabel,
                  style: GoogleFonts.kanit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
                  backgroundColor: Colors.white.withValues(alpha: 0.20),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'เวลา $currentTime • ล่าสุด: $lastLabel',
            style: GoogleFonts.kanit(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsBody extends StatelessWidget {
  const _MetricsBody({
    required this.homeFuture,
    required this.currentAdmin,
    required this.onRetry,
  });

  final Future<_HomePayload> homeFuture;
  final AdminUser currentAdmin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return FutureBuilder<_HomePayload>(
      future: homeFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const PageLoadingView(label: 'กำลังโหลดภาพรวม');
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(
                  'สรุปภาพรวม',
                  style: GoogleFonts.kanit(
                    fontSize: 18,
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
              style: GoogleFonts.kanit(fontSize: 13, color: Colors.black54),
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
              label: Text('จัดการธุรกรรม', style: GoogleFonts.kanit()),
            ),
          ],
        );
      },
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF11A8BA)),
        title: Text(
          title,
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          value,
          style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
