import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_scope.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../tour/tour_controller.dart';
import '../widgets/ui.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final wide = isWide(context);
    final tabs = wide ? [...navItems, Dest.menu] : phoneTabs;
    final current = tabs.contains(shell.tab) ? shell.tab : Dest.dashboard;
    final index = tabs.indexOf(current);

    final body = IndexedStack(
      index: index,
      children: [
        for (final d in tabs)
          _KeepTab(
            active: d == current,
            child: sectionBody(d, shell.paramsOf(d), key: shell.keyOf(d)),
          ),
      ],
    );

    return PopScope(
      canPop: current == Dest.dashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.select(Dest.dashboard);
      },
      child: wide
          ? Scaffold(
              body: Row(
                children: [
                  _Sidebar(current: current),
                  const VerticalDivider(width: 1),
                  Expanded(child: SafeArea(left: false, bottom: false, child: body)),
                ],
              ),
            )
          : Scaffold(
              appBar: const _BrandBar(),
              body: body,
              bottomNavigationBar: BottomTabs(current: current),
            ),
    );
  }
}

/// Builds a tab's body lazily the first time it is shown, then keeps it alive.
class _KeepTab extends StatefulWidget {
  const _KeepTab({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_KeepTab> createState() => _KeepTabState();
}

class _KeepTabState extends State<_KeepTab> {
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    if (widget.active) _built = true;
    if (!_built) return const SizedBox.shrink();
    return TickerMode(enabled: widget.active, child: widget.child);
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset('assets/branding/pirasit-logo.png', height: large ? 48 : 36),
        SizedBox(width: large ? 12 : 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'หจก. พีรสิทธิ์ วัสดุก่อสร้าง',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
              ),
              Text(
                'ออเดอร์หิน-ทราย',
                style: TextStyle(fontSize: large ? 18 : 14, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandBar extends StatelessWidget implements PreferredSizeWidget {
  const _BrandBar();

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final locked = AuthScope.of(context).lockedSource;
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      title: const _BrandTitle(),
      actions: [
        if (locked != null) Padding(padding: const EdgeInsets.only(right: 16), child: SourceBadge(locked, long: true)),
      ],
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
    );
  }
}

class BottomTabs extends StatelessWidget {
  const BottomTabs({super.key, required this.current});
  final Dest current;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tab(Dest d) {
      final active = d == current;
      final color = active ? AppColors.primary : AppColors.muted;
      return Expanded(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            shell.select(d);
          },
          highlightColor: AppColors.primarySoft.withValues(alpha: 0.6),
          splashColor: AppColors.primarySoft.withValues(alpha: 0.8),
          child: SizedBox(
            height: 60,
            // Stack lets the indicator overlay the bottom without adding to the
            // Column intrinsic height (Thai text renders taller than fontSize).
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(active ? d.activeIcon : d.icon, size: 22, color: color),
                    const SizedBox(height: 2),
                    Text(
                      d.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                // Animated pill indicator — zero cost on the Column's height.
                Positioned(
                  bottom: 4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: active ? 16.0 : 0.0,
                    height: 3.0,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TourTarget(
      'main-nav',
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              tab(phoneTabs[0]),
              tab(phoneTabs[1]),
              Expanded(
                child: Center(
                  child: TourTarget(
                    'new-order',
                    child: Tooltip(
                      message: 'สร้างออเดอร์',
                      child: Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(side: BorderSide(color: AppColors.surface, width: 4)),
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.35),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            openNewOrder(context);
                          },
                          child: const SizedBox(
                            width: 56,
                            height: 56,
                            child: Icon(Icons.add, size: 28, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              tab(phoneTabs[2]),
              tab(phoneTabs[3]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current});
  final Dest current;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final user = auth.user;
    final shell = ShellScope.read(context);

    Widget item(Dest d, {Color? color, VoidCallback? onTap, IconData? icon, String? label}) {
      final active = d == current && onTap == null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: active ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(kRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(kRadius),
            onTap: onTap ?? () => shell.select(d),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    icon ?? (active ? d.activeIcon : d.icon),
                    size: 20,
                    color: color ?? (active ? AppColors.primary : AppColors.muted),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label ?? d.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: color ?? (active ? AppColors.primary : AppColors.muted),
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 256,
      color: AppColors.surface,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandTitle(large: true),
                  if (auth.lockedSource != null) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 60),
                      child: SourceBadge(auth.lockedSource!, long: true),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TourTarget(
                'new-order',
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => openNewOrder(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('สร้างออเดอร์'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: TourTarget(
                  'main-nav',
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [for (final d in navItems) item(d)],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  item(
                    Dest.menu,
                    icon: Icons.school_outlined,
                    label: 'สอนใช้งาน / เมนู',
                    color: const Color(0xFF6D28D9),
                    onTap: () => shell.select(Dest.menu),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? '',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        Text(user?.role ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  item(Dest.menu, icon: Icons.logout, label: 'ออกจากระบบ', onTap: () => signOutWithConfirm(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> signOutWithConfirm(BuildContext context) async {
  final auth = AuthScope.read(context);
  final ok = await confirmDialog(context, title: 'ออกจากระบบ?', confirmLabel: 'ออกจากระบบ', destructive: true);
  if (ok) auth.signOut();
}
