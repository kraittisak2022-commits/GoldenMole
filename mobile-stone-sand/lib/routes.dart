import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/new_order/new_order_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/placeholder_screen.dart';
import 'widgets/ui.dart';

/// Top-level sections, in the web's NAV_ITEMS order plus the phone menu.
enum Dest {
  dashboard('หน้าหลัก', Icons.dashboard_outlined, Icons.dashboard),
  orders('ออเดอร์', Icons.assignment_outlined, Icons.assignment),
  customers('ลูกค้า', Icons.people_outline, Icons.people),
  statements('เคลียร์บิล', Icons.fact_check_outlined, Icons.fact_check),
  driverPay('เคลียร์ค่ารถ', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
  drivers('รถ / คนขับ', Icons.local_shipping_outlined, Icons.local_shipping),
  settings('ตั้งค่า', Icons.settings_outlined, Icons.settings),
  menu('เมนู', Icons.grid_view_outlined, Icons.grid_view_rounded);

  const Dest(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Web route, used as the menu-hint key.
  String get route => switch (this) {
        Dest.dashboard => '/',
        Dest.orders => '/orders',
        Dest.customers => '/customers',
        Dest.statements => '/statements',
        Dest.driverPay => '/driver-pay',
        Dest.drivers => '/drivers',
        Dest.settings => '/settings',
        Dest.menu => '/menu',
      };
}

const navItems = [
  Dest.dashboard,
  Dest.orders,
  Dest.customers,
  Dest.statements,
  Dest.driverPay,
  Dest.drivers,
  Dest.settings,
];

/// Phone bottom bar: two tabs, the create button, then two more tabs.
const phoneTabs = [Dest.dashboard, Dest.orders, Dest.statements, Dest.menu];

const wideBreakpoint = 840.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Selected section and per-section query params (the web's `?f=…&r=…`).
class ShellController extends ChangeNotifier {
  Dest tab = Dest.dashboard;
  final Map<Dest, Map<String, String>> _params = {};
  final Map<Dest, int> _generation = {};

  Map<String, String> paramsOf(Dest d) => _params[d] ?? const {};

  /// Changes whenever new params are pushed so the section rebuilds fresh.
  Key keyOf(Dest d) => ValueKey('${d.name}:${_generation[d] ?? 0}');

  void select(Dest d, [Map<String, String>? params]) {
    tab = d;
    if (params != null) {
      _params[d] = params;
      _generation[d] = (_generation[d] ?? 0) + 1;
    }
    notifyListeners();
  }

  void reset() {
    tab = Dest.dashboard;
    _params.clear();
    _generation.clear();
    notifyListeners();
  }
}

class ShellScope extends InheritedNotifier<ShellController> {
  const ShellScope({super.key, required ShellController controller, required super.child})
      : super(notifier: controller);

  static ShellController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()!.notifier!;

  static ShellController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()!.notifier!;
}

/// Section body without chrome; the shell or [_SectionPage] adds the app bar.
Widget sectionBody(Dest d, Map<String, String> params, {Key? key}) => switch (d) {
      Dest.dashboard => DashboardScreen(key: key, params: params),
      Dest.orders => OrdersScreen(key: key, params: params),
      Dest.menu => MenuScreen(key: key),
      _ => Center(key: key, child: const EmptyState('กำลังพัฒนา')),
    };

class _SectionPage extends StatelessWidget {
  const _SectionPage({required this.dest, required this.params});
  final Dest dest;
  final Map<String, String> params;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(dest.label)),
        body: sectionBody(dest, params),
      );
}

/// Opens a section like a web link: switches the shell tab when the section has one, else pushes it.
void goTo(BuildContext context, Dest d, [Map<String, String> params = const {}]) {
  final nav = Navigator.of(context, rootNavigator: true);
  if (isWide(context) || phoneTabs.contains(d)) {
    nav.popUntil((r) => r.isFirst);
    ShellScope.read(context).select(d, params);
    return;
  }
  nav.push(MaterialPageRoute<void>(builder: (_) => _SectionPage(dest: d, params: params)));
}

Future<void> openOrder(BuildContext context, String id) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(builder: (_) => const PlaceholderScreen('รายละเอียดออเดอร์')));

Future<void> openNewOrder(BuildContext context, {String? customerId}) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(builder: (_) => NewOrderScreen(customerId: customerId)));

/// Bill for an order; [created] shows the "order saved" banner, [replace] swaps out the current page.
Future<void> openOrderBill(BuildContext context, String orderId, {bool created = false, bool replace = false}) {
  final route = MaterialPageRoute<void>(builder: (_) => const PlaceholderScreen('บิล'));
  final nav = Navigator.of(context, rootNavigator: true);
  return replace ? nav.pushReplacement(route) : nav.push(route);
}
