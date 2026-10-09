import 'package:flutter/material.dart';

import '../auth/auth_scope.dart';
import '../data/catalog_scope.dart';
import '../data/customers_repo.dart';
import '../data/orders_repo.dart';
import '../data/statements_repo.dart';
import '../logic/format.dart';
import '../logic/menu_hints.dart';
import '../models/models.dart';
import '../routes.dart';
import '../theme/app_theme.dart';
import '../widgets/loader.dart';
import '../widgets/page.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';

Future<T?> _settled<T>(Future<T> f) async {
  try {
    return await f;
  } catch (_) {
    return null;
  }
}

/// Each count loads on its own; one failing only drops that card's number.
Future<MenuCounts> _loadCounts() async {
  final today = toIsoDate();
  final todayOrders = _settled(listOrders(from: today, to: today));
  final waiting = _settled(
    listOrders(deliveryStatuses: [DeliveryStatus.waiting, DeliveryStatus.dispatched], limit: 200),
  );
  final customers = _settled(listCustomers());
  final statements = _settled(listStatements());
  final driverUnpaid = _settled(listDriverUnpaidOrders());
  return MenuCounts(
    ordersToday: (await todayOrders)?.where((o) => !o.cancelled).length,
    waitingDelivery: (await waiting)?.length,
    customers: (await customers)?.length,
    openStatements: (await statements)?.where((s) => s.status == 'open').length,
    driverUnpaid: (await driverUnpaid)?.length,
  );
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with ReloadOnDataChange {
  final _counts = Loader<MenuCounts>(_loadCounts);

  @override
  List<Loader<dynamic>> get loaders => [_counts];

  @override
  void initState() {
    super.initState();
    _counts.load();
  }

  @override
  void dispose() {
    _counts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final catalog = CatalogScope.of(context);
    final user = auth.user;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024 ? 4 : (width >= 600 ? 3 : 2);
    return ListenableBuilder(
      listenable: _counts,
      builder: (context, _) {
        final c = _counts.data ?? const MenuCounts();
        final hints = menuHints(MenuCounts(
          ordersToday: c.ordersToday,
          waitingDelivery: c.waitingDelivery,
          customers: c.customers,
          openStatements: c.openStatements,
          driverUnpaid: c.driverUnpaid,
          drivers: catalog.loading ? null : catalog.drivers.length,
          products: catalog.loading ? null : catalog.products.length,
        ));
        return PageScroll(
          onRefresh: () async {
            await Future.wait([_counts.load(), catalog.reload()]);
          },
          children: [
            const PageHeader(title: 'เมนู', subtitle: 'เลือกส่วนที่ต้องการใช้งาน'),
            GridRows(
              columns: columns,
              children: [
                for (final d in navItems)
                  _MenuCard(
                    icon: d.icon,
                    label: d.label,
                    hint: hints[d.route] ?? '',
                    onTap: () => goTo(context, d),
                  ),
                _MenuCard(
                  icon: Icons.add,
                  label: 'สร้างออเดอร์',
                  hint: hints['/new'] ?? '',
                  onTap: () => openNewOrder(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                              ),
                              Text(user?.role ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        if (auth.lockedSource != null) SourceBadge(auth.lockedSource!, long: true),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kRadius),
                      onTap: () => signOutWithConfirm(context),
                      child: const SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            SizedBox(width: 12),
                            Icon(Icons.logout, size: 20, color: AppColors.destructive),
                            SizedBox(width: 12),
                            Text('ออกจากระบบ', style: TextStyle(fontSize: 14, color: AppColors.destructive)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 144),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: AppColors.primary),
                const SizedBox(height: 12),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
